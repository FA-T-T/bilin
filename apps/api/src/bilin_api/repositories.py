from __future__ import annotations

import json
import shutil
from collections import Counter
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

import aiosqlite

from bilin_api.credentials import (
    APP_SETTINGS_REF_PREFIX,
    KEYCHAIN_REF_PREFIX,
    app_settings_provider_key_ref,
    delete_provider_api_key_from_keychain,
    read_provider_api_key_from_keychain,
    store_provider_api_key,
)
from bilin_api.database import init_global_db, init_library_db, open_db, utc_now
from bilin_api.network_security import validate_provider_base_url
from bilin_api.schemas import (
    ArticleTaskProgress,
    ArticleTaskSummary,
    Job,
    JobStatus,
    JobSummary,
    JobType,
    Library,
    LibraryCreate,
    LibraryDeleteResult,
    LibraryStatus,
    LibraryUpdate,
    NoteTemplate,
    NoteTemplateCreate,
    NoteTemplateUpdate,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProfileUpdate,
    ProviderProtocol,
    TranslationMemoryEntry,
    TranslationMemoryEntryUpdate,
    TranslationMemoryReviewStatus,
)
from bilin_api.settings import get_settings

LIBRARY_MARKER_FILE = ".bilin-library.json"
CURRENT_ARTICLE_TASK_STATUSES = {
    JobStatus.queued,
    JobStatus.running,
    JobStatus.paused,
    JobStatus.failed,
}
ACTIVE_ARTICLE_TASK_STATUSES = {
    JobStatus.queued,
    JobStatus.running,
    JobStatus.paused,
}
TERMINAL_JOB_STATUSES = {
    JobStatus.succeeded,
    JobStatus.failed,
    JobStatus.cancelled,
}
PRIMARY_TASK_STATUS_RANK = {
    JobStatus.running: 0,
    JobStatus.queued: 1,
    JobStatus.paused: 2,
    JobStatus.failed: 3,
}


def _loads(value: str | None, fallback: Any) -> Any:
    if value is None:
        return fallback
    return json.loads(value)


def _library_from_row(row: aiosqlite.Row) -> Library:
    return Library(
        id=row["id"],
        name=row["name"],
        path=row["path"],
        status=row["status"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _job_from_row(row: aiosqlite.Row) -> Job:
    return Job(
        id=row["id"],
        type=row["type"],
        status=row["status"],
        priority=row["priority"],
        payload=_loads(row["payload_json"], {}),
        result=_loads(row["result_json"], None),
        error=_loads(row["error_json"], None),
        progress=row["progress"],
        attempts=row["attempts"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        started_at=row["started_at"],
        finished_at=row["finished_at"],
        lease_owner=row["lease_owner"],
    )


def _provider_from_row(row: aiosqlite.Row) -> ProviderProfile:
    return ProviderProfile(
        id=row["id"],
        name=row["name"],
        protocol=row["protocol"],
        base_url=row["base_url"],
        key_ref=row["key_ref"],
        default_model=row["default_model"],
        max_concurrent_requests=row["max_concurrent_requests"],
        requests_per_minute=row["requests_per_minute"],
        capabilities=_loads(row["capabilities_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _translation_memory_from_row(row: aiosqlite.Row) -> TranslationMemoryEntry:
    return TranslationMemoryEntry(
        id=row["id"],
        source_hash=row["source_hash"],
        source_markdown=row["source_markdown"],
        target_language=row["target_language"],
        raw_markdown=row["raw_markdown"],
        provider_profile_id=row["provider_profile_id"],
        model=row["model"],
        validation_status=row["validation_status"],
        review_status=row["review_status"],
        reuse_enabled=bool(row["reuse_enabled"]),
        glossary_version=row["glossary_version"],
        metadata=_loads(row["metadata_json"], {}),
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _note_template_from_row(row: aiosqlite.Row) -> NoteTemplate:
    return NoteTemplate(
        id=row["id"],
        name=row["name"],
        description=row["description"],
        custom=True,
        metadata=_loads(row["metadata_json"], {}),
    )


async def list_libraries() -> list[Library]:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM libraries ORDER BY updated_at DESC")
        rows = await cursor.fetchall()
    return [_library_from_row(row) for row in rows]


async def get_library(library_id: str) -> Library | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM libraries WHERE id = ?", (library_id,))
        row = await cursor.fetchone()
    return _library_from_row(row) if row else None


async def create_library(payload: LibraryCreate) -> Library:
    db_path = await init_global_db()
    library_path = Path(payload.path).expanduser().resolve()
    preexisting_path = library_path.exists()
    library_id = str(uuid4())
    await init_library_db(library_path)
    now_dt = datetime.now(UTC)
    now = now_dt.isoformat()
    library = Library(
        id=library_id,
        name=payload.name,
        path=str(library_path),
        status=LibraryStatus.active,
        metadata={},
        created_at=now_dt,
        updated_at=now_dt,
    )
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO libraries(id, name, path, status, metadata_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                library.id,
                library.name,
                library.path,
                library.status.value,
                json.dumps(library.metadata),
                now,
                now,
            ),
        )
        await conn.commit()
    (library_path / LIBRARY_MARKER_FILE).write_text(
        json.dumps(
            {
                "library_id": library.id,
                "managed_root": not preexisting_path,
                "created_at": now,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return library


async def update_library(library_id: str, payload: LibraryUpdate) -> Library | None:
    current = await get_library(library_id)
    if current is None:
        return None
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            "UPDATE libraries SET name = ?, updated_at = ? WHERE id = ?",
            (payload.name, utc_now(), library_id),
        )
        await conn.commit()
    return await get_library(library_id)


async def archive_library(library_id: str) -> Library | None:
    return await update_library_status(library_id, LibraryStatus.archived)


async def update_library_status(library_id: str, status: LibraryStatus) -> Library | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            "UPDATE libraries SET status = ?, updated_at = ? WHERE id = ?",
            (status.value, utc_now(), library_id),
        )
        await conn.commit()
    return await get_library(library_id)


async def delete_library(library_id: str) -> LibraryDeleteResult | None:
    library = await get_library(library_id)
    if library is None:
        return None
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT COUNT(*) AS count
            FROM jobs
            WHERE payload_json LIKE ?
              AND status IN (?, ?, ?)
            """,
            (
                f"%{library_id}%",
                JobStatus.queued.value,
                JobStatus.running.value,
                JobStatus.paused.value,
            ),
        )
        row = await cursor.fetchone()
        if row and int(row["count"]) > 0:
            msg = "Library has active jobs. Cancel or finish them before deleting the library."
            raise ValueError(msg)
        await conn.execute("DELETE FROM libraries WHERE id = ?", (library_id,))
        await conn.execute(
            "DELETE FROM jobs WHERE payload_json LIKE ?",
            (f"%{library_id}%",),
        )
        await conn.commit()
    library_path = Path(library.path)
    deleted_cache = False
    db_file = library_path / "library.sqlite"
    marker_file = library_path / LIBRARY_MARKER_FILE
    if library_path.exists() and db_file.exists():
        managed_root = False
        if marker_file.exists():
            try:
                marker = json.loads(marker_file.read_text(encoding="utf-8"))
                managed_root = (
                    marker.get("library_id") == library.id and marker.get("managed_root") is True
                )
            except (OSError, json.JSONDecodeError):
                managed_root = False
        if managed_root:
            shutil.rmtree(library_path)
            deleted_cache = not library_path.exists()
        else:
            db_file.unlink()
            marker_file.unlink(missing_ok=True)
            deleted_cache = not db_file.exists()
    return LibraryDeleteResult(
        library_id=library.id,
        path=library.path,
        deleted_cache=deleted_cache,
    )


def default_provider_base_url(protocol: ProviderProtocol) -> str:
    if protocol == ProviderProtocol.anthropic_compatible:
        return "https://api.anthropic.com"
    return "https://api.openai.com/v1"


async def list_provider_profiles() -> list[ProviderProfile]:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM provider_profiles ORDER BY updated_at DESC")
        rows = await cursor.fetchall()
    return [_provider_from_row(row) for row in rows]


async def get_provider_profile(provider_id: str) -> ProviderProfile | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM provider_profiles WHERE id = ?", (provider_id,))
        row = await cursor.fetchone()
    return _provider_from_row(row) if row else None


async def create_provider_profile(payload: ProviderProfileCreate) -> ProviderProfile:
    db_path = await init_global_db()
    now = utc_now()
    provider_id = str(uuid4())
    credential = store_provider_api_key(provider_id, payload.api_key) if payload.api_key else None
    key_ref = credential.key_ref if credential else None
    base_url = validate_provider_base_url(
        payload.base_url or default_provider_base_url(payload.protocol)
    )
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        await conn.execute(
            """
            INSERT INTO provider_profiles(
              id, name, protocol, base_url, key_ref, default_model,
              max_concurrent_requests, requests_per_minute, capabilities_json, created_at,
              updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                provider_id,
                payload.name,
                payload.protocol.value,
                base_url,
                key_ref,
                payload.default_model,
                payload.max_concurrent_requests,
                payload.requests_per_minute,
                json.dumps(payload.capabilities),
                now,
                now,
            ),
        )
        if payload.api_key and credential and credential.backend == "app_settings":
            await _set_provider_api_key(conn, provider_id, payload.api_key)
        if payload.api_key and credential and credential.backend == "keychain":
            await _delete_provider_api_key_setting(conn, provider_id)
        await conn.commit()
    provider = await get_provider_profile(provider_id)
    if provider is None:
        msg = "Created provider profile could not be read back"
        raise RuntimeError(msg)
    return provider


async def update_provider_profile(
    provider_id: str,
    payload: ProviderProfileUpdate,
) -> ProviderProfile | None:
    current = await get_provider_profile(provider_id)
    if current is None:
        return None
    protocol = payload.protocol or current.protocol
    base_url = payload.base_url if payload.base_url is not None else current.base_url
    if base_url is None:
        base_url = default_provider_base_url(protocol)
    base_url = validate_provider_base_url(base_url)
    key_ref = current.key_ref
    credential = None
    if payload.api_key is not None:
        credential = (
            store_provider_api_key(provider_id, payload.api_key) if payload.api_key else None
        )
        key_ref = credential.key_ref if credential else None
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        await conn.execute(
            """
            UPDATE provider_profiles
            SET name = ?, protocol = ?, base_url = ?, key_ref = ?, default_model = ?,
                max_concurrent_requests = ?, requests_per_minute = ?, capabilities_json = ?,
                updated_at = ?
            WHERE id = ?
            """,
            (
                payload.name if payload.name is not None else current.name,
                protocol.value,
                base_url,
                key_ref,
                payload.default_model
                if payload.default_model is not None
                else current.default_model,
                payload.max_concurrent_requests
                if payload.max_concurrent_requests is not None
                else current.max_concurrent_requests,
                payload.requests_per_minute
                if payload.requests_per_minute is not None
                else current.requests_per_minute,
                json.dumps(_provider_capabilities_for_update(payload, current)),
                now,
                provider_id,
            ),
        )
        if payload.api_key is not None:
            if payload.api_key:
                if credential and credential.backend == "app_settings":
                    await _set_provider_api_key(conn, provider_id, payload.api_key)
                if credential and credential.backend == "keychain":
                    await _delete_provider_api_key_setting(conn, provider_id)
            else:
                await _delete_provider_api_key_setting(conn, provider_id)
                delete_provider_api_key_from_keychain(provider_id)
            if (
                current.key_ref
                and current.key_ref.startswith(KEYCHAIN_REF_PREFIX)
                and (key_ref is None or not key_ref.startswith(KEYCHAIN_REF_PREFIX))
            ):
                delete_provider_api_key_from_keychain(provider_id)
        await conn.commit()
    return await get_provider_profile(provider_id)


async def get_provider_api_key(provider: ProviderProfile) -> str | None:
    if provider.key_ref is None:
        return None
    if provider.key_ref.startswith(KEYCHAIN_REF_PREFIX):
        keychain_value = read_provider_api_key_from_keychain(provider.id)
        if keychain_value:
            return keychain_value
        return await _get_provider_api_key_setting(provider.id)
    if not provider.key_ref.startswith(APP_SETTINGS_REF_PREFIX):
        return None
    key = provider.key_ref.removeprefix(APP_SETTINGS_REF_PREFIX)
    raw = await _get_app_setting_api_key(key)
    if raw:
        await _promote_provider_api_key_if_possible(provider.id, raw)
    return raw


async def _promote_provider_api_key_if_possible(provider_id: str, api_key: str) -> None:
    credential = store_provider_api_key(provider_id, api_key)
    if credential.backend != "keychain":
        return
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN")
        await conn.execute(
            """
            UPDATE provider_profiles
            SET key_ref = ?, updated_at = ?
            WHERE id = ?
            """,
            (credential.key_ref, utc_now(), provider_id),
        )
        await _delete_provider_api_key_setting(conn, provider_id)
        await conn.commit()


async def _get_provider_api_key_setting(provider_id: str) -> str | None:
    return await _get_app_setting_api_key(f"provider_api_key:{provider_id}")


async def _get_app_setting_api_key(key: str) -> str | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT value_json FROM app_settings WHERE key = ?", (key,))
        row = await cursor.fetchone()
    value = _loads(row["value_json"], {}) if row else {}
    raw = value.get("value") if isinstance(value, dict) else None
    return raw if isinstance(raw, str) and raw else None


async def _set_app_setting(
    conn: aiosqlite.Connection,
    key: str,
    value: dict[str, Any],
) -> None:
    await conn.execute(
        """
        INSERT INTO app_settings(key, value_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json,
                                      updated_at = excluded.updated_at
        """,
        (key, json.dumps(value), utc_now()),
    )


async def _set_provider_api_key(
    conn: aiosqlite.Connection,
    provider_id: str,
    api_key: str,
) -> None:
    await _set_app_setting(conn, f"provider_api_key:{provider_id}", {"value": api_key})


async def _delete_provider_api_key_setting(
    conn: aiosqlite.Connection,
    provider_id: str,
) -> None:
    await conn.execute(
        "DELETE FROM app_settings WHERE key = ?",
        (app_settings_provider_key_ref(provider_id).removeprefix(APP_SETTINGS_REF_PREFIX),),
    )


async def record_translation_memory_entry(
    *,
    source_hash: str,
    source_markdown: str,
    target_language: str,
    raw_markdown: str,
    provider_profile_id: str | None,
    model: str | None,
    validation_status: str,
    glossary_version: str | None,
    review_status: TranslationMemoryReviewStatus = TranslationMemoryReviewStatus.pending,
    reuse_enabled: bool = False,
    metadata: dict[str, Any] | None = None,
) -> TranslationMemoryEntry:
    db_path = await init_global_db()
    now = utc_now()
    entry_id = str(uuid4())
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO translation_memory(
              id, source_hash, source_markdown, target_language, raw_markdown,
              provider_profile_id, model, validation_status, review_status, reuse_enabled,
              glossary_version, metadata_json, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                entry_id,
                source_hash,
                source_markdown,
                target_language,
                raw_markdown,
                provider_profile_id,
                model,
                validation_status,
                review_status.value,
                int(reuse_enabled),
                glossary_version,
                json.dumps(metadata or {}),
                now,
                now,
            ),
        )
        await conn.commit()
    entry = await get_translation_memory_entry(entry_id)
    if entry is None:
        msg = "Created translation memory entry could not be read back"
        raise RuntimeError(msg)
    return entry


async def get_translation_memory_entry(entry_id: str) -> TranslationMemoryEntry | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            "SELECT * FROM translation_memory WHERE id = ?",
            (entry_id,),
        )
        row = await cursor.fetchone()
    return _translation_memory_from_row(row) if row else None


async def list_translation_memory_entries(
    *,
    target_language: str | None = None,
    review_status: TranslationMemoryReviewStatus | None = None,
    reuse_enabled: bool | None = None,
    include_non_candidates: bool = False,
    limit: int = 100,
) -> list[TranslationMemoryEntry]:
    db_path = await init_global_db()
    clauses: list[str] = []
    params: list[str | int] = []
    if target_language:
        clauses.append("target_language = ?")
        params.append(target_language)
    if review_status:
        clauses.append("review_status = ?")
        params.append(review_status.value)
    if reuse_enabled is not None:
        clauses.append("reuse_enabled = ?")
        params.append(int(reuse_enabled))
    if not include_non_candidates:
        clauses.append("COALESCE(json_extract(metadata_json, '$.review_candidate'), 1) != 0")
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            f"""
            SELECT *
            FROM translation_memory
            {where}
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            (*params, limit),
        )
        rows = await cursor.fetchall()
    return [_translation_memory_from_row(row) for row in rows]


async def update_translation_memory_entry(
    entry_id: str,
    payload: TranslationMemoryEntryUpdate,
) -> TranslationMemoryEntry | None:
    current = await get_translation_memory_entry(entry_id)
    if current is None:
        return None
    metadata = current.metadata.copy()
    if payload.metadata is not None:
        metadata.update(payload.metadata)
    reuse_enabled = (
        payload.reuse_enabled if payload.reuse_enabled is not None else current.reuse_enabled
    )
    now = utc_now()
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE translation_memory
            SET review_status = ?, reuse_enabled = ?, metadata_json = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                (payload.review_status or current.review_status).value,
                int(reuse_enabled),
                json.dumps(metadata),
                now,
                entry_id,
            ),
        )
        await conn.commit()
    return await get_translation_memory_entry(entry_id)


async def find_translation_memory_entries(
    *,
    source_hash: str,
    target_language: str,
    glossary_version: str | None,
    limit: int = 5,
) -> list[TranslationMemoryEntry]:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT *
            FROM translation_memory
            WHERE source_hash = ?
              AND target_language = ?
              AND glossary_version IS ?
              AND validation_status = 'ok'
              AND review_status = 'approved'
              AND reuse_enabled = 1
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            (source_hash, target_language, glossary_version, limit),
        )
        rows = await cursor.fetchall()
    return [_translation_memory_from_row(row) for row in rows]


async def list_custom_note_templates() -> list[NoteTemplate]:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM note_templates ORDER BY updated_at DESC")
        rows = await cursor.fetchall()
    return [_note_template_from_row(row) for row in rows]


async def get_custom_note_template(template_id: str) -> NoteTemplate | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM note_templates WHERE id = ?", (template_id,))
        row = await cursor.fetchone()
    return _note_template_from_row(row) if row else None


async def create_custom_note_template(payload: NoteTemplateCreate) -> NoteTemplate:
    db_path = await init_global_db()
    now = utc_now()
    template_id = str(uuid4())
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO note_templates(id, name, description, metadata_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                template_id,
                payload.name,
                payload.description,
                json.dumps(payload.metadata),
                now,
                now,
            ),
        )
        await conn.commit()
    template = await get_custom_note_template(template_id)
    if template is None:
        msg = "Created note template could not be read back"
        raise RuntimeError(msg)
    return template


async def update_custom_note_template(
    template_id: str,
    payload: NoteTemplateUpdate,
) -> NoteTemplate | None:
    current = await get_custom_note_template(template_id)
    if current is None:
        return None
    metadata = current.metadata.copy()
    if payload.metadata is not None:
        metadata.update(payload.metadata)
    now = utc_now()
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE note_templates
            SET name = ?, description = ?, metadata_json = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                payload.name if payload.name is not None else current.name,
                payload.description if payload.description is not None else current.description,
                json.dumps(metadata),
                now,
                template_id,
            ),
        )
        await conn.commit()
    return await get_custom_note_template(template_id)


def _provider_capabilities_for_update(
    payload: ProviderProfileUpdate,
    current: ProviderProfile,
) -> dict[str, Any]:
    return payload.capabilities if payload.capabilities is not None else current.capabilities


async def create_job(
    job_type: JobType,
    payload: dict[str, Any] | None = None,
    priority: int | None = None,
) -> Job:
    db_path = await init_global_db()
    now = utc_now()
    job_id = str(uuid4())
    effective_priority = default_job_priority(job_type) if priority is None else priority
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO jobs(
              id, type, status, priority, payload_json, result_json, error_json, progress,
              attempts, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?)
            """,
            (
                job_id,
                job_type.value,
                JobStatus.queued.value,
                effective_priority,
                json.dumps(payload or {}),
                0.0,
                0,
                now,
                now,
            ),
        )
        await conn.commit()
    job = await get_job(job_id)
    if job is None:
        msg = "Created job could not be read back"
        raise RuntimeError(msg)
    return job


async def create_translation_job_if_absent(
    payload: dict[str, Any],
    *,
    force: bool = False,
    priority: int | None = None,
) -> tuple[Job, bool]:
    db_path = await init_global_db()
    effective_priority = (
        default_job_priority(JobType.translate_block) if priority is None else priority
    )
    active_statuses = (
        JobStatus.queued.value,
        JobStatus.running.value,
        JobStatus.paused.value,
    )
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN IMMEDIATE")
        if not force:
            cursor = await conn.execute(
                """
                SELECT *
                FROM jobs
                WHERE type = ?
                  AND status IN (?, ?, ?)
                  AND json_extract(payload_json, '$.library_id') = ?
                  AND json_extract(payload_json, '$.article_revision_id') = ?
                  AND json_extract(payload_json, '$.block_uid') = ?
                  AND json_extract(payload_json, '$.target_language') = ?
                  AND json_extract(payload_json, '$.provider_profile_id') = ?
                  AND json_extract(payload_json, '$.model') IS ?
                  AND json_extract(payload_json, '$.context_hash') = ?
                ORDER BY created_at ASC
                LIMIT 1
                """,
                (
                    JobType.translate_block.value,
                    *active_statuses,
                    payload.get("library_id"),
                    payload.get("article_revision_id"),
                    payload.get("block_uid"),
                    payload.get("target_language"),
                    payload.get("provider_profile_id"),
                    payload.get("model"),
                    payload.get("context_hash"),
                ),
            )
            row = await cursor.fetchone()
            if row is not None:
                await conn.commit()
                return _job_from_row(row), False
        now = utc_now()
        job_id = str(uuid4())
        await conn.execute(
            """
            INSERT INTO jobs(
              id, type, status, priority, payload_json, result_json, error_json, progress,
              attempts, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?)
            """,
            (
                job_id,
                JobType.translate_block.value,
                JobStatus.queued.value,
                effective_priority,
                json.dumps(payload),
                0.0,
                0,
                now,
                now,
            ),
        )
        await conn.commit()
    job = await get_job(job_id)
    if job is None:
        msg = "Created translation job could not be read back"
        raise RuntimeError(msg)
    return job, True


async def create_parse_job_if_absent(payload: dict[str, Any]) -> tuple[Job, bool]:
    db_path = await init_global_db()
    active_statuses = (
        JobStatus.queued.value,
        JobStatus.running.value,
        JobStatus.paused.value,
    )
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN IMMEDIATE")
        cursor = await conn.execute(
            """
            SELECT *
            FROM jobs
            WHERE type = ?
              AND status IN (?, ?, ?)
              AND json_extract(payload_json, '$.library_id') = ?
              AND json_extract(payload_json, '$.article_revision_id') = ?
            ORDER BY created_at ASC
            LIMIT 1
            """,
            (
                JobType.parse_article.value,
                *active_statuses,
                payload.get("library_id"),
                payload.get("article_revision_id"),
            ),
        )
        row = await cursor.fetchone()
        if row is not None:
            await conn.commit()
            return _job_from_row(row), False
        now = utc_now()
        job_id = str(uuid4())
        await conn.execute(
            """
            INSERT INTO jobs(
              id, type, status, priority, payload_json, result_json, error_json, progress,
              attempts, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?)
            """,
            (
                job_id,
                JobType.parse_article.value,
                JobStatus.queued.value,
                default_job_priority(JobType.parse_article),
                json.dumps(payload),
                0.0,
                0,
                now,
                now,
            ),
        )
        await conn.commit()
    job = await get_job(job_id)
    if job is None:
        msg = "Created parse job could not be read back"
        raise RuntimeError(msg)
    return job, True


def default_job_priority(job_type: JobType) -> int:
    if job_type == JobType.parse_article:
        return 100
    if job_type == JobType.import_arxiv:
        return 90
    if job_type == JobType.translate_block:
        return 50
    if job_type == JobType.generate_reader_card:
        return 40
    if job_type == JobType.export_article:
        return 30
    if job_type == JobType.embed_article:
        return 20
    if job_type == JobType.extract_reader_cards:
        return 10
    return 0


async def list_jobs(
    *,
    limit: int | None = None,
    statuses: Sequence[JobStatus] | None = None,
) -> list[Job]:
    db_path = await init_global_db()
    where: list[str] = []
    params: list[object] = []
    if statuses:
        placeholders = ", ".join("?" for _ in statuses)
        where.append(f"status IN ({placeholders})")
        params.extend(status.value for status in statuses)
    sql = "SELECT * FROM jobs"
    if where:
        sql += f" WHERE {' AND '.join(where)}"
    sql += " ORDER BY created_at DESC"
    if limit is not None:
        sql += " LIMIT ?"
        params.append(max(1, min(limit, 500)))
    async with open_db(db_path) as conn:
        cursor = await conn.execute(sql, params)
        rows = await cursor.fetchall()
    return [_job_from_row(row) for row in rows]


async def get_job_summary() -> JobSummary:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT status, COUNT(*) AS count FROM jobs GROUP BY status")
        rows = await cursor.fetchall()
        cursor = await conn.execute("SELECT MAX(updated_at) AS updated_at FROM jobs")
        updated_row = await cursor.fetchone()
    counts = {row["status"]: int(row["count"]) for row in rows}
    queued = counts.get(JobStatus.queued.value, 0)
    running = counts.get(JobStatus.running.value, 0)
    paused = counts.get(JobStatus.paused.value, 0)
    updated_at = updated_row["updated_at"] if updated_row else None
    return JobSummary(
        total=sum(counts.values()),
        queued=queued,
        running=running,
        paused=paused,
        succeeded=counts.get(JobStatus.succeeded.value, 0),
        failed=counts.get(JobStatus.failed.value, 0),
        cancelled=counts.get(JobStatus.cancelled.value, 0),
        active=queued + running + paused,
        updated_at=updated_at,
    )


async def get_article_task_summary(limit: int = 120) -> ArticleTaskSummary:
    current_jobs = await _list_current_article_task_jobs()
    if not current_jobs:
        return ArticleTaskSummary()

    grouped, translation_batches = _group_current_article_task_jobs(current_jobs)
    terminal_translation_jobs = await _list_terminal_translation_jobs_for_batches(
        _translation_batch_refs_for_backfill(grouped, translation_batches)
    )
    for job in terminal_translation_jobs:
        key, _library_id, _revision_id = _article_task_key(job)
        if key not in grouped:
            continue
        if _is_selected_translation_batch_member(job, key, translation_batches):
            grouped[key].append(job)
    grouped = {key: _dedupe_jobs(group_jobs) for key, group_jobs in grouped.items()}

    article_refs = {
        (library_id, revision_id)
        for key in grouped
        for _group_key, library_id, revision_id in [_split_article_task_key(key)]
        if library_id and revision_id
    }
    article_titles = await _load_article_task_titles(article_refs)
    items = [
        _article_task_progress_from_jobs(key, group_jobs, article_titles)
        for key, group_jobs in grouped.items()
        if any(job.status in CURRENT_ARTICLE_TASK_STATUSES for job in group_jobs)
    ]
    items.sort(key=lambda item: item.updated_at or datetime.min.replace(tzinfo=UTC), reverse=True)
    total_items = len(items)
    limited_items = items[: max(1, min(limit, 200))]
    counts = Counter(item.status for item in items)
    queued = counts[JobStatus.queued]
    running = counts[JobStatus.running]
    paused = counts[JobStatus.paused]
    failed_items = sum(1 for item in items if item.failed_jobs > 0)
    updated_at = max((item.updated_at for item in items if item.updated_at), default=None)
    return ArticleTaskSummary(
        total=total_items,
        queued=queued,
        running=running,
        paused=paused,
        succeeded=counts[JobStatus.succeeded],
        failed=counts[JobStatus.failed],
        cancelled=counts[JobStatus.cancelled],
        active=queued + running + paused,
        updated_at=updated_at,
        failed_items=failed_items,
        items=limited_items,
    )


async def _list_current_article_task_jobs() -> list[Job]:
    statuses = sorted(CURRENT_ARTICLE_TASK_STATUSES, key=lambda status: status.value)
    placeholders = ", ".join("?" for _ in statuses)
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            f"""
            SELECT *
            FROM jobs
            WHERE status IN ({placeholders})
            ORDER BY updated_at DESC
            """,
            tuple(status.value for status in statuses),
        )
        rows = await cursor.fetchall()
    return [_job_from_row(row) for row in rows]


def _article_task_key(job: Job) -> tuple[str, str | None, str | None]:
    library_id = job.payload.get("library_id")
    library = library_id if isinstance(library_id, str) and library_id else None
    revision = _article_task_revision_id(job)
    if library and revision:
        return f"article:{library}:{revision}", library, revision
    if job.type == JobType.import_arxiv and library:
        arxiv_id = job.payload.get("arxiv_id")
        version = job.payload.get("version")
        if isinstance(arxiv_id, str) and arxiv_id:
            suffix = f"{arxiv_id}:{version}" if isinstance(version, str) and version else arxiv_id
            return f"import:{library}:{suffix}", library, None
    return f"job:{job.id}", library, None


def _article_task_revision_id(job: Job) -> str | None:
    if job.type == JobType.import_arxiv:
        source_revision_id = job.payload.get("source_article_revision_id")
        if isinstance(source_revision_id, str) and source_revision_id:
            return source_revision_id
    revision_id = job.payload.get("article_revision_id")
    if isinstance(revision_id, str) and revision_id:
        return revision_id
    return None


def _split_article_task_key(key: str) -> tuple[str, str | None, str | None]:
    parts = key.split(":", 2)
    if len(parts) == 3 and parts[0] == "article":
        library_id, revision_id = parts[1], parts[2]
        return key, library_id, revision_id
    return key, None, None


def _group_current_article_task_jobs(
    jobs: list[Job],
) -> tuple[dict[str, list[Job]], dict[str, set[str | None]]]:
    translation_batches = _current_translation_batches(jobs)
    grouped: dict[str, list[Job]] = {}
    for job in jobs:
        key, _library_id, _revision_id = _article_task_key(job)
        if job.type == JobType.translate_block and not _is_selected_translation_batch_member(
            job,
            key,
            translation_batches,
        ):
            continue
        grouped.setdefault(key, []).append(job)
    return grouped, translation_batches


def _current_translation_batches(jobs: list[Job]) -> dict[str, set[str | None]]:
    translation_jobs_by_key: dict[str, list[Job]] = {}
    for job in jobs:
        if job.type != JobType.translate_block:
            continue
        key, _library_id, _revision_id = _article_task_key(job)
        translation_jobs_by_key.setdefault(key, []).append(job)
    return {
        key: selected
        for key, key_jobs in translation_jobs_by_key.items()
        for selected in [_select_current_translation_batches(key_jobs)]
        if selected
    }


def _select_current_translation_batches(jobs: list[Job]) -> set[str | None]:
    explicit_active = [
        job
        for job in jobs
        if job.status in ACTIVE_ARTICLE_TASK_STATUSES and _translation_batch_id(job) is not None
    ]
    if explicit_active:
        return {_translation_batch_id(_select_primary_task_job(explicit_active))}
    explicit_current = [job for job in jobs if _translation_batch_id(job) is not None]
    if explicit_current:
        return {_translation_batch_id(_select_primary_task_job(explicit_current))}
    return {None}


def _is_selected_translation_batch_member(
    job: Job,
    key: str,
    translation_batches: dict[str, set[str | None]],
) -> bool:
    if job.type != JobType.translate_block:
        return False
    batches = translation_batches.get(key)
    if not batches:
        return False
    return _translation_batch_id(job) in batches


def _translation_batch_id(job: Job) -> str | None:
    batch = job.payload.get("translation_batch_id")
    return batch if isinstance(batch, str) and batch else None


def _translation_batch_refs_for_backfill(
    grouped: dict[str, list[Job]],
    translation_batches: dict[str, set[str | None]],
) -> set[tuple[str, str, str | None]]:
    refs: set[tuple[str, str, str | None]] = set()
    for key in grouped:
        _group_key, library_id, revision_id = _split_article_task_key(key)
        if not library_id or not revision_id:
            continue
        for batch_id in translation_batches.get(key, set()):
            refs.add((library_id, revision_id, batch_id))
    return refs


async def _list_terminal_translation_jobs_for_batches(
    batch_refs: set[tuple[str, str, str | None]],
) -> list[Job]:
    if not batch_refs:
        return []
    db_path = await init_global_db()
    rows: list[aiosqlite.Row] = []
    refs = sorted(batch_refs, key=lambda ref: (ref[0], ref[1], ref[2] or ""))
    chunk_size = 40
    async with open_db(db_path) as conn:
        for start in range(0, len(refs), chunk_size):
            chunk = refs[start : start + chunk_size]
            params: list[object] = [
                JobType.translate_block.value,
                JobStatus.succeeded.value,
                JobStatus.failed.value,
                JobStatus.cancelled.value,
            ]
            clauses: list[str] = []
            for library_id, revision_id, batch_id in chunk:
                if batch_id is None:
                    clauses.append(
                        """
                        (
                          json_extract(payload_json, '$.library_id') = ?
                          AND json_extract(payload_json, '$.article_revision_id') = ?
                          AND COALESCE(
                            json_extract(payload_json, '$.translation_batch_id'),
                            ''
                          ) = ''
                        )
                        """
                    )
                    params.extend((library_id, revision_id))
                    continue
                clauses.append(
                    """
                    (
                      json_extract(payload_json, '$.library_id') = ?
                      AND json_extract(payload_json, '$.article_revision_id') = ?
                      AND json_extract(payload_json, '$.translation_batch_id') = ?
                    )
                    """
                )
                params.extend((library_id, revision_id, batch_id))
            cursor = await conn.execute(
                f"""
                SELECT *
                FROM jobs
                WHERE type = ?
                  AND status IN (?, ?, ?)
                  AND ({" OR ".join(clauses)})
                ORDER BY updated_at DESC
                """,
                params,
            )
            rows.extend(await cursor.fetchall())
    return [_job_from_row(row) for row in rows]


def _dedupe_jobs(jobs: list[Job]) -> list[Job]:
    deduped: dict[str, Job] = {}
    for job in jobs:
        deduped[job.id] = job
    return list(deduped.values())


async def _load_article_task_titles(
    article_refs: set[tuple[str, str]],
) -> dict[tuple[str, str], tuple[str | None, str | None]]:
    if not article_refs:
        return {}
    libraries = {library.id: library for library in await list_libraries()}
    refs_by_library: dict[str, set[str]] = {}
    for library_id, revision_id in article_refs:
        refs_by_library.setdefault(library_id, set()).add(revision_id)

    titles: dict[tuple[str, str], tuple[str | None, str | None]] = {}
    for library_id, revision_ids in refs_by_library.items():
        library = libraries.get(library_id)
        if library is None:
            continue
        db_path = Path(library.path) / "library.sqlite"
        if not db_path.exists():
            continue
        placeholders = ", ".join("?" for _ in revision_ids)
        async with open_db(db_path) as conn:
            cursor = await conn.execute(
                f"""
                SELECT r.id AS revision_id, f.title AS title, f.external_id AS external_id
                FROM article_revisions r
                JOIN article_families f ON f.id = r.family_id
                WHERE r.id IN ({placeholders})
                """,
                tuple(revision_ids),
            )
            rows = await cursor.fetchall()
        for row in rows:
            titles[(library_id, row["revision_id"])] = (row["title"], row["external_id"])
    return titles


def _article_task_progress_from_jobs(
    key: str,
    jobs: list[Job],
    article_titles: dict[tuple[str, str], tuple[str | None, str | None]],
) -> ArticleTaskProgress:
    key_type, library_id, revision_id = _split_article_task_key(key)
    if library_id is None or revision_id is None:
        _key, library_id, revision_id = _article_task_key(jobs[0])
    title, source_id = _article_title_and_source(key, jobs, article_titles)
    counts = Counter(job.status for job in jobs)
    status = _aggregate_article_task_status(counts)
    primary = _select_primary_task_job(jobs)
    stage, message, progress, current, total = _article_task_stage_progress(primary, jobs)
    failed_status_jobs = [job for job in jobs if job.status == JobStatus.failed]
    failed_error_jobs = [job for job in failed_status_jobs if job.error]
    failed_error_jobs.sort(key=lambda job: job.updated_at, reverse=True)
    updated_at = max((job.updated_at for job in jobs), default=None)
    queued = counts[JobStatus.queued]
    running = counts[JobStatus.running]
    paused = counts[JobStatus.paused]
    return ArticleTaskProgress(
        id=key_type,
        library_id=library_id,
        article_revision_id=revision_id,
        article_title=title,
        source_id=source_id,
        status=status,
        stage=stage,
        message=message,
        progress=progress,
        current=current,
        total=total,
        queued_jobs=queued,
        running_jobs=running,
        paused_jobs=paused,
        succeeded_jobs=counts[JobStatus.succeeded],
        failed_jobs=counts[JobStatus.failed],
        cancelled_jobs=counts[JobStatus.cancelled],
        active_jobs=queued + running + paused,
        job_ids=[job.id for job in sorted(jobs, key=lambda job: job.created_at)],
        failed_job_ids=[
            job.id for job in sorted(failed_status_jobs, key=lambda job: job.created_at)
        ],
        error=failed_error_jobs[0].error if failed_error_jobs else None,
        updated_at=updated_at,
    )


def _article_title_and_source(
    key: str,
    jobs: list[Job],
    article_titles: dict[tuple[str, str], tuple[str | None, str | None]],
) -> tuple[str | None, str | None]:
    _group_key, library_id, revision_id = _split_article_task_key(key)
    if library_id and revision_id:
        title, source_id = article_titles.get((library_id, revision_id), (None, None))
        return title, source_id
    job = jobs[0]
    if job.type == JobType.import_arxiv:
        arxiv_id = job.payload.get("arxiv_id")
        version = job.payload.get("version")
        if isinstance(arxiv_id, str):
            source_id = f"{arxiv_id}{version}" if isinstance(version, str) and version else arxiv_id
            return None, source_id
    return None, None


def _aggregate_article_task_status(counts: Counter[JobStatus]) -> JobStatus:
    if counts[JobStatus.running]:
        return JobStatus.running
    if counts[JobStatus.queued]:
        return JobStatus.queued
    if counts[JobStatus.paused]:
        return JobStatus.paused
    if counts[JobStatus.failed]:
        return JobStatus.failed
    if counts[JobStatus.succeeded]:
        return JobStatus.succeeded
    if counts[JobStatus.cancelled]:
        return JobStatus.cancelled
    return JobStatus.queued


def _select_primary_task_job(jobs: list[Job]) -> Job:
    current_jobs = [job for job in jobs if job.status in CURRENT_ARTICLE_TASK_STATUSES]
    candidates = current_jobs or jobs
    return min(
        candidates,
        key=lambda job: (
            PRIMARY_TASK_STATUS_RANK.get(job.status, len(PRIMARY_TASK_STATUS_RANK)),
            -(job.updated_at.timestamp() if job.updated_at else 0.0),
        ),
    )


def _article_task_stage_progress(primary: Job, jobs: list[Job]) -> tuple[str, str, float, int, int]:
    if primary.type == JobType.import_arxiv:
        return _single_job_task_progress(primary, "importing", "从 arXiv 端下载源数据")
    if primary.type == JobType.parse_article:
        return _single_job_task_progress(primary, "parsing", "解析 TeX / 渲染 HTML")
    if primary.type == JobType.translate_block:
        return _translation_task_progress(jobs)
    if primary.type == JobType.embed_article:
        return _single_job_task_progress(primary, "embedding", "生成 embedding")
    if primary.type == JobType.extract_reader_cards:
        return _single_job_task_progress(primary, "extracting_reader_cards", "抽取阅读卡片")
    if primary.type == JobType.generate_reader_card:
        return _single_job_task_progress(primary, "generating_reader_card", "生成阅读卡片")
    if primary.type == JobType.export_article:
        return _single_job_task_progress(primary, "exporting", "导出文章")
    return _single_job_task_progress(primary, primary.type.value, primary.type.value)


def _single_job_task_progress(
    job: Job,
    stage: str,
    message: str,
) -> tuple[str, str, float, int, int]:
    metadata = _job_progress_metadata(job)
    if metadata is not None:
        stage, message, progress = metadata
    else:
        progress = job.progress
    current = 1 if job.status in TERMINAL_JOB_STATUSES else 0
    if job.status == JobStatus.failed:
        message = f"{message}失败"
    return stage, message, progress, current, 1


def _job_progress_metadata(job: Job) -> tuple[str, str, float] | None:
    metadata = job.payload.get("progress_metadata")
    if not isinstance(metadata, dict):
        return None
    stage = metadata.get("stage")
    message = metadata.get("message")
    progress = metadata.get("progress")
    if not isinstance(stage, str) or not stage:
        return None
    if not isinstance(message, str) or not message:
        return None
    if not isinstance(progress, int | float):
        return None
    return stage, message, max(0.0, min(float(progress), 1.0))


def _translation_task_progress(jobs: list[Job]) -> tuple[str, str, float, int, int]:
    translation_jobs = [job for job in jobs if job.type == JobType.translate_block]
    if not translation_jobs:
        return "translating", "翻译中 000/000", 0.0, 0, 0
    total = len(translation_jobs)
    finished = sum(1 for job in translation_jobs if job.status in TERMINAL_JOB_STATUSES)
    units = sum(
        1.0 if job.status in TERMINAL_JOB_STATUSES else max(0.0, min(job.progress, 1.0))
        for job in translation_jobs
    )
    progress = units / total if total else 0.0
    active = any(
        job.status in {JobStatus.queued, JobStatus.running, JobStatus.paused}
        for job in translation_jobs
    )
    failed = any(job.status == JobStatus.failed for job in translation_jobs)
    label = "翻译中" if active or not failed else "翻译失败"
    width = max(3, len(str(total)))
    return (
        "translating",
        f"{label} {finished:0{width}d}/{total:0{width}d}",
        progress,
        finished,
        total,
    )


async def clear_jobs() -> int:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            "SELECT COUNT(*) AS count FROM jobs WHERE status IN (?, ?, ?)",
            (
                JobStatus.succeeded.value,
                JobStatus.failed.value,
                JobStatus.cancelled.value,
            ),
        )
        row = await cursor.fetchone()
        count = int(row["count"]) if row else 0
        await conn.execute(
            "DELETE FROM jobs WHERE status IN (?, ?, ?)",
            (
                JobStatus.succeeded.value,
                JobStatus.failed.value,
                JobStatus.cancelled.value,
            ),
        )
        await conn.commit()
    return count


async def get_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
        row = await cursor.fetchone()
    return _job_from_row(row) if row else None


async def pause_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, updated_at = ?
            WHERE id = ? AND status IN (?, ?)
            """,
            (
                JobStatus.paused.value,
                utc_now(),
                job_id,
                JobStatus.queued.value,
                JobStatus.running.value,
            ),
        )
        await conn.commit()
    return await get_job(job_id)


async def resume_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT started_at FROM jobs WHERE id = ?", (job_id,))
        row = await cursor.fetchone()
        if row is None:
            return None
        status = JobStatus.running if row["started_at"] else JobStatus.queued
        await conn.execute(
            "UPDATE jobs SET status = ?, updated_at = ? WHERE id = ? AND status = ?",
            (status.value, now, job_id, JobStatus.paused.value),
        )
        await conn.commit()
    return await get_job(job_id)


async def retry_failed_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT id FROM jobs WHERE id = ?", (job_id,))
        row = await cursor.fetchone()
        if row is None:
            return None
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, error_json = NULL, result_json = NULL, attempts = 0,
                progress = 0, started_at = NULL, finished_at = NULL,
                lease_owner = NULL, updated_at = ?
            WHERE id = ? AND status = ?
            """,
            (
                JobStatus.queued.value,
                now,
                job_id,
                JobStatus.failed.value,
            ),
        )
        await conn.commit()
    return await get_job(job_id)


async def cancel_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, updated_at = ?, finished_at = COALESCE(finished_at, ?)
            WHERE id = ? AND status NOT IN (?, ?, ?)
            """,
            (
                JobStatus.cancelled.value,
                now,
                now,
                job_id,
                JobStatus.succeeded.value,
                JobStatus.failed.value,
                JobStatus.cancelled.value,
            ),
        )
        await conn.commit()
    return await get_job(job_id)


async def claim_next_job(
    worker_id: str,
    job_types: Sequence[JobType] | None = None,
) -> Job | None:
    if job_types is not None and not job_types:
        return None
    db_path = await init_global_db()
    now = utc_now()
    params: list[object] = [JobStatus.queued.value]
    type_filter = ""
    if job_types is not None:
        placeholders = ", ".join("?" for _ in job_types)
        type_filter = f" AND type IN ({placeholders})"
        params.extend(job_type.value for job_type in job_types)
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN IMMEDIATE")
        cursor = await conn.execute(
            f"""
            SELECT * FROM jobs
            WHERE status = ?
            {type_filter}
            ORDER BY priority DESC, created_at ASC
            LIMIT 1
            """,
            params,
        )
        row = await cursor.fetchone()
        if row is None:
            await conn.commit()
            return None
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, attempts = attempts + 1, started_at = COALESCE(started_at, ?),
                updated_at = ?, lease_owner = ?
            WHERE id = ? AND status = ?
            """,
            (
                JobStatus.running.value,
                now,
                now,
                worker_id,
                row["id"],
                JobStatus.queued.value,
            ),
        )
        await conn.commit()
    return await get_job(row["id"])


async def update_job_progress(job_id: str, progress: float) -> Job | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET progress = ?, updated_at = ?
            WHERE id = ? AND status = ?
            """,
            (max(0.0, min(progress, 1.0)), utc_now(), job_id, JobStatus.running.value),
        )
        await conn.commit()
    return await get_job(job_id)


async def complete_job(job_id: str, result: dict[str, Any] | None = None) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, result_json = ?, error_json = NULL, progress = 1, updated_at = ?,
                finished_at = ?, lease_owner = NULL
            WHERE id = ? AND status = ?
            """,
            (
                JobStatus.succeeded.value,
                json.dumps(result or {}),
                now,
                now,
                job_id,
                JobStatus.running.value,
            ),
        )
        await conn.commit()
    return await get_job(job_id)


async def fail_job(job_id: str, error: dict[str, Any]) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, error_json = ?, updated_at = ?, finished_at = ?, lease_owner = NULL
            WHERE id = ? AND status = ?
            """,
            (JobStatus.failed.value, json.dumps(error), now, now, job_id, JobStatus.running.value),
        )
        await conn.commit()
    return await get_job(job_id)


async def requeue_job(job_id: str, error: dict[str, Any] | None = None) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, error_json = ?, progress = 0, updated_at = ?, lease_owner = NULL
            WHERE id = ? AND status = ?
            """,
            (
                JobStatus.queued.value,
                json.dumps(error or {}),
                now,
                job_id,
                JobStatus.running.value,
            ),
        )
        await conn.commit()
    return await get_job(job_id)


def dev_info() -> dict[str, str]:
    settings = get_settings()
    return {
        "bilin_home": str(settings.bilin_home),
        "global_db_path": str(settings.global_db_path),
    }
