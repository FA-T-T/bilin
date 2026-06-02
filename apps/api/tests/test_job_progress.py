from __future__ import annotations

import io
import tarfile
from pathlib import Path
from typing import cast

import httpx
import pytest

import bilin_api.latexml_parser as parser_module
import bilin_api.worker as worker_module
from bilin_api.article_store import bundle_path_for_arxiv, upsert_arxiv_revision, write_manifest
from bilin_api.importer import ImportProgressCallback, import_arxiv, import_local_file
from bilin_api.latexml_parser import ParseProgressCallback, parse_article_revision
from bilin_api.repositories import (
    claim_next_job,
    create_job,
    create_library,
    get_article_task_summary,
    get_job,
    list_jobs,
)
from bilin_api.schemas import (
    ArticleManifest,
    ImportArxivRequest,
    ImportArxivResult,
    ImportLocalKind,
    JobStatus,
    JobType,
    LibraryCreate,
)

ATOM_RESPONSE = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>https://arxiv.org/abs/2401.00001v2</id>
    <updated>2024-01-03T00:00:00Z</updated>
    <published>2024-01-01T00:00:00Z</published>
    <title> Progress Test Paper </title>
    <summary> A compact abstract. </summary>
    <author><name>Ada Lovelace</name></author>
  </entry>
</feed>
"""


@pytest.mark.asyncio
async def test_import_arxiv_reports_fine_grained_progress(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("BILIN_ARXIV_API_INTERVAL_SECONDS", "0")
    library = await create_library(
        LibraryCreate(name="Import Progress", path=str(tmp_path / "library")),
    )
    source_bytes = source_tar_bytes(
        {"paper/main.tex": b"\\documentclass{article}\\begin{document}x\\end{document}"}
    )
    events: list[tuple[str, str, float]] = []

    async def record_progress(stage: str, message: str, progress: float) -> None:
        events.append((stage, message, progress))

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "export.arxiv.org/api/query" in url:
            return httpx.Response(200, text=ATOM_RESPONSE)
        if "arxiv.org/e-print/2401.00001v2" in url:
            return httpx.Response(200, content=source_bytes)
        if "arxiv.org/pdf/2401.00001v2.pdf" in url:
            return httpx.Response(200, content=b"%PDF-1.7\n")
        return httpx.Response(404)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await import_arxiv(
            library,
            ImportArxivRequest(arxiv_id="2401.00001", parse_after_import=True),
            client,
            progress=record_progress,
        )

    assert result.parse_job_id is not None
    assert [stage for stage, _message, _progress in events] == [
        "arxiv_metadata",
        "source_download",
        "pdf_download",
        "bundle_write",
        "queue_parse",
    ]
    assert [message for _stage, message, _progress in events] == [
        "解析 arXiv 元数据",
        "下载源数据",
        "下载 PDF",
        "写入 bundle",
        "排队解析",
    ]
    assert [progress for _stage, _message, progress in events] == sorted(
        progress for _stage, _message, progress in events
    )


@pytest.mark.asyncio
async def test_latexml_parser_reports_fine_grained_progress(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Parse Progress", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00002", "v1")
    original_dir = bundle_path / "original"
    original_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {"main.tex": b"\\documentclass{article}\\begin{document}Hello.\\end{document}"},
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00002",
        version="v1",
        title="Parser progress",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(bundle_path, ArticleManifest(article_revision_id=revision.id, source="arxiv"))
    events: list[tuple[str, str, float]] = []

    async def record_progress(stage: str, message: str, progress: float) -> None:
        events.append((stage, message, progress))

    async def fake_run_command(
        command: list[str],
        cwd: Path,
        log_path: Path,
        timeout_budget: object | None = None,
        activity_paths: list[Path] | None = None,
    ) -> None:
        _ = (cwd, timeout_budget, activity_paths)
        destination = Path(command[command.index("--destination") + 1])
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.suffix == ".html":
            destination.write_text(
                "<html><body><p>Hello Bilin.</p></body></html>",
                encoding="utf-8",
            )
        else:
            destination.write_text("<document />", encoding="utf-8")
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("ok\n", encoding="utf-8")

    monkeypatch.setattr(
        parser_module.shutil,
        "which",
        lambda name: f"/mock/{name}" if name in {"latexml", "latexmlpost"} else None,
    )
    monkeypatch.setattr(parser_module, "detect_version", lambda _path: "mock")
    monkeypatch.setattr(parser_module, "run_command", fake_run_command)

    result = await parse_article_revision(library, revision.id, progress=record_progress)

    assert result == {
        "article_revision_id": revision.id,
        "document_path": str(bundle_path / "document" / "document.json"),
        "source_md_path": str(bundle_path / "document" / "source.md"),
        "block_count": 1,
        "asset_count": 0,
    }
    assert [stage for stage, _message, _progress in events] == [
        "source_unpack",
        "dependency_check",
        "latexml_execution",
        "latexmlpost_execution",
        "html_normalization",
        "document_write",
    ]
    assert [message for _stage, message, _progress in events] == [
        "解包源文件",
        "依赖检查",
        "执行 LaTeXML",
        "执行 latexmlpost",
        "规范化 HTML",
        "写入文档",
    ]


@pytest.mark.asyncio
async def test_import_worker_persists_progress_metadata(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Import Worker Progress", path=str(tmp_path / "library")),
    )

    async def fake_import_arxiv(
        _library: object,
        _request: object,
        progress: object | None = None,
    ) -> ImportArxivResult:
        assert progress is not None
        progress_callback = cast(ImportProgressCallback, progress)
        await progress_callback("source_download", "下载源数据", 0.25)
        await progress_callback("bundle_write", "写入 bundle", 0.65)
        return ImportArxivResult(
            library_id=library.id,
            article_family_id="family-1",
            article_revision_id="revision-1",
            bundle_path=str(tmp_path / "bundle"),
        )

    monkeypatch.setattr(worker_module, "import_arxiv", fake_import_arxiv)
    job = await create_job(
        JobType.import_arxiv,
        {
            "library_id": library.id,
            "arxiv_id": "2401.00001",
            "version": None,
            "download_pdf": True,
            "parse_after_import": True,
        },
    )
    claimed = await claim_next_job("worker-progress")
    assert claimed is not None
    assert claimed.id == job.id

    await worker_module.run_job(claimed)

    completed = await get_job(job.id)
    jobs = await list_jobs()
    assert completed is not None
    assert completed.status == JobStatus.succeeded
    assert completed.payload["progress_metadata"] == {
        "stage": "queue_parse",
        "message": "排队解析",
        "progress": 0.9,
    }
    assert completed.result is not None
    assert completed.result["parse_job_id"]
    assert any(
        queued_job.type == JobType.parse_article
        and queued_job.payload["article_revision_id"] == "revision-1"
        for queued_job in jobs
    )


@pytest.mark.asyncio
async def test_article_task_summary_uses_progress_metadata(bilin_home: Path) -> None:
    job = await create_job(
        JobType.parse_article,
        {
            "library_id": "library",
            "article_revision_id": "revision",
            "progress_metadata": {
                "stage": "latexmlpost_execution",
                "message": "执行 latexmlpost",
                "progress": 0.6,
            },
        },
    )
    claimed = await claim_next_job("worker-progress")
    assert claimed is not None
    assert claimed.id == job.id

    summary = await get_article_task_summary()

    assert summary.total == 1
    item = summary.items[0]
    assert item.stage == "latexmlpost_execution"
    assert item.message == "执行 latexmlpost"
    assert item.progress == 0.6


@pytest.mark.asyncio
async def test_parse_worker_persists_progress_metadata(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Parse Worker Progress", path=str(tmp_path / "library")),
    )
    imported = await import_local_file(
        library,
        file_name="paper.md",
        content=b"# Title\n\nA paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=False,
    )

    async def fake_parse_article_revision(
        _library: object,
        revision_id: str,
        progress: object | None = None,
    ) -> dict[str, object]:
        assert progress is not None
        progress_callback = cast(ParseProgressCallback, progress)
        await progress_callback("dependency_check", "依赖检查", 0.2)
        await progress_callback("document_write", "写入文档", 0.9)
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
            "translate_after_parse": False,
        },
    )
    claimed = await claim_next_job("worker-progress")
    assert claimed is not None
    assert claimed.id == job.id

    await worker_module.run_job(claimed)

    completed = await get_job(job.id)
    assert completed is not None
    assert completed.status == JobStatus.succeeded
    assert completed.payload["progress_metadata"] == {
        "stage": "document_write",
        "message": "写入文档",
        "progress": 0.9,
    }
    assert completed.result is not None
    assert "progress_metadata" not in completed.result
    assert completed.result["embed_job_id"]
    assert completed.result["reader_card_job_id"]


def source_tar_bytes(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()


def write_tar(path: Path, files: dict[str, bytes]) -> None:
    with tarfile.open(path, mode="w") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
