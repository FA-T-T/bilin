from __future__ import annotations

import hashlib
import json
import re
import shutil
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

import aiosqlite

from bilin_api.content_notice import with_markdown_content_watermark
from bilin_api.database import init_global_db, init_library_db, open_db, utc_now
from bilin_api.repositories import get_library, list_libraries
from bilin_api.schemas import (
    ArticleDeleteResult,
    ArticleDocument,
    ArticleFamily,
    ArticleListItem,
    ArticleManifest,
    ArticleRevision,
    ArticleTranslationState,
    ArticleTranslationStatus,
    AssetRecord,
    ChatMessage,
    DocumentBlock,
    GlossaryTerm,
    JobStatus,
    JobType,
    Library,
    NotePatch,
    ReaderCard,
    ReaderCardPosition,
    ReaderCardSourceType,
    ReaderCardStatus,
    ReaderCardType,
    TranslationVariant,
)

TRANSLATABLE_BLOCK_TYPES = {"paragraph", "list", "figure", "table"}


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def sha256_text(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


async def resolve_library(identifier: str) -> Library:
    library = await get_library(identifier)
    if library is not None:
        return library
    target = Path(identifier).expanduser().resolve()
    for candidate in await list_libraries():
        if Path(candidate.path).expanduser().resolve() == target:
            return candidate
    msg = f"Library not found: {identifier}"
    raise ValueError(msg)


def library_db_path(library: Library) -> Path:
    return Path(library.path) / "library.sqlite"


def bundle_path_for_arxiv(library: Library, bare_id: str, version: str) -> Path:
    return Path(library.path) / "articles" / "arxiv" / bare_id / version


def bundle_path_for_upload(library: Library, upload_id: str, version: str) -> Path:
    return Path(library.path) / "articles" / "uploads" / upload_id / version


async def ensure_library_database(library: Library) -> Path:
    return await init_library_db(Path(library.path))


async def upsert_arxiv_revision(
    library: Library,
    bare_id: str,
    version: str,
    title: str | None,
    bundle_path: Path,
    metadata: dict[str, Any],
) -> tuple[ArticleFamily, ArticleRevision]:
    db_path = await ensure_library_database(library)
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        cursor = await conn.execute(
            "SELECT * FROM article_families WHERE source = ? AND external_id = ?",
            ("arxiv", bare_id),
        )
        family_row = await cursor.fetchone()
        if family_row is None:
            family_id = str(uuid4())
            await conn.execute(
                """
                INSERT INTO article_families(
                  id, source, external_id, title, metadata_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (family_id, "arxiv", bare_id, title, json.dumps(metadata), now, now),
            )
        else:
            family_id = family_row["id"]
            await conn.execute(
                """
                UPDATE article_families
                SET title = COALESCE(?, title), metadata_json = ?, updated_at = ?
                WHERE id = ?
                """,
                (title, json.dumps(metadata), now, family_id),
            )

        cursor = await conn.execute(
            "SELECT * FROM article_revisions WHERE family_id = ? AND version = ?",
            (family_id, version),
        )
        revision_row = await cursor.fetchone()
        revision_metadata = {"manifest_path": str(bundle_path / "manifest.json")}
        if revision_row is None:
            revision_id = str(uuid4())
            await conn.execute(
                """
                INSERT INTO article_revisions(
                  id, family_id, version, bundle_path, status, manifest_version,
                  metadata_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    revision_id,
                    family_id,
                    version,
                    str(bundle_path),
                    "imported",
                    1,
                    json.dumps(revision_metadata),
                    now,
                    now,
                ),
            )
        else:
            revision_id = revision_row["id"]
            await conn.execute(
                """
                UPDATE article_revisions
                SET bundle_path = ?, status = ?, metadata_json = ?, updated_at = ?
                WHERE id = ?
                """,
                (str(bundle_path), "imported", json.dumps(revision_metadata), now, revision_id),
            )
        await conn.commit()
    family = await get_article_family(library, family_id)
    revision = await get_article_revision(library, revision_id)
    if family is None or revision is None:
        msg = "Failed to read imported article revision"
        raise RuntimeError(msg)
    return family, revision


async def upsert_upload_revision(
    library: Library,
    upload_id: str,
    version: str,
    title: str | None,
    bundle_path: Path,
    metadata: dict[str, Any],
) -> tuple[ArticleFamily, ArticleRevision]:
    db_path = await ensure_library_database(library)
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        cursor = await conn.execute(
            "SELECT * FROM article_families WHERE source = ? AND external_id = ?",
            ("upload", upload_id),
        )
        family_row = await cursor.fetchone()
        if family_row is None:
            family_id = str(uuid4())
            await conn.execute(
                """
                INSERT INTO article_families(
                  id, source, external_id, title, metadata_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (family_id, "upload", upload_id, title, json.dumps(metadata), now, now),
            )
        else:
            family_id = family_row["id"]
            await conn.execute(
                """
                UPDATE article_families
                SET title = COALESCE(?, title), metadata_json = ?, updated_at = ?
                WHERE id = ?
                """,
                (title, json.dumps(metadata), now, family_id),
            )

        cursor = await conn.execute(
            "SELECT * FROM article_revisions WHERE family_id = ? AND version = ?",
            (family_id, version),
        )
        revision_row = await cursor.fetchone()
        revision_metadata = {"manifest_path": str(bundle_path / "manifest.json")}
        if revision_row is None:
            revision_id = str(uuid4())
            await conn.execute(
                """
                INSERT INTO article_revisions(
                  id, family_id, version, bundle_path, status, manifest_version,
                  metadata_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    revision_id,
                    family_id,
                    version,
                    str(bundle_path),
                    "imported",
                    1,
                    json.dumps(revision_metadata),
                    now,
                    now,
                ),
            )
        else:
            revision_id = revision_row["id"]
            await conn.execute(
                """
                UPDATE article_revisions
                SET bundle_path = ?, status = ?, metadata_json = ?, updated_at = ?
                WHERE id = ?
                """,
                (str(bundle_path), "imported", json.dumps(revision_metadata), now, revision_id),
            )
        await conn.commit()
    family = await get_article_family(library, family_id)
    revision = await get_article_revision(library, revision_id)
    if family is None or revision is None:
        msg = "Failed to read imported upload revision"
        raise RuntimeError(msg)
    return family, revision


async def get_article_family(library: Library, family_id: str) -> ArticleFamily | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM article_families WHERE id = ?", (family_id,))
        row = await cursor.fetchone()
    return _family_from_row(row) if row else None


async def get_article_revision(library: Library, revision_id: str) -> ArticleRevision | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM article_revisions WHERE id = ?", (revision_id,))
        row = await cursor.fetchone()
    return _revision_from_row(row) if row else None


async def list_article_items(
    library: Library,
    target_language: str = "zh-CN",
) -> list[ArticleListItem]:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT
              r.*, f.id AS family_id_value, f.source, f.external_id, f.title,
              f.metadata_json AS family_metadata_json,
              f.created_at AS family_created_at, f.updated_at AS family_updated_at,
              (SELECT COUNT(*) FROM blocks b WHERE b.article_revision_id = r.id) AS block_count,
              (SELECT COUNT(*) FROM assets a WHERE a.article_revision_id = r.id) AS asset_count
            FROM article_revisions r
            JOIN article_families f ON f.id = r.family_id
            ORDER BY r.updated_at DESC
            """
        )
        rows = await cursor.fetchall()
    revision_ids = [row["id"] for row in rows]
    translation_statuses = await article_translation_statuses(
        library,
        revision_ids,
        target_language,
    )
    items: list[ArticleListItem] = []
    for row in rows:
        revision = _revision_from_row(row)
        family = ArticleFamily(
            id=row["family_id_value"],
            source=row["source"],
            external_id=row["external_id"],
            title=row["title"],
            metadata=_loads(row["family_metadata_json"], {}),
            created_at=row["family_created_at"],
            updated_at=row["family_updated_at"],
        )
        items.append(
            ArticleListItem(
                article_revision=revision,
                family=family,
                manifest=read_manifest(Path(revision.bundle_path)),
                block_count=row["block_count"],
                asset_count=row["asset_count"],
                translation_status=translation_statuses.get(
                    revision.id,
                    ArticleTranslationStatus(target_language=target_language),
                ),
            )
        )
    return items


async def article_translation_statuses(
    library: Library,
    revision_ids: list[str],
    target_language: str = "zh-CN",
) -> dict[str, ArticleTranslationStatus]:
    if not revision_ids:
        return {}
    translatable: dict[str, set[str]] = {revision_id: set() for revision_id in revision_ids}
    translated: dict[str, set[str]] = {revision_id: set() for revision_id in revision_ids}
    invalid: dict[str, set[str]] = {revision_id: set() for revision_id in revision_ids}
    placeholders = ",".join("?" for _ in revision_ids)
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            f"""
            SELECT
              b.article_revision_id, b.id AS block_id, b.block_uid, b.content_hash,
              b.block_type, b.source_markdown, tv.id AS variant_id,
              tv.validation_status AS variant_validation_status,
              tv.metadata_json AS variant_metadata_json
            FROM blocks b
            LEFT JOIN translation_variants tv
              ON tv.block_id = b.id AND tv.target_language = ?
            WHERE b.article_revision_id IN ({placeholders})
            """,
            (target_language, *revision_ids),
        )
        rows = await cursor.fetchall()
    for row in rows:
        revision_id = row["article_revision_id"]
        if not _is_translatable_block_row(row):
            continue
        translatable[revision_id].add(row["block_id"])
        if (
            row["variant_id"]
            and row["variant_validation_status"] == "ok"
            and _translation_variant_row_matches_block(row)
        ):
            translated[revision_id].add(row["block_id"])
        elif row["variant_id"] and _translation_variant_row_matches_block(row):
            invalid[revision_id].add(row["block_id"])

    job_counts = await _translation_job_counts_by_revision(library, revision_ids, target_language)
    statuses: dict[str, ArticleTranslationStatus] = {}
    for revision_id in revision_ids:
        counts = job_counts.get(revision_id, Counter()).copy()
        invalid_blocks = len(invalid[revision_id] - translated[revision_id])
        counts[JobStatus.failed.value] = max(counts[JobStatus.failed.value], invalid_blocks)
        statuses[revision_id] = _build_article_translation_status(
            target_language=target_language,
            translatable_blocks=len(translatable[revision_id]),
            translated_blocks=len(translated[revision_id]),
            job_counts=counts,
        )
    return statuses


def _build_article_translation_status(
    *,
    target_language: str,
    translatable_blocks: int,
    translated_blocks: int,
    job_counts: Counter[str],
) -> ArticleTranslationStatus:
    queued_jobs = job_counts[JobStatus.queued.value]
    running_jobs = job_counts[JobStatus.running.value]
    paused_jobs = job_counts[JobStatus.paused.value]
    failed_jobs = job_counts[JobStatus.failed.value]
    if translatable_blocks == 0:
        state = ArticleTranslationState.not_required
    elif translated_blocks >= translatable_blocks:
        state = ArticleTranslationState.translated
    elif queued_jobs + running_jobs + paused_jobs > 0:
        state = ArticleTranslationState.translating
    elif failed_jobs > 0:
        state = ArticleTranslationState.failed
    elif translated_blocks > 0:
        state = ArticleTranslationState.partial
    else:
        state = ArticleTranslationState.not_started
    return ArticleTranslationStatus(
        target_language=target_language,
        status=state,
        translatable_blocks=translatable_blocks,
        translated_blocks=translated_blocks,
        queued_jobs=queued_jobs,
        running_jobs=running_jobs,
        paused_jobs=paused_jobs,
        failed_jobs=failed_jobs,
    )


async def _translation_job_counts_by_revision(
    library: Library,
    revision_ids: list[str],
    target_language: str,
) -> dict[str, Counter[str]]:
    revision_set = set(revision_ids)
    counts: dict[str, Counter[str]] = {revision_id: Counter() for revision_id in revision_ids}
    global_db_path = await init_global_db()
    async with open_db(global_db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT status, payload_json
            FROM jobs
            WHERE type = ? AND status IN (?, ?, ?, ?) AND payload_json LIKE ?
            """,
            (
                JobType.translate_block.value,
                JobStatus.queued.value,
                JobStatus.running.value,
                JobStatus.paused.value,
                JobStatus.failed.value,
                f"%{library.id}%",
            ),
        )
        rows = await cursor.fetchall()
    for row in rows:
        payload = _loads(row["payload_json"], {})
        revision_id = payload.get("article_revision_id")
        if (
            payload.get("library_id") == library.id
            and revision_id in revision_set
            and payload.get("target_language") == target_language
        ):
            counts[revision_id][row["status"]] += 1
    return counts


def _is_translatable_block_row(row: aiosqlite.Row) -> bool:
    source_markdown = row["source_markdown"] or ""
    return row["block_type"] in TRANSLATABLE_BLOCK_TYPES and bool(source_markdown.strip())


def _translation_variant_row_matches_block(row: aiosqlite.Row) -> bool:
    metadata = _loads(row["variant_metadata_json"], {})
    cached_hash = metadata.get("content_hash")
    cached_block_uid = metadata.get("block_uid")
    return (
        not isinstance(cached_hash, str)
        or cached_hash == row["content_hash"]
        or cached_block_uid == row["block_uid"]
    )


async def get_article_item(
    library: Library,
    revision_id: str,
    target_language: str = "zh-CN",
) -> ArticleListItem | None:
    items = await list_article_items(library, target_language)
    return next((item for item in items if item.article_revision.id == revision_id), None)


async def archive_article_revision(library: Library, revision_id: str) -> ArticleListItem | None:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        return None
    db_path = await ensure_library_database(library)
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute(
            "UPDATE article_revisions SET status = ?, updated_at = ? WHERE id = ?",
            ("archived", now, revision_id),
        )
        await conn.commit()
    return await get_article_item(library, revision_id)


async def delete_article_revision(library: Library, revision_id: str) -> ArticleDeleteResult | None:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        return None
    bundle_path = Path(revision.bundle_path)
    db_path = await ensure_library_database(library)
    removed_family = False
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        cursor = await conn.execute(
            "SELECT id FROM blocks WHERE article_revision_id = ?",
            (revision_id,),
        )
        block_ids = [row["id"] for row in await cursor.fetchall()]
        if block_ids:
            placeholders = ",".join("?" for _ in block_ids)
            await conn.execute(
                f"DELETE FROM translation_variants WHERE block_id IN ({placeholders})",
                tuple(block_ids),
            )
            await conn.execute(
                f"DELETE FROM block_embeddings WHERE block_id IN ({placeholders})",
                tuple(block_ids),
            )
            await conn.execute(
                f"DELETE FROM blocks WHERE id IN ({placeholders})",
                tuple(block_ids),
            )
        await conn.execute("DELETE FROM block_fts WHERE article_revision_id = ?", (revision_id,))
        await conn.execute(
            "DELETE FROM block_embeddings WHERE article_revision_id = ?",
            (revision_id,),
        )
        await conn.execute("DELETE FROM assets WHERE article_revision_id = ?", (revision_id,))
        await conn.execute(
            "DELETE FROM chat_messages WHERE article_revision_id = ?", (revision_id,)
        )
        await conn.execute("DELETE FROM note_patches WHERE article_revision_id = ?", (revision_id,))
        await conn.execute("DELETE FROM reader_cards WHERE article_revision_id = ?", (revision_id,))
        await _delete_article_scoped_glossary_terms(conn, revision_id)
        await conn.execute("DELETE FROM article_revisions WHERE id = ?", (revision_id,))
        cursor = await conn.execute(
            "SELECT COUNT(*) AS revision_count FROM article_revisions WHERE family_id = ?",
            (revision.family_id,),
        )
        row = await cursor.fetchone()
        if row is not None and row["revision_count"] == 0:
            await conn.execute("DELETE FROM article_families WHERE id = ?", (revision.family_id,))
            removed_family = True
        await conn.commit()
    if bundle_path.exists():
        shutil.rmtree(bundle_path)
    return ArticleDeleteResult(
        library_id=library.id,
        article_family_id=revision.family_id,
        article_revision_id=revision_id,
        bundle_path=str(bundle_path),
        deleted_cache=not bundle_path.exists(),
        removed_family=removed_family,
    )


async def _delete_article_scoped_glossary_terms(
    conn: aiosqlite.Connection,
    revision_id: str,
) -> None:
    cursor = await conn.execute("SELECT id, metadata_json FROM glossary_terms")
    rows = await cursor.fetchall()
    term_ids = [
        row["id"]
        for row in rows
        if _loads(row["metadata_json"], {}).get("article_revision_id") == revision_id
    ]
    if not term_ids:
        return
    placeholders = ",".join("?" for _ in term_ids)
    await conn.execute(
        f"DELETE FROM glossary_terms WHERE id IN ({placeholders})",
        tuple(term_ids),
    )


async def replace_document(
    library: Library,
    revision: ArticleRevision,
    manifest: ArticleManifest,
    blocks: list[DocumentBlock],
    assets: list[AssetRecord],
    source_md: str,
) -> None:
    db_path = await ensure_library_database(library)
    existing_blocks = await list_blocks(library, revision.id)
    existing_by_uid = {block.block_uid: block for block in existing_blocks}
    stored_blocks = [
        block.model_copy(
            update={
                "id": existing_by_uid[block.block_uid].id,
                "created_at": existing_by_uid[block.block_uid].created_at,
            }
        )
        if block.block_uid in existing_by_uid
        else block
        for block in blocks
    ]
    bundle_path = Path(revision.bundle_path)
    document_dir = bundle_path / "document"
    document_dir.mkdir(parents=True, exist_ok=True)
    (document_dir / "document.json").write_text(
        ArticleDocument(
            article_revision=revision,
            manifest=manifest,
            blocks=stored_blocks,
            assets=assets,
        ).model_dump_json(indent=2),
        encoding="utf-8",
    )
    (document_dir / "source.md").write_text(source_md, encoding="utf-8")
    manifest.generated_artifacts.update(
        {
            "document_json": str(document_dir / "document.json"),
            "source_md": str(document_dir / "source.md"),
        }
    )
    write_manifest(bundle_path, manifest)
    now = utc_now()
    incoming_uids = {block.block_uid for block in stored_blocks}
    stale_block_ids = [
        block.id for block in existing_blocks if block.block_uid not in incoming_uids
    ]
    unique_blocks_by_hash = _unique_blocks_by_content_hash(stored_blocks)
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        await conn.execute("DELETE FROM assets WHERE article_revision_id = ?", (revision.id,))
        await conn.execute("DELETE FROM block_fts WHERE article_revision_id = ?", (revision.id,))
        if stale_block_ids:
            placeholders = ",".join("?" for _ in stale_block_ids)
            await conn.execute(
                f"DELETE FROM translation_variants WHERE block_id IN ({placeholders})",
                stale_block_ids,
            )
            await conn.execute(
                f"DELETE FROM block_embeddings WHERE block_id IN ({placeholders})",
                stale_block_ids,
            )
            await conn.execute(
                f"DELETE FROM blocks WHERE id IN ({placeholders})",
                stale_block_ids,
            )
        for block in stored_blocks:
            await conn.execute(
                """
                INSERT INTO blocks(
                  id, article_revision_id, block_uid, structural_path, block_type,
                  parent_uid, content_hash, context_hash, source_markdown, source_latex,
                  metadata_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(article_revision_id, block_uid) DO UPDATE SET
                  structural_path = excluded.structural_path,
                  block_type = excluded.block_type,
                  parent_uid = excluded.parent_uid,
                  content_hash = excluded.content_hash,
                  context_hash = excluded.context_hash,
                  source_markdown = excluded.source_markdown,
                  source_latex = excluded.source_latex,
                  metadata_json = excluded.metadata_json,
                  updated_at = excluded.updated_at
                """,
                (
                    block.id,
                    block.article_revision_id,
                    block.block_uid,
                    block.structural_path,
                    block.block_type,
                    block.parent_uid,
                    block.content_hash,
                    block.context_hash,
                    block.source_markdown,
                    block.source_latex,
                    json.dumps(block.metadata),
                    block.created_at.isoformat(),
                    block.updated_at.isoformat(),
                ),
            )
            if block.source_markdown.strip():
                await conn.execute(
                    """
                    INSERT INTO block_fts(
                      block_id, article_revision_id, block_uid, source_markdown
                    )
                    VALUES (?, ?, ?, ?)
                    """,
                    (block.id, block.article_revision_id, block.block_uid, block.source_markdown),
                )
        await _reconcile_translation_variants_after_reparse(
            conn,
            revision.id,
            unique_blocks_by_hash,
            now,
        )
        for asset in assets:
            await conn.execute(
                """
                INSERT INTO assets(
                  id, article_revision_id, asset_id, kind, source_path, web_path, caption,
                  label, metadata_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    asset.id,
                    asset.article_revision_id,
                    asset.asset_id,
                    asset.kind,
                    asset.source_path,
                    asset.web_path,
                    asset.caption,
                    asset.label,
                    json.dumps(asset.metadata),
                    asset.created_at.isoformat(),
                    asset.updated_at.isoformat(),
                ),
            )
        await conn.execute(
            "UPDATE article_revisions SET status = ?, updated_at = ? WHERE id = ?",
            ("parsed", now, revision.id),
        )
        await conn.commit()


def _unique_blocks_by_content_hash(blocks: list[DocumentBlock]) -> dict[str, DocumentBlock]:
    blocks_by_hash: dict[str, DocumentBlock | None] = {}
    for block in blocks:
        existing = blocks_by_hash.get(block.content_hash)
        if existing is None and block.content_hash in blocks_by_hash:
            continue
        if existing is not None:
            blocks_by_hash[block.content_hash] = None
        else:
            blocks_by_hash[block.content_hash] = block
    return {content_hash: block for content_hash, block in blocks_by_hash.items() if block}


async def _reconcile_translation_variants_after_reparse(
    conn: aiosqlite.Connection,
    revision_id: str,
    unique_blocks_by_hash: dict[str, DocumentBlock],
    now: str,
) -> None:
    cursor = await conn.execute(
        """
        SELECT
          tv.id, tv.block_id, tv.target_language, tv.metadata_json,
          b.block_uid AS current_block_uid,
          b.content_hash AS current_content_hash
        FROM translation_variants tv
        JOIN blocks b ON b.id = tv.block_id
        WHERE b.article_revision_id = ?
        """,
        (revision_id,),
    )
    rows = await cursor.fetchall()
    for row in rows:
        metadata = _loads(row["metadata_json"], {})
        cached_hash = metadata.get("content_hash")
        if not isinstance(cached_hash, str) or not cached_hash:
            continue
        if cached_hash == row["current_content_hash"]:
            if metadata.get("block_uid") == row["current_block_uid"]:
                continue
            metadata["block_uid"] = row["current_block_uid"]
            await conn.execute(
                """
                UPDATE translation_variants
                SET metadata_json = ?, updated_at = ?
                WHERE id = ?
                """,
                (json.dumps(metadata), now, row["id"]),
            )
            continue
        target_block = unique_blocks_by_hash.get(cached_hash)
        if target_block is None:
            continue
        metadata["block_uid"] = target_block.block_uid
        metadata["content_hash"] = target_block.content_hash
        await conn.execute(
            """
            UPDATE translation_variants
            SET block_id = ?, metadata_json = ?, updated_at = ?
            WHERE id = ?
            """,
            (target_block.id, json.dumps(metadata), now, row["id"]),
        )


async def mark_revision_status(
    library: Library,
    revision_id: str,
    status: str,
    manifest: ArticleManifest | None = None,
) -> None:
    db_path = await ensure_library_database(library)
    now = utc_now()
    if manifest is not None:
        revision = await get_article_revision(library, revision_id)
        if revision is not None:
            write_manifest(Path(revision.bundle_path), manifest)
    async with open_db(db_path) as conn:
        await conn.execute(
            "UPDATE article_revisions SET status = ?, updated_at = ? WHERE id = ?",
            (status, now, revision_id),
        )
        await conn.commit()


async def read_article_document(library: Library, revision_id: str) -> ArticleDocument | None:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        return None
    manifest = read_manifest(Path(revision.bundle_path))
    if manifest is None:
        manifest = empty_manifest(revision)
    blocks = await list_blocks(library, revision.id)
    assets = await list_assets(library, revision.id)
    return ArticleDocument(
        article_revision=revision,
        manifest=manifest,
        blocks=blocks,
        assets=assets,
    )


async def list_blocks(library: Library, revision_id: str) -> list[DocumentBlock]:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            "SELECT * FROM blocks WHERE article_revision_id = ? ORDER BY structural_path",
            (revision_id,),
        )
        rows = await cursor.fetchall()
    return [_block_from_row(row) for row in rows]


async def list_assets(library: Library, revision_id: str) -> list[AssetRecord]:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            "SELECT * FROM assets WHERE article_revision_id = ? ORDER BY asset_id",
            (revision_id,),
        )
        rows = await cursor.fetchall()
    return [_asset_from_row(row) for row in rows]


async def get_block_by_uid(
    library: Library,
    revision_id: str,
    block_uid: str,
) -> DocumentBlock | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT * FROM blocks
            WHERE article_revision_id = ? AND block_uid = ?
            """,
            (revision_id, block_uid),
        )
        row = await cursor.fetchone()
    return _block_from_row(row) if row else None


async def get_block_by_id(library: Library, block_id: str) -> DocumentBlock | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM blocks WHERE id = ?", (block_id,))
        row = await cursor.fetchone()
    return _block_from_row(row) if row else None


async def search_blocks(
    library: Library,
    revision_id: str,
    query: str,
    limit: int = 8,
) -> list[tuple[DocumentBlock, float]]:
    db_path = await ensure_library_database(library)
    fts_query = to_fts_query(query)
    if not fts_query:
        return []
    async with open_db(db_path) as conn:
        try:
            cursor = await conn.execute(
                """
                SELECT b.*, bm25(block_fts) AS score
                FROM block_fts
                JOIN blocks b ON b.id = block_fts.block_id
                WHERE block_fts MATCH ? AND block_fts.article_revision_id = ?
                ORDER BY score
                LIMIT ?
                """,
                (fts_query, revision_id, limit),
            )
            rows = await cursor.fetchall()
        except aiosqlite.OperationalError:
            rows = []
    if rows:
        return [(_block_from_row(row), float(row["score"])) for row in rows]
    return await fallback_search_blocks(library, revision_id, query, limit)


async def fallback_search_blocks(
    library: Library,
    revision_id: str,
    query: str,
    limit: int = 8,
) -> list[tuple[DocumentBlock, float]]:
    tokens = query_tokens(query)
    if not tokens:
        return []
    matches: list[tuple[DocumentBlock, float]] = []
    for block in await list_blocks(library, revision_id):
        text = block.source_markdown.casefold()
        score = float(sum(text.count(token.casefold()) for token in tokens))
        if score > 0:
            matches.append((block, -score))
    return sorted(matches, key=lambda item: item[1])[:limit]


async def list_translation_variants(
    library: Library,
    revision_id: str,
    target_language: str | None = None,
) -> list[TranslationVariant]:
    db_path = await ensure_library_database(library)
    params: tuple[str, ...]
    where = "b.article_revision_id = ?"
    params = (revision_id,)
    if target_language:
        where += " AND tv.target_language = ?"
        params = (revision_id, target_language)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            f"""
            SELECT
              tv.*,
              b.block_uid AS current_block_uid,
              b.content_hash AS current_content_hash
            FROM translation_variants tv
            JOIN blocks b ON b.id = tv.block_id
            WHERE {where}
            ORDER BY b.structural_path, tv.updated_at DESC
            """,
            params,
        )
        rows = await cursor.fetchall()
    return [
        _translation_variant_from_row(row)
        for row in rows
        if _translation_variant_matches_current_block(row)
    ]


def _translation_variant_matches_current_block(row: aiosqlite.Row) -> bool:
    metadata = _loads(row["metadata_json"], {})
    cached_hash = metadata.get("content_hash")
    cached_block_uid = metadata.get("block_uid")
    return (
        not isinstance(cached_hash, str)
        or cached_hash == row["current_content_hash"]
        or cached_block_uid == row["current_block_uid"]
    )


async def find_cached_translation_variant(
    library: Library,
    block: DocumentBlock,
    target_language: str,
    provider_profile_id: str,
    model: str | None,
    glossary_version: str | None,
    context_hash: str,
) -> TranslationVariant | None:
    variants = await list_translation_variants(library, block.article_revision_id, target_language)
    for variant in variants:
        metadata = variant.metadata
        if (
            variant.block_id == block.id
            and variant.provider_profile_id == provider_profile_id
            and variant.model == model
            and variant.glossary_version == glossary_version
            and metadata.get("content_hash") == block.content_hash
            and metadata.get("context_hash") == context_hash
            and variant.validation_status == "ok"
        ):
            return variant
    return None


async def create_translation_variant(
    library: Library,
    block: DocumentBlock,
    target_language: str,
    raw_markdown: str,
    provider_profile_id: str | None,
    model: str | None,
    glossary_version: str | None,
    metadata: dict[str, Any] | None = None,
    is_default: bool = True,
    validation_status: str = "ok",
) -> TranslationVariant:
    db_path = await ensure_library_database(library)
    now = utc_now()
    variant_id = str(uuid4())
    metadata_payload = metadata or {}
    metadata_payload.setdefault("block_uid", block.block_uid)
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        if is_default:
            await conn.execute(
                """
                UPDATE translation_variants
                SET is_default = 0, updated_at = ?
                WHERE block_id = ? AND target_language = ?
                """,
                (now, block.id, target_language),
            )
        await conn.execute(
            """
            INSERT INTO translation_variants(
              id, block_id, target_language, provider_profile_id, model, raw_markdown,
              render_ast_json, validation_status, glossary_version, is_default,
              metadata_json, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                variant_id,
                block.id,
                target_language,
                provider_profile_id,
                model,
                raw_markdown,
                None,
                validation_status,
                glossary_version,
                1 if is_default else 0,
                json.dumps(metadata_payload),
                now,
                now,
            ),
        )
        await conn.commit()
    variant = await get_translation_variant(library, variant_id)
    if variant is None:
        msg = "Created translation variant could not be read back"
        raise RuntimeError(msg)
    return variant


async def get_translation_variant(
    library: Library,
    variant_id: str,
) -> TranslationVariant | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            "SELECT * FROM translation_variants WHERE id = ?",
            (variant_id,),
        )
        row = await cursor.fetchone()
    return _translation_variant_from_row(row) if row else None


async def set_translation_variant_default(
    library: Library,
    revision_id: str,
    variant_id: str,
) -> TranslationVariant | None:
    db_path = await ensure_library_database(library)
    now = utc_now()
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT tv.*
            FROM translation_variants tv
            JOIN blocks b ON b.id = tv.block_id
            WHERE tv.id = ? AND b.article_revision_id = ?
            """,
            (variant_id, revision_id),
        )
        row = await cursor.fetchone()
        if row is None:
            return None
        block_id = row["block_id"]
        target_language = row["target_language"]
        await conn.execute("BEGIN")
        await conn.execute(
            """
            UPDATE translation_variants
            SET is_default = 0, updated_at = ?
            WHERE block_id = ? AND target_language = ?
            """,
            (now, block_id, target_language),
        )
        await conn.execute(
            """
            UPDATE translation_variants
            SET is_default = 1, updated_at = ?
            WHERE id = ?
            """,
            (now, variant_id),
        )
        await conn.commit()
    return await get_translation_variant(library, variant_id)


async def list_chat_messages(library: Library, revision_id: str) -> list[ChatMessage]:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT * FROM chat_messages
            WHERE article_revision_id = ?
            ORDER BY created_at
            """,
            (revision_id,),
        )
        rows = await cursor.fetchall()
    return [_chat_message_from_row(row) for row in rows]


async def get_chat_message(
    library: Library,
    revision_id: str,
    message_id: str,
) -> ChatMessage | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT *
            FROM chat_messages
            WHERE id = ? AND article_revision_id = ?
            """,
            (message_id, revision_id),
        )
        row = await cursor.fetchone()
    return _chat_message_from_row(row) if row else None


async def create_chat_message(
    library: Library,
    revision_id: str,
    role: str,
    content: str,
    source_refs: list[str] | None = None,
    external_refs: list[dict[str, Any]] | None = None,
    metadata: dict[str, Any] | None = None,
) -> ChatMessage:
    db_path = await ensure_library_database(library)
    now = utc_now()
    message_id = str(uuid4())
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO chat_messages(
              id, article_revision_id, role, content, source_refs_json,
              external_refs_json, metadata_json, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                message_id,
                revision_id,
                role,
                content,
                json.dumps(source_refs or []),
                json.dumps(external_refs or []),
                json.dumps(metadata or {}),
                now,
            ),
        )
        await conn.commit()
    messages = await list_chat_messages(library, revision_id)
    for message in messages:
        if message.id == message_id:
            return message
    msg = "Created chat message could not be read back"
    raise RuntimeError(msg)


async def list_note_patches(library: Library, revision_id: str) -> list[NotePatch]:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT * FROM note_patches
            WHERE article_revision_id = ?
            ORDER BY updated_at DESC
            """,
            (revision_id,),
        )
        rows = await cursor.fetchall()
    return [_note_patch_from_row(row) for row in rows]


async def get_note_patch(library: Library, patch_id: str) -> NotePatch | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM note_patches WHERE id = ?", (patch_id,))
        row = await cursor.fetchone()
    return _note_patch_from_row(row) if row else None


async def create_note_patch(
    library: Library,
    revision_id: str,
    title: str,
    patch_markdown: str,
    source_refs: list[str] | None = None,
    metadata: dict[str, Any] | None = None,
    status: str = "proposed",
) -> NotePatch:
    db_path = await ensure_library_database(library)
    now = utc_now()
    patch_id = str(uuid4())
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO note_patches(
              id, article_revision_id, status, title, patch_markdown,
              source_refs_json, metadata_json, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                patch_id,
                revision_id,
                status,
                title,
                patch_markdown,
                json.dumps(source_refs or []),
                json.dumps(metadata or {}),
                now,
                now,
            ),
        )
        await conn.commit()
    patch = await get_note_patch(library, patch_id)
    if patch is None:
        msg = "Created note patch could not be read back"
        raise RuntimeError(msg)
    return patch


async def update_note_patch(
    library: Library,
    patch_id: str,
    title: str | None = None,
    patch_markdown: str | None = None,
    status: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> NotePatch | None:
    current = await get_note_patch(library, patch_id)
    if current is None:
        return None
    metadata_payload = current.metadata.copy()
    if metadata is not None:
        metadata_payload.update(metadata)
    now = utc_now()
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE note_patches
            SET title = ?, patch_markdown = ?, status = ?, metadata_json = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                title if title is not None else current.title,
                patch_markdown if patch_markdown is not None else current.patch_markdown,
                status if status is not None else current.status,
                json.dumps(metadata_payload),
                now,
                patch_id,
            ),
        )
        await conn.commit()
    return await get_note_patch(library, patch_id)


async def write_lecture_notes(library: Library, revision_id: str) -> Path:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Article revision not found: {revision_id}"
        raise ValueError(msg)
    accepted = [
        patch
        for patch in await list_note_patches(library, revision_id)
        if patch.status == "accepted"
    ]
    accepted = sorted(accepted, key=lambda patch: patch.updated_at)
    notes_dir = Path(revision.bundle_path) / "notes"
    notes_dir.mkdir(parents=True, exist_ok=True)
    notes_path = notes_dir / "lecture-notes.md"
    content_parts = [f"# Lecture Notes\n\nArticle revision: `{revision_id}`"]
    for patch in accepted:
        refs = ", ".join(f"`{ref}`" for ref in patch.source_refs) or "none"
        content_parts.append(
            "\n".join(
                [
                    f"<!-- bilin-note-patch:{patch.id} -->",
                    f"## {patch.title}",
                    "",
                    patch.patch_markdown.strip(),
                    "",
                    f"Source refs: {refs}",
                    f"<!-- /bilin-note-patch:{patch.id} -->",
                ]
            )
        )
    notes_path.write_text(
        with_markdown_content_watermark("\n\n".join(content_parts).strip() + "\n"),
        encoding="utf-8",
    )
    return notes_path


async def list_glossary_terms(
    library: Library,
    revision_id: str | None = None,
    target_language: str | None = None,
    status: str | None = None,
    scope: str | None = None,
) -> list[GlossaryTerm]:
    db_path = await ensure_library_database(library)
    clauses: list[str] = []
    params: list[str] = []
    if scope:
        clauses.append("scope = ?")
        params.append(scope)
    if status:
        clauses.append("status = ?")
        params.append(status)
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            f"SELECT * FROM glossary_terms {where} ORDER BY updated_at DESC",
            tuple(params),
        )
        rows = await cursor.fetchall()
    terms = [_glossary_term_from_row(row) for row in rows]
    if revision_id is not None:
        terms = [
            term
            for term in terms
            if term.metadata.get("article_revision_id") == revision_id or term.scope != "article"
        ]
    if target_language is not None:
        terms = [
            term
            for term in terms
            if term.metadata.get("target_language") in {None, target_language}
            or term.language_direction.endswith(f"->{target_language}")
        ]
    return terms


async def get_glossary_term(library: Library, term_id: str) -> GlossaryTerm | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM glossary_terms WHERE id = ?", (term_id,))
        row = await cursor.fetchone()
    return _glossary_term_from_row(row) if row else None


async def find_glossary_term_by_source(
    library: Library,
    revision_id: str,
    source_term: str,
    target_language: str,
    scope: str = "article",
) -> GlossaryTerm | None:
    normalized = " ".join(source_term.casefold().split())
    terms = await list_glossary_terms(
        library,
        revision_id=revision_id,
        target_language=target_language,
        scope=scope,
    )
    for term in terms:
        term_normalized = str(term.metadata.get("normalized_source_term") or "").casefold()
        fallback = " ".join(term.source_term.casefold().split())
        if term_normalized == normalized or fallback == normalized:
            return term
    return None


async def create_glossary_term(
    library: Library,
    scope: str,
    source_term: str,
    target_term: str,
    language_direction: str,
    status: str,
    metadata: dict[str, Any] | None = None,
) -> GlossaryTerm:
    db_path = await ensure_library_database(library)
    now = utc_now()
    term_id = str(uuid4())
    metadata_payload = metadata or {}
    metadata_payload.setdefault("normalized_source_term", " ".join(source_term.casefold().split()))
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO glossary_terms(
              id, scope, source_term, target_term, language_direction, status,
              metadata_json, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                term_id,
                scope,
                source_term,
                target_term,
                language_direction,
                status,
                json.dumps(metadata_payload),
                now,
                now,
            ),
        )
        await conn.commit()
    term = await get_glossary_term(library, term_id)
    if term is None:
        msg = "Created glossary term could not be read back"
        raise RuntimeError(msg)
    return term


async def update_glossary_term(
    library: Library,
    term_id: str,
    target_term: str | None = None,
    status: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> GlossaryTerm | None:
    current = await get_glossary_term(library, term_id)
    if current is None:
        return None
    metadata_payload = current.metadata.copy()
    if metadata is not None:
        metadata_payload.update(metadata)
    if target_term is not None and target_term != current.target_term:
        previous = metadata_payload.get("previous_target_terms")
        previous_terms = previous if isinstance(previous, list) else []
        if current.target_term and current.target_term not in previous_terms:
            previous_terms.append(current.target_term)
        metadata_payload["previous_target_terms"] = previous_terms
    now = utc_now()
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE glossary_terms
            SET target_term = ?, status = ?, metadata_json = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                target_term if target_term is not None else current.target_term,
                status if status is not None else current.status,
                json.dumps(metadata_payload),
                now,
                term_id,
            ),
        )
        await conn.commit()
    return await get_glossary_term(library, term_id)


async def list_reader_cards(
    library: Library,
    revision_id: str,
    target_language: str | None = None,
    include_archived: bool = False,
) -> list[ReaderCard]:
    db_path = await ensure_library_database(library)
    clauses = ["article_revision_id = ?"]
    params: list[str] = [revision_id]
    if target_language is not None:
        clauses.append("target_language = ?")
        params.append(target_language)
    if not include_archived:
        clauses.append("status != ?")
        params.append(ReaderCardStatus.archived.value)
    where = " AND ".join(clauses)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            f"""
            SELECT * FROM reader_cards
            WHERE {where}
            ORDER BY anchor_block_uid, updated_at DESC
            """,
            tuple(params),
        )
        rows = await cursor.fetchall()
    return [_reader_card_from_row(row) for row in rows]


async def get_reader_card(
    library: Library,
    revision_id: str,
    card_id: str,
) -> ReaderCard | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT * FROM reader_cards
            WHERE id = ? AND article_revision_id = ?
            """,
            (card_id, revision_id),
        )
        row = await cursor.fetchone()
    return _reader_card_from_row(row) if row else None


async def find_reader_card_by_canonical_key(
    library: Library,
    revision_id: str,
    canonical_key: str,
    target_language: str,
) -> ReaderCard | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT * FROM reader_cards
            WHERE article_revision_id = ?
              AND canonical_key = ?
              AND target_language = ?
              AND status != ?
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (revision_id, canonical_key, target_language, ReaderCardStatus.archived.value),
        )
        row = await cursor.fetchone()
    return _reader_card_from_row(row) if row else None


async def find_shared_reader_card(
    library: Library,
    canonical_key: str,
    target_language: str,
) -> ReaderCard | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT * FROM reader_cards
            WHERE canonical_key = ?
              AND target_language = ?
              AND status != ?
              AND body_markdown != ''
            ORDER BY
              CASE status WHEN 'pinned' THEN 0 WHEN 'exported' THEN 1 ELSE 2 END,
              updated_at DESC
            LIMIT 1
            """,
            (canonical_key, target_language, ReaderCardStatus.archived.value),
        )
        row = await cursor.fetchone()
    return _reader_card_from_row(row) if row else None


async def create_reader_card(
    library: Library,
    *,
    revision_id: str,
    card_type: ReaderCardType,
    anchor_block_uid: str,
    anchor_text: str,
    canonical_key: str,
    abbreviation: str | None,
    full_form: str | None,
    title: str,
    body_markdown: str,
    target_language: str,
    source_type: ReaderCardSourceType,
    source_url: str | None = None,
    position: ReaderCardPosition = ReaderCardPosition.right,
    status: ReaderCardStatus = ReaderCardStatus.candidate,
    metadata: dict[str, Any] | None = None,
) -> ReaderCard:
    db_path = await ensure_library_database(library)
    now = utc_now()
    card_id = str(uuid4())
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO reader_cards(
              id, article_revision_id, card_type, anchor_block_uid, anchor_text, canonical_key,
              abbreviation, full_form, title, body_markdown, target_language, source_type,
              source_url, position, status, metadata_json, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                card_id,
                revision_id,
                card_type.value,
                anchor_block_uid,
                anchor_text,
                canonical_key,
                abbreviation,
                full_form,
                title,
                body_markdown,
                target_language,
                source_type.value,
                source_url,
                position.value,
                status.value,
                json.dumps(metadata or {}),
                now,
                now,
            ),
        )
        await conn.commit()
    card = await get_reader_card(library, revision_id, card_id)
    if card is None:
        msg = "Created reader card could not be read back"
        raise RuntimeError(msg)
    return card


async def update_reader_card(
    library: Library,
    revision_id: str,
    card_id: str,
    *,
    anchor_text: str | None = None,
    abbreviation: str | None = None,
    full_form: str | None = None,
    title: str | None = None,
    body_markdown: str | None = None,
    source_url: str | None = None,
    position: ReaderCardPosition | None = None,
    status: ReaderCardStatus | None = None,
    metadata: dict[str, Any] | None = None,
    canonical_key: str | None = None,
    source_type: ReaderCardSourceType | None = None,
) -> ReaderCard | None:
    current = await get_reader_card(library, revision_id, card_id)
    if current is None:
        return None
    metadata_payload = current.metadata.copy()
    if metadata is not None:
        metadata_payload.update(metadata)
    if body_markdown is not None and body_markdown != current.body_markdown:
        metadata_payload["user_edited"] = True
    now = utc_now()
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE reader_cards
            SET anchor_text = ?, canonical_key = ?, abbreviation = ?, full_form = ?, title = ?,
                body_markdown = ?, source_type = ?, source_url = ?, position = ?, status = ?,
                metadata_json = ?, updated_at = ?
            WHERE id = ? AND article_revision_id = ?
            """,
            (
                anchor_text if anchor_text is not None else current.anchor_text,
                canonical_key if canonical_key is not None else current.canonical_key,
                abbreviation if abbreviation is not None else current.abbreviation,
                full_form if full_form is not None else current.full_form,
                title if title is not None else current.title,
                body_markdown if body_markdown is not None else current.body_markdown,
                (source_type if source_type is not None else current.source_type).value,
                source_url if source_url is not None else current.source_url,
                (position if position is not None else current.position).value,
                (status if status is not None else current.status).value,
                json.dumps(metadata_payload),
                now,
                card_id,
                revision_id,
            ),
        )
        await conn.commit()
    return await get_reader_card(library, revision_id, card_id)


async def archive_reader_card(
    library: Library,
    revision_id: str,
    card_id: str,
) -> ReaderCard | None:
    return await update_reader_card(
        library,
        revision_id,
        card_id,
        status=ReaderCardStatus.archived,
    )


def read_manifest(bundle_path: Path) -> ArticleManifest | None:
    path = bundle_path / "manifest.json"
    if not path.exists():
        return None
    return ArticleManifest.model_validate_json(path.read_text(encoding="utf-8"))


def write_manifest(bundle_path: Path, manifest: ArticleManifest) -> None:
    bundle_path.mkdir(parents=True, exist_ok=True)
    (bundle_path / "manifest.json").write_text(manifest.model_dump_json(indent=2), encoding="utf-8")


def empty_manifest(revision: ArticleRevision) -> ArticleManifest:
    return ArticleManifest(article_revision_id=revision.id, source="unknown")


def make_block(
    revision_id: str,
    block_uid: str,
    structural_path: str,
    block_type: str,
    source_markdown: str,
    source_latex: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> DocumentBlock:
    now = datetime.now(UTC)
    return DocumentBlock(
        id=str(uuid4()),
        article_revision_id=revision_id,
        block_uid=block_uid,
        structural_path=structural_path,
        block_type=block_type,
        parent_uid=None,
        content_hash=sha256_text(" ".join(source_markdown.split())),
        context_hash=None,
        source_markdown=source_markdown,
        source_latex=source_latex,
        metadata=metadata or {},
        created_at=now,
        updated_at=now,
    )


def make_asset(
    revision_id: str,
    asset_id: str,
    kind: str,
    caption: str | None = None,
    label: str | None = None,
    source_path: str | None = None,
    web_path: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> AssetRecord:
    now = datetime.now(UTC)
    return AssetRecord(
        id=str(uuid4()),
        article_revision_id=revision_id,
        asset_id=asset_id,
        kind=kind,
        source_path=source_path,
        web_path=web_path,
        caption=caption,
        label=label,
        metadata=metadata or {},
        created_at=now,
        updated_at=now,
    )


def to_fts_query(query: str) -> str:
    tokens = query_tokens(query)
    if not tokens:
        return ""
    return " OR ".join(tokens[:12])


def query_tokens(query: str) -> list[str]:
    return [token for token in re.findall(r"[\w]+", query, flags=re.UNICODE) if len(token) > 1]


def _family_from_row(row: aiosqlite.Row) -> ArticleFamily:
    return ArticleFamily(
        id=row["id"],
        source=row["source"],
        external_id=row["external_id"],
        title=row["title"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _revision_from_row(row: aiosqlite.Row) -> ArticleRevision:
    return ArticleRevision(
        id=row["id"],
        family_id=row["family_id"],
        version=row["version"],
        bundle_path=row["bundle_path"],
        status=row["status"],
        manifest_version=row["manifest_version"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _block_from_row(row: aiosqlite.Row) -> DocumentBlock:
    return DocumentBlock(
        id=row["id"],
        article_revision_id=row["article_revision_id"],
        block_uid=row["block_uid"],
        structural_path=row["structural_path"],
        block_type=row["block_type"],
        parent_uid=row["parent_uid"],
        content_hash=row["content_hash"],
        context_hash=row["context_hash"],
        source_markdown=row["source_markdown"],
        source_latex=row["source_latex"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _asset_from_row(row: aiosqlite.Row) -> AssetRecord:
    return AssetRecord(
        id=row["id"],
        article_revision_id=row["article_revision_id"],
        asset_id=row["asset_id"],
        kind=row["kind"],
        source_path=row["source_path"],
        web_path=row["web_path"],
        caption=row["caption"],
        label=row["label"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _translation_variant_from_row(row: aiosqlite.Row) -> TranslationVariant:
    return TranslationVariant(
        id=row["id"],
        block_id=row["block_id"],
        target_language=row["target_language"],
        provider_profile_id=row["provider_profile_id"],
        model=row["model"],
        raw_markdown=row["raw_markdown"],
        render_ast=_loads(row["render_ast_json"], None),
        validation_status=row["validation_status"],
        glossary_version=row["glossary_version"],
        is_default=bool(row["is_default"]),
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _chat_message_from_row(row: aiosqlite.Row) -> ChatMessage:
    return ChatMessage(
        id=row["id"],
        article_revision_id=row["article_revision_id"],
        role=row["role"],
        content=row["content"],
        source_refs=_loads(row["source_refs_json"], []),
        external_refs=_loads(row["external_refs_json"], []),
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
    )


def _note_patch_from_row(row: aiosqlite.Row) -> NotePatch:
    return NotePatch(
        id=row["id"],
        article_revision_id=row["article_revision_id"],
        status=row["status"],
        title=row["title"],
        patch_markdown=row["patch_markdown"],
        source_refs=_loads(row["source_refs_json"], []),
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _glossary_term_from_row(row: aiosqlite.Row) -> GlossaryTerm:
    return GlossaryTerm(
        id=row["id"],
        scope=row["scope"],
        source_term=row["source_term"],
        target_term=row["target_term"],
        language_direction=row["language_direction"],
        status=row["status"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _reader_card_from_row(row: aiosqlite.Row) -> ReaderCard:
    return ReaderCard(
        id=row["id"],
        article_revision_id=row["article_revision_id"],
        card_type=row["card_type"],
        anchor_block_uid=row["anchor_block_uid"],
        anchor_text=row["anchor_text"],
        canonical_key=row["canonical_key"],
        abbreviation=row["abbreviation"],
        full_form=row["full_form"],
        title=row["title"],
        body_markdown=row["body_markdown"],
        target_language=row["target_language"],
        source_type=row["source_type"],
        source_url=row["source_url"],
        position=row["position"],
        status=row["status"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _loads(value: str | None, fallback: Any) -> Any:
    if value is None:
        return fallback
    return json.loads(value)
