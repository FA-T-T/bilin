from __future__ import annotations

import httpx
import pytest

from bilin_api.llm import list_provider_models
from bilin_api.schemas import ProviderProtocol


@pytest.mark.asyncio
async def test_openai_compatible_model_listing_uses_models_endpoint() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "https://api.example.com/v1/models"
        assert request.headers["authorization"] == "Bearer test-key"
        return httpx.Response(
            200,
            json={
                "data": [
                    {"id": "text-embedding-3-large", "owned_by": "example"},
                    {"id": "z-model", "owned_by": "example"},
                    {"id": "a-model", "display_name": "A Model"},
                ]
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        models = await list_provider_models(
            ProviderProtocol.openai_compatible,
            "test-key",
            "https://api.example.com/v1",
            client,
        )

    assert [model.id for model in models] == ["a-model", "text-embedding-3-large", "z-model"]
    assert models[0].display_name == "A Model"
    assert models[1].capabilities["chat"] is False
    assert models[1].capabilities["translation"] is False
    assert models[2].owned_by == "example"


@pytest.mark.asyncio
async def test_anthropic_compatible_model_listing_uses_models_endpoint() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "https://api.anthropic.test/v1/models"
        assert request.headers["x-api-key"] == "test-key"
        assert request.headers["anthropic-version"] == "2023-06-01"
        return httpx.Response(
            200,
            json={
                "data": [
                    {
                        "id": "claude-test",
                        "display_name": "Claude Test",
                        "created_at": "2026-01-01T00:00:00Z",
                    }
                ]
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        models = await list_provider_models(
            ProviderProtocol.anthropic_compatible,
            "test-key",
            "https://api.anthropic.test",
            client,
        )

    assert models[0].id == "claude-test"
    assert models[0].display_name == "Claude Test"
    assert models[0].created_at == "2026-01-01T00:00:00Z"
