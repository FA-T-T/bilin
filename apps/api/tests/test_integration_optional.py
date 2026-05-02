from __future__ import annotations

import io
import os
import shutil
import tarfile
from pathlib import Path

import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    read_article_document,
    upsert_arxiv_revision,
)
from bilin_api.golden import run_live_latexml_golden_fixture
from bilin_api.importer import import_arxiv
from bilin_api.latexml_parser import parse_article_revision
from bilin_api.repositories import create_library
from bilin_api.schemas import ImportArxivRequest, LibraryCreate

RUN_LATEXML_INTEGRATION = os.getenv("BILIN_RUN_LATEXML_INTEGRATION") == "1"


@pytest.mark.integration_live_arxiv
@pytest.mark.skipif(
    os.getenv("BILIN_RUN_LIVE_ARXIV") != "1",
    reason="Set BILIN_RUN_LIVE_ARXIV=1 to run live arXiv import.",
)
@pytest.mark.asyncio
async def test_live_arxiv_import_downloads_bundle(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Live arXiv", path=str(tmp_path / "library")),
    )
    result = await import_arxiv(
        library,
        ImportArxivRequest(
            arxiv_id=os.getenv("BILIN_LIVE_ARXIV_ID", "2401.00001"),
            parse_after_import=False,
        ),
    )
    bundle_path = Path(result.bundle_path)
    assert (bundle_path / "original" / "source.tar").exists()
    assert (bundle_path / "original" / "paper.pdf").exists()


@pytest.mark.integration_latexml
@pytest.mark.skipif(
    not RUN_LATEXML_INTEGRATION or not shutil.which("latexml") or not shutil.which("latexmlpost"),
    reason="Set BILIN_RUN_LATEXML_INTEGRATION=1 and install LaTeXML to run live parser tests.",
)
@pytest.mark.asyncio
async def test_latexml_parse_generates_document(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="LaTeXML", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00001", "v1")
    original_dir = bundle_path / "original"
    original_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {
            "main.tex": (
                rb"\documentclass{article}"
                rb"\begin{document}"
                rb"\section{Introduction}"
                rb"Hello Bilin."
                rb"\[E=mc^2\]"
                rb"\end{document}"
            )
        },
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="LaTeXML integration",
        bundle_path=bundle_path,
        metadata={},
    )
    result = await parse_article_revision(library, revision.id)
    document = await read_article_document(library, revision.id)
    assert result["block_count"] > 0
    assert document is not None
    assert (bundle_path / "document" / "document.json").exists()
    assert (bundle_path / "document" / "source.md").exists()


@pytest.mark.integration_latexml
@pytest.mark.skipif(
    not RUN_LATEXML_INTEGRATION or not shutil.which("latexml") or not shutil.which("latexmlpost"),
    reason="Set BILIN_RUN_LATEXML_INTEGRATION=1 and install LaTeXML to run live parser tests.",
)
@pytest.mark.asyncio
async def test_latexml_golden_fixture_matches_expected(bilin_home: Path) -> None:
    fixture_path = Path(__file__).resolve().parents[3] / "fixtures" / "golden" / "minimal-paper"

    result = await run_live_latexml_golden_fixture(fixture_path)

    assert result.fixture == "minimal-paper"
    assert result.block_types == ["section", "paragraph", "equation", "figure", "table"]
    assert result.asset_count == 2


def write_tar(path: Path, files: dict[str, bytes]) -> None:
    with tarfile.open(path, mode="w") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
