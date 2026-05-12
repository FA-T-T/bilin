from __future__ import annotations

import asyncio
from uuid import uuid4

from bilin_api.article_store import resolve_library
from bilin_api.embedding_service import build_article_embeddings, queue_article_embedding
from bilin_api.export_service import export_article
from bilin_api.importer import import_arxiv, import_result_to_json
from bilin_api.latexml_parser import ParseFailure, parse_article_revision
from bilin_api.reader_card_service import (
    extract_article_reader_cards,
    generate_article_reader_card,
    queue_reader_card_extraction,
)
from bilin_api.repositories import (
    claim_next_job,
    complete_job,
    create_job,
    fail_job,
    get_job,
    list_provider_profiles,
    requeue_job,
    update_job_progress,
)
from bilin_api.schemas import (
    ArticleExportRequest,
    EmbedArticleRequest,
    ImportArxivRequest,
    Job,
    JobStatus,
    JobType,
    ProviderProfile,
    ReaderCardExtractionRequest,
    ReaderCardGenerationRequest,
    TranslationBatchRequest,
)
from bilin_api.translation_service import (
    is_transient_translation_error,
    queue_article_translation,
    run_translate_block_job,
)

LOCAL_PREPARATION_JOB_TYPES = (
    JobType.import_arxiv,
    JobType.parse_article,
    JobType.embed_article,
    JobType.export_article,
    JobType.extract_reader_cards,
)
MODEL_JOB_TYPES = (
    JobType.translate_block,
    JobType.generate_reader_card,
)


async def run_worker(
    poll_interval: float = 0.5,
    max_poll_interval: float | None = None,
    once: bool = False,
    stop_event: asyncio.Event | None = None,
) -> None:
    worker_id = f"worker-{uuid4()}"
    if max_poll_interval is None:
        max_poll_interval = max(poll_interval, min(5.0, poll_interval * 10))
    if once:
        while True:
            job = await claim_next_job(worker_id)
            if job is None:
                return
            await run_job(job)

    await asyncio.gather(
        run_worker_lane(
            worker_id=f"{worker_id}-local",
            poll_interval=poll_interval,
            max_poll_interval=max_poll_interval,
            job_types=LOCAL_PREPARATION_JOB_TYPES,
            stop_event=stop_event,
        ),
        run_worker_lane(
            worker_id=f"{worker_id}-model",
            poll_interval=poll_interval,
            max_poll_interval=max_poll_interval,
            job_types=MODEL_JOB_TYPES,
            stop_event=stop_event,
        ),
    )


async def run_worker_lane(
    *,
    worker_id: str,
    poll_interval: float,
    max_poll_interval: float,
    job_types: tuple[JobType, ...],
    stop_event: asyncio.Event | None = None,
) -> None:
    idle_interval = poll_interval
    while True:
        if stop_event is not None and stop_event.is_set():
            return
        job = await claim_next_job(worker_id, job_types)
        if job is None:
            if stop_event is None:
                await asyncio.sleep(idle_interval)
            else:
                try:
                    await asyncio.wait_for(stop_event.wait(), timeout=idle_interval)
                except TimeoutError:
                    idle_interval = min(max_poll_interval, max(poll_interval, idle_interval * 1.5))
                    continue
                return
            idle_interval = min(max_poll_interval, max(poll_interval, idle_interval * 1.5))
            continue
        idle_interval = poll_interval
        await run_job(job)


async def run_job(job: Job) -> None:
    try:
        if job.type == JobType.import_arxiv:
            await run_import_arxiv_job(job)
            return
        if job.type == JobType.parse_article:
            await run_parse_article_job(job)
            return
        if job.type == JobType.translate_block:
            await run_translate_block_worker_job(job)
            return
        if job.type == JobType.embed_article:
            await run_embed_article_job(job)
            return
        if job.type == JobType.export_article:
            await run_export_article_job(job)
            return
        if job.type == JobType.extract_reader_cards:
            await run_extract_reader_cards_job(job)
            return
        if job.type == JobType.generate_reader_card:
            await run_generate_reader_card_job(job)
            return
        await fail_job(job.id, {"message": f"Unsupported job type: {job.type}."})
    except Exception as exc:  # pragma: no cover - defensive worker boundary
        await fail_job(job.id, {"message": str(exc), "type": type(exc).__name__})


async def run_import_arxiv_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    parse_after_import = bool(job.payload.get("parse_after_import", True))
    request = ImportArxivRequest(
        arxiv_id=str(job.payload["arxiv_id"]),
        version=job.payload.get("version"),
        download_pdf=bool(job.payload.get("download_pdf", True)),
        parse_after_import=False,
    )
    await update_job_progress(job.id, 0.1)
    result = await import_arxiv(library, request)
    if parse_after_import:
        parse_payload: dict[str, object] = {
            "library_id": library.id,
            "article_revision_id": result.article_revision_id,
        }
        if isinstance(job.payload.get("source"), str):
            parse_payload["source"] = job.payload["source"]
        if isinstance(job.payload.get("translate_after_parse"), dict):
            parse_payload["translate_after_parse"] = job.payload["translate_after_parse"]
        parse_job = await create_parse_job(parse_payload)
        result = result.model_copy(update={"parse_job_id": parse_job.id})
    await update_job_progress(job.id, 1.0)
    await complete_job(job.id, import_result_to_json(result))


async def run_parse_article_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    revision_id = str(job.payload["article_revision_id"])
    try:
        await update_job_progress(job.id, 0.1)
        result = await parse_article_revision(library, revision_id)
        embed_job = await queue_article_embedding(library, revision_id)
        result["embed_job_id"] = embed_job.id
        card_job = await queue_reader_card_extraction(
            library,
            revision_id,
            ReaderCardExtractionRequest(
                target_language=str(job.payload.get("target_language") or "zh-CN")
            ),
        )
        result["reader_card_job_id"] = card_job.id
        translation_request = await translation_request_after_parse(job)
        if translation_request is not None:
            translation_result = await queue_article_translation(
                library,
                revision_id,
                translation_request,
            )
            result["translation_job_ids"] = translation_result.job_ids
        await update_job_progress(job.id, 1.0)
        await complete_job(job.id, result)
    except ParseFailure as exc:
        await fail_job(job.id, {"code": exc.code, "message": exc.message, "details": exc.details})


async def create_parse_job(payload: dict[str, object]) -> Job:
    return await create_job(JobType.parse_article, payload=payload)


async def translation_request_after_parse(job: Job) -> TranslationBatchRequest | None:
    payload = job.payload.get("translate_after_parse")
    if payload is False:
        return None
    if isinstance(payload, dict):
        return TranslationBatchRequest.model_validate(payload)
    if job.payload.get("source") == "citation":
        return None
    provider = await default_translation_provider()
    if provider is None or not provider.default_model:
        return None
    return TranslationBatchRequest(
        target_language=str(job.payload.get("target_language") or "zh-CN"),
        provider_profile_id=provider.id,
        model=provider.default_model,
    )


async def default_translation_provider() -> ProviderProfile | None:
    for provider in await list_provider_profiles():
        if provider.default_model and provider_supports_translation(provider):
            return provider
    return None


def provider_supports_translation(provider: ProviderProfile) -> bool:
    capabilities = provider.capabilities
    selected = capabilities.get("selected_model_capabilities")
    if isinstance(selected, dict) and selected.get("translation") is False:
        return False
    return capabilities.get("translation") is not False


async def run_translate_block_worker_job(job: Job) -> None:
    try:
        await update_job_progress(job.id, 0.1)
        result = await run_translate_block_job(job)
        validation_status = result.get("validation_status")
        if validation_status and validation_status != "ok":
            max_attempts = int(job.payload.get("max_attempts") or 1)
            error = {
                "code": "translation_validation_failed",
                "message": (
                    f"Translation output for block {result.get('block_uid')} failed validation: "
                    f"{validation_status}"
                ),
                "validation_status": validation_status,
                "block_uid": result.get("block_uid"),
                "target_language": result.get("target_language"),
                "translation_variant_id": result.get("translation_variant_id"),
                "retryable": job.attempts < max_attempts,
                "attempt": job.attempts,
                "max_attempts": max_attempts,
            }
            if job.attempts < max_attempts:
                await requeue_job(job.id, error)
                return
            await fail_job(job.id, error)
            return
        await update_job_progress(job.id, 1.0)
        await complete_job(job.id, result)
    except Exception as exc:
        max_attempts = int(job.payload.get("max_attempts") or 1)
        if job.attempts < max_attempts and is_transient_translation_error(exc):
            await requeue_job(
                job.id,
                {
                    "message": str(exc),
                    "type": type(exc).__name__,
                    "retryable": True,
                    "attempt": job.attempts,
                    "max_attempts": max_attempts,
                },
            )
            return
        raise


async def run_export_article_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    revision_id = str(job.payload["article_revision_id"])
    request = ArticleExportRequest.model_validate(job.payload.get("request", {}))
    current = await get_job(job.id)
    if current is None or current.status == JobStatus.cancelled:
        return
    await update_job_progress(job.id, 0.2)
    result = await export_article(library, revision_id, request)
    await update_job_progress(job.id, 1.0)
    await complete_job(job.id, result.model_dump(mode="json"))


async def run_embed_article_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    revision_id = str(job.payload["article_revision_id"])
    request = EmbedArticleRequest.model_validate(job.payload.get("request", {}))
    current = await get_job(job.id)
    if current is None or current.status == JobStatus.cancelled:
        return
    await update_job_progress(job.id, 0.2)
    result = await build_article_embeddings(library, revision_id, request)
    await update_job_progress(job.id, 1.0)
    await complete_job(job.id, result.model_dump(mode="json"))


async def run_extract_reader_cards_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    revision_id = str(job.payload["article_revision_id"])
    request = ReaderCardExtractionRequest.model_validate(job.payload.get("request", {}))
    current = await get_job(job.id)
    if current is None or current.status == JobStatus.cancelled:
        return
    await update_job_progress(job.id, 0.2)
    result = await extract_article_reader_cards(library, revision_id, request)
    await update_job_progress(job.id, 1.0)
    await complete_job(job.id, result.model_dump(mode="json"))


async def run_generate_reader_card_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    revision_id = str(job.payload["article_revision_id"])
    request = ReaderCardGenerationRequest.model_validate(job.payload.get("request", {}))
    current = await get_job(job.id)
    if current is None or current.status == JobStatus.cancelled:
        return
    await update_job_progress(job.id, 0.2)
    result = await generate_article_reader_card(library, revision_id, request)
    await update_job_progress(job.id, 1.0)
    await complete_job(job.id, result.model_dump(mode="json"))
