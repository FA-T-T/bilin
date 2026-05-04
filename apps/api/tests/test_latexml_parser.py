from __future__ import annotations

import asyncio
import io
import tarfile
from pathlib import Path

import pytest
from typer.testing import CliRunner

import bilin_api.latexml_parser as parser_module
from bilin_api.article_store import (
    bundle_path_for_arxiv,
    get_article_revision,
    read_manifest,
    upsert_arxiv_revision,
    write_manifest,
)
from bilin_api.cli import app
from bilin_api.latexml_parser import (
    ParseFailure,
    find_main_tex,
    normalize_latexml_html,
    parse_article_revision,
    render_source_markdown,
    safe_unpack,
)
from bilin_api.repositories import create_library
from bilin_api.schemas import ArticleManifest, LibraryCreate


def test_safe_unpack_detects_main_tex(tmp_path: Path) -> None:
    archive_path = tmp_path / "source.tar"
    write_tar(
        archive_path,
        {
            "paper/supplement.tex": b"Supplement only",
            "paper/main.tex": (
                rb"\documentclass{article}"
                rb"\begin{document}"
                rb"Hello."
                rb"\end{document}"
            ),
        },
    )
    unpack_dir = tmp_path / "unpacked"
    safe_unpack(archive_path, unpack_dir)
    assert find_main_tex(unpack_dir).name == "main.tex"


def test_safe_unpack_rejects_path_traversal(tmp_path: Path) -> None:
    archive_path = tmp_path / "unsafe.tar"
    write_tar(archive_path, {"../evil.tex": b"bad"})
    with pytest.raises(ParseFailure) as exc_info:
        safe_unpack(archive_path, tmp_path / "unpacked")
    assert exc_info.value.code == "unsafe_archive:path_traversal"


def test_normalize_latexml_html_outputs_blocks_assets_and_markdown() -> None:
    fixture = Path(__file__).parent / "fixtures" / "latexml" / "minimal.html"
    blocks, assets = normalize_latexml_html(fixture, "revision-1")
    assert [block.block_type for block in blocks] == [
        "section",
        "paragraph",
        "equation",
        "figure",
    ]
    assert blocks[0].source_markdown == "Introduction"
    assert blocks[2].source_markdown == "E=mc^2"
    assert blocks[3].metadata["asset_id"] == "fig-0001"
    assert len(assets) == 1
    assert assets[0].caption == "An overview pipeline."
    assert assets[0].web_path is None
    assert "# Introduction" in render_source_markdown(blocks)


def test_normalize_latexml_html_accepts_html5_void_tags(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    image_path = tmp_path / "figures" / "pipeline.png"
    image_path.parent.mkdir()
    image_path.write_bytes(b"fake image bytes")
    html_path.write_text(
        """
        <!DOCTYPE html><html lang="en">
          <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="LaTeXML.css" type="text/css">
          </head>
          <body>
            <h1>Attention Is All You Need</h1>
            <p>Line one<br>line two&nbsp;with entity.</p>
            <figure id="fig:pipeline">
              <img src="figures/pipeline.png">
              <figcaption>A copied pipeline asset.</figcaption>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    bundle_path = tmp_path / "bundle"

    blocks, assets = normalize_latexml_html(html_path, "revision-1", bundle_path=bundle_path)

    assert [block.block_type for block in blocks] == ["section", "paragraph", "figure"]
    assert blocks[1].source_markdown == "Line one line two with entity."
    assert assets[0].web_path == str(bundle_path / "assets" / "fig-0001.png")


def test_normalize_latexml_html_copies_assets_and_preserves_metadata(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    image_path = tmp_path / "figures" / "pipeline.png"
    image_path.parent.mkdir()
    image_path.write_bytes(b"fake image bytes")
    html_path.write_text(
        """
        <html>
          <body>
            <h1>Introduction</h1>
            <p>See <a href="#bib-key">[1]</a> for context.</p>
            <math display="block" id="eq:energy" alttext="E=mc^2">
              <semantics>
                <annotation encoding="application/x-tex">E=mc^2</annotation>
              </semantics>
            </math>
            <figure id="fig:pipeline">
              <img src="figures/pipeline.png" />
              <figcaption>A copied pipeline asset.</figcaption>
            </figure>
            <table id="tab:results">
              <caption>Regression table.</caption>
              <tr><td>Block</td><td>Expected</td></tr>
            </table>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    bundle_path = tmp_path / "bundle"

    blocks, assets = normalize_latexml_html(html_path, "revision-1", bundle_path=bundle_path)

    paragraph = next(block for block in blocks if block.block_type == "paragraph")
    equation = next(block for block in blocks if block.block_type == "equation")
    table = next(block for block in blocks if block.block_type == "table")
    figure_asset = next(asset for asset in assets if asset.kind == "figure")
    assert paragraph.source_markdown == "See [1](#bib-key) for context."
    assert paragraph.metadata["references"] == [{"href": "#bib-key", "text": "[1]"}]
    assert equation.source_latex == "E=mc^2"
    assert equation.metadata["display"] == "block"
    assert "html_fragment" in equation.metadata
    assert table.metadata["html_fragment"]
    assert figure_asset.source_path == str(image_path)
    assert figure_asset.web_path == str(bundle_path / "assets" / "fig-0001.png")
    assert (bundle_path / "assets" / "fig-0001.png").read_bytes() == b"fake image bytes"


def test_normalize_latexml_html_treats_equation_tables_as_equations(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <table class="ltx_equation ltx_eqn_table" id="S3.E1">
              <tbody>
                <tr class="ltx_equation ltx_eqn_row">
                  <td class="ltx_eqn_cell">
                    <math display="block" alttext="\mathrm{Attention}(Q,K,V)=V"></math>
                  </td>
                  <td class="ltx_eqn_cell ltx_eqn_eqno">(1)</td>
                </tr>
              </tbody>
            </table>
            <table class="ltx_equationgroup ltx_eqn_align ltx_eqn_table" id="S3.EG1">
              <tbody>
                <tr class="ltx_equation ltx_eqn_row">
                  <td><math display="inline" alttext="\displaystyle a"></math></td>
                  <td><math display="inline" alttext="\displaystyle=b"></math></td>
                </tr>
                <tr class="ltx_equation ltx_eqn_row">
                  <td><math display="inline" alttext="\displaystyle c"></math></td>
                  <td><math display="inline" alttext="\displaystyle=d"></math></td>
                </tr>
              </tbody>
            </table>
            <figure class="ltx_table" id="S4.T1">
              <figcaption>A real table with math.</figcaption>
              <table><tr><td><math display="inline" alttext="O(n^2)"></math></td></tr></table>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["equation", "equation", "table"]
    assert blocks[0].block_uid == "eq-0001"
    assert blocks[0].metadata["label"] == "S3.E1"
    assert blocks[0].source_markdown == r"\mathrm{Attention}(Q,K,V)=V"
    assert blocks[1].source_markdown == "\\begin{aligned}\na =b \\\\\nc =d\n\\end{aligned}"
    assert len(assets) == 1
    assert assets[0].kind == "table"


def test_normalize_latexml_html_tracks_latexml_table_figures_and_multiple_images(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    figure_dir = tmp_path / "figures"
    figure_dir.mkdir()
    (figure_dir / "left.png").write_bytes(b"left")
    (figure_dir / "right.png").write_bytes(b"right")
    html_path.write_text(
        """
        <html>
          <body>
            <p>See Figure <a href="#fig:pair">1</a> and Table <a href="#tab:results">1</a>.</p>
            <figure id="fig:pair">
              <img src="figures/left.png" />
              <img src="figures/right.png" />
              <figcaption>A paired image figure.</figcaption>
            </figure>
            <figure class="ltx_table" id="tab:results">
              <figcaption>
                <span class="ltx_tag ltx_tag_table">Table 1: </span>
                A LaTeXML table wrapped in a figure.
              </figcaption>
              <table><tr><td>Model</td><td>Score</td></tr></table>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, assets = normalize_latexml_html(
        html_path,
        "revision-1",
        bundle_path=tmp_path / "bundle",
    )

    assert [block.block_type for block in blocks] == ["paragraph", "figure", "table"]
    assert blocks[0].source_markdown == ("See Figure [1](#fig:pair) and Table [1](#tab:results).")
    assert blocks[2].block_uid == "tbl-0001"
    assert blocks[2].source_markdown == "**Table 1.** A LaTeXML table wrapped in a figure."
    assert blocks[2].metadata["label"] == "tab:results"
    figure_asset = next(asset for asset in assets if asset.kind == "figure")
    assert figure_asset.web_path == str(tmp_path / "bundle" / "assets" / "fig-0001.png")
    assert figure_asset.metadata["asset_files"][1]["web_path"] == str(
        tmp_path / "bundle" / "assets" / "fig-0001-2.png"
    )
    table_asset = next(asset for asset in assets if asset.kind == "table")
    assert table_asset.web_path is None
    assert "<table>" in table_asset.metadata["html_fragment"]


def test_normalize_latexml_html_keeps_layout_tables_inside_figures_as_figures(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <figure class="ltx_figure" id="fig:layout">
              <table class="layout-grid"><tr><td>left panel</td><td>right panel</td></tr></table>
              <figcaption>
                <span class="ltx_tag ltx_tag_figure">Figure 1: </span>
                A figure whose internal layout happens to use a table.
              </figcaption>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["figure"]
    assert blocks[0].source_markdown == (
        "**Figure 1.** A figure whose internal layout happens to use a table."
    )
    assert assets[0].kind == "figure"


def test_normalize_latexml_html_degrades_pdf_asset_when_converter_missing(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    html_path = tmp_path / "latexml.html"
    pdf_path = tmp_path / "figures" / "plot.pdf"
    pdf_path.parent.mkdir()
    pdf_path.write_bytes(b"%PDF-1.7\n")
    html_path.write_text(
        """
        <html>
          <body>
            <figure id="fig:plot">
              <img src="figures/plot.pdf" />
              <figcaption>A PDF plot.</figcaption>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    _blocks, assets = normalize_latexml_html(
        html_path,
        "revision-1",
        bundle_path=tmp_path / "bundle",
    )

    assert assets[0].source_path == str(pdf_path)
    assert assets[0].web_path is None
    assert assets[0].metadata["asset_resolution"] == "missing_dependency"
    assert assets[0].metadata["missing_tool"] == "magick"


def test_normalize_latexml_html_converts_pdf_asset_when_tools_exist(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    html_path = tmp_path / "latexml.html"
    pdf_path = tmp_path / "figures" / "plot.pdf"
    pdf_path.parent.mkdir()
    pdf_path.write_bytes(b"%PDF-1.7\n")
    html_path.write_text(
        """
        <html>
          <body>
            <figure id="fig:plot">
              <img src="figures/plot.pdf" />
              <figcaption>A converted PDF plot.</figcaption>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    def fake_which(name: str) -> str | None:
        if name in {"magick", "gs"}:
            return f"/usr/bin/{name}"
        return None

    def fake_run(
        command: list[str],
        check: bool,
        capture_output: bool,
        text: bool,
        timeout: int,
    ):
        void_values = (check, capture_output, text, timeout)
        assert void_values == (False, True, True, 60)
        Path(command[-1]).write_bytes(b"png")

        class Completed:
            returncode = 0
            stderr = ""

        return Completed()

    monkeypatch.setattr(parser_module.shutil, "which", fake_which)
    monkeypatch.setattr(parser_module.subprocess, "run", fake_run)

    _blocks, assets = normalize_latexml_html(
        html_path,
        "revision-1",
        bundle_path=tmp_path / "bundle",
    )

    assert assets[0].web_path == str(tmp_path / "bundle" / "assets" / "fig-0001.png")
    assert assets[0].metadata["asset_resolution"] == "converted"
    assert assets[0].metadata["web_asset_kind"] == "png"
    assert assets[0].web_path is not None
    assert Path(assets[0].web_path).read_bytes() == b"png"


def test_normalize_latexml_html_marks_code_generated_figure_for_controlled_render(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <figure id="fig:tikz" class="tikzpicture">
              <pre>\begin{tikzpicture}\draw (0,0) -- (1,1);\end{tikzpicture}</pre>
              <figcaption>A generated TikZ figure.</figcaption>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    blocks, assets = normalize_latexml_html(
        html_path,
        "revision-1",
        bundle_path=tmp_path / "bundle",
    )

    assert blocks[0].block_type == "figure"
    assert assets[0].web_path is None
    assert assets[0].metadata["asset_resolution"] == "requires_controlled_render"
    assert assets[0].metadata["generated_asset_kind"] == "tikz"
    assert assets[0].metadata["render_tools"] == {
        "tectonic": False,
        "pdflatex": False,
        "magick": False,
    }


@pytest.mark.asyncio
async def test_parse_article_fails_explicitly_when_latexml_is_missing(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Papers", path=str(tmp_path / "library")),
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
                rb"Hello."
                rb"\end{document}"
            )
        },
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Missing dependency test",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(
        bundle_path,
        ArticleManifest(
            article_revision_id=revision.id,
            arxiv_id="2401.00001v1",
            source="arxiv",
        ),
    )
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    with pytest.raises(ParseFailure) as exc_info:
        await parse_article_revision(library, revision.id)

    assert exc_info.value.code == "missing_dependency:latexml"
    updated_revision = await get_article_revision(library, revision.id)
    assert updated_revision is not None
    assert updated_revision.status == "parse_failed"
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert manifest.parse_status == "failed"
    assert manifest.errors[0].code == "missing_dependency:latexml"
    assert manifest.errors[0].details["doctor_command"] == "bilin doctor"
    assert "Install LaTeXML" in manifest.errors[0].details["install_hint"]
    error_log = bundle_path / "logs" / "parse-error.json"
    assert error_log.exists()
    assert manifest.generated_artifacts["parse_error_log"] == str(error_log)
    assert "missing_dependency:latexml" in error_log.read_text(encoding="utf-8")


def test_parse_cli_prints_missing_latexml_guidance(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library_id, revision_id = asyncio.run(prepare_missing_dependency_cli_fixture(tmp_path))
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    result = CliRunner().invoke(app, ["parse", "article", library_id, revision_id])

    assert result.exit_code == 1
    assert "missing_dependency:latexml" in result.output
    assert "Install LaTeXML" in result.output
    assert "bilin doctor" in result.output


async def prepare_missing_dependency_cli_fixture(tmp_path: Path) -> tuple[str, str]:
    library = await create_library(LibraryCreate(name="Parse CLI", path=str(tmp_path / "library")))
    bundle_path = bundle_path_for_arxiv(library, "2401.00002", "v1")
    original_dir = bundle_path / "original"
    original_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {"main.tex": b"\\documentclass{article}\\begin{document}x\\end{document}"},
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00002",
        version="v1",
        title="Missing dependency CLI test",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(bundle_path, ArticleManifest(article_revision_id=revision.id, source="arxiv"))
    return library.id, revision.id


def write_tar(path: Path, files: dict[str, bytes]) -> None:
    with tarfile.open(path, mode="w") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
