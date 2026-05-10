from __future__ import annotations

import asyncio
import io
import sys
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
    CommandTimeoutBudget,
    ParseFailure,
    estimate_latexml_timeout_budget,
    find_main_tex,
    normalize_latexml_html,
    parse_article_revision,
    prepare_latexml_included_source,
    prepare_latexml_side_sources,
    prepare_latexml_source,
    render_source_markdown,
    run_command,
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


def test_find_main_tex_accepts_old_style_documentstyle_ltx(tmp_path: Path) -> None:
    source_dir = tmp_path / "old-style"
    source_dir.mkdir()
    (source_dir / "notes.tex").write_text(
        "\\section{Notes only}\nNo document wrapper.",
        encoding="utf-8",
    )
    (source_dir / "paper_v1.ltx").write_text(
        "\\documentstyle[aps]{revtex}\n"
        "\\title{Old paper}\n"
        "\\begin{document}\n"
        "Hello old arXiv.\n"
        "\\end{document}\n",
        encoding="utf-8",
    )

    assert find_main_tex(source_dir).name == "paper_v1.ltx"


def test_find_main_tex_accepts_extensionless_old_arxiv_source(tmp_path: Path) -> None:
    source_dir = tmp_path / "extensionless"
    source_dir.mkdir()
    (source_dir / "9407022").write_text(
        "\\documentstyle{article}\n"
        "\\author{A. Author}\n"
        "\\begin{document}\n"
        "Old style source without a file extension.\n"
        "\\end{document}\n",
        encoding="utf-8",
    )

    assert find_main_tex(source_dir).name == "9407022"


def test_safe_unpack_rejects_path_traversal(tmp_path: Path) -> None:
    archive_path = tmp_path / "unsafe.tar"
    write_tar(archive_path, {"../evil.tex": b"bad"})
    with pytest.raises(ParseFailure) as exc_info:
        safe_unpack(archive_path, tmp_path / "unpacked")
    assert exc_info.value.code == "unsafe_archive:path_traversal"


def test_prepare_latexml_source_disables_babel_without_touching_other_packages() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{article}\n"
        "\\usepackage{graphicx,babel,amsmath}\n"
        "\\RequirePackage[main=english]{polyglossia}\n"
        "\\usepackage[acronym]{glossaries}\n"
        "\\usepackage[bookmarks=false]{hyperref}\n"
        "\\begin{document}x\\end{document}\n"
    )

    assert prepared.startswith("% Bilin LaTeXML parser entry.")
    assert "\\usepackage{graphicx,amsmath}" in prepared
    assert "% Bilin disabled for LaTeXML: babel" in prepared
    assert "% Bilin disabled for LaTeXML: \\RequirePackage[main=english]{polyglossia}" in prepared
    assert "% Bilin disabled for LaTeXML: \\usepackage[acronym]{glossaries}" in prepared
    assert "\\usepackage[bookmarks=false]{hyperref}" in prepared
    assert "% Bilin LaTeXML compatibility shims." in prepared
    assert "\\providecommand{\\vmathbb}[1]{\\mathbb{#1}}" in prepared
    assert "\\providecommand{\\gls}[1]{#1}" in prepared
    assert "\\providecommand{\\newacronym}[3]{}" in prepared
    assert "\\providecommand{\\resizebox}[3]{#3}" in prepared


def test_prepare_latexml_source_injects_after_documentstyle() -> None:
    prepared = prepare_latexml_source(
        "\\documentstyle[aps]{revtex}\n\\begin{document}x\\end{document}\n"
    )

    assert "\\documentstyle[aps]{revtex}\n% Bilin LaTeXML compatibility shims." in prepared


def test_prepare_latexml_source_replaces_elsevier_cas_class_with_article_shims() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass[a4paper,fleqn]{cas-sc}\n"
        "\\begin{document}\n"
        "\\title[mode=title]{A CAS Paper}\n"
        "\\author[1]{Ada Lovelace}[orcid=0000-0000]\n"
        "\\author[2]{Grace Hopper}[\n"
        "  type=editor, orcid=0000-0001-5034-474X]\n"
        "\\author[1,2]{Katherine Johnson}[corref=cor1, fnref=fn1]\n"
        "\\address[1]{Analytical Engine Lab}\n"
        "\\begin{abstract}x\\end{abstract}\n"
        "\\maketitle\n"
        "\\end{document}\n"
    )

    assert "\\documentclass{article}" in prepared
    assert "\\documentclass[a4paper,fleqn]{cas-sc}" not in prepared
    assert "% Bilin replaced layout document class for LaTeXML: cas-sc" in prepared
    assert "\\RequirePackage{expl3,xparse}" not in prepared
    assert "\\providecommand{\\shorttitle}[1]{}" in prepared
    assert "\\def\\BilinCASTitleWith[#1]#2{\\BilinArticleTitle{#2}}" in prepared
    assert "\\def\\BilinCASAuthorWithMeta#1[#2]{\\BilinArticleAuthor{#1}}" in prepared
    assert "\\providecommand{\\address}" in prepared
    assert "[orcid=0000-0000]" not in prepared
    assert "type=editor, orcid=0000-0001-5034-474X" not in prepared
    assert "[corref=cor1, fnref=fn1]" not in prepared
    assert "\\author[1]{Ada Lovelace}" in prepared
    assert "\\author[2]{Grace Hopper}" in prepared
    assert "\\author[1,2]{Katherine Johnson}" in prepared


def test_prepare_latexml_side_sources_disables_incompatible_packages_in_inputs(
    tmp_path: Path,
) -> None:
    unpack_dir = tmp_path / "unpacked"
    preamble_dir = unpack_dir / "00_preamble"
    preamble_dir.mkdir(parents=True)
    main_tex = unpack_dir / "main.tex"
    main_tex.write_text(
        "\\documentclass{article}\n\\input{00_preamble/preamble.tex}\n",
        encoding="utf-8",
    )
    preamble = preamble_dir / "preamble.tex"
    preamble.write_text(
        "\\usepackage[english]{babel}\n\\usepackage{graphicx,polyglossia,amsmath}\n",
        encoding="utf-8",
    )

    prepare_latexml_side_sources(unpack_dir, main_tex)

    assert main_tex.read_text(encoding="utf-8").startswith("\\documentclass{article}")
    prepared = preamble.read_text(encoding="utf-8")
    assert "% Bilin disabled for LaTeXML: \\usepackage[english]{babel}" in prepared
    assert "\\usepackage{graphicx,amsmath}% Bilin disabled for LaTeXML: polyglossia" in prepared


def test_prepare_latexml_included_source_replaces_qcircuit_blocks() -> None:
    prepared = prepare_latexml_included_source(
        "\\usepackage{qcircuit}\n"
        "\\begin{figure}\n"
        "\\Qcircuit @C=1em @!R {"
        "\\lstick{\\ket{0}} & \\gate{H} & \\qw \\\\"
        "}\n"
        "\\caption{Circuit}\n"
        "\\end{figure}\n"
    )

    assert "% Bilin disabled for LaTeXML: \\usepackage{qcircuit}" in prepared
    assert "\\Qcircuit" not in prepared
    assert "\\gate{H}" not in prepared
    assert "\\mbox{Quantum circuit diagram}" in prepared
    assert "\\caption{Circuit}" in prepared


def test_latexml_timeout_budget_scales_with_source_size(tmp_path: Path) -> None:
    small = tmp_path / "small"
    large = tmp_path / "large"
    small.mkdir()
    large.mkdir()
    small_main = small / "main.tex"
    large_main = large / "main.tex"
    small_main.write_text(
        "\\documentclass{article}\\begin{document}Small.\\end{document}",
        encoding="utf-8",
    )
    large_main.write_text(
        "\\documentclass{article}\\begin{document}"
        + ("Long paragraph.\n" * 50_000)
        + "\\end{document}",
        encoding="utf-8",
    )
    for index in range(12):
        (large / f"figure-{index}.pdf").write_bytes(b"%PDF-1.7\n")

    small_budget = estimate_latexml_timeout_budget(small, small_main, "latexml")
    large_budget = estimate_latexml_timeout_budget(large, large_main, "latexml")

    assert small_budget.soft_seconds >= 60
    assert large_budget.soft_seconds > small_budget.soft_seconds
    assert large_budget.hard_seconds > large_budget.soft_seconds


@pytest.mark.asyncio
async def test_run_command_keeps_running_while_output_shows_activity(tmp_path: Path) -> None:
    log_path = tmp_path / "active.log"
    await run_command(
        [
            sys.executable,
            "-c",
            (
                "import time\n"
                "for index in range(4):\n"
                "    print(f'latexml progress {index}', flush=True)\n"
                "    time.sleep(0.15)\n"
            ),
        ],
        cwd=tmp_path,
        log_path=log_path,
        timeout_budget=CommandTimeoutBudget(
            soft_seconds=0.05,
            idle_seconds=0.25,
            hard_seconds=2,
        ),
    )

    assert "latexml progress 3" in log_path.read_text(encoding="utf-8")


@pytest.mark.asyncio
async def test_run_command_times_out_after_idle_soft_limit(tmp_path: Path) -> None:
    log_path = tmp_path / "idle.log"
    with pytest.raises(ParseFailure) as exc_info:
        await run_command(
            [sys.executable, "-c", "import time; time.sleep(1)"],
            cwd=tmp_path,
            log_path=log_path,
            timeout_budget=CommandTimeoutBudget(
                soft_seconds=0.05,
                idle_seconds=0.1,
                hard_seconds=2,
            ),
        )

    assert exc_info.value.code == "latexml_timeout"
    assert exc_info.value.details["timeout_reason"] == "idle"
    assert "timeout_error" in log_path.read_text(encoding="utf-8")


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


def test_normalize_latexml_html_preserves_inline_math_as_markdown_math(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p>
              Most models cite <cite class="ltx_cite">[<a href="#bib.bib5">5</a>,
              <a href="#bib.bib2">2</a>]</cite>. Here, the encoder maps
              an input sequence of symbol representations
              <math alttext="(x_1,\ldots,x_n)"></math> to a sequence of continuous
              representations <math alttext="\mathbf{z}=(z_1,\ldots,z_n)"></math>.
            </p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert blocks[0].source_markdown == (
        "Most models cite [5](#bib.bib5), [2](#bib.bib2). Here, the encoder maps "
        "an input sequence of symbol representations "
        "$(x_1,\\ldots,x_n)$ to a sequence of continuous representations "
        "$\\mathbf{z}=(z_1,\\ldots,z_n)$."
    )
    assert "[[5]" not in blocks[0].source_markdown
    assert "$(x_1,\\ldots,x_n)$" in render_source_markdown(blocks)


def test_normalize_latexml_html_inlines_footnote_urls_as_links(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <p class="ltx_p">Deep residual nets are foundations of our submissions
            to ILSVRC &amp; COCO 2015 competitions<span id="footnote1"
            class="ltx_note ltx_role_footnote"><sup class="ltx_note_mark">1</sup>
            <span class="ltx_note_outer"><span class="ltx_note_content">
            <sup class="ltx_note_mark">1</sup>
            <span class="ltx_tag ltx_tag_note">1</span>
            <a href="http://image-net.org/challenges/LSVRC/2015/"
            class="ltx_ref ltx_url ltx_font_typewriter">
            http://image-net.org/challenges/LSVRC/2015/</a> and
            <a href="http://mscoco.org/dataset/#detections-challenge2015"
            class="ltx_ref ltx_url ltx_font_typewriter">
            http://mscoco.org/dataset/#detections-challenge2015</a>.
            </span></span></span>, where we also won the first places.</p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert blocks[0].source_markdown == (
        "Deep residual nets are foundations of our submissions to ILSVRC & COCO 2015 "
        "competitions "
        "([http://image-net.org/challenges/LSVRC/2015/]"
        "(http://image-net.org/challenges/LSVRC/2015/) and "
        "[http://mscoco.org/dataset/#detections-challenge2015]"
        "(http://mscoco.org/dataset/#detections-challenge2015)), "
        "where we also won the first places."
    )
    assert "11 1" not in blocks[0].source_markdown
    assert ">., where" not in blocks[0].source_markdown


def test_normalize_latexml_html_links_bare_urls_without_nested_markdown(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <p>Code is available at https://github.com/example/project.</p>
            <p>Already linked <a href="https://github.com/example/project">
            https://github.com/example/project</a>.</p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert blocks[0].source_markdown == (
        "Code is available at [https://github.com/example/project]"
        "(https://github.com/example/project)."
    )
    assert blocks[1].source_markdown == (
        "Already linked [https://github.com/example/project](https://github.com/example/project)."
    )
    assert "[[https://github.com/example/project]" not in blocks[1].source_markdown


def test_normalize_latexml_html_preserves_latexml_lists_as_single_blocks(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p>The construction has three stages.</p>
            <ul class="ltx_itemize">
              <li class="ltx_item">
                <span class="ltx_tag ltx_tag_item">•</span>
                <div class="ltx_para"><p>Prepare the stabilizer generators.</p></div>
              </li>
              <li class="ltx_item">
                <span class="ltx_tag ltx_tag_item">•</span>
                <div class="ltx_para"><p>Group commuting operators.</p></div>
                <ol class="ltx_enumerate">
                  <li class="ltx_item">
                    <span class="ltx_tag ltx_tag_item">(1)</span>
                    <p>Measure each group once.</p>
                  </li>
                  <li class="ltx_item">
                    <span class="ltx_tag ltx_tag_item">(2)</span>
                    <p>Reuse the outcomes.</p>
                  </li>
                </ol>
              </li>
            </ul>
            <ol class="ltx_enumerate">
              <li class="ltx_item">
                <span class="ltx_tag ltx_tag_item">1.</span>
                <p>Run the decoder.</p>
              </li>
              <li class="ltx_item">
                <span class="ltx_tag ltx_tag_item">2.</span>
                <p>Return the correction.</p>
              </li>
            </ol>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["paragraph", "list", "list"]
    assert blocks[1].block_uid == "lst-0001"
    assert blocks[1].source_markdown == (
        "- Prepare the stabilizer generators.\n"
        "- Group commuting operators.\n"
        "  1. Measure each group once.\n"
        "  2. Reuse the outcomes."
    )
    assert blocks[1].metadata["list_kind"] == "unordered"
    assert blocks[1].metadata["item_count"] == 2
    assert blocks[2].source_markdown == "1. Run the decoder.\n2. Return the correction."


def test_normalize_latexml_html_skips_generated_toc_navigation(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <nav class="ltx_TOC ltx_list_toc ltx_toc_toc">
              <h6 class="ltx_title ltx_title_contents">Contents</h6>
              <ol class="ltx_toclist">
                <li><a href="#Ch1">Chapter 1 Introduction</a></li>
                <li><a href="#Ch1.S1">1.1 Quantum Computers</a></li>
              </ol>
            </nav>
            <nav class="ltx_TOC ltx_list_lot ltx_toc_lot">
              <h6 class="ltx_title ltx_title_contents">List of Tables</h6>
              <ol class="ltx_toclist">
                <li><a href="#tbl-1">Table 1 Decoder outcomes</a></li>
              </ol>
            </nav>
            <nav class="ltx_TOC ltx_list_lof ltx_toc_lof">
              <h6 class="ltx_title ltx_title_contents">List of Figures</h6>
              <ol class="ltx_toclist">
                <li><a href="#fig-1">Figure 1 Code geometry</a></li>
              </ol>
            </nav>
            <section id="Ch1" class="ltx_chapter">
              <h2 class="ltx_title ltx_title_chapter">Chapter 1 Introduction</h2>
              <p>Stabilizer codes encode quantum information.</p>
            </section>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["section", "paragraph"]
    assert [block.source_markdown for block in blocks] == [
        "Chapter 1 Introduction",
        "Stabilizer codes encode quantum information.",
    ]
    assert not any(block.source_markdown in {"Contents", "List of Tables"} for block in blocks)


def test_normalize_latexml_html_skips_author_metadata_attribute_paragraph(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <article class="ltx_document ltx_authors_1line">
              <div id="p1" class="ltx_para">
                <p class="ltx_p">[type=editor,
                orcid=0000-0001-5034-474X]
                [orcid=0000-0002-6517-2458]
                [corref=cor1, fnref=fn1]</p>
              </div>
              <div id="p2" class="ltx_para">
                <p class="ltx_p">[corref=cor2, fnref=fn2]</p>
              </div>
              <h1 class="ltx_title ltx_title_document">
                The Variational Quantum Eigensolver: a review of methods and best practices
              </h1>
              <p class="ltx_p">The VQE computes an upper bound for a ground-state energy.</p>
            </article>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["section", "paragraph"]
    source_markdown = render_source_markdown(blocks).lower()
    assert "orcid" not in source_markdown
    assert "corref" not in source_markdown
    assert blocks[0].source_markdown == (
        "The Variational Quantum Eigensolver: a review of methods and best practices"
    )
    assert blocks[1].source_markdown == (
        "The VQE computes an upper bound for a ground-state energy."
    )


def test_normalize_latexml_html_cleans_author_year_citation_artifacts(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p>
              Stabilizer codes follow \citeauthor*qec_binary_orthogonal_geometry
              <cite class="ltx_cite">
                <a href="#bib.bib7">
                  Calderbank et al.(1997)Calderbank, Rains, Shor, and Sloane
                </a>
              </cite>.
            </p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert "\\citeauthor" not in blocks[0].source_markdown
    assert "qec_binary_orthogonal_geometry" not in blocks[0].source_markdown
    assert "Calderbank, Rains" not in blocks[0].source_markdown
    assert blocks[0].source_markdown == (
        "Stabilizer codes follow [Calderbank et al. (1997)](#bib.bib7)."
    )


def test_normalize_latexml_html_normalizes_custom_math_macros_and_matrix_options(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <math display="block"
              alttext="\mathcal{G}_{1}\coloneqq\Big{\{}\{4\,X_{1},\ Z_{2}\}\Big{\}},
                \mathrm{Var}[P_{i}]\coloneqq 1-\expectationvalue{P_{i}}^{2}."></math>
            <math display="block"
              alttext="Q_{1}\coloneqq\begin{pmatrix}[cccc|cccc]\\[1.0pt]
                1&amp;0\\[1.0pt]\hline\cr\\[1.0pt]0&amp;1\\[1.0pt]\end{pmatrix}."></math>
            <math display="block"
              alttext="\left[\begin{array}[]{c}\text{3$\times$3, 64}\\[-1.00006pt]
                \text{3$\times$3, 64}\end{array}\right]\times2"></math>
            <math display="block"
              alttext="\sigma_{x}=\pmatrix{0&amp;1\cr 1&amp;0},\ {\rm and}\
                \ \sigma_{z}=\pmatrix{1&amp;0\cr 0&amp;-1}."></math>
            <math display="block"
              alttext="f_{M}(E)=\left\{\begin{array}[]{ll}0&amp;\mbox{if $[M,E]=0$}\\
                1&amp;\mbox{if $\{M,E\}=0$}\end{array}\right."></math>
            <math display="block"
              alttext="\begin{array}[]{r}r\{\\ n-k-r\{\end{array}\left(\begin{array}[]{cc|cc}
                \raisebox{0.0pt}[6.45831pt]{$\overbrace{I}^{r}$}&amp;\raisebox{0.0pt}[6.45831pt]{$\overbrace{A}^{n-r}$}&amp;B&amp;C\\
                0&amp;0&amp;D&amp;E\end{array}\right)."></math>
            <math display="block"
              alttext="L\eqqcolon \textsc{mask}"></math>
            <math display="block"
              alttext="\vmathbb{1}+\varmathbb{N}+\vvmathbb{C}+\mathds{R}
                +\mathbbm{Z}+\mathbbold{Q}+\text{\sl N}_{\mathrm{BN}}\nopagebreak"></math>
            <math display="block"
              alttext="\wideparen{AB}+\buildrel{d}\over{=}+\cancelto{0}{x}
                +\mspace{2mu}y+\strut z+\rotatebox{90}{r}+\scalebox{2}{s}
                +\resizebox{1cm}{!}{t}+\multicolumn{2}{c}{u}
                +\ensuremath{v}+w\xspace+\label{eq:w}+\iddots
                +\begin{split}a&amp;=b\end{split}"></math>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == [
        "equation",
        "equation",
        "equation",
        "equation",
        "equation",
        "equation",
        "equation",
        "equation",
        "equation",
    ]
    assert r"\coloneqq" not in blocks[0].source_markdown
    assert r"\expectationvalue" not in blocks[0].source_markdown
    assert ":=" in blocks[0].source_markdown
    assert r"\Big\{" in blocks[0].source_markdown
    assert r"\left\langle P_{i} \right\rangle" in blocks[0].source_markdown
    assert "[cccc|cccc]" not in blocks[1].source_markdown
    assert r"\hline" not in blocks[1].source_markdown
    assert r"\cr" not in blocks[1].source_markdown
    assert "[1.0pt]" not in blocks[1].source_markdown
    assert r"\begin{array}[]" not in blocks[2].source_markdown
    assert r"\begin{array}{c}" in blocks[2].source_markdown
    assert r"\pmatrix" not in blocks[3].source_markdown
    assert r"\begin{pmatrix}0&1\\ 1&0\end{pmatrix}" in blocks[3].source_markdown
    assert r"\mbox" not in blocks[4].source_markdown
    assert r"\text{if }[M,E]=0" in blocks[4].source_markdown
    assert r"\raisebox" not in blocks[5].source_markdown
    assert r"$\overbrace" not in blocks[5].source_markdown
    assert r"\overbrace{I}^{r}" in blocks[5].source_markdown
    assert r"\eqqcolon" not in blocks[6].source_markdown
    assert r"\mathrel{=:}" in blocks[6].source_markdown
    assert r"\text{MASK}" in blocks[6].source_markdown
    assert r"\vmathbb" not in blocks[7].source_markdown
    assert r"\mathds" not in blocks[7].source_markdown
    assert r"\mathbbm" not in blocks[7].source_markdown
    assert r"\sl" not in blocks[7].source_markdown
    assert r"\nopagebreak" not in blocks[7].source_markdown
    assert r"\mathbb{1}+\mathbb{N}+\mathbb{C}+\mathbb{R}" in blocks[7].source_markdown
    assert r"\textit{N}_{\mathrm{BN}}" in blocks[7].source_markdown
    assert r"\wideparen" not in blocks[8].source_markdown
    assert r"\buildrel" not in blocks[8].source_markdown
    assert r"\cancelto" not in blocks[8].source_markdown
    assert r"\mspace" not in blocks[8].source_markdown
    assert r"\strut" not in blocks[8].source_markdown
    assert r"\rotatebox" not in blocks[8].source_markdown
    assert r"\scalebox" not in blocks[8].source_markdown
    assert r"\resizebox" not in blocks[8].source_markdown
    assert r"\multicolumn" not in blocks[8].source_markdown
    assert r"\xspace" not in blocks[8].source_markdown
    assert r"\label" not in blocks[8].source_markdown
    assert r"\iddots" not in blocks[8].source_markdown
    assert r"\overset{\frown}{AB}" in blocks[8].source_markdown
    assert r"\overset{d}{=}" in blocks[8].source_markdown
    assert r"\overset{0}{x}" in blocks[8].source_markdown
    assert r"\ddots" in blocks[8].source_markdown
    assert r"\begin{aligned}a&=b\end{aligned}" in blocks[8].source_markdown


def test_normalize_latexml_html_escapes_inline_math_less_than_before_markdown(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p class="ltx_p">For a nondegenerate code,
              <math display="inline" alttext="A_{d^{\prime}}=B_{d^{\prime}}=0"></math>
              for <math display="inline" alttext="d^{\prime}&lt;d"></math>.
              These constraints along with equation
              (<a href="#Ch7.E14" class="ltx_ref"><span>7.14</span></a>)
              restrict the allowed values of <math display="inline" alttext="A_{d}"></math>.
            </p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert len(blocks) == 1
    assert "$d^{\\prime}<d$" in blocks[0].source_markdown
    assert "These constraints along with equation ([7.14](#Ch7.E14))" in (blocks[0].source_markdown)
    assert "$d^{\\prime}7.14)" not in blocks[0].source_markdown


def test_normalize_latexml_html_keeps_paragraph_headings_as_sections(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <h2>Model Architecture</h2>
            <div class="ltx_para" id="S3.p1">
              <h5 class="ltx_title ltx_title_paragraph">Encoder:</h5>
              <p>The encoder is composed of a stack of identical layers.</p>
            </div>
            <div class="ltx_para" id="S3.p2">
              <h6 class="ltx_title ltx_title_subparagraph">Decoder:</h6>
              <p>The decoder follows the same overall structure.</p>
            </div>
            <h5 class="ltx_title ltx_title_paragraph" id="S3.p3">Attention:</h5>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == [
        "section",
        "section",
        "paragraph",
        "section",
        "paragraph",
        "section",
    ]
    assert blocks[1].source_markdown == "Encoder:"
    assert blocks[1].metadata["label"] is None
    assert blocks[2].source_markdown == "The encoder is composed of a stack of identical layers."
    assert blocks[3].source_markdown == "Decoder:"
    assert blocks[4].source_markdown == "The decoder follows the same overall structure."
    assert blocks[5].source_markdown == "Attention:"
    source_markdown = render_source_markdown(blocks)
    assert "## Model Architecture" in source_markdown
    assert "##### Encoder:" in source_markdown
    assert "**Encoder:** The encoder is composed" not in source_markdown


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


def test_normalize_latexml_html_recovers_missing_image_sources_from_latexml_xml(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    xml_path = tmp_path / "latexml.xml"
    source_root = tmp_path / "source"
    vis_dir = source_root / "vis"
    vis_dir.mkdir(parents=True)
    (vis_dir / "making.png").write_bytes(b"making")
    (vis_dir / "anaphora-a.png").write_bytes(b"anaphora-a")
    (vis_dir / "anaphora-b.png").write_bytes(b"anaphora-b")
    html_path.write_text(
        """
        <html>
          <body>
            <figure id="Sx1.F3">
              <img class="ltx_missing_image" id="Sx1.F3.g1" src="">
              <figcaption>Figure 3: Missing HTML source.</figcaption>
            </figure>
            <figure id="Sx1.F4">
              <img class="ltx_missing_image" id="Sx1.F4.g1" src="">
              <img class="ltx_missing_image" id="Sx1.F4.g2" src="">
              <figcaption>Figure 4: Two missing HTML sources.</figcaption>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    xml_path.write_text(
        """
        <document>
          <figure xml:id="Sx1.F3">
            <graphics xml:id="Sx1.F3.g1" candidates="vis/making.png"
              options="width=433.62pt,trim=0.0pt 0.0pt 0.0pt 36.135pt,clip=true"/>
          </figure>
          <figure xml:id="Sx1.F4">
            <graphics xml:id="Sx1.F4.g1" candidates="./vis/anaphora-a.png"
              options="width=433.62pt,clip=true"/>
            <graphics xml:id="Sx1.F4.g2" candidates="./vis/anaphora-b.png"
              options="width=433.62pt,clip=true"/>
          </figure>
        </document>
        """,
        encoding="utf-8",
    )
    bundle_path = tmp_path / "bundle"

    blocks, assets = normalize_latexml_html(
        html_path,
        "revision-1",
        bundle_path=bundle_path,
        source_root=source_root,
    )

    assert [block.block_type for block in blocks] == ["figure", "figure"]
    assert blocks[0].metadata["asset_source"] == str(vis_dir / "making.png")
    assert assets[0].web_path == str(bundle_path / "assets" / "fig-0001.png")
    assert assets[0].metadata["original_reference"] == "vis/making.png"
    assert assets[0].metadata["display_width_pt"] == 433.62
    assert assets[0].metadata["asset_resolution"] == "copied"
    assert assets[1].metadata["original_references"] == [
        "vis/anaphora-a.png",
        "vis/anaphora-b.png",
    ]
    assert assets[1].metadata["asset_files"][1]["web_path"] == str(
        bundle_path / "assets" / "fig-0002-2.png"
    )


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
    assert blocks[0].metadata["equation_number"] == "(1)"
    assert blocks[0].metadata["equation_numbers"] == ["(1)"]
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
              <div style="width:144pt;">
                <img src="figures/left.png" width="288" height="180" />
              </div>
              <div style="width:216pt;">
                <img src="figures/right.png" width="432" height="270" />
              </div>
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
    assert figure_asset.metadata["article_layout"] == "multi-panel"
    assert figure_asset.metadata["total_panel_width_pt"] == 360.0
    assert figure_asset.metadata["asset_files"][0]["panel_width_pt"] == 144.0
    assert figure_asset.metadata["asset_files"][0]["subfigure_group_width_pt"] == 360.0
    assert figure_asset.metadata["asset_files"][1]["panel_width_pt"] == 216.0
    assert figure_asset.metadata["asset_files"][1]["web_path"] == str(
        tmp_path / "bundle" / "assets" / "fig-0001-2.png"
    )
    table_asset = next(asset for asset in assets if asset.kind == "table")
    assert table_asset.web_path is None
    assert "<table>" in table_asset.metadata["html_fragment"]


def test_normalize_latexml_html_prefers_table_root_over_nested_figure_tags(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <figure class="ltx_table" id="S7.T4">
              <div class="ltx_flex_figure ltx_flex_table">
                <div class="ltx_flex_cell">
                  <figure class="ltx_figure ltx_figure_panel" id="S7.T4.fig1">
                    <table><tr><td>Model</td><td>Score</td></tr></table>
                    <figcaption>
                      <span class="ltx_tag ltx_tag_figure">Table 3: </span>
                      Percent accuracy by group.
                    </figcaption>
                  </figure>
                </div>
              </div>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["table"]
    assert blocks[0].block_uid == "tbl-0001"
    assert blocks[0].source_markdown == "**Table 1.** Percent accuracy by group."
    assert assets[0].kind == "table"
    assert assets[0].web_path is None
    assert "<table>" in assets[0].metadata["html_fragment"]


def test_normalize_latexml_html_strips_booktabs_rule_rows_from_table_fragments(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <figure class="ltx_table" id="tab:rules">
              <figcaption><span class="ltx_tag ltx_tag_table">Table 1: </span>Results.</figcaption>
              <table>
                <tr><td><span class="ltx_ERROR undefined">\toprule</span></td></tr>
                <tr><td>Method</td><td>Score</td></tr>
                <tr><td><span class="ltx_ERROR undefined">\bottomrule</span></td></tr>
              </table>
            </figure>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    _blocks, assets = normalize_latexml_html(html_path, "revision-1")

    html_fragment = assets[0].metadata["html_fragment"]
    assert r"\toprule" not in html_fragment
    assert r"\bottomrule" not in html_fragment
    assert "Method" in html_fragment
    assert "Score" in html_fragment


def test_normalize_latexml_html_preserves_algorithms_as_environment_blocks(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <figure class="ltx_float_algorithm" id="alg:decode">
              <figcaption>
                <span class="ltx_tag ltx_tag_algorithm">Algorithm 1: </span>
                Syndrome decoding.
              </figcaption>
              <div class="ltx_listingline">Input: syndrome s</div>
              <div class="ltx_listingline">Output: correction c</div>
            </figure>
            <p>After the algorithm, the proof continues.</p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["algorithm", "paragraph"]
    assert blocks[0].block_uid == "alg-0001"
    assert blocks[0].source_markdown == "**Algorithm 1.** Syndrome decoding."
    assert assets[0].kind == "algorithm"
    assert assets[0].caption == "Syndrome decoding."


def test_normalize_latexml_html_does_not_promote_page_wrapper_to_algorithm(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        """
        <html>
          <body>
            <div class="ltx_page_main">
              <article class="ltx_document">
                <h1>Batch Normalization</h1>
                <p>The paper starts with ordinary text.</p>
                <figure class="ltx_float_algorithm" id="alg:bn">
                  <figcaption>
                    <span class="ltx_tag ltx_tag_algorithm">Algorithm 1: </span>
                    Batch normalizing transform.
                  </figcaption>
                  <div class="ltx_listingline">Input: activations x</div>
                </figure>
                <p>The paper continues after the algorithm.</p>
              </article>
            </div>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == [
        "section",
        "paragraph",
        "algorithm",
        "paragraph",
    ]
    assert blocks[2].source_markdown == "**Algorithm 1.** Batch normalizing transform."
    assert assets[0].kind == "algorithm"


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


def test_normalize_latexml_html_records_figure_layout_metadata(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    figure_dir = tmp_path / "figures"
    figure_dir.mkdir()
    (figure_dir / "wide.png").write_bytes(b"wide")
    html_path.write_text(
        """
        <html>
          <body>
            <figure class="ltx_figure" id="fig:wide">
              <div style="width:432.5pt;">
                <img src="figures/wide.png" width="1200" height="460" />
              </div>
              <figcaption>
                <span class="ltx_tag ltx_tag_figure">Figure 2: </span>
                A double-column architecture figure.
              </figcaption>
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

    assert [block.block_type for block in blocks] == ["figure"]
    figure_asset = assets[0]
    assert figure_asset.metadata["article_layout"] == "double-column"
    assert figure_asset.metadata["display_width_pt"] == 432.5
    assert figure_asset.metadata["max_panel_width_pt"] == 432.5
    assert figure_asset.metadata["image_width"] == 1200.0
    assert figure_asset.metadata["image_height"] == 460.0
    assert figure_asset.metadata["asset_files"][0]["display_width_pt"] == 432.5
    assert figure_asset.metadata["asset_files"][0]["article_layout"] == "double-column"


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


def test_normalize_latexml_html_resolves_extensionless_latex_graphics(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    html_path = tmp_path / "document" / "latexml.html"
    source_root = tmp_path / "source" / "unpacked"
    pdf_path = source_root / "eps" / "arch.pdf"
    html_path.parent.mkdir()
    pdf_path.parent.mkdir(parents=True)
    pdf_path.write_bytes(b"%PDF-1.7\n")
    html_path.write_text(
        """
        <html>
          <body>
            <figure id="fig:arch">
              <img src="eps/arch" />
              <figcaption>A ResNet architecture figure.</figcaption>
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
        assert command[3] == f"{pdf_path}[0]"
        Path(command[-1]).write_bytes(b"png")

        class Completed:
            returncode = 0
            stderr = ""

        return Completed()

    monkeypatch.setattr(parser_module.shutil, "which", fake_which)
    monkeypatch.setattr(parser_module.subprocess, "run", fake_run)

    blocks, assets = normalize_latexml_html(
        html_path,
        "revision-1",
        bundle_path=tmp_path / "bundle",
        source_root=source_root,
    )

    assert blocks[0].metadata["asset_source"] == str(pdf_path)
    assert assets[0].source_path == str(pdf_path)
    assert assets[0].web_path == str(tmp_path / "bundle" / "assets" / "fig-0001.png")
    assert assets[0].metadata["original_reference"] == "eps/arch"
    assert assets[0].metadata["asset_resolution"] == "converted"


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
