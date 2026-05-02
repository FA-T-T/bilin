from __future__ import annotations

from pathlib import Path

import aiosqlite
import pytest

from bilin_api.database import init_global_db, init_library_db


@pytest.mark.asyncio
async def test_global_migration_initializes_database(bilin_home: Path) -> None:
    db_path = await init_global_db()
    assert db_path == bilin_home / "bilin.sqlite"
    async with aiosqlite.connect(db_path) as conn:
        cursor = await conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        tables = {row[0] for row in await cursor.fetchall()}
        cursor = await conn.execute("PRAGMA table_info(provider_profiles)")
        columns = {row[1] for row in await cursor.fetchall()}
    assert {
        "schema_migrations",
        "libraries",
        "provider_profiles",
        "jobs",
        "app_settings",
        "translation_memory",
    } <= tables
    assert {"max_concurrent_requests", "requests_per_minute"} <= columns


@pytest.mark.asyncio
async def test_library_migration_initializes_database(tmp_path: Path) -> None:
    db_path = await init_library_db(tmp_path / "library")
    async with aiosqlite.connect(db_path) as conn:
        cursor = await conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        tables = {row[0] for row in await cursor.fetchall()}
    assert {
        "article_families",
        "article_revisions",
        "assets",
        "blocks",
        "translation_variants",
    } <= tables
