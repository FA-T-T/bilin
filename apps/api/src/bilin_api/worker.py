from __future__ import annotations

import asyncio
from uuid import uuid4

from bilin_api.article_store import resolve_library
from bilin_api.embedding_service import build_article_embeddings, queue_article_embedding
from bilin_api.export_service import export_article
from bilin_api.importer import import_arxiv, import_result_to_json
from bilin_api.latexml_parser import ParseFailure, parse_article_revision
from bilin_api.repositories import (
    claim_next_job,
    complete_job,
    fail_job,
    get_job,
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
)
from bilin_api.translation_service import is_transient_translation_error, run_translate_block_job


async def run_worker(poll_interval: float = 0.5, once: bool = False) -> None:
    worker_id = f"worker-{uuid4()}"
    while True:
        job = await claim_next_job(worker_id)
        if job is None:
            if once:
                return
            await asyncio.sleep(poll_interval)
            continue
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
        await fail_job(job.id, {"message": f"Unsupported job type: {job.type}."})
    except Exception as exc:  # pragma: no cover - defensive worker boundary
        await fail_job(job.id, {"message": str(exc), "type": type(exc).__name__})


async def run_import_arxiv_job(job: Job) -> None:
    library = await resolve_library(str(job.payload["library_id"]))
    request = ImportArxivRequest(
        arxiv_id=str(job.payload["arxiv_id"]),
        version=job.payload.get("version"),
        download_pdf=bool(job.payload.get("download_pdf", True)),
        parse_after_import=bool(job.payload.get("parse_after_import", True)),
    )
    await update_job_progress(job.id, 0.1)
    result = await import_arxiv(library, request)
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
        await update_job_progress(job.id, 1.0)
        await complete_job(job.id, result)
    except ParseFailure as exc:
        await fail_job(job.id, {"code": exc.code, "message": exc.message, "details": exc.details})


async def run_translate_block_worker_job(job: Job) -> None:
    try:
        await update_job_progress(job.id, 0.1)
        result = await run_translate_block_job(job)
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
