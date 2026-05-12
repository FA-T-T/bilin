from __future__ import annotations

import asyncio
import io
import tarfile
from contextlib import suppress
from pathlib import Path

import pytest

import bilin_api.latexml_parser as parser_module
import bilin_api.worker as worker_module
from bilin_api.importer import import_local_file
from bilin_api.repositories import (
    cancel_job,
    claim_next_job,
    create_job,
    create_library,
    create_provider_profile,
    get_job,
    get_job_summary,
    list_jobs,
    pause_job,
    resume_job,
)
from bilin_api.schemas import (
    ArticleExportKind,
    ArticleExportRequest,
    ImportLocalKind,
    Job,
    JobStatus,
    JobType,
    LibraryCreate,
    ProviderProfileCreate,
    ProviderProtocol,
)
from bilin_api.worker import run_worker


@pytest.mark.asyncio
async def test_export_job_can_complete(bilin_home: Path, tmp_path: Path) -> None:
    job = await create_source_export_job(tmp_path)
    await run_worker(once=True)
    completed = await get_job(job.id)
    assert completed is not None
    assert completed.status == JobStatus.succeeded
    assert completed.progress == 1
    assert completed.result is not None
    assert completed.result["file_name"] == "paper-source.zip"


@pytest.mark.asyncio
async def test_job_pause_resume_cancel_state_changes(bilin_home: Path, tmp_path: Path) -> None:
    job = await create_source_export_job(tmp_path)
    paused = await pause_job(job.id)
    assert paused is not None
    assert paused.status == JobStatus.paused
    resumed = await resume_job(job.id)
    assert resumed is not None
    assert resumed.status == JobStatus.queued
    cancelled = await cancel_job(job.id)
    assert cancelled is not None
    assert cancelled.status == JobStatus.cancelled


@pytest.mark.asyncio
async def test_jobs_summary_and_limited_listing_scale_with_large_queues(bilin_home: Path) -> None:
    for index in range(150):
        await create_job(JobType.translate_block, {"index": index})

    limited_jobs = await list_jobs(limit=25)
    summary = await get_job_summary()

    assert len(limited_jobs) == 25
    assert summary.total == 150
    assert summary.queued == 150
    assert summary.active == 150
    assert summary.updated_at is not None


@pytest.mark.asyncio
async def test_parse_jobs_preempt_existing_translation_queue(bilin_home: Path) -> None:
    for index in range(3):
        await create_job(JobType.translate_block, {"index": index})
    parse_job = await create_job(
        JobType.parse_article,
        {
            "library_id": "library",
            "article_revision_id": "revision",
        },
    )

    claimed = await claim_next_job("test-worker")
    next_claimed = await claim_next_job("test-worker")

    assert claimed is not None
    assert claimed.id == parse_job.id
    assert claimed.priority == 100
    assert next_claimed is not None
    assert next_claimed.type == JobType.translate_block
    assert next_claimed.priority == 50


@pytest.mark.asyncio
async def test_worker_parses_while_translation_job_waits_on_provider(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Concurrent Jobs", path=str(tmp_path / "library"))
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nA paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )
    translation_job = await create_job(
        JobType.translate_block,
        {
            "library_id": library.id,
            "article_revision_id": imported.article_revision_id,
            "block_uid": "p-0001",
            "target_language": "zh-CN",
        },
    )
    translation_started = asyncio.Event()
    release_translation = asyncio.Event()

    async def blocked_translation(job: object) -> dict[str, object]:
        _ = job
        translation_started.set()
        await release_translation.wait()
        return {"block_uid": "p-0001", "target_language": "zh-CN"}

    async def fake_parse_article_revision(_library: object, revision_id: str) -> dict[str, object]:
        return {
            "article_revision_id": revision_id,
            "document_path": "document.json",
            "source_md_path": "source.md",
            "block_count": 2,
            "asset_count": 0,
        }

    monkeypatch.setattr(worker_module, "run_translate_block_job", blocked_translation)
    monkeypatch.setattr(worker_module, "parse_article_revision", fake_parse_article_revision)

    stop_worker = asyncio.Event()
    worker_task = asyncio.create_task(run_worker(poll_interval=0.01, stop_event=stop_worker))
    try:
        await asyncio.wait_for(translation_started.wait(), timeout=1)
        parse_job = await create_job(
            JobType.parse_article,
            {
                "library_id": library.id,
                "article_revision_id": imported.article_revision_id,
                "translate_after_parse": False,
            },
        )

        completed_parse = await wait_for_job_status(parse_job.id, JobStatus.succeeded)
        still_waiting_translation = await get_job(translation_job.id)

        assert completed_parse.status == JobStatus.succeeded
        assert still_waiting_translation is not None
        assert still_waiting_translation.status == JobStatus.running
    finally:
        release_translation.set()
        with suppress(asyncio.TimeoutError):
            await asyncio.wait_for(wait_for_job_status(translation_job.id, JobStatus.succeeded), 1)
        stop_worker.set()
        await asyncio.wait_for(worker_task, timeout=1)


@pytest.mark.asyncio
async def test_parse_job_missing_latexml_surfaces_structured_error(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(LibraryCreate(name="Parse Jobs", path=str(tmp_path / "library")))
    imported = await import_local_file(
        library,
        file_name="paper.tar",
        content=source_tar_bytes(
            {"main.tex": b"\\documentclass{article}\\begin{document}x\\end{document}"}
        ),
        kind=ImportLocalKind.tex_archive,
        parse_after_import=False,
    )
    job = await create_job(
        JobType.parse_article,
        {
            "library_id": library.id,
            "article_revision_id": imported.article_revision_id,
        },
    )
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    await run_worker(once=True)
    completed = await get_job(job.id)

    assert completed is not None
    assert completed.status == JobStatus.failed
    assert completed.error is not None
    assert completed.error["code"] == "missing_dependency:latexml"
    assert completed.error["details"]["doctor_command"] == "bilin doctor"


@pytest.mark.asyncio
async def test_parse_job_queues_default_translation_and_reader_cards(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Default Translation", path=str(tmp_path / "library"))
    )
    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Mock Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="mock-model",
            capabilities={"selected_model_capabilities": {"translation": True}},
        )
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nA translatable paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )

    async def fake_parse_article_revision(_library: object, revision_id: str) -> dict[str, object]:
        return {
            "article_revision_id": revision_id,
            "document_path": "document.json",
            "source_md_path": "source.md",
            "block_count": 2,
            "asset_count": 0,
        }

    monkeypatch.setattr(worker_module, "parse_article_revision", fake_parse_article_revision)
    job = await create_job(
        JobType.parse_article,
        {
            "library_id": library.id,
            "article_revision_id": imported.article_revision_id,
        },
    )

    await run_worker(once=True)
    completed = await get_job(job.id)
    jobs = await list_jobs()

    assert completed is not None
    assert completed.status == JobStatus.succeeded
    assert completed.result is not None
    assert completed.result["reader_card_job_id"]
    assert completed.result["translation_job_ids"]
    assert any(
        queued_job.type == JobType.extract_reader_cards
        and queued_job.payload["article_revision_id"] == imported.article_revision_id
        for queued_job in jobs
    )
    assert any(
        queued_job.type == JobType.translate_block
        and queued_job.payload["provider_profile_id"] == provider.id
        and queued_job.payload["model"] == "mock-model"
        for queued_job in jobs
    )


@pytest.mark.asyncio
async def test_parse_job_does_not_default_translate_citation_imports(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Citation Default", path=str(tmp_path / "library"))
    )
    await create_provider_profile(
        ProviderProfileCreate(
            name="Mock Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="mock-model",
        )
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nA translatable paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )

    async def fake_parse_article_revision(_library: object, revision_id: str) -> dict[str, object]:
        return {
            "article_revision_id": revision_id,
            "document_path": "document.json",
            "source_md_path": "source.md",
            "block_count": 2,
            "asset_count": 0,
        }

    monkeypatch.setattr(worker_module, "parse_article_revision", fake_parse_article_revision)
    job = await create_job(
        JobType.parse_article,
        {
            "library_id": library.id,
            "article_revision_id": imported.article_revision_id,
            "source": "citation",
        },
    )

    await run_worker(once=True)
    completed = await get_job(job.id)
    jobs = await list_jobs()

    assert completed is not None
    assert completed.status == JobStatus.succeeded
    assert completed.result is not None
    assert "translation_job_ids" not in completed.result
    assert not any(queued_job.type == JobType.translate_block for queued_job in jobs)


async def create_source_export_job(tmp_path: Path):
    library = await create_library(
        LibraryCreate(name="Export Jobs", path=str(tmp_path / "library"))
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nA paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )
    return await create_job(
        JobType.export_article,
        {
            "library_id": library.id,
            "article_revision_id": imported.article_revision_id,
            "request": ArticleExportRequest(kind=ArticleExportKind.source_markdown).model_dump(
                mode="json"
            ),
        },
    )


async def wait_for_job_status(
    job_id: str,
    status: JobStatus,
    *,
    timeout: float = 1,
) -> Job:
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        job = await get_job(job_id)
        if job is not None and job.status == status:
            return job
        await asyncio.sleep(0.01)
    job = await get_job(job_id)
    msg = f"Job {job_id} did not reach {status}; last status was {job.status if job else None}"
    raise AssertionError(msg)


def source_tar_bytes(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()
