from __future__ import annotations

import io
import tarfile
from pathlib import Path

import pytest

import bilin_api.latexml_parser as parser_module
from bilin_api.importer import import_local_file
from bilin_api.repositories import (
    cancel_job,
    create_job,
    create_library,
    get_job,
    pause_job,
    resume_job,
)
from bilin_api.schemas import (
    ArticleExportKind,
    ArticleExportRequest,
    ImportLocalKind,
    JobStatus,
    JobType,
    LibraryCreate,
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
    assert completed.result["file_name"] == "source.md"


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


def source_tar_bytes(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()
