from __future__ import annotations

import io
import json
import tarfile
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from bilin_api.article_store import (
    get_article_revision,
    read_manifest,
    replace_document,
)
from bilin_api.export_service import export_article
from bilin_api.golden import default_golden_fixture_path
from bilin_api.importer import import_local_file
from bilin_api.latexml_parser import (
    normalize_latexml_html,
    parse_article_revision,
    render_source_markdown,
)
from bilin_api.repositories import create_library
from bilin_api.schemas import (
    ArticleExportKind,
    ArticleExportRequest,
    ArticleExportResult,
    ArticleManifest,
    ArticleRevision,
    ImportLocalKind,
    Library,
    LibraryCreate,
)


class GoldenAcceptanceResult(BaseModel):
    fixture: str
    fixture_path: str
    library_id: str
    library_path: str
    article_revision_id: str
    bundle_path: str
    parse_mode: str
    parse_result: dict[str, Any] = Field(default_factory=dict)
    reader_route: str
    exports: list[ArticleExportResult]


MVP_EXPORT_KINDS = (
    ArticleExportKind.source_markdown,
    ArticleExportKind.translated_markdown,
    ArticleExportKind.bilingual_markdown,
    ArticleExportKind.lecture_notes,
    ArticleExportKind.bundle_zip,
)


async def run_golden_acceptance(
    output_dir: Path,
    fixture_path: Path | None = None,
    *,
    live_latexml: bool = False,
    target_language: str = "zh-CN",
) -> GoldenAcceptanceResult:
    fixture = (fixture_path or default_golden_fixture_path()).expanduser().resolve()
    fixture_config = load_fixture_config(fixture)
    source_root = fixture / string_value(fixture_config.get("source_root"), "source")
    if not source_root.exists():
        msg = f"Missing golden source directory: {source_root}"
        raise ValueError(msg)

    output = output_dir.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    library = await create_library(
        LibraryCreate(name=f"Acceptance {fixture.name}", path=str(output / "library"))
    )
    imported = await import_local_file(
        library,
        file_name=f"{fixture.name}.tar",
        content=source_tar_bytes(source_root),
        kind=ImportLocalKind.tex_archive,
        parse_after_import=False,
    )
    revision = await require_revision(library, imported.article_revision_id)

    if live_latexml:
        parse_result = await parse_article_revision(library, revision.id)
        parse_mode = "latexml"
    else:
        parse_result = await write_fixture_document(library, revision, fixture, fixture_config)
        parse_mode = "fixture-html"

    exports: list[ArticleExportResult] = []
    for kind in MVP_EXPORT_KINDS:
        exports.append(
            await export_article(
                library,
                revision.id,
                ArticleExportRequest(
                    kind=kind,
                    target_language=target_language,
                    include_untranslated=True,
                ),
            )
        )

    return GoldenAcceptanceResult(
        fixture=fixture.name,
        fixture_path=str(fixture),
        library_id=library.id,
        library_path=library.path,
        article_revision_id=revision.id,
        bundle_path=revision.bundle_path,
        parse_mode=parse_mode,
        parse_result=parse_result,
        reader_route=f"/articles/{revision.id}?libraryId={library.id}",
        exports=exports,
    )


async def require_revision(library: Library, revision_id: str) -> ArticleRevision:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Imported revision could not be read: {revision_id}"
        raise RuntimeError(msg)
    return revision


async def write_fixture_document(
    library: Library,
    revision: ArticleRevision,
    fixture: Path,
    fixture_config: dict[str, Any],
) -> dict[str, Any]:
    html_path = fixture / string_value(fixture_config.get("latexml_html"), "latexml.html")
    if not html_path.exists():
        msg = f"Missing LaTeXML HTML fixture: {html_path}"
        raise ValueError(msg)
    bundle_path = Path(revision.bundle_path)
    manifest = read_manifest(bundle_path) or ArticleManifest(
        article_revision_id=revision.id,
        source="upload",
    )
    blocks, assets = normalize_latexml_html(
        html_path,
        revision.id,
        bundle_path=bundle_path,
        source_root=fixture,
    )
    source_md = render_source_markdown(blocks)
    manifest.parse_status = "parsed"
    manifest.generated_artifacts["latexml_html_fixture"] = str(html_path)
    manifest.metadata.update(
        {
            "acceptance_fixture": fixture.name,
            "parse_mode": "fixture-html",
        }
    )
    await replace_document(library, revision, manifest, blocks, assets, source_md)
    return {
        "article_revision_id": revision.id,
        "document_path": str(bundle_path / "document" / "document.json"),
        "source_md_path": str(bundle_path / "document" / "source.md"),
        "block_count": len(blocks),
        "asset_count": len(assets),
    }


def source_tar_bytes(source_root: Path) -> bytes:
    files = sorted(path for path in source_root.rglob("*") if path.is_file())
    if not files:
        msg = f"Golden source directory contains no files: {source_root}"
        raise ValueError(msg)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for path in files:
            content = path.read_bytes()
            info = tarfile.TarInfo(path.relative_to(source_root).as_posix())
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()


def load_fixture_config(fixture: Path) -> dict[str, Any]:
    expected_path = fixture / "expected.json"
    if not expected_path.exists():
        msg = f"Missing expected.json in golden fixture: {fixture}"
        raise ValueError(msg)
    payload = json.loads(expected_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        msg = f"expected.json must contain an object: {expected_path}"
        raise ValueError(msg)
    return payload


def string_value(value: object, fallback: str) -> str:
    return value if isinstance(value, str) and value else fallback
