from __future__ import annotations

import json
import shutil
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
from bilin_api.schemas import (
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
    await init_library_db(library_path)
    now_dt = datetime.now(UTC)
    now = now_dt.isoformat()
    library = Library(
        id=str(uuid4()),
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
        await conn.execute("DELETE FROM libraries WHERE id = ?", (library_id,))
        await conn.execute(
            "DELETE FROM jobs WHERE payload_json LIKE ?",
            (f"%{library_id}%",),
        )
        await conn.commit()
    library_path = Path(library.path)
    deleted_cache = False
    if library_path.exists() and (library_path / "library.sqlite").exists():
        shutil.rmtree(library_path)
        deleted_cache = not library_path.exists()
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
    base_url = payload.base_url or default_provider_base_url(payload.protocol)
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


async def clear_jobs() -> int:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT COUNT(*) AS count FROM jobs")
        row = await cursor.fetchone()
        count = int(row["count"]) if row else 0
        await conn.execute("DELETE FROM jobs")
        await conn.commit()
    return count


async def get_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
        row = await cursor.fetchone()
    return _job_from_row(row) if row else None


async def pause_job(job_id: str) -> Job | None:
    await _set_job_status(job_id, JobStatus.paused)
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


async def cancel_job(job_id: str) -> Job | None:
    db_path = await init_global_db()
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            UPDATE jobs
            SET status = ?, updated_at = ?, finished_at = COALESCE(finished_at, ?)
            WHERE id = ? AND status NOT IN (?, ?)
            """,
            (
                JobStatus.cancelled.value,
                now,
                now,
                job_id,
                JobStatus.succeeded.value,
                JobStatus.failed.value,
            ),
        )
        await conn.commit()
    return await get_job(job_id)


async def _set_job_status(job_id: str, status: JobStatus) -> None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            "UPDATE jobs SET status = ?, updated_at = ? WHERE id = ?",
            (status.value, utc_now(), job_id),
        )
        await conn.commit()


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
            WHERE id = ?
            """,
            (JobStatus.running.value, now, now, worker_id, row["id"]),
        )
        await conn.commit()
    return await get_job(row["id"])


async def update_job_progress(job_id: str, progress: float) -> Job | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            "UPDATE jobs SET progress = ?, updated_at = ? WHERE id = ?",
            (max(0.0, min(progress, 1.0)), utc_now(), job_id),
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
                finished_at = ?
            WHERE id = ?
            """,
            (JobStatus.succeeded.value, json.dumps(result or {}), now, now, job_id),
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
            SET status = ?, error_json = ?, updated_at = ?, finished_at = ?
            WHERE id = ?
            """,
            (JobStatus.failed.value, json.dumps(error), now, now, job_id),
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
            WHERE id = ?
            """,
            (JobStatus.queued.value, json.dumps(error or {}), now, job_id),
        )
        await conn.commit()
    return await get_job(job_id)


def dev_info() -> dict[str, str]:
    settings = get_settings()
    return {
        "bilin_home": str(settings.bilin_home),
        "global_db_path": str(settings.global_db_path),
    }
