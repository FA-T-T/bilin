from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path

import aiosqlite

from bilin_api.settings import get_settings


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


async def connect(db_path: Path) -> aiosqlite.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = await aiosqlite.connect(db_path)
    conn.row_factory = aiosqlite.Row
    await conn.execute("PRAGMA foreign_keys = ON")
    await conn.execute("PRAGMA journal_mode = WAL")
    return conn


@asynccontextmanager
async def open_db(db_path: Path) -> AsyncIterator[aiosqlite.Connection]:
    conn = await connect(db_path)
    try:
        yield conn
    finally:
        await conn.close()


async def apply_migrations(db_path: Path, scope: str) -> None:
    migrations_dir = Path(__file__).parent / "migrations" / scope
    if not migrations_dir.exists():
        msg = f"Unknown migration scope: {scope}"
        raise ValueError(msg)

    async with open_db(db_path) as conn:
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version TEXT PRIMARY KEY,
              applied_at TEXT NOT NULL
            )
            """
        )
        cursor = await conn.execute("SELECT version FROM schema_migrations")
        applied = {row["version"] for row in await cursor.fetchall()}

        for migration_path in sorted(migrations_dir.glob("*.sql")):
            version = migration_path.stem
            if version in applied:
                continue
            sql = migration_path.read_text(encoding="utf-8")
            await conn.executescript(sql)
            await conn.execute(
                "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                (version, utc_now()),
            )
        await conn.commit()


async def init_global_db() -> Path:
    settings = get_settings()
    settings.bilin_home.mkdir(parents=True, exist_ok=True)
    await apply_migrations(settings.global_db_path, "global")
    return settings.global_db_path


async def init_library_db(library_path: Path) -> Path:
    library_path.mkdir(parents=True, exist_ok=True)
    db_path = library_path / "library.sqlite"
    await apply_migrations(db_path, "library")
    return db_path
