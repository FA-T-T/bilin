from __future__ import annotations

import json
import re
from pathlib import Path

import httpx

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    bundle_path_for_upload,
    make_block,
    replace_document,
    sha256_bytes,
    upsert_arxiv_revision,
    upsert_upload_revision,
    write_manifest,
)
from bilin_api.arxiv import ArxivMetadata, download_bytes, resolve_arxiv_metadata
from bilin_api.embedding_service import build_article_embeddings
from bilin_api.repositories import create_job
from bilin_api.schemas import (
    ArticleManifest,
    ImportArxivRequest,
    ImportArxivResult,
    ImportLocalKind,
    ImportLocalResult,
    JobType,
    Library,
)


async def import_arxiv(
    library: Library,
    request: ImportArxivRequest,
    client: httpx.AsyncClient | None = None,
) -> ImportArxivResult:
    metadata = await resolve_arxiv_metadata(request.arxiv_id, request.version, client)
    bundle_path = bundle_path_for_arxiv(library, metadata.bare_id, metadata.version)
    original_dir = bundle_path / "original"
    for directory in (
        original_dir,
        bundle_path / "source" / "unpacked",
        bundle_path / "document",
        bundle_path / "assets",
        bundle_path / "logs",
    ):
        directory.mkdir(parents=True, exist_ok=True)

    source_bytes = await download_bytes(metadata.source_url, client)
    source_path = original_dir / "source.tar"
    source_path.write_bytes(source_bytes)
    pdf_fingerprint = None
    if request.download_pdf:
        pdf_bytes = await download_bytes(metadata.pdf_url, client)
        (original_dir / "paper.pdf").write_bytes(pdf_bytes)
        pdf_fingerprint = sha256_bytes(pdf_bytes)

    family, revision = await upsert_arxiv_revision(
        library=library,
        bare_id=metadata.bare_id,
        version=metadata.version,
        title=metadata.title,
        bundle_path=bundle_path,
        metadata=metadata.to_json(),
    )
    manifest = build_manifest(
        revision_id=revision.id,
        metadata=metadata,
        source_fingerprint=sha256_bytes(source_bytes),
        pdf_fingerprint=pdf_fingerprint,
    )
    write_manifest(bundle_path, manifest)
    parse_job_id = None
    if request.parse_after_import:
        parse_job = await create_job(
            JobType.parse_article,
            payload={"library_id": library.id, "article_revision_id": revision.id},
        )
        parse_job_id = parse_job.id
    return ImportArxivResult(
        library_id=library.id,
        article_family_id=family.id,
        article_revision_id=revision.id,
        bundle_path=str(bundle_path),
        parse_job_id=parse_job_id,
    )


def build_manifest(
    revision_id: str,
    metadata: ArxivMetadata,
    source_fingerprint: str,
    pdf_fingerprint: str | None,
) -> ArticleManifest:
    return ArticleManifest(
        article_revision_id=revision_id,
        arxiv_id=metadata.concrete_id,
        source="arxiv",
        source_fingerprint=source_fingerprint,
        pdf_fingerprint=pdf_fingerprint,
        arxiv_metadata=metadata.to_json(),
        parse_status="not_started",
        generated_artifacts={
            "source_archive": "original/source.tar",
            "pdf": "original/paper.pdf" if pdf_fingerprint else None,
        },
        metadata={"manifest_format": "bilin.article_manifest.v1"},
    )


async def import_local_file(
    library: Library,
    *,
    file_name: str,
    content: bytes,
    kind: ImportLocalKind,
    parse_after_import: bool = True,
) -> ImportLocalResult:
    if not content:
        msg = "Uploaded file is empty."
        raise ValueError(msg)
    safe_name = sanitize_file_name(file_name)
    source_fingerprint = sha256_bytes(content)
    upload_id = f"{kind.value}-{source_fingerprint[:16]}"
    version = "v1"
    bundle_path = bundle_path_for_upload(library, upload_id, version)
    original_dir = bundle_path / "original"
    for directory in (
        original_dir,
        bundle_path / "source" / "unpacked",
        bundle_path / "document",
        bundle_path / "assets",
        bundle_path / "logs",
    ):
        directory.mkdir(parents=True, exist_ok=True)

    source_artifact = write_local_source(original_dir, safe_name, content, kind)
    family, revision = await upsert_upload_revision(
        library=library,
        upload_id=upload_id,
        version=version,
        title=Path(safe_name).stem or safe_name,
        bundle_path=bundle_path,
        metadata={
            "source_kind": kind.value,
            "file_name": safe_name,
            "source_fingerprint": source_fingerprint,
        },
    )
    manifest = ArticleManifest(
        article_revision_id=revision.id,
        source="upload",
        source_fingerprint=source_fingerprint,
        parse_status="not_started",
        generated_artifacts={source_artifact[0]: source_artifact[1]},
        metadata={
            "manifest_format": "bilin.article_manifest.v1",
            "source_kind": kind.value,
            "file_name": safe_name,
            "upload_id": upload_id,
        },
    )
    write_manifest(bundle_path, manifest)

    parse_job_id = None
    if kind == ImportLocalKind.markdown:
        blocks = markdown_blocks(content.decode("utf-8", errors="replace"), revision.id)
        manifest.parse_status = "parsed"
        source_md = render_markdown_source(blocks)
        await replace_document(library, revision, manifest, blocks, [], source_md)
        await build_article_embeddings(library, revision.id)
    elif kind == ImportLocalKind.tex_archive and parse_after_import:
        parse_job = await create_job(
            JobType.parse_article,
            payload={"library_id": library.id, "article_revision_id": revision.id},
        )
        parse_job_id = parse_job.id

    return ImportLocalResult(
        library_id=library.id,
        article_family_id=family.id,
        article_revision_id=revision.id,
        bundle_path=str(bundle_path),
        source_kind=kind,
        parse_job_id=parse_job_id,
    )


def write_local_source(
    original_dir: Path,
    file_name: str,
    content: bytes,
    kind: ImportLocalKind,
) -> tuple[str, str]:
    if kind == ImportLocalKind.pdf:
        path = original_dir / "paper.pdf"
        path.write_bytes(content)
        return ("pdf", "original/paper.pdf")
    if kind == ImportLocalKind.markdown:
        path = original_dir / "source.md"
        path.write_bytes(content)
        return ("source_markdown", "original/source.md")
    if file_name.lower().endswith(".zip"):
        path = original_dir / "source.zip"
    elif file_name.lower().endswith(".gz"):
        path = original_dir / "source.gz"
    else:
        path = original_dir / "source.tar"
    path.write_bytes(content)
    return ("source_archive", f"original/{path.name}")


def markdown_blocks(markdown: str, revision_id: str) -> list:
    blocks = []
    section_count = 0
    paragraph_count = 0
    paragraph_lines: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph_count
        text = "\n".join(paragraph_lines).strip()
        paragraph_lines.clear()
        if not text:
            return
        paragraph_count += 1
        blocks.append(
            make_block(
                revision_id,
                block_uid=f"p-{paragraph_count:04d}",
                structural_path=f"{len(blocks) + 1:05d}",
                block_type="paragraph",
                source_markdown=text,
                metadata={"source_kind": "markdown"},
            )
        )

    for line in markdown.splitlines():
        heading = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if heading:
            flush_paragraph()
            section_count += 1
            blocks.append(
                make_block(
                    revision_id,
                    block_uid=f"sec-{section_count:03d}",
                    structural_path=f"{len(blocks) + 1:05d}",
                    block_type="section",
                    source_markdown=heading.group(2),
                    metadata={"level": len(heading.group(1)), "source_kind": "markdown"},
                )
            )
            continue
        if line.strip():
            paragraph_lines.append(line.rstrip())
        else:
            flush_paragraph()
    flush_paragraph()
    if not blocks:
        blocks.append(
            make_block(
                revision_id,
                block_uid="p-0001",
                structural_path="00001",
                block_type="paragraph",
                source_markdown=markdown.strip() or "(empty markdown import)",
                metadata={"source_kind": "markdown"},
            )
        )
    return blocks


def render_markdown_source(blocks: list) -> str:
    lines: list[str] = []
    for block in blocks:
        if block.block_type == "section":
            level = int(block.metadata.get("level", 1))
            lines.extend([f"{'#' * min(max(level, 1), 6)} {block.source_markdown}", ""])
        else:
            lines.extend([block.source_markdown, ""])
    return "\n".join(lines).strip() + "\n"


def sanitize_file_name(file_name: str) -> str:
    name = Path(file_name).name.strip()
    return name or "uploaded-source"


def import_result_to_json(result: ImportArxivResult) -> dict:
    return json.loads(result.model_dump_json())
