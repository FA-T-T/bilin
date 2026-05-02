from __future__ import annotations

from pathlib import Path

import pytest

from bilin_api.repositories import create_library, get_library, list_libraries
from bilin_api.schemas import LibraryCreate, LibraryStatus


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
