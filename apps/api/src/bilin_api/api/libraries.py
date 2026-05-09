from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from bilin_api.repositories import (
    archive_library,
    create_library,
    delete_library,
    get_library,
    list_libraries,
)
from bilin_api.schemas import (
    Library,
    LibraryCreate,
    LibraryDeleteResult,
    LibraryTranslationBatchResult,
    TranslationBatchRequest,
)
from bilin_api.translation_service import queue_library_missing_translations

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


@router.post("/{library_id}/archive", response_model=Library)
async def archive_library_by_id(library_id: str) -> Library:
    library = await archive_library(library_id)
    if library is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Library not found")
    return library


@router.post("/{library_id}/translations/missing", response_model=LibraryTranslationBatchResult)
async def translate_missing_library_blocks(
    library_id: str,
    payload: TranslationBatchRequest,
) -> LibraryTranslationBatchResult:
    library = await get_library(library_id)
    if library is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Library not found")
    try:
        return await queue_library_missing_translations(library, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.delete("/{library_id}", response_model=LibraryDeleteResult)
async def delete_library_by_id(library_id: str) -> LibraryDeleteResult:
    result = await delete_library(library_id)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Library not found")
    return result
