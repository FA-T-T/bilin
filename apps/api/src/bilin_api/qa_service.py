from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator, Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from bilin_api.article_store import (
    create_chat_message,
    get_block_by_uid,
    list_blocks,
    list_chat_messages,
    search_blocks,
)
from bilin_api.database import utc_now
from bilin_api.embedding_service import get_article_embedding_status, hybrid_search_blocks
from bilin_api.llm import LLMResponse, answer_article_question
from bilin_api.repositories import get_provider_api_key, get_provider_profile
from bilin_api.schemas import (
    ArticleChatHistory,
    ChatAskRequest,
    ChatAskResult,
    DocumentBlock,
    ExternalCitation,
    Library,
    ProviderProfile,
    RetrievalMode,
    RetrievedBlock,
)

Answerer = Callable[
    [ProviderProfile, str, str, str, str, bool],
    Awaitable[LLMResponse],
]

CONTEXT_NEIGHBORS = 1
ANSWER_STREAM_CHARS = 120


@dataclass(frozen=True)
class QuestionContext:
    provider: ProviderProfile
    api_key: str
    model: str
    retrieved_blocks: list[RetrievedBlock]
    evidence_markdown: str


@dataclass(frozen=True)
class EvidenceCandidate:
    block: DocumentBlock
    score: float
    retrieval_method: str = "fts"
    fts_score: float | None = None
    vector_score: float | None = None


async def get_article_chat_history(library: Library, revision_id: str) -> ArticleChatHistory:
    return ArticleChatHistory(
        article_revision_id=revision_id,
        messages=await list_chat_messages(library, revision_id),
    )


async def ask_article_question(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
    answerer: Answerer | None = None,
) -> ChatAskResult:
    context = await prepare_question_context(library, revision_id, request)
    response = await complete_question_answer(context, request, answerer)
    return await persist_question_answer(library, revision_id, request, context, response)


async def prepare_question_context(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
) -> QuestionContext:
    provider = await get_provider_profile(request.provider_profile_id)
    if provider is None:
        msg = f"Provider profile not found: {request.provider_profile_id}"
        raise ValueError(msg)
    if request.native_search and not provider.capabilities.get("native_search"):
        msg = "Native search was requested, but the selected provider profile does not support it."
        raise ValueError(msg)
    model = request.model or provider.default_model
    if not model:
        msg = "Question answering requires a model or provider default_model."
        raise ValueError(msg)
    api_key = await get_provider_api_key(provider)
    if not api_key:
        msg = f"Provider profile has no API key: {provider.id}"
        raise ValueError(msg)

    evidence_candidates = await retrieve_evidence_candidates(library, revision_id, request)
    if not evidence_candidates:
        msg = "No article blocks were available for grounded question answering."
        raise ValueError(msg)
    retrieved = [retrieved_block_from_candidate(candidate) for candidate in evidence_candidates]
    evidence_markdown = evidence_to_markdown(retrieved)
    return QuestionContext(
        provider=provider,
        api_key=api_key,
        model=model,
        retrieved_blocks=retrieved,
        evidence_markdown=evidence_markdown,
    )


async def complete_question_answer(
    context: QuestionContext,
    request: ChatAskRequest,
    answerer: Answerer | None = None,
) -> LLMResponse:
    active_answerer = answerer or answer_article_question
    return await active_answerer(
        context.provider,
        context.api_key,
        context.model,
        request.question,
        context.evidence_markdown,
        request.native_search,
    )


async def persist_question_answer(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
    context: QuestionContext,
    response: LLMResponse,
) -> ChatAskResult:
    source_refs = [block.block_uid for block in context.retrieved_blocks]
    external_refs = (
        normalize_external_refs(response.raw, context.provider, context.model)
        if request.native_search
        else []
    )
    user_message = await create_chat_message(
        library=library,
        revision_id=revision_id,
        role="user",
        content=request.question,
        metadata={
            "provider_profile_id": context.provider.id,
            "model": context.model,
            "current_block_uid": request.current_block_uid,
            "native_search": request.native_search,
        },
    )
    assistant_message = await create_chat_message(
        library=library,
        revision_id=revision_id,
        role="assistant",
        content=response.text,
        source_refs=source_refs,
        external_refs=[citation.model_dump(mode="json") for citation in external_refs],
        metadata={
            "provider_profile_id": context.provider.id,
            "model": context.model,
            "usage": response.usage,
            "retrieval": [block.model_dump() for block in context.retrieved_blocks],
            "native_search": request.native_search,
            "current_block_uid": request.current_block_uid,
            "evidence_policy": "external_native_search_allowed"
            if request.native_search
            else "current_paper_only",
        },
    )
    return ChatAskResult(
        article_revision_id=revision_id,
        user_message=user_message,
        assistant_message=assistant_message,
        cited_blocks=context.retrieved_blocks,
        external_refs=external_refs,
        native_search_used=request.native_search,
    )


async def stream_question_answer_events(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
    context: QuestionContext,
    answerer: Answerer | None = None,
) -> AsyncIterator[str]:
    yield sse_event(
        "evidence",
        {
            "article_revision_id": revision_id,
            "cited_blocks": [block.model_dump(mode="json") for block in context.retrieved_blocks],
            "native_search_requested": request.native_search,
            "evidence_policy": "external_native_search_allowed"
            if request.native_search
            else "current_paper_only",
        },
    )
    response = await complete_question_answer(context, request, answerer)
    for chunk in chunk_text(response.text, ANSWER_STREAM_CHARS):
        yield sse_event("delta", {"text": chunk})
        await asyncio.sleep(0)
    result = await persist_question_answer(library, revision_id, request, context, response)
    yield sse_event("done", result.model_dump(mode="json"))


def sse_event(event: str, data: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def chunk_text(text: str, size: int) -> list[str]:
    if not text:
        return [""]
    return [text[index : index + size] for index in range(0, len(text), size)]


async def retrieve_evidence_blocks(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
) -> list[tuple[DocumentBlock, float]]:
    return [
        (candidate.block, candidate.score)
        for candidate in await retrieve_evidence_candidates(library, revision_id, request)
    ]


async def retrieve_evidence_candidates(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
) -> list[EvidenceCandidate]:
    selected: dict[str, tuple[DocumentBlock, float]] = {}
    if request.current_block_uid:
        blocks = await list_blocks(library, revision_id)
        current_index = next(
            (
                index
                for index, block in enumerate(blocks)
                if block.block_uid == request.current_block_uid
            ),
            -1,
        )
        if current_index >= 0:
            for index in range(
                max(0, current_index - CONTEXT_NEIGHBORS),
                min(len(blocks), current_index + CONTEXT_NEIGHBORS + 1),
            ):
                selected[blocks[index].block_uid] = (
                    blocks[index],
                    -100.0 + abs(index - current_index),
                )
        else:
            current = await get_block_by_uid(library, revision_id, request.current_block_uid)
            if current is not None:
                selected[current.block_uid] = (current, -100.0)
    candidates = [
        EvidenceCandidate(block=block, score=score, retrieval_method="current_block")
        for block, score in selected.values()
    ]
    search_candidates = await retrieve_search_candidates(library, revision_id, request)
    existing = {candidate.block.block_uid for candidate in candidates}
    candidates.extend(
        candidate for candidate in search_candidates if candidate.block.block_uid not in existing
    )
    return sorted(candidates, key=lambda item: item.score)[: request.max_blocks]


async def retrieve_search_candidates(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
) -> list[EvidenceCandidate]:
    retrieval_mode = await resolve_retrieval_mode(library, revision_id, request)
    if retrieval_mode == RetrievalMode.hybrid:
        matches = await hybrid_search_blocks(
            library,
            revision_id,
            request.question,
            limit=request.max_blocks,
        )
        if matches:
            return [
                EvidenceCandidate(
                    block=match.block,
                    score=match.score,
                    retrieval_method=match.retrieval_method,
                    fts_score=match.fts_score,
                    vector_score=match.vector_score,
                )
                for match in matches
            ]
    return [
        EvidenceCandidate(block=block, score=score, retrieval_method="fts", fts_score=score)
        for block, score in await search_blocks(
            library,
            revision_id,
            request.question,
            limit=request.max_blocks,
        )
    ]


async def resolve_retrieval_mode(
    library: Library,
    revision_id: str,
    request: ChatAskRequest,
) -> RetrievalMode:
    if request.retrieval_mode != RetrievalMode.auto:
        return request.retrieval_mode
    status = await get_article_embedding_status(library, revision_id)
    if status.embedded_blocks > 0 and status.stale_blocks == 0:
        return RetrievalMode.hybrid
    return RetrievalMode.fts


def retrieved_block_from_candidate(candidate: EvidenceCandidate) -> RetrievedBlock:
    return RetrievedBlock(
        block_uid=candidate.block.block_uid,
        block_type=candidate.block.block_type,
        structural_path=candidate.block.structural_path,
        source_markdown=candidate.block.source_markdown,
        score=candidate.score,
        retrieval_method=candidate.retrieval_method,
        fts_score=candidate.fts_score,
        vector_score=candidate.vector_score,
    )


def evidence_to_markdown(blocks: list[RetrievedBlock]) -> str:
    return "\n\n".join(
        (f"[{block.block_uid}] {block.block_type} {block.structural_path}\n{block.source_markdown}")
        for block in blocks
    )


def normalize_external_refs(
    raw: dict[str, Any],
    provider: ProviderProfile,
    model: str,
) -> list[ExternalCitation]:
    citations = raw.get("citations") or raw.get("external_refs") or []
    if not isinstance(citations, list):
        return []
    normalized: list[ExternalCitation] = []
    retrieved_at = utc_now()
    for item in citations:
        if not isinstance(item, dict):
            continue
        metadata = {
            key: value
            for key, value in item.items()
            if key
            not in {
                "title",
                "url",
                "doi",
                "arxiv_id",
                "arxivId",
                "arxiv",
                "snippet",
                "raw_snippet",
                "text",
            }
        }
        normalized.append(
            ExternalCitation(
                title=optional_string(item.get("title")),
                url=optional_string(item.get("url")),
                doi=optional_string(item.get("doi")),
                arxiv_id=optional_string(
                    item.get("arxiv_id") or item.get("arxivId") or item.get("arxiv")
                ),
                retrieved_at=retrieved_at,
                model=model,
                raw_snippet=optional_string(
                    item.get("raw_snippet") or item.get("snippet") or item.get("text")
                )
                or "",
                metadata={"provider_profile_id": provider.id, **metadata},
            )
        )
    return normalized


def optional_string(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None
