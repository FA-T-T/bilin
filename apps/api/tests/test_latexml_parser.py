from __future__ import annotations

import asyncio
import io
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import cast

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
    build_parser_profile,
    diagnose_parse_revision,
    estimate_latexml_timeout_budget,
    find_main_tex,
    normalize_latexml_html,
    parse_article_revision,
    prepare_latexml_entry,
    prepare_latexml_included_source,
    prepare_latexml_side_sources,
    prepare_latexml_source,
    render_source_markdown,
    run_command,
    safe_unpack,
)
from bilin_api.repositories import create_job, create_library
from bilin_api.schemas import ArticleManifest, JobType, LibraryCreate, ParseErrorInfo


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


def test_build_parser_profile_records_local_latex_features(tmp_path: Path) -> None:
    source_dir = tmp_path / "profile"
    source_dir.mkdir()
    main_tex = source_dir / "main.tex"
    main_tex.write_text(
        "\\documentclass{article}\n"
        "\\usepackage{siunitx,tcolorbox,qcircuit}\n"
        "\\newtcolorbox{tbox}[1][]{title={#1}}\n"
        "\\begin{document}\n"
        "\\SI{10}{\\micro\\second}\n"
        "\\Qcircuit @C=1em {& \\gate{H} & \\qw}\n"
        "\\bibliography{missing}\n"
        "\\end{document}\n",
        encoding="utf-8",
    )
    (source_dir / "main.bbl").write_text(
        "\\begin{thebibliography}{1}\\bibitem{Bellman}Bellman.\\end{thebibliography}",
        encoding="utf-8",
    )
    (source_dir / "9407022").write_text(
        "\\documentstyle{article}\\begin{document}old\\end{document}",
        encoding="utf-8",
    )

    profile = build_parser_profile(source_dir, main_tex)

    assert profile.document_command == "\\documentclass"
    assert profile.document_class == "article"
    assert profile.has_siunitx is True
    assert profile.has_tcolorbox is True
    assert profile.has_qcircuit is True
    assert profile.has_bbl is True
    assert profile.has_multiple_main_candidates is True
    assert "package:siunitx:siunitx-commands" in profile.compatibility_rules
    assert "package:tcolorbox:tcolorbox-environment" in profile.compatibility_rules
    assert "bibliography:bbl_fallback" in profile.compatibility_rules


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
        "\\usepackage[noEnd,commentColor=black]{algpseudocodex}\n"
        "\\RequirePackage[main=english]{polyglossia}\n"
        "\\usepackage[acronym]{glossaries}\n"
        "\\usepackage{siunitx}\n"
        "\\usepackage{tcolorbox}\n"
        "\\usepackage[bookmarks=false]{hyperref}\n"
        "\\begin{document}x\\end{document}\n"
    )

    assert prepared.startswith("% Bilin LaTeXML parser entry.")
    assert "\\usepackage{graphicx,amsmath}" in prepared
    assert "% Bilin disabled for LaTeXML: babel" in prepared
    assert (
        "% Bilin disabled for LaTeXML: \\usepackage[noEnd,commentColor=black]{algpseudocodex}"
    ) in prepared
    assert "% Bilin disabled for LaTeXML: \\RequirePackage[main=english]{polyglossia}" in prepared
    assert "% Bilin disabled for LaTeXML: \\usepackage[acronym]{glossaries}" in prepared
    assert "% Bilin disabled for LaTeXML: \\usepackage{siunitx}" in prepared
    assert "% Bilin disabled for LaTeXML: \\usepackage{tcolorbox}" in prepared
    assert "\\usepackage[bookmarks=false]{hyperref}" in prepared
    assert "% Bilin LaTeXML compatibility shims." in prepared
    assert "\\newenvironment{algorithmic}[1][]" in prepared
    assert "\\providecommand{\\State}{}" in prepared
    assert "\\newenvironment{tcolorbox}[1][]" in prepared
    assert "\\providecommand{\\tcbox}[2][]{#2}" in prepared
    assert "\\providecommand{\\vmathbb}[1]{\\mathbb{#1}}" in prepared
    assert "\\providecommand{\\gls}[1]{#1}" in prepared
    assert "\\providecommand{\\newacronym}[3]{}" in prepared
    assert "\\providecommand{\\resizebox}[3]{#3}" in prepared
    assert "\\providecommand{\\SI}[3][]{#2\\,#3}" in prepared
    assert "\\providecommand{\\micro}{\\ensuremath{\\mu}}" in prepared


def test_prepare_latexml_source_injects_after_documentstyle() -> None:
    prepared = prepare_latexml_source(
        "\\documentstyle[aps]{revtex}\n\\begin{document}x\\end{document}\n"
    )

    assert "\\documentstyle[aps]{revtex}\n% Bilin LaTeXML compatibility shims." in prepared


def test_prepare_latexml_source_ignores_commented_documentclass_for_preamble_injection() -> None:
    prepared = prepare_latexml_source(
        "%  \\documentclass[showpacs,twocolumn,prx]{revtex4-1}\n"
        "% another historical class line\n"
        "\\documentclass[rmp,aps,reprint]{revtex4-1}\n"
        "\\begin{document}x\\end{document}\n"
    )

    assert (
        "\\documentclass[rmp,aps,reprint]{revtex4-1}\n% Bilin LaTeXML compatibility shims."
    ) in prepared
    assert (
        "%  \\documentclass[showpacs,twocolumn,prx]{revtex4-1}\n"
        "% Bilin LaTeXML compatibility shims."
    ) not in prepared


def test_prepare_latexml_source_replaces_complex_tcolorbox_definitions() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{article}\n"
        "\\usepackage[most]{tcolorbox}\n"
        "\\newtcolorbox[auto counter]{tbox}[2][]{%\n"
        "  title={#2}, #1\n"
        "}\n"
        "\\newtcolorbox{codebox}{enhanced,width=.95\\columnwidth}\n"
        "\\begin{document}\n"
        "\\begin{tbox}[label=tcolorbox:Gradient]{Algorithm.1}Body\\end{tbox}\n"
        "\\begin{codebox}Code\\end{codebox}\n"
        "\\end{document}\n"
    )

    assert "\\newtcolorbox[auto counter]" not in prepared
    assert "\\newenvironment{tbox}[2][]" in prepared
    assert "\\newenvironment{codebox}" in prepared
    assert "\\\\newenvironment{tbox}" not in prepared
    assert "\\\\@ifundefined{tbox}" not in prepared
    assert "title={#2}" not in prepared


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


def test_prepare_latexml_source_replaces_koma_class_without_cas_shims() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass[abstract=true, DIV=14, parskip=half]{scrartcl}\n"
        "\\author{Ada Lovelace}\n"
        "\\begin{document}\n"
        "\\begin{abstract}x\\end{abstract}\n"
        "\\maketitle\n"
        "\\end{document}\n"
    )

    assert "\\documentclass{article}" in prepared
    assert "\\documentclass[abstract=true, DIV=14, parskip=half]{scrartcl}" not in prepared
    assert "% Bilin replaced layout document class for LaTeXML: scrartcl" in prepared
    assert "\\providecommand{\\shorttitle}[1]{}" not in prepared
    assert "\\providecommand{\\address}" not in prepared
    assert "\\author{Ada Lovelace}" in prepared


def test_prepare_latexml_source_replaces_memoir_class_with_book_shims() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass[12pt]{memoir}\n"
        "\\renewcommand{\\maketitlehookb}{\\vspace{-3mm}}\n"
        "\\sloppybottom\n"
        "\\setlength{\\droptitle}{-2cm}\n"
        "\\pretitle{\\begin{center}\\huge\\bfseries}\n"
        "\\posttitle{\\end{center}}\n"
        "\\maxtocdepth{chapter}\n"
        "\\newcommand{\\unit}[2][]{\\part{#2}\\parttoc\\clearpage}\n"
        "\\renewcommand{\\printpartname}{Unit}\n"
        "\\begin{document}\n"
        "\\frontmatter\n"
        "\\unit[Basics]{Basics of Quantum Information}\n"
        "\\chapter{Preface}\n"
        "\\mainmatter\n"
        "\\chapter{Lesson}\n"
        "\\end{document}\n"
    )

    assert "\\documentclass{book}" in prepared
    assert "\\documentclass[12pt]{memoir}" not in prepared
    assert "% Bilin replaced layout document class for LaTeXML: memoir [12pt]" in prepared
    assert "\\providecommand{\\maketitlehookb}{}" in prepared
    assert "\\providecommand{\\sloppybottom}{}" in prepared
    assert "\\providecommand{\\@pnumwidth}{1.55em}" in prepared
    assert "\\providecommand{\\pretitle}[1]{}" in prepared
    assert "\\providecommand{\\posttitle}[1]{}" in prepared
    assert "\\providecommand{\\maxtocdepth}[1]{}" in prepared
    assert "\\newcommand{\\BilinMemoirUnit}[2][]{\\chapter{#2}}" in prepared
    assert "\\AtBeginDocument{\\let\\unit\\BilinMemoirUnit}" in prepared
    assert "\\@ifundefined{droptitle}{\\newlength{\\droptitle}}{}" in prepared
    assert "\\providecommand{\\address}" not in prepared
    assert "\\chapter{Lesson}" in prepared


def test_prepare_latexml_source_replaces_code_generated_diagram_environments() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{article}\n"
        "\\usepackage{tikz,circuitikz,pgfplots,blochsphere,tikz-3dplot}\n"
        "\\pgfplotsset{compat=1.18}\n"
        "\\begin{document}\n"
        "\\begin{figure}\n"
        "\\begin{tikzpicture}\\draw (0,0) -- (1,1);\\end{tikzpicture}\n"
        "\\caption{A TikZ figure.}\n"
        "\\end{figure}\n"
        "\\begin{circuitikz}\\draw (0,0) to[R] (1,0);\\end{circuitikz}\n"
        "\\begin{blochsphere}\\drawBallGrid{}\\end{blochsphere}\n"
        "\\begin{axis}\\addplot coordinates {(0,0) (1,1)};\\end{axis}\n"
        "\\end{document}\n"
    )

    assert (
        "% Bilin disabled for LaTeXML: "
        "\\usepackage{tikz,circuitikz,pgfplots,blochsphere,tikz-3dplot}"
        in prepared
    )
    assert "\\providecommand{\\pgfplotsset}[1]{}" in prepared
    assert "\\begin{tikzpicture}" not in prepared
    assert "\\begin{circuitikz}" not in prepared
    assert "\\begin{blochsphere}" not in prepared
    assert "\\begin{axis}" not in prepared
    assert "\\draw" not in prepared
    assert "\\addplot" not in prepared
    assert "\\mbox{tikzpicture diagram}" in prepared
    assert "\\caption{A TikZ figure.}" in prepared


def test_prepare_latexml_source_disables_title_toc_layout_package() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{book}\n"
        "\\usepackage{titletoc}\n"
        "\\begin{document}\n"
        "\\startcontents[part]\n"
        "\\printcontents[part]{}{0}{\\setcounter{tocdepth}{1}}\n"
        "\\chapter{One}\n"
        "\\end{document}\n"
    )

    assert "% Bilin disabled for LaTeXML: \\usepackage{titletoc}" in prepared
    assert "\\providecommand{\\startcontents}[1][]" in prepared
    assert "\\providecommand{\\stopcontents}[1][]" in prepared
    assert "\\providecommand{\\printcontents}[4][]" in prepared
    assert "\\chapter{One}" in prepared


def test_prepare_latexml_source_renames_trivlist_without_dropping_items() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{book}\n"
        "\\begin{document}\n"
        "\\chapter{Overview}\n"
        "\\begin{trivlist}\n"
        "\\item First lesson.\n"
        "\\item Second lesson.\n"
        "\\end{trivlist}\n"
        "\\end{document}\n"
    )

    assert "\\begin{trivlist}" not in prepared
    assert "\\end{trivlist}" not in prepared
    assert "\\begin{itemize}" in prepared
    assert "\\end{itemize}" in prepared
    assert "\\item First lesson." in prepared
    assert "\\item Second lesson." in prepared


def test_prepare_latexml_source_replaces_listings_environments() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{book}\n"
        "\\usepackage{listings}\n"
        "\\lstset{language=Python}\n"
        "\\begin{document}\n"
        "\\begin{code}\n"
        "\\begin{lstlisting}[language=Python]\n"
        "state_vector = {0: 1}\n"
        "\\end{lstlisting}\n"
        "\\end{code}\n"
        "\\lstinputlisting[language=Python]{example.py}\n"
        "\\chapter{Next}\n"
        "\\end{document}\n"
    )

    assert "% Bilin disabled for LaTeXML: \\usepackage{listings}" in prepared
    assert "\\providecommand{\\lstset}[1]{}" in prepared
    assert "\\begin{code}" not in prepared
    assert "\\begin{lstlisting}" not in prepared
    assert "state_vector" not in prepared
    assert "\\lstinputlisting[language=Python]{example.py}" not in prepared
    assert prepared.count("\\mbox{Code listing}") >= 2
    assert "\\chapter{Next}" in prepared


def test_build_parser_profile_records_memoir_replacement_rule(tmp_path: Path) -> None:
    main_tex = tmp_path / "UQIC.tex"
    main_tex.write_text(
        "\\documentclass[12pt]{memoir}\n"
        "\\begin{document}\n"
        "\\chapter{One}\n"
        "\\end{document}\n",
        encoding="utf-8",
    )

    profile = build_parser_profile(tmp_path, main_tex)

    assert profile.document_class == "memoir"
    assert "documentclass:memoir" in profile.compatibility_rules


def test_prepare_latexml_entry_uses_available_bbl_instead_of_bibtex_placeholder(
    tmp_path: Path,
) -> None:
    main_tex = tmp_path / "main.tex"
    main_tex.write_text(
        "\\documentclass{article}\n"
        "\\begin{document}\n"
        "Body \\cite{Bellman}.\n"
        "\\bibliographystyle{alpha}\n"
        "\\bibliography{main}\n"
        "\\end{document}\n",
        encoding="utf-8",
    )
    (tmp_path / "main.bbl").write_text(
        "\\begin{thebibliography}{Bel58}\n"
        "\\bibitem[Bel58]{Bellman}Richard Bellman.\n"
        "\\end{thebibliography}\n",
        encoding="utf-8",
    )

    entry = prepare_latexml_entry(main_tex)
    prepared = entry.read_text(encoding="utf-8")

    assert "\\bibliography{main}" not in prepared
    assert "\\input{main.bbl}" in prepared


def test_prepare_latexml_entry_uses_main_stem_bbl_when_bibliography_name_differs(
    tmp_path: Path,
) -> None:
    main_tex = tmp_path / "ghost_pauli_v15_arxiv.tex"
    main_tex.write_text(
        "\\documentclass{article}\n"
        "\\begin{document}\n"
        "Body \\cite{Peruzzo_OBrien:2014}.\n"
        "\\bibliography{ghost_pauli}\n"
        "\\end{document}\n",
        encoding="utf-8",
    )
    (tmp_path / "ghost_pauli_v15_arxiv.bbl").write_text(
        "\\begin{thebibliography}{1}\n"
        "\\bibitem{Peruzzo_OBrien:2014}Peruzzo et al. A variational eigenvalue solver.\n"
        "\\end{thebibliography}\n",
        encoding="utf-8",
    )

    entry = prepare_latexml_entry(main_tex)
    prepared = entry.read_text(encoding="utf-8")

    assert "\\bibliography{ghost_pauli}" not in prepared
    assert "\\input{ghost_pauli_v15_arxiv.bbl}" in prepared


def test_prepare_latexml_source_adds_common_latexml_layout_and_citation_shims() -> None:
    prepared = prepare_latexml_source(
        "\\documentclass{quantumarticle}\n"
        "\\begin{document}\n"
        "\\citeauthor*{vandennest2004_graph_states}\n"
        "\\section{Proof of \\texorpdfstring{$R$}{R}}\n"
        "\\onecolumngrid\n"
        "\\begin{tabular}{cc}\\toprule A & B \\\\ \\bottomrule\\end{tabular}\n"
        "\\end{document}\n"
    )

    assert "\\providecommand{\\citeauthor}" in prepared
    assert "\\providecommand{\\texorpdfstring}[2]{#1}" in prepared
    assert "\\providecommand{\\onecolumngrid}{}" in prepared
    assert "\\providecommand{\\toprule}{}" in prepared


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


def test_latexml_timeout_budget_gives_books_longer_budget(tmp_path: Path) -> None:
    main_tex = tmp_path / "main.tex"
    main_tex.write_text(
        "\\documentclass{book}\n\\begin{document}\n"
        + "\n".join(f"\\chapter{{Lesson {index}}} Body." for index in range(16))
        + "\n\\end{document}\n",
        encoding="utf-8",
    )
    profile = parser_module.ParserProfile(document_class="book")

    latexml_budget = estimate_latexml_timeout_budget(
        tmp_path,
        main_tex,
        "latexml",
        profile=profile,
    )
    latexmlpost_budget = estimate_latexml_timeout_budget(
        tmp_path,
        main_tex,
        "latexmlpost",
        profile=profile,
    )

    assert latexml_budget.split_level == "chapter"
    assert latexml_budget.structure_unit_count == 16
    assert latexml_budget.soft_seconds >= parser_module.LATEXML_BOOK_SOFT_TIMEOUT_FLOOR_SECONDS
    assert latexml_budget.hard_seconds >= parser_module.LATEXML_BOOK_HARD_TIMEOUT_FLOOR_SECONDS
    assert latexmlpost_budget.soft_seconds >= parser_module.LATEXML_BOOK_SOFT_TIMEOUT_FLOOR_SECONDS
    assert latexmlpost_budget.hard_seconds >= parser_module.LATEXML_BOOK_HARD_TIMEOUT_FLOOR_SECONDS


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
async def test_run_command_strips_proxy_environment_for_local_parser_tools(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("HTTPS_PROXY", "“http://127.0.0.1:7897”")
    log_path = tmp_path / "proxy.log"
    await run_command(
        [
            sys.executable,
            "-c",
            "import os; print(os.getenv('HTTPS_PROXY'))",
        ],
        cwd=tmp_path,
        log_path=log_path,
        timeout_budget=CommandTimeoutBudget(soft_seconds=1, idle_seconds=1, hard_seconds=2),
    )

    assert "--- STDOUT ---\nNone\n" in log_path.read_text(encoding="utf-8")


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


class DummyProcess:
    def __init__(self) -> None:
        self.pid = 4321
        self.terminated = False
        self.killed = False
        self.wait_count = 0

    def terminate(self) -> None:
        self.terminated = True

    def kill(self) -> None:
        self.killed = True

    async def wait(self) -> int:
        self.wait_count += 1
        return 0


@pytest.mark.asyncio
async def test_terminate_process_tree_uses_taskkill_on_windows(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    taskkill_pids: list[int] = []

    monkeypatch.setattr(parser_module, "_has_posix_process_group_kill", lambda: False)
    monkeypatch.setattr(parser_module, "_is_windows_platform", lambda: True)
    monkeypatch.setattr(
        parser_module,
        "_run_windows_taskkill",
        lambda pid: taskkill_pids.append(pid) or True,
    )
    process = DummyProcess()

    await parser_module._terminate_process_tree(cast(asyncio.subprocess.Process, process))

    assert taskkill_pids == [4321]
    assert process.terminated is False
    assert process.killed is False
    assert process.wait_count == 1


@pytest.mark.asyncio
async def test_terminate_process_tree_falls_back_to_direct_child_when_taskkill_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(parser_module, "_has_posix_process_group_kill", lambda: False)
    monkeypatch.setattr(parser_module, "_is_windows_platform", lambda: True)
    monkeypatch.setattr(parser_module, "_run_windows_taskkill", lambda _pid: False)
    process = DummyProcess()

    await parser_module._terminate_process_tree(cast(asyncio.subprocess.Process, process))

    assert process.terminated is True
    assert process.killed is False
    assert process.wait_count == 1


def test_run_windows_taskkill_invokes_tree_force_kill(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    recorded: dict[str, object] = {}

    def fake_run(
        command: list[str],
        check: bool,
        capture_output: bool,
        text: bool,
        timeout: int,
    ) -> subprocess.CompletedProcess[str]:
        recorded.update(
            {
                "command": command,
                "check": check,
                "capture_output": capture_output,
                "text": text,
                "timeout": timeout,
            }
        )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(parser_module.subprocess, "run", fake_run)

    assert parser_module._run_windows_taskkill(1234) is True
    assert recorded == {
        "command": ["taskkill", "/T", "/F", "/PID", "1234"],
        "check": False,
        "capture_output": True,
        "text": True,
        "timeout": 10,
    }


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
              Most models cite <cite class="ltx_cite">[<a href="#bib:vaswani2017">5</a>,
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
        "Most models cite [5](#bib:vaswani2017), [2](#bib.bib2). Here, the encoder maps "
        "an input sequence of symbol representations "
        "$(x_1,\\ldots,x_n)$ to a sequence of continuous representations "
        "$\\mathbf{z}=(z_1,\\ldots,z_n)$."
    )
    assert "[[5]" not in blocks[0].source_markdown
    assert "$(x_1,\\ldots,x_n)$" in render_source_markdown(blocks)


def test_normalize_latexml_html_preserves_bibliography_items(tmp_path: Path) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <h2>References</h2>
            <ul class="ltx_biblist">
              <li id="bib.bib1" class="ltx_bibitem">
                <span class="ltx_tag ltx_role_refnum ltx_tag_bibitem">[1]</span>
                <span class="ltx_bibblock">
                  Jimmy Lei Ba, Jamie Ryan Kiros, and Geoffrey E Hinton.
                </span>
                <span class="ltx_bibblock">Layer normalization.</span>
                <span class="ltx_bibblock">
                  <span class="ltx_text ltx_font_italic">
                    arXiv preprint arXiv:1607.06450
                  </span>, 2016.
                </span>
              </li>
              <li id="bib.bib2" class="ltx_bibitem">
                <span class="ltx_tag ltx_role_refnum ltx_tag_bibitem">[2]</span>
                <span class="ltx_bibblock">
                  Dzmitry Bahdanau, Kyunghyun Cho, and Yoshua Bengio.
                </span>
                <span class="ltx_bibblock">
                  Neural machine translation by jointly learning to align and translate.
                </span>
              </li>
            </ul>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == ["section", "list"]
    assert blocks[1].metadata["list_kind"] == "bibliography"
    assert blocks[1].metadata["item_count"] == 2
    assert blocks[1].metadata["bibliography_ids"] == ["bib.bib1", "bib.bib2"]
    assert r"[\[1\]](#bib.bib1)" in blocks[1].source_markdown
    assert "Layer normalization" in blocks[1].source_markdown
    assert r"[\[2\]](#bib.bib2)" in blocks[1].source_markdown
    assert "Neural machine translation by jointly learning" in blocks[1].source_markdown
    rendered = render_source_markdown(blocks)
    assert "## References" in rendered
    assert r"- [\[1\]](#bib.bib1)" in rendered


def test_normalize_latexml_html_preserves_missing_citation_brackets(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p>
              VQE is a hybrid quantum-classical algorithm
              <cite class="ltx_cite ltx_citemacro_cite">[
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  peruzzo2014variational
                </span>
              ]</cite>, which is commonly used for ground states
              <cite class="ltx_cite ltx_citemacro_cite">[
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  peruzzo2014variational
                </span>,
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  mcclean2016theory
                </span>,
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  omalley2016scalable
                </span>
              ]</cite>. See
              <cite class="ltx_cite ltx_citemacro_cite">[
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  gokhale2019_commute
                </span>, Sec. 10.1
              ]</cite>.
            </p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert blocks[0].source_markdown == (
        "VQE is a hybrid quantum-classical algorithm [peruzzo2014variational], "
        "which is commonly used for ground states "
        "[peruzzo2014variational, mcclean2016theory, omalley2016scalable]. "
        "See [gokhale2019_commute, Sec. 10.1]."
    )
    assert "algorithm peruzzo2014variational" not in blocks[0].source_markdown


def test_normalize_latexml_html_humanizes_author_year_missing_citations(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p>
              The variational quantum eigensolver
              <cite class="ltx_cite ltx_citemacro_cite">[
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  Peruzzo_OBrien:2014
                </span>,
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  McClean_Aspuru-Guzik: 2016
                </span>,
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  Rybinkin_Izmaylov:2020
                </span>,
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  Cerezo_Coles:2021
                </span>,
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  Anand_Aspuru-Guzik:2022
                </span>
              ]</cite>
              is a hybrid algorithm.
            </p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert blocks[0].source_markdown == (
        "The variational quantum eigensolver "
        "[Peruzzo and OBrien 2014, McClean and Aspuru-Guzik 2016, "
        "Rybinkin and Izmaylov 2020, Cerezo and Coles 2021, "
        "Anand and Aspuru-Guzik 2022] is a hybrid algorithm."
    )


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


def test_combine_latexml_split_html_preserves_page_order_and_asset_paths(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    document_dir = tmp_path / "document"
    split_dir = document_dir / "latexml-split"
    asset_dir = split_dir / "generated"
    split_dir.mkdir(parents=True)
    asset_dir.mkdir()
    (asset_dir / "plot.png").write_bytes(b"png")
    (split_dir / "index.html").write_text(
        """
        <html>
          <body>
            <div class="ltx_page_content">
              <article class="ltx_document">
                <h1 class="ltx_title ltx_title_document">A Long Book</h1>
                <nav class="ltx_TOC">
                  <a href="Ch1.html">Chapter 1</a>
                  <a href="Ch2.html">Chapter 2</a>
                </nav>
              </article>
            </div>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    (split_dir / "Ch1.html").write_text(
        """
        <html>
          <body>
            <div class="ltx_page_content">
              <section class="ltx_chapter">
                <h1>Chapter 1 Foundations</h1>
                <p>First chapter.</p>
                <figure><img src="generated/plot.png" /><figcaption>A plot.</figcaption></figure>
              </section>
            </div>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    (split_dir / "Ch2.html").write_text(
        """
        <html>
          <body>
            <div class="ltx_page_content">
              <section class="ltx_chapter">
                <h1>Chapter 2 Methods</h1>
                <p>Second chapter.</p>
              </section>
            </div>
          </body>
        </html>
        """,
        encoding="utf-8",
    )
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    pages = parser_module.combine_latexml_split_html(
        split_dir / "index.html",
        document_dir / "latexml.html",
    )
    blocks, assets = normalize_latexml_html(
        document_dir / "latexml.html",
        "revision-1",
        bundle_path=tmp_path / "bundle",
    )

    assert [path.name for path in pages] == ["Ch1.html", "Ch2.html"]
    assert [block.source_markdown for block in blocks[:3]] == [
        "A Long Book",
        "Chapter 1 Foundations",
        "First chapter.",
    ]
    assert "A plot." in blocks[3].source_markdown
    assert "Chapter 2 Methods" in [block.source_markdown for block in blocks]
    assert assets[0].source_path == str(asset_dir / "plot.png")
    combined = (document_dir / "latexml.html").read_text(encoding="utf-8")
    assert 'src="latexml-split/generated/plot.png"' in combined


def test_latexml_xml_to_html_recovers_blocks_without_latexmlpost(tmp_path: Path) -> None:
    xml_path = tmp_path / "latexml.xml"
    html_path = tmp_path / "latexml.html"
    xml_path.write_text(
        """
        <document xmlns="http://dlmf.nist.gov/LaTeXML">
          <title>Recovered Paper</title>
          <creator role="author"><personname>A. Author</personname></creator>
          <chapter xml:id="Chx1">
            <title>Contents</title>
            <para><ERROR class="undefined">\\@starttoc</ERROR><p><text>toc</text></p></para>
          </chapter>
          <chapter xml:id="Chx2">
            <title>Introduction</title>
            <para>
              <p>We optimize <Math mode="inline" tex="f(x)" text="f of x" />.</p>
              <equation><Math mode="display" tex="x^2" text="x squared" /></equation>
            </para>
            <figure xml:id="Chx2.F1">
              <picture>
                <Math mode="inline" tex="x_t" />
              </picture>
              <toccaption><tag close=" ">1</tag>Short figure.</toccaption>
              <caption>
                <tag close=": ">Figure 1</tag>Curve for
                <Math mode="inline" tex="\\alpha_t" />.
              </caption>
            </figure>
            <table xml:id="Chx2.T1">
              <tabular>
                <tr><td><Math mode="inline" tex="n" /></td></tr>
              </tabular>
              <toccaption><tag close=" ">1</tag>Short table.</toccaption>
              <caption>
                <tag close=": ">Table 1</tag>Runtime
                <Math mode="inline" tex="O(n^2)" />.
              </caption>
            </table>
          </chapter>
        </document>
        """,
        encoding="utf-8",
    )

    parser_module.latexml_xml_to_html(xml_path, html_path)
    html = html_path.read_text(encoding="utf-8")
    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [block.block_type for block in blocks] == [
        "section",
        "paragraph",
        "section",
        "paragraph",
        "equation",
        "figure",
        "table",
    ]
    assert [block.source_markdown for block in blocks] == [
        "Recovered Paper",
        "A. Author",
        "Introduction",
        "We optimize $f(x)$.",
        "x^2",
        "**Figure 1.** Curve for $\\alpha_t$.",
        "**Table 1.** Runtime $O(n^2)$.",
    ]
    assert "$f(x)$" in render_source_markdown(blocks)
    assert "<figcaption>" in html
    assert "Short figure" not in blocks[-2].source_markdown
    assert "x_t" not in blocks[-2].source_markdown


def test_latexml_xml_to_html_recovers_deeper_structure_and_deduplicates_math(
    tmp_path: Path,
) -> None:
    xml_path = tmp_path / "latexml.xml"
    html_path = tmp_path / "latexml.html"
    xml_path.write_text(
        r"""
        <document xmlns="http://dlmf.nist.gov/LaTeXML">
          <part><title>Part I</title></part>
          <section>
            <title>Optimization</title>
            <paragraph>
              <title>Oracle model</title>
              <para><p>Use <Math tex="\alpha" />.</p></para>
            </paragraph>
            <equation>
              <Math mode="display" tex="\mathrm{min.}\;f(x)" />
              <Math mode="display" tex="\mathrm{min.}\;f(x)" />
              <Math mode="display" tex="\text{s.t.}\;x\in\mathcal{X}" />
              <Math mode="display" tex="\text{s.t.}\;x\in\mathcal{X}" />
            </equation>
          </section>
        </document>
        """,
        encoding="utf-8",
    )

    parser_module.latexml_xml_to_html(xml_path, html_path)
    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert [(block.block_type, block.source_markdown) for block in blocks[:4]] == [
        ("section", "Part I"),
        ("section", "Optimization"),
        ("section", "Oracle model"),
        ("paragraph", "Use $\\alpha$."),
    ]
    equation = next(block for block in blocks if block.block_type == "equation")
    assert equation.source_markdown == (
        r"\mathrm{min.}\;f(x) \text{s.t.}\;x\in\mathcal{X}"
    )


def test_latexmlpost_splits_large_section_sources_by_default(tmp_path: Path) -> None:
    main_tex = tmp_path / "main.tex"
    main_tex.write_text(
        "\\documentclass{article}\n\\begin{document}\n"
        + "\n".join(f"\\section{{S{index}}} Body." for index in range(30))
        + "\n\\end{document}\n",
        encoding="utf-8",
    )
    profile = parser_module.ParserProfile(document_class="article")
    timeout_budget = CommandTimeoutBudget(
        soft_seconds=120,
        idle_seconds=180,
        hard_seconds=300,
        source_bytes=50_000,
        tex_file_count=1,
        graphic_file_count=0,
    )

    assert parser_module.preferred_latexml_split_level(profile, main_tex) == "section"
    assert parser_module.should_split_latexmlpost_by_default(
        profile,
        main_tex,
        timeout_budget,
    )


def test_latexmlpost_detects_chapters_from_included_sources(tmp_path: Path) -> None:
    main_tex = tmp_path / "main.tex"
    chapters = tmp_path / "chapters"
    chapters.mkdir()
    main_tex.write_text(
        "\\documentclass{custom}\n\\begin{document}\n\\input{chapters/one}\n\\end{document}\n",
        encoding="utf-8",
    )
    (chapters / "one.tex").write_text("\\chapter{Included} Body.", encoding="utf-8")
    profile = parser_module.ParserProfile(document_class="custom")

    assert parser_module.source_has_chapters(main_tex)
    assert parser_module.preferred_latexml_split_level(profile, main_tex) == "chapter"


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


def test_normalize_latexml_html_cleans_undefined_citeauthor_missing_citation_echo(
    tmp_path: Path,
) -> None:
    html_path = tmp_path / "latexml.html"
    html_path.write_text(
        r"""
        <html>
          <body>
            <p>
              VQE follows <span class="ltx_ERROR undefined">\citeauthor</span>
              mcclean2016theory
              <cite class="ltx_cite ltx_citemacro_cite">[
                <span class="ltx_ref ltx_missing_citation ltx_ref_self">
                  mcclean2016theory
                </span>
              ]</cite>.
            </p>
          </body>
        </html>
        """,
        encoding="utf-8",
    )

    blocks, _assets = normalize_latexml_html(html_path, "revision-1")

    assert "\\citeauthor" not in blocks[0].source_markdown
    assert blocks[0].source_markdown == "VQE follows [mcclean2016theory]."


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
async def test_parse_article_uses_chapter_split_for_book_sources(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Books", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00010", "v1")
    original_dir = bundle_path / "original"
    original_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {
            "main.tex": (
                rb"\documentclass{book}"
                rb"\begin{document}"
                rb"\chapter{One}Hello."
                rb"\end{document}"
            )
        },
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00010",
        version="v1",
        title="Long book",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(bundle_path, ArticleManifest(article_revision_id=revision.id, source="arxiv"))
    commands: list[list[str]] = []
    events: list[str] = []

    async def record_progress(stage: str, message: str, progress: float) -> None:
        _ = (message, progress)
        events.append(stage)

    async def fake_run_command(
        command: list[str],
        cwd: Path,
        log_path: Path,
        timeout_budget: object | None = None,
        activity_paths: list[Path] | None = None,
    ) -> None:
        _ = (cwd, timeout_budget, activity_paths)
        commands.append(command)
        destination = Path(command[command.index("--destination") + 1])
        destination.parent.mkdir(parents=True, exist_ok=True)
        if "--split" in command:
            destination.write_text(
                '<html><body><nav class="ltx_TOC">'
                '<a href="Ch1.html">Chapter 1</a>'
                "</nav></body></html>",
                encoding="utf-8",
            )
            (destination.parent / "Ch1.html").write_text(
                """
                <html><body><div class="ltx_page_content">
                  <section class="ltx_chapter"><h1>Chapter 1 One</h1><p>Hello.</p></section>
                </div></body></html>
                """,
                encoding="utf-8",
            )
        elif destination.suffix == ".xml":
            destination.write_text("<document />", encoding="utf-8")
        else:
            raise AssertionError("book sources should not use unsplit latexmlpost")
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
    manifest = read_manifest(bundle_path)

    assert result["block_count"] == 2
    assert any("--split" in command for command in commands)
    assert any("--splitat=chapter" in command for command in commands)
    assert "latexmlpost_split_execution" in events
    assert manifest is not None
    assert manifest.metadata["latexmlpost_mode"] == "split"
    assert manifest.metadata["latexml_split_level"] == "chapter"


@pytest.mark.asyncio
async def test_parse_article_falls_back_to_split_when_latexmlpost_times_out(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Papers", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00011", "v1")
    original_dir = bundle_path / "original"
    original_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {
            "main.tex": (
                rb"\documentclass{article}"
                rb"\begin{document}"
                rb"\section{One}Hello."
                rb"\end{document}"
            )
        },
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00011",
        version="v1",
        title="Large article",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(bundle_path, ArticleManifest(article_revision_id=revision.id, source="arxiv"))
    commands: list[list[str]] = []
    events: list[tuple[str, str]] = []

    async def record_progress(stage: str, message: str, progress: float) -> None:
        _ = progress
        events.append((stage, message))

    async def fake_run_command(
        command: list[str],
        cwd: Path,
        log_path: Path,
        timeout_budget: object | None = None,
        activity_paths: list[Path] | None = None,
    ) -> None:
        _ = (cwd, timeout_budget, activity_paths)
        commands.append(command)
        destination = Path(command[command.index("--destination") + 1])
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.suffix == ".xml":
            destination.write_text("<document />", encoding="utf-8")
        elif "--split" in command:
            destination.write_text(
                '<html><body><nav class="ltx_TOC">'
                '<a href="S1.html">Section 1</a>'
                "</nav></body></html>",
                encoding="utf-8",
            )
            (destination.parent / "S1.html").write_text(
                """
                <html><body><div class="ltx_page_content">
                  <section class="ltx_section"><h1>Section 1 One</h1><p>Hello.</p></section>
                </div></body></html>
                """,
                encoding="utf-8",
            )
        else:
            raise ParseFailure(
                "latexml_timeout",
                "Command timed out by idle limit",
                {"timeout_reason": "idle"},
            )
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
    manifest = read_manifest(bundle_path)

    assert result["block_count"] == 2
    assert [("--split" in command) for command in commands] == [False, False, True]
    assert any(message == "latexmlpost 超时，按章节渲染 HTML" for _stage, message in events)
    assert manifest is not None
    assert manifest.metadata["latexmlpost_mode"] == "split_after_timeout"
    assert manifest.metadata["latexmlpost_single_timeout"]["timeout_reason"] == "idle"
    assert manifest.metadata["latexml_split_level"] == "section"


@pytest.mark.asyncio
async def test_parse_article_retry_resumes_from_latexmlpost_timeout(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Retry parse", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00012", "v1")
    original_dir = bundle_path / "original"
    document_dir = bundle_path / "document"
    original_dir.mkdir(parents=True, exist_ok=True)
    document_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {
            "main.tex": (
                rb"\documentclass{article}"
                rb"\begin{document}"
                rb"\section{One}Hello."
                rb"\end{document}"
            )
        },
    )
    (document_dir / "latexml.xml").write_text("<document />", encoding="utf-8")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00012",
        version="v1",
        title="Retry parse",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(
        bundle_path,
        ArticleManifest(
            article_revision_id=revision.id,
            source="arxiv",
            parse_status="failed",
            errors=[
                ParseErrorInfo(
                    code="latexml_timeout",
                    message="Command timed out by idle limit.",
                    details={"stage": "latexmlpost_execution", "timeout_reason": "idle"},
                )
            ],
        ),
    )
    commands: list[list[str]] = []
    events: list[tuple[str, str]] = []

    async def record_progress(stage: str, message: str, progress: float) -> None:
        _ = progress
        events.append((stage, message))

    async def fake_run_command(
        command: list[str],
        cwd: Path,
        log_path: Path,
        timeout_budget: object | None = None,
        activity_paths: list[Path] | None = None,
    ) -> None:
        _ = (cwd, timeout_budget, activity_paths)
        commands.append(command)
        destination = Path(command[command.index("--destination") + 1])
        if destination.suffix == ".xml":
            raise AssertionError("Retry should reuse existing latexml.xml")
        assert "--split" in command
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            '<html><body><nav class="ltx_TOC">'
            '<a href="S1.html">Section 1</a>'
            "</nav></body></html>",
            encoding="utf-8",
        )
        (destination.parent / "S1.html").write_text(
            """
            <html><body><div class="ltx_page_content">
              <section class="ltx_section"><h1>Section 1 One</h1><p>Hello.</p></section>
            </div></body></html>
            """,
            encoding="utf-8",
        )
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
    manifest = read_manifest(bundle_path)

    assert result["block_count"] == 2
    assert len(commands) == 1
    assert "--split" in commands[0]
    assert ("latexmlpost_execution", "从失败阶段继续：渲染 HTML") in events
    assert ("latexmlpost_split_execution", "从失败阶段继续：按章节渲染 HTML") in events
    assert manifest is not None
    assert manifest.metadata["parse_resume_from"] == "latexmlpost_execution"
    assert manifest.metadata["latexmlpost_mode"] == "split_after_retry"


@pytest.mark.asyncio
async def test_parse_article_retry_falls_back_to_xml_when_split_times_out(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="XML recovery", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00013", "v1")
    original_dir = bundle_path / "original"
    document_dir = bundle_path / "document"
    original_dir.mkdir(parents=True, exist_ok=True)
    document_dir.mkdir(parents=True, exist_ok=True)
    write_tar(
        original_dir / "source.tar",
        {
            "main.tex": (
                rb"\documentclass{book}"
                rb"\begin{document}"
                rb"\chapter{One}Hello."
                rb"\end{document}"
            )
        },
    )
    (document_dir / "latexml.xml").write_text(
        """
        <document xmlns="http://dlmf.nist.gov/LaTeXML">
          <title>Recovered Book</title>
          <chapter><title>One</title><para><p>Hello from XML.</p></para></chapter>
        </document>
        """,
        encoding="utf-8",
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00013",
        version="v1",
        title="XML recovery",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(
        bundle_path,
        ArticleManifest(
            article_revision_id=revision.id,
            source="arxiv",
            parse_status="failed",
            errors=[
                ParseErrorInfo(
                    code="latexml_timeout",
                    message="Command timed out by idle limit.",
                    details={"stage": "latexmlpost_split_execution", "timeout_reason": "idle"},
                )
            ],
        ),
    )
    events: list[tuple[str, str]] = []

    async def record_progress(stage: str, message: str, progress: float) -> None:
        _ = progress
        events.append((stage, message))

    async def fake_run_command(
        command: list[str],
        cwd: Path,
        log_path: Path,
        timeout_budget: object | None = None,
        activity_paths: list[Path] | None = None,
    ) -> None:
        _ = (command, cwd, log_path, timeout_budget, activity_paths)
        raise ParseFailure(
            "latexml_timeout",
            "Command timed out by idle limit.",
            {"timeout_reason": "idle"},
        )

    monkeypatch.setattr(
        parser_module.shutil,
        "which",
        lambda name: f"/mock/{name}" if name in {"latexml", "latexmlpost"} else None,
    )
    monkeypatch.setattr(parser_module, "detect_version", lambda _path: "mock")
    monkeypatch.setattr(parser_module, "run_command", fake_run_command)

    result = await parse_article_revision(library, revision.id, progress=record_progress)
    manifest = read_manifest(bundle_path)

    assert result["block_count"] == 3
    assert ("latexml_xml_recovery", "latexmlpost 仍超时，使用 XML 快速恢复") in events
    assert manifest is not None
    assert manifest.metadata["latexmlpost_mode"] == "xml_fallback_after_split_timeout"
    assert manifest.metadata["parse_fidelity"] == "structure_only"
    assert manifest.metadata["parse_recovery"]["stage"] == "latexml_xml_recovery"
    assert manifest.metadata["parse_recovery"]["reason"] == "latexmlpost_timeout"
    assert manifest.metadata["parse_resume_from"] == "latexmlpost_execution"


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
    assert manifest.errors[0].details["stage"] == "dependency_check"
    assert manifest.errors[0].details["profile"]["main_tex_file"] == "main.tex"
    assert "Install LaTeXML" in manifest.errors[0].details["install_hint"]
    diagnostics_path = Path(manifest.errors[0].details["diagnostics_path"])
    assert diagnostics_path.exists()
    diagnostics = diagnostics_path.read_text(encoding="utf-8")
    assert "dependency_check" in diagnostics
    assert "main.tex" in diagnostics
    error_log = bundle_path / "logs" / "parse-error.json"
    assert error_log.exists()
    assert manifest.generated_artifacts["parse_error_log"] == str(error_log)
    assert manifest.generated_artifacts["parser_diagnostics"] == str(diagnostics_path)
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


def test_parse_diagnose_cli_reads_existing_profile_without_reparse(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library_id, revision_id = asyncio.run(prepare_missing_dependency_cli_fixture(tmp_path))
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    parse_result = CliRunner().invoke(app, ["parse", "article", library_id, revision_id])
    diagnose_result = CliRunner().invoke(app, ["parse", "diagnose", library_id, revision_id])

    assert parse_result.exit_code == 1
    assert diagnose_result.exit_code == 0
    assert '"article_revision_id"' in diagnose_result.output
    assert '"main_tex_file": "main.tex"' in diagnose_result.output
    assert '"stage": "dependency_check"' in diagnose_result.output


def test_parse_diagnose_cli_accepts_parse_job_id(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library_id, revision_id = asyncio.run(prepare_missing_dependency_cli_fixture(tmp_path))
    job = asyncio.run(
        create_job(
            JobType.parse_article,
            {"library_id": library_id, "article_revision_id": revision_id},
        )
    )
    monkeypatch.setattr(parser_module.shutil, "which", lambda _name: None)

    CliRunner().invoke(app, ["parse", "article", library_id, revision_id])
    diagnose_result = CliRunner().invoke(app, ["parse", "diagnose", library_id, job.id])

    assert diagnose_result.exit_code == 0
    assert '"article_revision_id"' in diagnose_result.output
    assert revision_id in diagnose_result.output


@pytest.mark.asyncio
async def test_diagnose_parse_revision_returns_stored_latexml_failure(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(LibraryCreate(name="Diagnose", path=str(tmp_path / "library")))
    bundle_path = bundle_path_for_arxiv(library, "2401.00004", "v1")
    (bundle_path / "source" / "unpacked").mkdir(parents=True)
    (bundle_path / "logs").mkdir(parents=True)
    (bundle_path / "source" / "unpacked" / "main.tex").write_text(
        "\\documentclass{article}\\begin{document}x\\end{document}",
        encoding="utf-8",
    )
    (bundle_path / "logs" / "latexml.log").write_text(
        "--- STDERR ---\nError:undefined:\\foo The token T_CS[\\foo] is not defined.\n",
        encoding="utf-8",
    )
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00004",
        version="v1",
        title="Diagnose",
        bundle_path=bundle_path,
        metadata={},
    )
    write_manifest(
        bundle_path,
        ArticleManifest(
            article_revision_id=revision.id,
            source="arxiv",
            main_tex_file="main.tex",
            parse_status="failed",
        ),
    )

    result = await diagnose_parse_revision(library, revision.id)

    assert result["profile"]["main_tex_file"] == "main.tex"
    assert result["logs"]["latexml"]["first_error"].startswith("Error:undefined")


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
