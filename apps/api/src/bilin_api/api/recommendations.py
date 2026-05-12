from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status

from bilin_api.article_store import resolve_library
from bilin_api.arxiv_recommendations import (
    daily_arxiv_recommendations,
    get_arxiv_categories,
    get_arxiv_recommendation_preferences,
    update_arxiv_recommendation_preferences,
)
from bilin_api.schemas import (
    ArxivCategoryListResult,
    ArxivRecommendationPreferences,
    ArxivRecommendationPreferencesUpdate,
    ArxivRecommendationRequest,
    ArxivRecommendationResult,
)

router = APIRouter(prefix="/libraries/{library_id}/recommendations/arxiv", tags=["recommendations"])


@router.get("/categories", response_model=ArxivCategoryListResult)
async def arxiv_categories(
    library_id: str,
    refresh: bool = Query(False),
) -> ArxivCategoryListResult:
    await _library_or_404(library_id)
    try:
        return await get_arxiv_categories(refresh=refresh)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/preferences", response_model=ArxivRecommendationPreferences)
async def get_preferences(library_id: str) -> ArxivRecommendationPreferences:
    library = await _library_or_404(library_id)
    return await get_arxiv_recommendation_preferences(library)


@router.put("/preferences", response_model=ArxivRecommendationPreferences)
async def put_preferences(
    library_id: str,
    payload: ArxivRecommendationPreferencesUpdate,
) -> ArxivRecommendationPreferences:
    library = await _library_or_404(library_id)
    return await update_arxiv_recommendation_preferences(library, payload)


@router.post("/daily", response_model=ArxivRecommendationResult)
async def arxiv_daily(
    library_id: str,
    payload: ArxivRecommendationRequest,
) -> ArxivRecommendationResult:
    library = await _library_or_404(library_id)
    try:
        return await daily_arxiv_recommendations(library, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


async def _library_or_404(library_id: str):
    try:
        return await resolve_library(library_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
