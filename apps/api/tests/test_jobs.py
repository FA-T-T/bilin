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
    clear_jobs,
    complete_job,
    create_import_arxiv_job_if_absent,
    create_job,
    create_library,
    create_parse_job_if_absent,
    create_provider_profile,
    create_translation_job_if_absent,
    fail_job,
    get_article_task_summary,
    get_job,
    get_job_summary,
    list_jobs,
    pause_job,
    resume_job,
    retry_failed_job,
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
async def test_retry_failed_job_requeues_failed_job_and_updates_article_task(
    bilin_home: Path,
) -> None:
    job = await create_job(
        JobType.parse_article,
        {
            "library_id": "library-1",
            "article_revision_id": "revision-1",
            "progress_metadata": {
                "stage": "latexmlpost_execution",
                "message": "执行 latexmlpost",
                "progress": 0.6,
            },
        },
    )
    claimed = await claim_next_job("worker")
    assert claimed is not None
    assert claimed.id == job.id
    failed = await fail_job(
        job.id,
        {"code": "latexml_timeout", "message": "Command timed out."},
    )
    assert failed is not None
    assert failed.status == JobStatus.failed

    failed_summary = await get_article_task_summary()
    failed_item = failed_summary.items[0]
    assert failed_item.status == JobStatus.failed
    assert failed_item.failed_job_ids == [job.id]

    retried = await retry_failed_job(job.id)

    assert retried is not None
    assert retried.status == JobStatus.queued
    assert retried.error is None
    assert retried.result is None
    assert retried.attempts == 0
    assert retried.started_at is None
    assert retried.finished_at is None
    assert retried.progress == 0.0
    assert retried.payload["progress_metadata"]["stage"] == "latexmlpost_execution"

    retry_summary = await get_article_task_summary()
    retry_item = retry_summary.items[0]
    assert retry_item.status == JobStatus.queued
    assert retry_item.failed_jobs == 0
    assert retry_item.failed_job_ids == []
    assert retry_item.message == "执行 latexmlpost"


@pytest.mark.asyncio
async def test_cancelled_running_job_is_not_completed_later(bilin_home: Path) -> None:
    job = await create_job(JobType.export_article, {"library_id": "library"})
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == job.id

    cancelled = await cancel_job(job.id)
    completed = await complete_job(job.id, {"ok": True})
    reloaded = await get_job(job.id)

    assert cancelled is not None
    assert cancelled.status == JobStatus.cancelled
    assert completed is not None
    assert completed.status == JobStatus.cancelled
    assert reloaded is not None
    assert reloaded.status == JobStatus.cancelled
    assert reloaded.result is None


@pytest.mark.asyncio
async def test_pause_does_not_reopen_terminal_job(bilin_home: Path) -> None:
    job = await create_job(JobType.export_article, {"library_id": "library"})
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    await complete_job(job.id, {"ok": True})

    paused = await pause_job(job.id)

    assert paused is not None
    assert paused.status == JobStatus.succeeded


@pytest.mark.asyncio
async def test_clear_jobs_preserves_active_jobs(bilin_home: Path) -> None:
    active = await create_job(JobType.export_article, {"library_id": "library"})
    terminal = await create_job(JobType.export_article, {"library_id": "library"})
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == active.id
    await cancel_job(terminal.id)

    cleared = await clear_jobs()
    jobs = await list_jobs()

    assert cleared == 1
    assert [job.id for job in jobs] == [active.id]


@pytest.mark.asyncio
async def test_parse_job_creation_dedupes_active_revision_jobs(bilin_home: Path) -> None:
    payload = {"library_id": "library", "article_revision_id": "revision"}

    first, first_created = await create_parse_job_if_absent(payload)
    second, second_created = await create_parse_job_if_absent(payload)

    assert first_created is True
    assert second_created is False
    assert second.id == first.id


@pytest.mark.asyncio
async def test_translation_job_creation_dedupes_active_block_jobs(bilin_home: Path) -> None:
    payload = {
        "library_id": "library",
        "article_revision_id": "revision",
        "block_uid": "p-0001",
        "target_language": "zh-CN",
        "provider_profile_id": "provider",
        "model": "model",
        "context_hash": "context",
    }

    first, first_created = await create_translation_job_if_absent(payload)
    second, second_created = await create_translation_job_if_absent(payload)

    assert first_created is True
    assert second_created is False
    assert second.id == first.id


@pytest.mark.asyncio
async def test_import_arxiv_job_creation_dedupes_active_requests(bilin_home: Path) -> None:
    payload = {
        "library_id": "library",
        "arxiv_id": "2401.00001",
        "version": None,
        "download_pdf": True,
        "parse_after_import": True,
    }

    first, first_created = await create_import_arxiv_job_if_absent(payload)
    second, second_created = await create_import_arxiv_job_if_absent(payload)
    changed, changed_created = await create_import_arxiv_job_if_absent(
        {**payload, "download_pdf": False}
    )

    assert first_created is True
    assert second_created is False
    assert second.id == first.id
    assert changed_created is True
    assert changed.id != first.id


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
async def test_article_task_summary_groups_translation_jobs_by_article_batch(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Article Tasks", path=str(tmp_path / "library"))
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nA paragraph.\n\nAnother paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )
    payload = {
        "library_id": library.id,
        "article_revision_id": imported.article_revision_id,
        "translation_batch_id": "batch-1",
        "target_language": "zh-CN",
        "provider_profile_id": "provider",
        "model": "model",
    }
    completed_job = await create_job(
        JobType.translate_block,
        {**payload, "block_uid": "p-0001"},
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == completed_job.id
    await complete_job(completed_job.id, {"ok": True})
    await create_job(JobType.translate_block, {**payload, "block_uid": "p-0002"})

    summary = await get_article_task_summary()

    assert summary.total == 1
    assert summary.active == 1
    item = summary.items[0]
    assert item.article_revision_id == imported.article_revision_id
    assert item.article_title == "paper"
    assert item.stage == "translating"
    assert item.message == "翻译中 001/002"
    assert item.current == 1
    assert item.total == 2


@pytest.mark.asyncio
async def test_article_task_summary_hides_terminal_only_jobs(bilin_home: Path) -> None:
    job = await create_job(
        JobType.translate_block,
        {
            "library_id": "library",
            "article_revision_id": "revision",
            "translation_batch_id": "batch-1",
            "block_uid": "p-0001",
        },
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == job.id
    await complete_job(job.id, {"ok": True})

    summary = await get_article_task_summary()

    assert summary.total == 0
    assert summary.items == []


@pytest.mark.asyncio
async def test_article_task_summary_uses_active_batch_without_old_failed_pollution(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Batch Isolation", path=str(tmp_path / "library"))
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nOne paragraph.\n\nAnother paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )
    base_payload = {
        "library_id": library.id,
        "article_revision_id": imported.article_revision_id,
        "target_language": "zh-CN",
        "provider_profile_id": "provider",
        "model": "model",
    }
    old_failed = await create_job(
        JobType.translate_block,
        {**base_payload, "translation_batch_id": "batch-old", "block_uid": "p-old"},
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == old_failed.id
    await fail_job(old_failed.id, {"code": "old_batch_failed", "message": "Old batch failed."})

    completed_new = await create_job(
        JobType.translate_block,
        {**base_payload, "translation_batch_id": "batch-new", "block_uid": "p-done"},
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == completed_new.id
    await complete_job(completed_new.id, {"ok": True})
    active_new = await create_job(
        JobType.translate_block,
        {**base_payload, "translation_batch_id": "batch-new", "block_uid": "p-active"},
    )

    summary = await get_article_task_summary()

    assert summary.total == 1
    assert summary.failed_items == 0
    item = summary.items[0]
    assert item.status == JobStatus.queued
    assert item.failed_jobs == 0
    assert item.succeeded_jobs == 1
    assert item.current == 1
    assert item.total == 2
    assert item.error is None
    assert old_failed.id not in item.job_ids
    assert set(item.job_ids) == {completed_new.id, active_new.id}


@pytest.mark.asyncio
async def test_article_task_summary_keeps_legacy_unbatched_translation_grouping(
    bilin_home: Path,
) -> None:
    base_payload = {
        "library_id": "library",
        "article_revision_id": "revision",
        "target_language": "zh-CN",
    }
    completed = await create_job(
        JobType.translate_block,
        {**base_payload, "block_uid": "p-done"},
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == completed.id
    await complete_job(completed.id, {"ok": True})
    queued = await create_job(
        JobType.translate_block,
        {**base_payload, "block_uid": "p-queued"},
    )

    summary = await get_article_task_summary()

    assert summary.total == 1
    item = summary.items[0]
    assert item.article_revision_id == "revision"
    assert item.current == 1
    assert item.total == 2
    assert set(item.job_ids) == {completed.id, queued.id}


@pytest.mark.asyncio
async def test_article_task_summary_all_failed_translation_keeps_error(
    bilin_home: Path,
) -> None:
    job = await create_job(
        JobType.translate_block,
        {
            "library_id": "library",
            "article_revision_id": "revision",
            "translation_batch_id": "batch-failed",
            "block_uid": "p-0001",
        },
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == job.id
    await fail_job(job.id, {"code": "translation_failed", "message": "Translation failed."})

    summary = await get_article_task_summary()

    assert summary.total == 1
    assert summary.active == 0
    assert summary.failed == 1
    assert summary.failed_items == 1
    item = summary.items[0]
    assert item.status == JobStatus.failed
    assert item.message == "翻译失败 001/001"
    assert item.error == {"code": "translation_failed", "message": "Translation failed."}


@pytest.mark.asyncio
async def test_article_task_summary_paused_jobs_are_current_items(bilin_home: Path) -> None:
    job = await create_job(
        JobType.translate_block,
        {
            "library_id": "library",
            "article_revision_id": "revision",
            "translation_batch_id": "batch-paused",
            "block_uid": "p-0001",
        },
    )
    paused = await pause_job(job.id)
    assert paused is not None
    assert paused.status == JobStatus.paused

    summary = await get_article_task_summary()

    assert summary.total == 1
    assert summary.paused == 1
    assert summary.active == 1
    item = summary.items[0]
    assert item.status == JobStatus.paused
    assert item.paused_jobs == 1
    assert item.message == "翻译中 000/001"


@pytest.mark.asyncio
async def test_article_task_summary_citation_import_uses_source_article_revision(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Citation Import Tasks", path=str(tmp_path / "library"))
    )
    imported = await import_local_file(
        library,
        file_name="source.md",
        content=b"# Source\n\nA paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )
    job = await create_job(
        JobType.import_arxiv,
        {
            "library_id": library.id,
            "arxiv_id": "2401.00001",
            "article_revision_id": "imported-citation-revision",
            "source": "citation",
            "source_article_revision_id": imported.article_revision_id,
            "source_citation_id": "bib.bib1",
        },
    )

    summary = await get_article_task_summary()

    assert summary.total == 1
    item = summary.items[0]
    assert item.id == f"article:{library.id}:{imported.article_revision_id}"
    assert item.article_revision_id == imported.article_revision_id
    assert item.article_title == "source"
    assert item.stage == "importing"
    assert item.job_ids == [job.id]


@pytest.mark.asyncio
async def test_article_task_summary_counts_mixed_failed_items(bilin_home: Path) -> None:
    base_payload = {
        "library_id": "library",
        "article_revision_id": "revision",
        "translation_batch_id": "batch-mixed",
        "target_language": "zh-CN",
    }
    failed = await create_job(
        JobType.translate_block,
        {**base_payload, "block_uid": "p-failed"},
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == failed.id
    await fail_job(failed.id, {"code": "block_failed", "message": "Block failed."})
    queued = await create_job(
        JobType.translate_block,
        {**base_payload, "block_uid": "p-queued"},
    )

    summary = await get_article_task_summary()

    assert summary.total == 1
    assert summary.failed == 0
    assert summary.failed_items == 1
    item = summary.items[0]
    assert item.status == JobStatus.queued
    assert item.failed_jobs == 1
    assert item.queued_jobs == 1
    assert item.error == {"code": "block_failed", "message": "Block failed."}
    assert set(item.job_ids) == {failed.id, queued.id}


@pytest.mark.asyncio
async def test_article_task_summary_limit_order_and_shape(bilin_home: Path) -> None:
    await create_job(
        JobType.parse_article,
        {"library_id": "library", "article_revision_id": "revision-oldest"},
    )
    await asyncio.sleep(0.001)
    middle = await create_job(
        JobType.parse_article,
        {"library_id": "library", "article_revision_id": "revision-middle"},
    )
    await asyncio.sleep(0.001)
    newest = await create_job(
        JobType.parse_article,
        {"library_id": "library", "article_revision_id": "revision-newest"},
    )

    summary = await get_article_task_summary(limit=2)
    payload = summary.model_dump(mode="json")

    assert summary.total == 3
    assert len(summary.items) == 2
    assert payload["failed_items"] == 0
    assert isinstance(payload["items"], list)
    assert [item.article_revision_id for item in summary.items] == [
        "revision-newest",
        "revision-middle",
    ]
    assert summary.items[0].job_ids == [newest.id]
    assert summary.items[1].job_ids == [middle.id]


@pytest.mark.asyncio
async def test_article_task_summary_primary_stage_prefers_status_then_updated_at(
    bilin_home: Path,
) -> None:
    running_translation = await create_job(
        JobType.translate_block,
        {
            "library_id": "library",
            "article_revision_id": "running-beats-queued",
            "translation_batch_id": "batch-running",
            "block_uid": "p-0001",
        },
    )
    claimed = await claim_next_job("worker-1")
    assert claimed is not None
    assert claimed.id == running_translation.id
    await asyncio.sleep(0.001)
    await create_job(
        JobType.parse_article,
        {"library_id": "library", "article_revision_id": "running-beats-queued"},
    )

    older = await create_job(
        JobType.parse_article,
        {"library_id": "library", "article_revision_id": "same-status-latest"},
    )
    await asyncio.sleep(0.001)
    newer = await create_job(
        JobType.export_article,
        {"library_id": "library", "article_revision_id": "same-status-latest"},
    )

    summary = await get_article_task_summary()
    items = {item.article_revision_id: item for item in summary.items}

    assert items["running-beats-queued"].stage == "translating"
    assert items["same-status-latest"].stage == "exporting"
    assert items["same-status-latest"].job_ids == [older.id, newer.id]


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
async def test_worker_surfaces_empty_exception_messages(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class EmptyMessageError(Exception):
        def __str__(self) -> str:
            return ""

    library = await create_library(
        LibraryCreate(name="Import Failure", path=str(tmp_path / "library"))
    )

    async def broken_import_arxiv(_library: object, _request: object) -> object:
        raise EmptyMessageError()

    monkeypatch.setattr(worker_module, "import_arxiv", broken_import_arxiv)
    job = await create_job(
        JobType.import_arxiv,
        {
            "library_id": library.id,
            "arxiv_id": "2208.06563",
            "version": None,
            "download_pdf": True,
            "parse_after_import": True,
        },
    )

    await run_worker(once=True)
    completed = await get_job(job.id)

    assert completed is not None
    assert completed.status == JobStatus.failed
    assert completed.error is not None
    assert completed.error["type"] == "EmptyMessageError"
    assert completed.error["message"] == "import_arxiv failed with EmptyMessageError."


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
