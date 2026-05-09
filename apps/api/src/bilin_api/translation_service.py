from __future__ import annotations

import asyncio
import json
import re
from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager
from time import monotonic
from typing import Any

from bilin_api.article_store import (
    create_translation_variant,
    find_cached_translation_variant,
    get_block_by_uid,
    list_article_items,
    list_blocks,
    list_translation_variants,
    resolve_library,
    set_translation_variant_default,
    sha256_text,
)
from bilin_api.glossary_service import active_article_glossary_version, glossary_context_markdown
from bilin_api.llm import LLMClientError, LLMResponse, translate_markdown
from bilin_api.repositories import (
    create_job,
    find_translation_memory_entries,
    get_provider_api_key,
    get_provider_profile,
    list_jobs,
    record_translation_memory_entry,
)
from bilin_api.schemas import (
    ArticleTranslations,
    DocumentBlock,
    Job,
    JobStatus,
    JobType,
    Library,
    LibraryTranslationBatchResult,
    ProviderProfile,
    TranslationBatchRequest,
    TranslationBatchResult,
    TranslationMemoryLookupResult,
    TranslationVariant,
)

Translator = Callable[
    [ProviderProfile, str, str, str, str, str, str | None],
    Awaitable[LLMResponse],
]

TRANSLATABLE_BLOCK_TYPES = {"paragraph", "list", "figure", "table"}
_PROVIDER_SEMAPHORES: dict[tuple[str, int], asyncio.Semaphore] = {}
_PROVIDER_RATE_LOCKS: dict[str, asyncio.Lock] = {}
_PROVIDER_NEXT_REQUEST_AT: dict[str, float] = {}


async def queue_article_translation(
    library: Library,
    revision_id: str,
    request: TranslationBatchRequest,
) -> TranslationBatchResult:
    provider = await get_provider_profile(request.provider_profile_id)
    if provider is None:
        msg = f"Provider profile not found: {request.provider_profile_id}"
        raise ValueError(msg)
    model = request.model or provider.default_model
    if not model:
        msg = "Translation requires a model or provider default_model."
        raise ValueError(msg)
    effective_glossary_version = request.glossary_version or await active_article_glossary_version(
        library,
        revision_id,
        request.target_language,
    )

    selected_uids = set(request.block_uids or [])
    blocks = await list_blocks(library, revision_id)
    glossary_context = await glossary_context_markdown(
        library,
        revision_id,
        request.target_language,
    )
    job_ids: list[str] = []
    jobs_created = 0
    existing_jobs = 0
    cached_blocks = 0
    skipped_blocks = 0
    for block in blocks:
        if selected_uids and block.block_uid not in selected_uids:
            continue
        if not is_translatable_block(block):
            skipped_blocks += 1
            continue
        context_markdown = build_translation_context(blocks, block, glossary_context)
        context_hash = translation_context_hash(
            block=block,
            target_language=request.target_language,
            provider_profile_id=provider.id,
            model=model,
            glossary_version=effective_glossary_version,
            context_markdown=context_markdown,
            custom_prompt=request.custom_prompt,
        )
        cached = await find_cached_translation_variant(
            library=library,
            block=block,
            target_language=request.target_language,
            provider_profile_id=provider.id,
            model=model,
            glossary_version=effective_glossary_version,
            context_hash=context_hash,
        )
        if cached is not None and not request.force:
            cached_blocks += 1
            continue
        existing_job_id = await find_existing_translation_job(
            library_id=library.id,
            revision_id=revision_id,
            block_uid=block.block_uid,
            target_language=request.target_language,
            provider_profile_id=provider.id,
            model=model,
            context_hash=context_hash,
        )
        if existing_job_id and not request.force:
            existing_jobs += 1
            job_ids.append(existing_job_id)
            continue
        job = await create_job(
            JobType.translate_block,
            payload={
                "library_id": library.id,
                "article_revision_id": revision_id,
                "block_uid": block.block_uid,
                "target_language": request.target_language,
                "provider_profile_id": provider.id,
                "model": model,
                "glossary_version": effective_glossary_version,
                "content_hash": block.content_hash,
                "context_hash": context_hash,
                "custom_prompt": request.custom_prompt,
                "force": request.force,
                "max_attempts": 3,
            },
        )
        job_ids.append(job.id)
        jobs_created += 1
    return TranslationBatchResult(
        library_id=library.id,
        article_revision_id=revision_id,
        target_language=request.target_language,
        jobs_created=jobs_created,
        existing_jobs=existing_jobs,
        cached_blocks=cached_blocks,
        skipped_blocks=skipped_blocks,
        job_ids=job_ids,
    )


async def queue_library_missing_translations(
    library: Library,
    request: TranslationBatchRequest,
) -> LibraryTranslationBatchResult:
    await require_translation_provider(request)
    article_results: list[TranslationBatchResult] = []
    job_ids: list[str] = []
    articles_considered = 0
    for item in await list_article_items(library, request.target_language):
        if item.article_revision.status == "archived":
            continue
        articles_considered += 1
        status = item.translation_status
        if status.translatable_blocks == 0 or status.status == "translated":
            continue
        missing_uids = await missing_translation_block_uids(
            library,
            item.article_revision.id,
            request.target_language,
        )
        if not missing_uids:
            continue
        scoped_request = request.model_copy(
            update={
                "block_uids": missing_uids,
                "force": False,
            }
        )
        result = await queue_article_translation(library, item.article_revision.id, scoped_request)
        if result.jobs_created or result.existing_jobs or result.cached_blocks:
            article_results.append(result)
            job_ids.extend(result.job_ids)
    return LibraryTranslationBatchResult(
        library_id=library.id,
        target_language=request.target_language,
        articles_considered=articles_considered,
        articles_queued=sum(
            1
            for result in article_results
            if result.jobs_created or result.existing_jobs or result.cached_blocks
        ),
        jobs_created=sum(result.jobs_created for result in article_results),
        existing_jobs=sum(result.existing_jobs for result in article_results),
        cached_blocks=sum(result.cached_blocks for result in article_results),
        skipped_blocks=sum(result.skipped_blocks for result in article_results),
        job_ids=job_ids,
        article_results=article_results,
    )


async def require_translation_provider(request: TranslationBatchRequest) -> ProviderProfile:
    provider = await get_provider_profile(request.provider_profile_id)
    if provider is None:
        msg = f"Provider profile not found: {request.provider_profile_id}"
        raise ValueError(msg)
    model = request.model or provider.default_model
    if not model:
        msg = "Translation requires a model or provider default_model."
        raise ValueError(msg)
    return provider


async def missing_translation_block_uids(
    library: Library,
    revision_id: str,
    target_language: str,
) -> list[str]:
    blocks = await list_blocks(library, revision_id)
    variants = await list_translation_variants(library, revision_id, target_language)
    translated_block_ids = {
        variant.block_id
        for variant in variants
        if translation_variant_matches_current_block(variant, blocks)
    }
    return [
        block.block_uid
        for block in blocks
        if is_translatable_block(block) and block.id not in translated_block_ids
    ]


def translation_variant_matches_current_block(
    variant: TranslationVariant,
    blocks: list[DocumentBlock],
) -> bool:
    if variant.validation_status != "ok":
        return False
    block = next((candidate for candidate in blocks if candidate.id == variant.block_id), None)
    if block is None:
        return False
    metadata = variant.metadata
    if metadata.get("block_uid") and metadata["block_uid"] != block.block_uid:
        return False
    return not (metadata.get("content_hash") and metadata["content_hash"] != block.content_hash)


async def run_translate_block_job(
    job: Job,
    translator: Translator | None = None,
) -> dict[str, Any]:
    library = await resolve_library(str(job.payload["library_id"]))
    revision_id = str(job.payload["article_revision_id"])
    block_uid = str(job.payload["block_uid"])
    block = await get_block_by_uid(library, revision_id, block_uid)
    if block is None:
        msg = f"Block not found: {block_uid}"
        raise ValueError(msg)
    if not is_translatable_block(block):
        msg = f"Block is not translatable: {block.block_type}"
        raise ValueError(msg)
    if job.payload.get("content_hash") and job.payload["content_hash"] != block.content_hash:
        msg = f"Block content changed before translation: {block_uid}"
        raise ValueError(msg)

    provider = await get_provider_profile(str(job.payload["provider_profile_id"]))
    if provider is None:
        msg = f"Provider profile not found: {job.payload['provider_profile_id']}"
        raise ValueError(msg)
    api_key = await get_provider_api_key(provider)
    if not api_key:
        msg = f"Provider profile has no API key: {provider.id}"
        raise ValueError(msg)
    model = str(job.payload.get("model") or provider.default_model or "")
    if not model:
        raise ValueError("Translation job has no model.")

    target_language = str(job.payload["target_language"])
    glossary_version = job.payload.get("glossary_version")
    context_hash = str(job.payload["context_hash"])
    glossary_version_text = str(glossary_version) if glossary_version else None
    force = bool(job.payload.get("force"))
    if not force:
        cached = await find_cached_translation_variant(
            library=library,
            block=block,
            target_language=target_language,
            provider_profile_id=provider.id,
            model=model,
            glossary_version=glossary_version_text,
            context_hash=context_hash,
        )
        if cached is not None:
            return {
                "article_revision_id": revision_id,
                "block_uid": block.block_uid,
                "translation_variant_id": cached.id,
                "target_language": target_language,
                "cache_hit": True,
                "cache_source": "article",
            }
        memory_hit = await create_variant_from_translation_memory(
            library=library,
            block=block,
            target_language=target_language,
            glossary_version=glossary_version_text,
            context_hash=context_hash,
        )
        if memory_hit is not None:
            return {
                "article_revision_id": revision_id,
                "block_uid": block.block_uid,
                "translation_variant_id": memory_hit.id,
                "target_language": target_language,
                "cache_hit": True,
                "cache_source": "translation_memory",
            }

    blocks = await list_blocks(library, revision_id)
    glossary_context = await glossary_context_markdown(library, revision_id, target_language)
    context_markdown = build_translation_context(blocks, block, glossary_context)
    active_translator = translator or translate_markdown
    async with provider_request_slot(provider):
        response = await active_translator(
            provider,
            api_key,
            model,
            block.source_markdown,
            target_language,
            context_markdown,
            job.payload.get("custom_prompt"),
        )
    cleaned_translation = clean_translation_markdown(block.source_markdown, response.text)
    validation_status = validate_translation_markdown(block.source_markdown, cleaned_translation)
    variant = await create_translation_variant(
        library=library,
        block=block,
        target_language=target_language,
        raw_markdown=cleaned_translation,
        provider_profile_id=provider.id,
        model=model,
        glossary_version=glossary_version_text,
        validation_status=validation_status,
        metadata={
            "block_uid": block.block_uid,
            "content_hash": block.content_hash,
            "context_hash": context_hash,
            "provider_protocol": provider.protocol.value,
            "usage": response.usage,
            "custom_prompt_hash": custom_prompt_hash(job.payload.get("custom_prompt")),
            "validation_status": validation_status,
        },
    )
    if validation_status == "ok" and custom_prompt_hash(job.payload.get("custom_prompt")) is None:
        await record_translation_memory_entry(
            source_hash=block.content_hash,
            source_markdown=block.source_markdown,
            target_language=target_language,
            raw_markdown=cleaned_translation,
            provider_profile_id=provider.id,
            model=model,
            validation_status=validation_status,
            glossary_version=glossary_version_text,
            metadata={
                "library_id": library.id,
                "article_revision_id": revision_id,
                "block_uid": block.block_uid,
                "translation_variant_id": variant.id,
                "context_hash": context_hash,
            },
        )
    return {
        "article_revision_id": revision_id,
        "block_uid": block.block_uid,
        "translation_variant_id": variant.id,
        "target_language": target_language,
        "cache_hit": False,
        "validation_status": validation_status,
    }


async def get_article_translations(
    library: Library,
    revision_id: str,
    target_language: str,
) -> ArticleTranslations:
    return ArticleTranslations(
        article_revision_id=revision_id,
        target_language=target_language,
        variants=await list_translation_variants(library, revision_id, target_language),
    )


async def select_article_translation_variant(
    library: Library,
    revision_id: str,
    variant_id: str,
) -> TranslationVariant | None:
    return await set_translation_variant_default(library, revision_id, variant_id)


async def lookup_article_translation_memory(
    library: Library,
    revision_id: str,
    block_uid: str,
    target_language: str,
    glossary_version: str | None = None,
) -> TranslationMemoryLookupResult:
    block = await get_block_by_uid(library, revision_id, block_uid)
    if block is None:
        msg = f"Block not found: {block_uid}"
        raise ValueError(msg)
    effective_glossary_version = glossary_version or await active_article_glossary_version(
        library,
        revision_id,
        target_language,
    )
    entries = await find_translation_memory_entries(
        source_hash=block.content_hash,
        target_language=target_language,
        glossary_version=effective_glossary_version,
    )
    return TranslationMemoryLookupResult(
        article_revision_id=revision_id,
        block_uid=block.block_uid,
        target_language=target_language,
        content_hash=block.content_hash,
        glossary_version=effective_glossary_version,
        entries=entries,
    )


async def create_variant_from_translation_memory(
    *,
    library: Library,
    block: DocumentBlock,
    target_language: str,
    glossary_version: str | None,
    context_hash: str,
) -> TranslationVariant | None:
    entries = await find_translation_memory_entries(
        source_hash=block.content_hash,
        target_language=target_language,
        glossary_version=glossary_version,
        limit=1,
    )
    if not entries:
        return None
    entry = entries[0]
    return await create_translation_variant(
        library=library,
        block=block,
        target_language=target_language,
        raw_markdown=entry.raw_markdown,
        provider_profile_id=entry.provider_profile_id,
        model=entry.model,
        glossary_version=glossary_version,
        validation_status=entry.validation_status,
        metadata={
            "block_uid": block.block_uid,
            "content_hash": block.content_hash,
            "context_hash": context_hash,
            "cache_source": "translation_memory",
            "translation_memory_entry_id": entry.id,
        },
    )


def is_translatable_block(block: DocumentBlock) -> bool:
    return block.block_type in TRANSLATABLE_BLOCK_TYPES and bool(block.source_markdown.strip())


async def find_existing_translation_job(
    library_id: str,
    revision_id: str,
    block_uid: str,
    target_language: str,
    provider_profile_id: str,
    model: str | None,
    context_hash: str,
) -> str | None:
    active_statuses = {JobStatus.queued, JobStatus.running, JobStatus.paused}
    for job in await list_jobs():
        if job.type != JobType.translate_block or job.status not in active_statuses:
            continue
        payload = job.payload
        if (
            payload.get("library_id") == library_id
            and payload.get("article_revision_id") == revision_id
            and payload.get("block_uid") == block_uid
            and payload.get("target_language") == target_language
            and payload.get("provider_profile_id") == provider_profile_id
            and payload.get("model") == model
            and payload.get("context_hash") == context_hash
        ):
            return job.id
    return None


def build_neighbor_context(blocks: list[DocumentBlock], block: DocumentBlock) -> str:
    index = next((i for i, candidate in enumerate(blocks) if candidate.id == block.id), -1)
    if index < 0:
        return ""
    context: list[str] = []
    for candidate in blocks[max(0, index - 2) : index]:
        if candidate.source_markdown.strip():
            context.append(f"Previous {candidate.block_type}: {candidate.source_markdown}")
    for candidate in blocks[index + 1 : index + 3]:
        if candidate.source_markdown.strip():
            context.append(f"Next {candidate.block_type}: {candidate.source_markdown}")
    return "\n\n".join(context)


def build_translation_context(
    blocks: list[DocumentBlock],
    block: DocumentBlock,
    glossary_context: str,
) -> str:
    parts = [part for part in (glossary_context, build_neighbor_context(blocks, block)) if part]
    return "\n\n".join(parts)


def translation_context_hash(
    block: DocumentBlock,
    target_language: str,
    provider_profile_id: str,
    model: str | None,
    glossary_version: str | None,
    context_markdown: str,
    custom_prompt: str | None,
) -> str:
    payload = {
        "content_hash": block.content_hash,
        "target_language": target_language,
        "provider_profile_id": provider_profile_id,
        "model": model,
        "glossary_version": glossary_version,
        "context_markdown_hash": sha256_text(context_markdown),
        "custom_prompt_hash": custom_prompt_hash(custom_prompt),
        "prompt_version": "translation.v1",
    }
    return sha256_text(json.dumps(payload, sort_keys=True))


def custom_prompt_hash(custom_prompt: Any) -> str | None:
    if not isinstance(custom_prompt, str) or not custom_prompt.strip():
        return None
    return sha256_text(custom_prompt.strip())


def clean_translation_markdown(source_markdown: str, translated_markdown: str) -> str:
    source = source_markdown.strip()
    translated = translated_markdown.strip()
    if not source or not translated:
        return translated
    if normalize_translation_text(source) == normalize_translation_text(translated):
        return translated
    if translated.startswith(source):
        remainder = translated[len(source) :].lstrip()
        remainder = remainder.lstrip("\n\r\t :：-—–")
        if remainder and normalize_translation_text(remainder) != normalize_translation_text(
            source
        ):
            return remainder.strip()
    return translated


def normalize_translation_text(markdown: str) -> str:
    return re.sub(r"\s+", " ", markdown.strip()).casefold()


def validate_translation_markdown(source_markdown: str, translated_markdown: str) -> str:
    translated = translated_markdown.strip()
    if not translated:
        return "empty"
    if normalize_translation_text(source_markdown) == normalize_translation_text(
        translated
    ) and not is_translation_invariant_markdown(source_markdown):
        return "unchanged_source"
    if translated.count("```") % 2 != 0:
        return "unbalanced_code_fence"
    source_fences = source_markdown.count("```")
    translated_fences = translated_markdown.count("```")
    if source_fences and translated_fences != source_fences:
        return "code_fence_count_changed"
    return "ok"


def is_translation_invariant_markdown(markdown: str) -> bool:
    text = markdown.strip()
    if not text:
        return False
    visible = re.sub(r"\[([^\]]+)]\([^)]*\)", r"\1", text)
    visible = re.sub(r"[^A-Za-z0-9]+", " ", visible).strip()
    words = re.findall(r"[A-Za-z][A-Za-z0-9-]*", visible)
    if not words:
        return True
    return len(words) <= 4 and all(word.upper() == word for word in words)


@asynccontextmanager
async def provider_request_slot(provider: ProviderProfile):
    limit = max(1, min(provider.max_concurrent_requests, 32))
    semaphore_key = (provider.id, limit)
    semaphore = _PROVIDER_SEMAPHORES.setdefault(semaphore_key, asyncio.Semaphore(limit))
    async with semaphore:
        await wait_for_provider_rate_limit(provider)
        yield


async def wait_for_provider_rate_limit(provider: ProviderProfile) -> None:
    if provider.requests_per_minute is None:
        return
    requests_per_minute = max(1, min(provider.requests_per_minute, 6000))
    interval_seconds = 60.0 / requests_per_minute
    lock = _PROVIDER_RATE_LOCKS.setdefault(provider.id, asyncio.Lock())
    async with lock:
        now = monotonic()
        next_at = _PROVIDER_NEXT_REQUEST_AT.get(provider.id, now)
        delay = max(0.0, next_at - now)
        if delay > 0:
            await asyncio.sleep(delay)
            now = monotonic()
        _PROVIDER_NEXT_REQUEST_AT[provider.id] = max(next_at, now) + interval_seconds


def reset_provider_throttles() -> None:
    _PROVIDER_SEMAPHORES.clear()
    _PROVIDER_RATE_LOCKS.clear()
    _PROVIDER_NEXT_REQUEST_AT.clear()


def is_transient_translation_error(exc: Exception) -> bool:
    if not isinstance(exc, LLMClientError):
        return False
    message = str(exc).lower()
    terminal_markers = (
        "400",
        "401",
        "403",
        "404",
        "unauthorized",
        "forbidden",
        "authentication",
        "api key",
        "invalid_api_key",
        "model_not_found",
        "context_length",
        "maximum context",
    )
    return not any(marker in message for marker in terminal_markers)
