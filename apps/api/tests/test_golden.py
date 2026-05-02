from __future__ import annotations

import json
from pathlib import Path

from typer.testing import CliRunner

from bilin_api.cli import app
from bilin_api.golden import GoldenRegressionFailure, run_golden_fixture


def test_golden_fixture_passes_structural_assertions() -> None:
    result = run_golden_fixture(golden_fixture_path())

    assert result.fixture == "minimal-paper"
    assert result.block_count == 5
    assert result.asset_count == 2
    assert result.block_types == ["section", "paragraph", "equation", "figure", "table"]
    assert result.block_uids == ["sec-001", "p-0001", "eq-0001", "fig-0001", "tbl-0001"]
    assert result.summary["source_markdown_sha256"]
    assets = result.summary["assets"]
    assert assets[0]["source_path"].endswith("fixtures/golden/minimal-paper/assets/pipeline.svg")
    assert result.summary["duplicate_block_uids"] == []


def test_public_arxiv_golden_fixture_passes_structural_assertions() -> None:
    result = run_golden_fixture(public_arxiv_golden_fixture_path())

    assert result.fixture == "public-arxiv-2408.13687"
    assert result.block_count == 7
    assert result.asset_count == 2
    assert result.block_types == [
        "section",
        "paragraph",
        "equation",
        "section",
        "paragraph",
        "figure",
        "table",
    ]
    assert result.block_uids == [
        "sec-001",
        "p-0001",
        "eq-0001",
        "sec-002",
        "p-0002",
        "fig-0001",
        "tbl-0001",
    ]
    assert result.summary["duplicate_block_uids"] == []
    assert result.summary["blocks"][4]["source_markdown"].endswith(
        "Ref. [1](#bib:acharya2024threshold)."
    )
    assets = result.summary["assets"]
    assert assets[0]["source_path"].endswith(
        "fixtures/golden/public-arxiv-2408.13687/assets/surface-code-memory.svg"
    )


def test_golden_fixture_reports_meaningful_failures(tmp_path: Path) -> None:
    fixture = tmp_path / "broken"
    fixture.mkdir()
    (fixture / "latexml.html").write_text(
        "<html><body><h1>Only one block</h1></body></html>",
        encoding="utf-8",
    )
    (fixture / "expected.json").write_text(
        json.dumps(
            {
                "latexml_html": "latexml.html",
                "block_count": 2,
                "block_types": ["section", "paragraph"],
            }
        ),
        encoding="utf-8",
    )

    try:
        run_golden_fixture(fixture)
    except GoldenRegressionFailure as exc:
        assert "block_count" in "\n".join(exc.failures)
        assert "block_types" in "\n".join(exc.failures)
    else:  # pragma: no cover - assertion guard
        raise AssertionError("Expected golden regression failure")


def test_golden_cli_runs_fixture() -> None:
    runner = CliRunner()
    result = runner.invoke(app, ["golden", "run", str(golden_fixture_path())])

    assert result.exit_code == 0
    assert "minimal-paper" in result.output
    assert '"block_count": 5' in result.output


def test_golden_cli_runs_public_arxiv_fixture() -> None:
    runner = CliRunner()
    result = runner.invoke(app, ["golden", "run", str(public_arxiv_golden_fixture_path())])

    assert result.exit_code == 0
    assert "public-arxiv-2408.13687" in result.output
    assert '"block_count": 7' in result.output
    assert '"p-0002"' in result.output


def test_acceptance_cli_exports_golden_fixture(bilin_home: Path, tmp_path: Path) -> None:
    runner = CliRunner()
    output_dir = tmp_path / "acceptance"
    result = runner.invoke(
        app,
        [
            "acceptance",
            "golden",
            str(golden_fixture_path()),
            "--output-dir",
            str(output_dir),
        ],
    )

    assert result.exit_code == 0
    assert '"parse_mode": "fixture-html"' in result.output
    library_path = output_dir / "library"
    assert list(library_path.rglob("document/document.json"))
    assert list(library_path.rglob("export/source.md"))
    assert list(library_path.rglob("export/translation.zh-CN.md"))
    assert list(library_path.rglob("export/bilingual.zh-CN.md"))
    assert list(library_path.rglob("export/lecture-notes.md"))
    assert list(library_path.rglob("export/article-bundle.zip"))


def golden_fixture_path() -> Path:
    return Path(__file__).resolve().parents[3] / "fixtures" / "golden" / "minimal-paper"


def public_arxiv_golden_fixture_path() -> Path:
    return Path(__file__).resolve().parents[3] / "fixtures" / "golden" / "public-arxiv-2408.13687"
