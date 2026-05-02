from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

from bilin_api.repositories import list_translation_memory_entries, update_translation_memory_entry
from bilin_api.schemas import (
    TranslationMemoryEntry,
    TranslationMemoryEntryUpdate,
    TranslationMemoryListResult,
    TranslationMemoryReviewStatus,
)

router = APIRouter(prefix="/translation-memory", tags=["translation-memory"])


@router.get("", response_model=TranslationMemoryListResult)
async def get_translation_memory_entries(
    target_language: str | None = None,
    review_status: TranslationMemoryReviewStatus | None = None,
    reuse_enabled: bool | None = None,
    limit: int = Query(default=100, ge=1, le=500),
) -> TranslationMemoryListResult:
    return TranslationMemoryListResult(
        entries=await list_translation_memory_entries(
            target_language=target_language,
            review_status=review_status,
            reuse_enabled=reuse_enabled,
            limit=limit,
        )
    )


@router.patch("/{entry_id}", response_model=TranslationMemoryEntry)
async def patch_translation_memory_entry(
    entry_id: str,
    payload: TranslationMemoryEntryUpdate,
) -> TranslationMemoryEntry:
    entry = await update_translation_memory_entry(entry_id, payload)
    if entry is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Translation memory entry not found",
        )
    return entry
