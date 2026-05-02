from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import httpx

from bilin_api.repositories import default_provider_base_url
from bilin_api.schemas import ProviderModelInfo, ProviderProfile, ProviderProtocol


class LLMClientError(Exception):
    pass


@dataclass(frozen=True)
class LLMResponse:
    text: str
    raw: dict[str, Any] = field(default_factory=dict)
    usage: dict[str, Any] = field(default_factory=dict)


async def list_provider_models(
    protocol: ProviderProtocol,
    api_key: str,
    base_url: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> list[ProviderModelInfo]:
    if protocol == ProviderProtocol.anthropic_compatible:
        return await list_anthropic_models(api_key, base_url, client)
    return await list_openai_models(api_key, base_url, client)


async def list_openai_models(
    api_key: str,
    base_url: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> list[ProviderModelInfo]:
    active_base_url = (
        base_url or default_provider_base_url(ProviderProtocol.openai_compatible)
    ).rstrip("/")
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=30)
    try:
        response = await active_client.get(
            f"{active_base_url}/models",
            headers={"Authorization": f"Bearer {api_key}"},
        )
        response.raise_for_status()
        return normalize_openai_models(response.json())
    except httpx.HTTPError as exc:
        raise LLMClientError(str(exc)) from exc
    finally:
        if owns_client:
            await active_client.aclose()


async def list_anthropic_models(
    api_key: str,
    base_url: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> list[ProviderModelInfo]:
    active_base_url = (
        base_url or default_provider_base_url(ProviderProtocol.anthropic_compatible)
    ).rstrip("/")
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=30)
    try:
        response = await active_client.get(
            f"{active_base_url}/v1/models",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
            },
        )
        response.raise_for_status()
        return normalize_anthropic_models(response.json())
    except httpx.HTTPError as exc:
        raise LLMClientError(str(exc)) from exc
    finally:
        if owns_client:
            await active_client.aclose()


async def translate_markdown(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    source_markdown: str,
    target_language: str,
    context_markdown: str = "",
    custom_prompt: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> LLMResponse:
    system_prompt, user_prompt = build_translation_prompt(
        source_markdown=source_markdown,
        target_language=target_language,
        context_markdown=context_markdown,
        custom_prompt=custom_prompt,
    )
    if provider.protocol == ProviderProtocol.anthropic_compatible:
        return await complete_anthropic(
            provider,
            api_key,
            model,
            system_prompt,
            user_prompt,
            client,
        )
    return await complete_openai(provider, api_key, model, system_prompt, user_prompt, client)


async def answer_article_question(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    question: str,
    evidence_markdown: str,
    native_search: bool = False,
    client: httpx.AsyncClient | None = None,
) -> LLMResponse:
    system_prompt, user_prompt = build_question_answer_prompt(
        question=question,
        evidence_markdown=evidence_markdown,
        native_search=native_search,
    )
    if provider.protocol == ProviderProtocol.anthropic_compatible:
        return await complete_anthropic(
            provider,
            api_key,
            model,
            system_prompt,
            user_prompt,
            client,
        )
    return await complete_openai(provider, api_key, model, system_prompt, user_prompt, client)


async def generate_note_patch_markdown(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    template_name: str,
    template_prompt: str,
    evidence_markdown: str,
    chat_markdown: str = "",
    client: httpx.AsyncClient | None = None,
) -> LLMResponse:
    system_prompt, user_prompt = build_note_patch_prompt(
        template_name=template_name,
        template_prompt=template_prompt,
        evidence_markdown=evidence_markdown,
        chat_markdown=chat_markdown,
    )
    if provider.protocol == ProviderProtocol.anthropic_compatible:
        return await complete_anthropic(
            provider,
            api_key,
            model,
            system_prompt,
            user_prompt,
            client,
        )
    return await complete_openai(provider, api_key, model, system_prompt, user_prompt, client)


def build_translation_prompt(
    source_markdown: str,
    target_language: str,
    context_markdown: str = "",
    custom_prompt: str | None = None,
) -> tuple[str, str]:
    system_prompt = (
        "You are translating academic paper blocks. Translate only the current block into "
        f"{target_language}. Preserve Markdown, citations, variable names, formulas, and code. "
        "Do not add explanations or translate surrounding context."
    )
    if custom_prompt:
        system_prompt = f"{system_prompt}\nAdditional user instruction: {custom_prompt.strip()}"
    user_prompt = (
        "Read-only context:\n"
        f"{context_markdown.strip() or '(none)'}\n\n"
        "Current block to translate:\n"
        f"{source_markdown.strip()}\n\n"
        "Return only the translated Markdown for the current block."
    )
    return system_prompt, user_prompt


def build_note_patch_prompt(
    template_name: str,
    template_prompt: str,
    evidence_markdown: str,
    chat_markdown: str = "",
) -> tuple[str, str]:
    system_prompt = (
        "You generate a proposed lecture-note patch for one academic paper. Use only supplied "
        "paper blocks and saved chat history. Cite source block identifiers in square brackets, "
        "such as [p-0001]. Do not invent external claims."
    )
    user_prompt = (
        f"Template: {template_name}\n"
        f"Template requirements:\n{template_prompt.strip()}\n\n"
        f"Paper evidence:\n{evidence_markdown.strip() or '(none)'}\n\n"
        f"Saved chat context:\n{chat_markdown.strip() or '(none)'}\n\n"
        "Return only Markdown for the proposed note patch."
    )
    return system_prompt, user_prompt


def build_question_answer_prompt(
    question: str,
    evidence_markdown: str,
    native_search: bool = False,
) -> tuple[str, str]:
    external_policy = (
        "External model-native search is enabled. Separate current-paper evidence from external "
        "evidence, and include external citation metadata when available."
        if native_search
        else "Do not use or invent external evidence. If the supplied paper blocks do not support "
        "an answer, say that the paper context is insufficient."
    )
    system_prompt = (
        "You answer questions about one academic paper. Ground every substantive claim in the "
        "provided paper blocks and cite block identifiers in square brackets, such as [p-0001]. "
        f"{external_policy}"
    )
    user_prompt = (
        "Paper evidence blocks:\n"
        f"{evidence_markdown.strip() or '(none)'}\n\n"
        "Question:\n"
        f"{question.strip()}\n\n"
        "Return a concise answer with block citations."
    )
    return system_prompt, user_prompt


def normalize_openai_models(payload: dict[str, Any]) -> list[ProviderModelInfo]:
    raw_models = payload.get("data")
    if not isinstance(raw_models, list):
        raw_models = payload.get("models")
    if not isinstance(raw_models, list):
        raise LLMClientError("OpenAI-compatible model listing did not contain a model list.")
    models: list[ProviderModelInfo] = []
    for raw_model in raw_models:
        if not isinstance(raw_model, dict):
            continue
        model_id = raw_model.get("id") or raw_model.get("name")
        if not isinstance(model_id, str) or not model_id.strip():
            continue
        models.append(
            ProviderModelInfo(
                id=model_id,
                display_name=string_or_none(raw_model.get("display_name"))
                or string_or_none(raw_model.get("name"))
                or model_id,
                owned_by=string_or_none(raw_model.get("owned_by")),
                created_at=string_or_none(raw_model.get("created"))
                or string_or_none(raw_model.get("created_at")),
                capabilities=infer_model_capabilities(model_id, raw_model),
                metadata=raw_model,
            )
        )
    return sorted_models(models)


def normalize_anthropic_models(payload: dict[str, Any]) -> list[ProviderModelInfo]:
    raw_models = payload.get("data")
    if not isinstance(raw_models, list):
        raw_models = payload.get("models")
    if not isinstance(raw_models, list):
        raise LLMClientError("Anthropic-compatible model listing did not contain a model list.")
    models: list[ProviderModelInfo] = []
    for raw_model in raw_models:
        if not isinstance(raw_model, dict):
            continue
        model_id = raw_model.get("id") or raw_model.get("name")
        if not isinstance(model_id, str) or not model_id.strip():
            continue
        models.append(
            ProviderModelInfo(
                id=model_id,
                display_name=string_or_none(raw_model.get("display_name"))
                or string_or_none(raw_model.get("name"))
                or model_id,
                owned_by=string_or_none(raw_model.get("owned_by")),
                created_at=string_or_none(raw_model.get("created_at")),
                capabilities=infer_model_capabilities(model_id, raw_model),
                metadata=raw_model,
            )
        )
    return sorted_models(models)


def sorted_models(models: list[ProviderModelInfo]) -> list[ProviderModelInfo]:
    return sorted(models, key=lambda model: model.id.casefold())


def string_or_none(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value
    if isinstance(value, int | float):
        return str(value)
    return None


def infer_model_capabilities(model_id: str, raw_model: dict[str, Any]) -> dict[str, Any]:
    joined = " ".join(
        str(value).casefold()
        for value in (model_id, raw_model.get("display_name"), raw_model.get("name"))
        if value
    )
    chat_capable = infer_chat_capability(joined, raw_model)
    return {
        "chat": chat_capable,
        "translation": chat_capable,
        "streaming": True,
        "vision": any(token in joined for token in ("vision", "gpt-4o", "claude-3")),
        "native_search": any(token in joined for token in ("search", "web", "sonar")),
        "pdf": any(token in joined for token in ("pdf", "document")),
    }


def infer_chat_capability(joined_model_text: str, raw_model: dict[str, Any]) -> bool:
    raw_capabilities = raw_model.get("capabilities")
    if isinstance(raw_capabilities, dict):
        for key in ("chat", "messages", "completion", "completions"):
            value = raw_capabilities.get(key)
            if isinstance(value, bool):
                return value
    non_chat_markers = (
        "embedding",
        "embed",
        "rerank",
        "reranker",
        "moderation",
        "audio",
        "whisper",
        "tts",
        "speech",
        "image",
        "dall-e",
        "sora",
        "flux",
        "clip",
    )
    return not any(marker in joined_model_text for marker in non_chat_markers)


async def complete_openai(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    system_prompt: str,
    user_prompt: str,
    client: httpx.AsyncClient | None = None,
) -> LLMResponse:
    base_url = (provider.base_url or "https://api.openai.com/v1").rstrip("/")
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=120)
    try:
        response = await active_client.post(
            f"{base_url}/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "temperature": 0.1,
            },
        )
        response.raise_for_status()
        payload = response.json()
        text = extract_openai_text(payload)
        return LLMResponse(text=text, raw=payload, usage=payload.get("usage") or {})
    except httpx.HTTPError as exc:
        raise LLMClientError(str(exc)) from exc
    finally:
        if owns_client:
            await active_client.aclose()


async def complete_anthropic(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    system_prompt: str,
    user_prompt: str,
    client: httpx.AsyncClient | None = None,
) -> LLMResponse:
    base_url = (provider.base_url or "https://api.anthropic.com").rstrip("/")
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=120)
    try:
        response = await active_client.post(
            f"{base_url}/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
            },
            json={
                "model": model,
                "system": system_prompt,
                "messages": [{"role": "user", "content": user_prompt}],
                "max_tokens": 4096,
                "temperature": 0.1,
            },
        )
        response.raise_for_status()
        payload = response.json()
        text = extract_anthropic_text(payload)
        return LLMResponse(text=text, raw=payload, usage=payload.get("usage") or {})
    except httpx.HTTPError as exc:
        raise LLMClientError(str(exc)) from exc
    finally:
        if owns_client:
            await active_client.aclose()


def extract_openai_text(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise LLMClientError("OpenAI-compatible response did not contain choices.")
    message = choices[0].get("message") if isinstance(choices[0], dict) else None
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = [
            part.get("text", "")
            for part in content
            if isinstance(part, dict) and isinstance(part.get("text"), str)
        ]
        return "\n".join(parts).strip()
    raise LLMClientError("OpenAI-compatible response did not contain text content.")


def extract_anthropic_text(payload: dict[str, Any]) -> str:
    content = payload.get("content")
    if not isinstance(content, list):
        raise LLMClientError("Anthropic-compatible response did not contain content.")
    parts = [
        part.get("text", "")
        for part in content
        if isinstance(part, dict)
        and part.get("type") == "text"
        and isinstance(part.get("text"), str)
    ]
    text = "\n".join(parts).strip()
    if not text:
        raise LLMClientError("Anthropic-compatible response did not contain text content.")
    return text
