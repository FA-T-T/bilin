from __future__ import annotations

import json
from datetime import UTC, datetime

import httpx
import pytest

from bilin_api.llm import (
    LLMClientError,
    build_translation_prompt,
    complete_openai,
    list_provider_models,
)
from bilin_api.schemas import ProviderProfile, ProviderProtocol


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


@pytest.mark.asyncio
async def test_openai_compatible_completion_sets_explicit_output_budget() -> None:
    seen_payload: dict[str, object] = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal seen_payload
        seen_payload = json.loads(request.content.decode("utf-8"))
        return httpx.Response(
            200,
            json={
                "choices": [{"message": {"content": "译文"}}],
                "usage": {
                    "prompt_tokens": 10,
                    "completion_tokens": 2,
                    "total_tokens": 12,
                },
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        response = await complete_openai(
            make_test_provider_profile(),
            "test-key",
            "deepseek-v4-flash",
            "system",
            "user",
            client,
        )

    assert response.text == "译文"
    assert seen_payload["max_tokens"] == 4096
    assert seen_payload["stream"] is False
    assert seen_payload["thinking"] == {"type": "disabled"}


@pytest.mark.asyncio
async def test_openai_compatible_completion_does_not_send_deepseek_options_to_other_models() -> (
    None
):
    seen_payload: dict[str, object] = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal seen_payload
        seen_payload = json.loads(request.content.decode("utf-8"))
        return httpx.Response(200, json={"choices": [{"message": {"content": "ok"}}]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        response = await complete_openai(
            make_test_provider_profile().model_copy(update={"default_model": "gpt-test"}),
            "test-key",
            "gpt-test",
            "system",
            "user",
            client,
        )

    assert response.text == "ok"
    assert "thinking" not in seen_payload


@pytest.mark.asyncio
async def test_openai_compatible_completion_rejects_empty_content() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        _ = request
        return httpx.Response(
            200,
            json={
                "choices": [{"message": {"content": ""}}],
                "usage": {
                    "prompt_tokens": 680,
                    "completion_tokens": 87,
                    "completion_tokens_details": {"reasoning_tokens": 87},
                    "total_tokens": 767,
                },
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(LLMClientError, match="empty text content"):
            await complete_openai(
                make_test_provider_profile(),
                "test-key",
                "deepseek-v4-flash",
                "system",
                "user",
                client,
            )


def test_translation_prompt_uses_human_readable_target_language() -> None:
    system_prompt, user_prompt = build_translation_prompt(
        "Recall that $P_{i:}=\\mathrm{softmax}(S_{i:})$.",
        "zh-CN",
    )

    assert "Simplified Chinese (zh-CN)" in system_prompt
    assert "Translate every natural-language English sentence" in system_prompt
    assert "never leave the response blank" in system_prompt
    assert "Current block to translate" in user_prompt


def make_test_provider_profile() -> ProviderProfile:
    now = datetime.now(UTC)
    return ProviderProfile(
        id="provider-1",
        name="DeepSeek Compatible",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.example.com/v1",
        key_ref=None,
        default_model="deepseek-v4-flash",
        capabilities={},
        created_at=now,
        updated_at=now,
    )
