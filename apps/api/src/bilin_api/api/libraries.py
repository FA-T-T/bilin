from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from bilin_api.repositories import create_library, get_library, list_libraries
from bilin_api.schemas import Library, LibraryCreate

router = APIRouter(prefix="/libraries", tags=["libraries"])


@router.get("", response_model=list[Library])
async def get_libraries() -> list[Library]:
    return await list_libraries()


@router.post("", response_model=Library, status_code=status.HTTP_201_CREATED)
async def post_library(payload: LibraryCreate) -> Library:
    return await create_library(payload)


@router.get("/{library_id}", response_model=Library)
async def get_library_by_id(library_id: str) -> Library:
    library = await get_library(library_id)
    if library is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Library not found")
    return library
