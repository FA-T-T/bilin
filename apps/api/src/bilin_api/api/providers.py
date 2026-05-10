from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from bilin_api.llm import LLMClientError, list_provider_models
from bilin_api.provider_presets import PROVIDER_PRESETS
from bilin_api.repositories import (
    create_provider_profile,
    default_provider_base_url,
    get_provider_profile,
    list_provider_profiles,
    update_provider_profile,
)
from bilin_api.schemas import (
    ProviderModelDiscoveryRequest,
    ProviderModelDiscoveryResult,
    ProviderPreset,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProfileUpdate,
)

router = APIRouter(prefix="/providers", tags=["providers"])


@router.get("", response_model=list[ProviderProfile])
async def get_providers() -> list[ProviderProfile]:
    return await list_provider_profiles()


@router.post("", response_model=ProviderProfile, status_code=status.HTTP_201_CREATED)
async def post_provider(payload: ProviderProfileCreate) -> ProviderProfile:
    return await create_provider_profile(payload)


@router.post("/discover-models", response_model=ProviderModelDiscoveryResult)
async def post_discover_models(
    payload: ProviderModelDiscoveryRequest,
) -> ProviderModelDiscoveryResult:
    base_url = payload.base_url or default_provider_base_url(payload.protocol)
    try:
        models = await list_provider_models(payload.protocol, payload.api_key, base_url)
    except LLMClientError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not list provider models: {exc}",
        ) from exc
    chat_models = [model for model in models if model.capabilities.get("chat") is not False]
    default_model = chat_models[0].id if chat_models else None
    return ProviderModelDiscoveryResult(
        protocol=payload.protocol,
        base_url=base_url,
        models=models,
        default_model=default_model,
        capabilities={
            "model_discovery": True,
            "model_count": len(models),
            "chat_model_count": len(chat_models),
        },
    )


@router.get("/presets", response_model=list[ProviderPreset])
async def get_provider_presets() -> list[ProviderPreset]:
    return list(PROVIDER_PRESETS)


@router.get("/{provider_id}", response_model=ProviderProfile)
async def get_provider(provider_id: str) -> ProviderProfile:
    provider = await get_provider_profile(provider_id)
    if provider is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Provider not found")
    return provider


@router.put("/{provider_id}", response_model=ProviderProfile)
async def put_provider(provider_id: str, payload: ProviderProfileUpdate) -> ProviderProfile:
    provider = await update_provider_profile(provider_id, payload)
    if provider is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Provider not found")
    return provider
