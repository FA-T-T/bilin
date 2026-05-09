from __future__ import annotations

import io
import tarfile
import xml.etree.ElementTree as ET
from pathlib import Path

import httpx
import pytest

from bilin_api.article_store import (
    archive_article_revision,
    delete_article_revision,
    list_article_items,
    read_manifest,
)
from bilin_api.arxiv import metadata_from_entry, parse_arxiv_identity
from bilin_api.importer import import_arxiv, import_local_file
from bilin_api.repositories import create_library, list_jobs
from bilin_api.schemas import ImportArxivRequest, ImportLocalKind, JobType, LibraryCreate

ATOM_RESPONSE = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>https://arxiv.org/abs/2401.00001v2</id>
    <updated>2024-01-03T00:00:00Z</updated>
    <published>2024-01-01T00:00:00Z</published>
    <title> A Minimal Bilin Test Paper </title>
    <summary> A compact abstract. </summary>
    <author><name>Ada Lovelace</name></author>
    <author><name>Grace Hopper</name></author>
  </entry>
</feed>
"""


def test_parse_arxiv_identity_accepts_urls_and_versions() -> None:
    identity = parse_arxiv_identity("https://arxiv.org/abs/2401.00001v2")
    assert identity.bare_id == "2401.00001"
    assert identity.version == "v2"
    assert parse_arxiv_identity("2401.00001", "3").concrete_id == "2401.00001v3"
    assert parse_arxiv_identity("quant-ph/9705052").bare_id == "quant-ph/9705052"
    assert parse_arxiv_identity("https://arxiv.org/abs/cond-mat/9407022v1").concrete_id == (
        "cond-mat/9407022v1"
    )
    assert parse_arxiv_identity("condmat/9407022").bare_id == "cond-mat/9407022"


def test_parse_arxiv_identity_rejects_ambiguous_old_style_bare_number() -> None:
    with pytest.raises(ValueError, match="archive prefix"):
        parse_arxiv_identity("9407022")


def test_metadata_from_entry_preserves_old_style_archive_prefix() -> None:
    entry = httpx.Response(
        200,
        text="""<entry xmlns="http://www.w3.org/2005/Atom">
          <id>https://arxiv.org/abs/quant-ph/9705052v1</id>
          <title>Old Style Quantum Paper</title>
          <summary>Abstract.</summary>
          <author><name>A. Researcher</name></author>
        </entry>""",
    )
    root = ET.fromstring(entry.text)

    metadata = metadata_from_entry(root)

    assert metadata.bare_id == "quant-ph/9705052"
    assert metadata.concrete_id == "quant-ph/9705052v1"
    assert metadata.source_url == "https://arxiv.org/e-print/quant-ph/9705052v1"


@pytest.mark.asyncio
async def test_import_arxiv_writes_bundle_manifest_and_parse_job(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Papers", path=str(tmp_path / "library")),
    )
    source_bytes = make_source_tar()

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
        )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.library_id == library.id
    assert result.parse_job_id is not None
    assert (bundle_path / "original" / "source.tar").read_bytes() == source_bytes
    assert (bundle_path / "original" / "paper.pdf").read_bytes().startswith(b"%PDF")
    assert manifest.arxiv_id == "2401.00001v2"
    assert manifest.source_fingerprint is not None
    assert manifest.pdf_fingerprint is not None
    assert manifest.generated_artifacts["source_archive"] == "original/source.tar"

    articles = await list_article_items(library)
    assert len(articles) == 1
    assert articles[0].family.external_id == "2401.00001"
    assert articles[0].article_revision.id == result.article_revision_id
    jobs = await list_jobs()
    assert any(job.type == JobType.parse_article for job in jobs)


@pytest.mark.asyncio
async def test_import_local_tex_archive_writes_source_and_parse_job(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Uploads", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="paper.tar.gz",
        content=make_source_tar(),
        kind=ImportLocalKind.tex_archive,
        parse_after_import=True,
    )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.source_kind == ImportLocalKind.tex_archive
    assert result.parse_job_id is not None
    assert (bundle_path / "original" / "source.gz").exists()
    assert manifest.source == "upload"
    assert manifest.metadata["source_kind"] == "tex_archive"
    assert manifest.generated_artifacts["source_archive"] == "original/source.gz"

    jobs = await list_jobs()
    assert any(job.type == JobType.parse_article for job in jobs)


@pytest.mark.asyncio
async def test_import_local_markdown_creates_weak_document(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Markdown", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="note.md",
        content=b"# Title\n\nFirst paragraph.\n\n## Method\n\nSecond paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=True,
    )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.parse_job_id is None
    assert manifest.parse_status == "parsed"
    assert (bundle_path / "document" / "document.json").exists()
    assert (
        (bundle_path / "document" / "source.md").read_text(encoding="utf-8").startswith("# Title")
    )

    articles = await list_article_items(library)
    assert articles[0].article_revision.status == "parsed"
    assert articles[0].block_count == 4


@pytest.mark.asyncio
async def test_archive_and_delete_article_revision_keep_or_remove_cache(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Actions", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="note.md",
        content=b"# Title\n\nFirst paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=True,
    )
    bundle_path = Path(result.bundle_path)
    assert bundle_path.exists()

    archived = await archive_article_revision(library, result.article_revision_id)
    assert archived is not None
    assert archived.article_revision.status == "archived"
    assert bundle_path.exists()

    deleted = await delete_article_revision(library, result.article_revision_id)
    assert deleted is not None
    assert deleted.article_revision_id == result.article_revision_id
    assert deleted.deleted_cache is True
    assert deleted.removed_family is True
    assert not bundle_path.exists()
    assert await list_article_items(library) == []


@pytest.mark.asyncio
async def test_import_local_pdf_is_save_only(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="PDF", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="paper.pdf",
        content=b"%PDF-1.7\n",
        kind=ImportLocalKind.pdf,
        parse_after_import=True,
    )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.parse_job_id is None
    assert (bundle_path / "original" / "paper.pdf").read_bytes().startswith(b"%PDF")
    assert not (bundle_path / "document" / "document.json").exists()
    assert manifest.parse_status == "not_started"
    assert manifest.generated_artifacts["pdf"] == "original/paper.pdf"


def make_source_tar() -> bytes:
    content = (
        rb"\documentclass{article}"
        rb"\begin{document}"
        rb"Hello Bilin."
        rb"\end{document}"
    )
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        info = tarfile.TarInfo("paper/main.tex")
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()
