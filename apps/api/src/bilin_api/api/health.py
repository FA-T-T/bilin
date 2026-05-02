from __future__ import annotations

from fastapi import APIRouter

from bilin_api import __version__
from bilin_api.schemas import Health

router = APIRouter(tags=["health"])


@router.get("/health", response_model=Health)
async def health() -> Health:
    return Health(version=__version__)
