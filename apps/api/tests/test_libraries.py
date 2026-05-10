from __future__ import annotations

from pathlib import Path

import pytest

from bilin_api.repositories import create_library, get_library, list_libraries, update_library
from bilin_api.schemas import LibraryCreate, LibraryStatus, LibraryUpdate


@pytest.mark.asyncio
async def test_create_library_registers_and_initializes_database(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library_path = tmp_path / "papers"
    library = await create_library(LibraryCreate(name="Papers", path=str(library_path)))
    assert library.status == LibraryStatus.active
    assert (library_path / "library.sqlite").exists()
    assert await get_library(library.id) == library
    assert [item.id for item in await list_libraries()] == [library.id]


@pytest.mark.asyncio
async def test_update_library_renames_registered_library(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library_path = tmp_path / "papers"
    library = await create_library(LibraryCreate(name="Papers", path=str(library_path)))
    updated = await update_library(library.id, LibraryUpdate(name="Reading List"))

    assert updated is not None
    assert updated.id == library.id
    assert updated.name == "Reading List"
    assert updated.path == library.path
    assert (await get_library(library.id)) == updated
