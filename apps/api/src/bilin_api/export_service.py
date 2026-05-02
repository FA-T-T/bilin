from __future__ import annotations

import re
import zipfile
from datetime import UTC, datetime
from pathlib import Path

from bilin_api.article_store import (
    get_article_revision,
    list_blocks,
    list_translation_variants,
    read_manifest,
    write_lecture_notes,
    write_manifest,
)
from bilin_api.glossary_service import active_article_glossary_terms, apply_glossary_to_markdown
from bilin_api.repositories import create_job
from bilin_api.schemas import (
    ArticleExportKind,
    ArticleExportRequest,
    ArticleExportResult,
    DocumentBlock,
    Job,
    JobType,
    Library,
    TranslationVariant,
)
from bilin_api.translation_service import is_translatable_block


async def export_article(
    library: Library,
    revision_id: str,
    request: ArticleExportRequest,
) -> ArticleExportResult:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Article revision not found: {revision_id}"
        raise ValueError(msg)

    bundle_path = Path(revision.bundle_path)
    export_dir = bundle_path / "export"
    export_dir.mkdir(parents=True, exist_ok=True)

    missing: list[str] = []
    if request.kind == ArticleExportKind.source_markdown:
        output_path = export_dir / "source.md"
        output_path.write_text(
            await render_source_markdown(library, revision_id),
            encoding="utf-8",
        )
    elif request.kind == ArticleExportKind.translated_markdown:
        output_path = export_dir / f"translation.{safe_file_token(request.target_language)}.md"
        output_path.write_text(
            await render_translated_markdown(
                library,
                revision_id,
                request.target_language,
                request.include_untranslated,
                missing,
            ),
            encoding="utf-8",
        )
    elif request.kind == ArticleExportKind.bilingual_markdown:
        output_path = export_dir / f"bilingual.{safe_file_token(request.target_language)}.md"
        output_path.write_text(
            await render_bilingual_markdown(
                library,
                revision_id,
                request.target_language,
                request.include_untranslated,
                missing,
            ),
            encoding="utf-8",
        )
    elif request.kind == ArticleExportKind.lecture_notes:
        notes_path = await write_lecture_notes(library, revision_id)
        output_path = export_dir / "lecture-notes.md"
        output_path.write_text(notes_path.read_text(encoding="utf-8"), encoding="utf-8")
    elif request.kind == ArticleExportKind.bundle_zip:
        output_path = export_dir / "article-bundle.zip"
        write_bundle_zip(bundle_path, output_path)
    else:
        msg = f"Unsupported export kind: {request.kind}"
        raise ValueError(msg)

    result = ArticleExportResult(
        article_revision_id=revision_id,
        kind=request.kind,
        target_language=target_language_for_result(request.kind, request.target_language),
        file_name=output_path.name,
        path=str(output_path),
        bytes_written=output_path.stat().st_size,
        missing_translation_block_uids=sorted(set(missing)),
        metadata=export_metadata(bundle_path, export_dir, output_path),
        created_at=datetime.now(UTC),
    )
    write_export_manifest_entry(bundle_path, result)
    return result


async def queue_article_export(
    library: Library,
    revision_id: str,
    request: ArticleExportRequest,
) -> Job:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Article revision not found: {revision_id}"
        raise ValueError(msg)
    return await create_job(
        JobType.export_article,
        payload={
            "library_id": library.id,
            "article_revision_id": revision_id,
            "request": request.model_dump(mode="json"),
        },
    )


async def render_source_markdown(library: Library, revision_id: str) -> str:
    blocks = await list_blocks(library, revision_id)
    return render_markdown_document(
        title="Source Markdown",
        revision_id=revision_id,
        body_parts=[render_source_block(block) for block in blocks],
    )


async def render_translated_markdown(
    library: Library,
    revision_id: str,
    target_language: str,
    include_untranslated: bool,
    missing: list[str],
) -> str:
    blocks = await list_blocks(library, revision_id)
    translations = await default_translation_by_block_uid(library, revision_id, target_language)
    body_parts = [
        render_translated_block(block, translations, include_untranslated, missing)
        for block in blocks
    ]
    return render_markdown_document(
        title=f"Translation ({target_language})",
        revision_id=revision_id,
        body_parts=[part for part in body_parts if part],
    )


async def render_bilingual_markdown(
    library: Library,
    revision_id: str,
    target_language: str,
    include_untranslated: bool,
    missing: list[str],
) -> str:
    blocks = await list_blocks(library, revision_id)
    translations = await default_translation_by_block_uid(library, revision_id, target_language)
    parts: list[str] = []
    for block in blocks:
        translation = translation_for_block(block, translations, include_untranslated, missing)
        parts.append(
            "\n\n".join(
                part
                for part in (
                    anchor_for_block(block),
                    f"### {block.block_uid} · {block.block_type}",
                    "**Source**",
                    render_source_content(block),
                    f"**Translation ({target_language})**",
                    translation or "_Translation unavailable._",
                )
                if part
            )
        )
    return render_markdown_document(
        title=f"Bilingual Markdown ({target_language})",
        revision_id=revision_id,
        body_parts=parts,
    )


def render_markdown_document(title: str, revision_id: str, body_parts: list[str]) -> str:
    body = "\n\n".join(part.strip() for part in body_parts if part.strip())
    return f"# {title}\n\nArticle revision: `{revision_id}`\n\n{body}".strip() + "\n"


def render_source_block(block: DocumentBlock) -> str:
    return "\n\n".join(
        part for part in (anchor_for_block(block), render_source_content(block)) if part
    )


def render_source_content(block: DocumentBlock) -> str:
    content = block.source_markdown.strip()
    if block.block_type == "section" and content and not content.startswith("#"):
        level = block.metadata.get("level")
        heading_level = level if isinstance(level, int) and 1 <= level <= 6 else 2
        return f"{'#' * heading_level} {content}"
    return content


def render_translated_block(
    block: DocumentBlock,
    translations: dict[str, str],
    include_untranslated: bool,
    missing: list[str],
) -> str:
    return "\n\n".join(
        part
        for part in (
            anchor_for_block(block),
            translation_for_block(block, translations, include_untranslated, missing),
        )
        if part
    )


def translation_for_block(
    block: DocumentBlock,
    translations: dict[str, str],
    include_untranslated: bool,
    missing: list[str],
) -> str:
    if is_translatable_block(block):
        translated = translations.get(block.block_uid)
        if translated:
            return translated
        missing.append(block.block_uid)
        if not include_untranslated:
            return ""
        source = render_source_content(block)
        return f"<!-- untranslated:{block.block_uid} -->\n\n{source}" if source else ""
    return render_source_content(block)


async def default_translation_by_block_uid(
    library: Library,
    revision_id: str,
    target_language: str,
) -> dict[str, str]:
    active_terms = await active_article_glossary_terms(library, revision_id, target_language)
    translations: dict[str, str] = {}
    for variant in await list_translation_variants(library, revision_id, target_language):
        block_uid = block_uid_for_variant(variant)
        if not block_uid:
            continue
        if block_uid not in translations or variant.is_default:
            translations[block_uid] = apply_glossary_to_markdown(variant.raw_markdown, active_terms)
    return translations


def block_uid_for_variant(variant: TranslationVariant) -> str | None:
    block_uid = variant.metadata.get("block_uid")
    return block_uid if isinstance(block_uid, str) and block_uid else None


def anchor_for_block(block: DocumentBlock) -> str:
    return f'<a id="{block.block_uid}"></a>'


def write_bundle_zip(bundle_path: Path, output_path: Path) -> None:
    if output_path.exists():
        output_path.unlink()
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(bundle_path.rglob("*")):
            if not path.is_file() or path == output_path:
                continue
            archive.write(path, path.relative_to(bundle_path))


def write_export_manifest_entry(bundle_path: Path, result: ArticleExportResult) -> None:
    manifest = read_manifest(bundle_path)
    if manifest is None:
        return
    exports = manifest.generated_artifacts.get("exports")
    if not isinstance(exports, dict):
        exports = {}
    exports[result.kind.value] = {
        "path": result.path,
        "file_name": result.file_name,
        "target_language": result.target_language,
        "bytes_written": result.bytes_written,
        "created_at": result.created_at.isoformat(),
        "missing_translation_block_uids": result.missing_translation_block_uids,
        "metadata": result.metadata,
    }
    manifest.generated_artifacts["exports"] = exports
    write_manifest(bundle_path, manifest)


def export_metadata(bundle_path: Path, export_dir: Path, output_path: Path) -> dict[str, str]:
    return {
        "bundle_path": str(bundle_path),
        "export_dir": str(export_dir),
        "manifest_path": str(bundle_path / "manifest.json"),
        "relative_path": output_path.relative_to(bundle_path).as_posix(),
    }


def target_language_for_result(kind: ArticleExportKind, target_language: str) -> str | None:
    if kind in {ArticleExportKind.translated_markdown, ArticleExportKind.bilingual_markdown}:
        return target_language
    return None


def safe_file_token(value: str) -> str:
    token = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return token.strip(".-") or "target"
