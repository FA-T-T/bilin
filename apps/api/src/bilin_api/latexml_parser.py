from __future__ import annotations

import asyncio
import gzip
import json
import os
import re
import shutil
import signal
import subprocess
import tarfile
import xml.etree.ElementTree as ET
import zipfile
from collections.abc import Awaitable, Callable
from dataclasses import asdict, dataclass
from html import escape, unescape
from html.parser import HTMLParser
from pathlib import Path
from time import monotonic
from typing import Any
from urllib.parse import unquote, urlparse

from html_to_markdown import ConversionOptions, convert

from bilin_api.article_store import (
    empty_manifest,
    get_article_revision,
    make_asset,
    make_block,
    mark_revision_status,
    read_manifest,
    replace_document,
    write_manifest,
)
from bilin_api.citation_keys import humanize_missing_citation_text
from bilin_api.doctor import detect_version
from bilin_api.schemas import AssetRecord, DocumentBlock, Library, ParseErrorInfo

ParseProgressCallback = Callable[[str, str, float], Awaitable[None]]

WEB_ASSET_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
CONVERTIBLE_ASSET_SUFFIXES = {".pdf", ".eps"}
LATEX_GRAPHIC_SUFFIXES = (".pdf", ".png", ".jpg", ".jpeg", ".eps", ".svg", ".webp", ".gif")
HTML_VOID_TAGS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}
MARKDOWN_CONVERSION_OPTIONS = ConversionOptions(
    heading_style="atx",
    list_indent_type="spaces",
    list_indent_width=2,
    bullets="-",
    escape_asterisks=False,
    escape_underscores=False,
    escape_misc=False,
    wrap=False,
    strip_newlines=False,
    extract_metadata=False,
    convert_as_inline=False,
)
LATEXML_ENTRY_FILE = "__bilin_latexml_entry.tex"
LATEXML_SPLIT_OUTPUT_DIR = "latexml-split"
LATEXML_XML_RECOVERY_MODE = "xml_fallback_after_split_timeout"
LATEXML_XML_RECOVERY_FIDELITY = "structure_only"
LATEXML_CHAPTER_SPLIT_DOCUMENT_CLASSES = {
    "book",
    "report",
    "memoir",
    "scrbook",
    "scrreprt",
}
LATEXML_LAYOUT_ONLY_DOCUMENT_CLASSES = {
    "cas-dc",
    "cas-sc",
}
LATEXML_CAS_DOCUMENT_CLASSES = {
    "cas-dc",
    "cas-sc",
}
LATEXML_KOMA_DOCUMENT_CLASS_REPLACEMENTS = {
    "scrartcl": "article",
    "scrbook": "book",
    "scrreprt": "report",
    "memoir": "book",
}
LATEXML_LAYOUT_AUTHOR_METADATA_KEYS = frozenset(
    {
        "affiliation",
        "affiliationid",
        "auid",
        "bioid",
        "collab",
        "corref",
        "credit",
        "degree",
        "ead",
        "email",
        "fnref",
        "orcid",
        "prefix",
        "role",
        "suffix",
        "type",
    }
)
TEX_MAIN_FILE_SUFFIXES = {".tex", ".ltx", ".latex"}
TEX_SIDE_FILE_SUFFIXES = {".bbl", ".bib", ".sty", ".cls"}
TEX_MAIN_FILE_NAME_HINTS = {
    "main",
    "paper",
    "article",
    "ms",
    "manuscript",
    "source",
    "submission",
    "arxiv",
}
TEX_CANDIDATE_READ_LIMIT_BYTES = 8_000_000
LATEXML_BASE_TIMEOUT_SECONDS = float(
    os.getenv(
        "BILIN_LATEXML_BASE_TIMEOUT_SECONDS", os.getenv("BILIN_LATEXML_TIMEOUT_SECONDS", "600")
    )
)
LATEXML_IDLE_TIMEOUT_SECONDS = float(os.getenv("BILIN_LATEXML_IDLE_TIMEOUT_SECONDS", "600"))
LATEXML_MAX_TIMEOUT_SECONDS = float(os.getenv("BILIN_LATEXML_MAX_TIMEOUT_SECONDS", "14400"))
LATEXML_BOOK_TIMEOUT_MULTIPLIER = float(os.getenv("BILIN_LATEXML_BOOK_TIMEOUT_MULTIPLIER", "2"))
LATEXML_BOOK_SOFT_TIMEOUT_FLOOR_SECONDS = float(
    os.getenv("BILIN_LATEXML_BOOK_SOFT_TIMEOUT_FLOOR_SECONDS", "1800")
)
LATEXML_BOOK_HARD_TIMEOUT_FLOOR_SECONDS = float(
    os.getenv("BILIN_LATEXML_BOOK_HARD_TIMEOUT_FLOOR_SECONDS", "7200")
)
LATEXML_LARGE_DOCUMENT_SOFT_TIMEOUT_FLOOR_SECONDS = float(
    os.getenv("BILIN_LATEXML_LARGE_DOCUMENT_SOFT_TIMEOUT_FLOOR_SECONDS", "900")
)
LATEXML_LARGE_DOCUMENT_HARD_TIMEOUT_FLOOR_SECONDS = float(
    os.getenv("BILIN_LATEXML_LARGE_DOCUMENT_HARD_TIMEOUT_FLOOR_SECONDS", "3600")
)
LATEXML_LARGE_SOURCE_SPLIT_BYTES = int(
    os.getenv("BILIN_LATEXML_LARGE_SOURCE_SPLIT_BYTES", "220000")
)
LATEXML_LARGE_SOURCE_SPLIT_TEX_FILES = int(
    os.getenv("BILIN_LATEXML_LARGE_SOURCE_SPLIT_TEX_FILES", "8")
)
LATEXML_LARGE_SOURCE_SPLIT_SECTIONS = int(
    os.getenv("BILIN_LATEXML_LARGE_SOURCE_SPLIT_SECTIONS", "24")
)
LATEX_COMPATIBILITY_TABLE = json.loads(
    (Path(__file__).resolve().parents[4] / "shared" / "latex-compatibility.json").read_text(
        encoding="utf-8"
    )
)
LATEXML_PACKAGE_POLICIES = {
    str(policy["package"]): policy
    for policy in LATEX_COMPATIBILITY_TABLE.get("latexml_package_policies", [])
}
LATEXML_DISABLED_PACKAGES = {
    package
    for package, policy in LATEXML_PACKAGE_POLICIES.items()
    if policy.get("disable_for_latexml")
}
LATEX_COMPATIBILITY_COMMAND_GROUP_RULES = LATEX_COMPATIBILITY_TABLE["command_group_rules"]
LATEX_COMPATIBILITY_SINGLE_TOKEN_COMMANDS = tuple(
    command
    for rule in LATEX_COMPATIBILITY_COMMAND_GROUP_RULES
    if rule.get("allow_single_token")
    for command in rule["commands"]
)
LEGACY_TEXT_FONT_COMMANDS = {
    entry["command"]: (entry["text_replacement"], entry["math_replacement"])
    for entry in LATEX_COMPATIBILITY_TABLE["legacy_text_font_commands"]
}
LATEXML_COMPATIBILITY_PREAMBLE = "\n".join(
    [
        r"\AtBeginDocument{%",
        *[
            rf"\providecommand{{\{entry['command']}}}"
            f"{'[' + str(int(entry['args'])) + ']' if int(entry['args']) else ''}"
            rf"{{{entry['replacement']}}}%"
            for entry in LATEX_COMPATIBILITY_TABLE["latexml_preamble_commands"]
        ],
        r"}%",
    ]
)
LATEXML_CITATION_FALLBACK_PREAMBLE = r"""
\makeatletter
\providecommand{\citeauthor}{\@ifstar{\BilinCiteAuthorStar}{\BilinCiteAuthor}}
\providecommand{\BilinCiteAuthorStar}[1]{}
\providecommand{\BilinCiteAuthor}[1]{}
\makeatother
"""
LATEXML_ALGORITHMIC_FALLBACK_PREAMBLE = r"""
\makeatletter
\@ifundefined{algorithmic}{\newenvironment{algorithmic}[1][]{\par}{\par}}{}
\@ifundefined{algorithm}{\newenvironment{algorithm}[1][]{\par}{\par}}{}
\providecommand{\State}{}
\providecommand{\Statex}{}
\providecommand{\Procedure}[2]{#1 #2}
\providecommand{\EndProcedure}{}
\providecommand{\Function}[2]{#1 #2}
\providecommand{\EndFunction}{}
\providecommand{\If}[1]{if #1}
\providecommand{\ElsIf}[1]{else if #1}
\providecommand{\Else}{else}
\providecommand{\EndIf}{}
\providecommand{\For}[1]{for #1}
\providecommand{\ForAll}[1]{for all #1}
\providecommand{\EndFor}{}
\providecommand{\While}[1]{while #1}
\providecommand{\EndWhile}{}
\providecommand{\Repeat}{repeat}
\providecommand{\Until}[1]{until #1}
\providecommand{\Return}[1]{return #1}
\providecommand{\Call}[2]{#1 #2}
\providecommand{\Comment}[1]{#1}
\providecommand{\Require}{}
\providecommand{\Ensure}{}
\makeatother
"""
LATEXML_TCOLORBOX_FALLBACK_PREAMBLE = r"""
\makeatletter
\@ifundefined{tcolorbox}{\newenvironment{tcolorbox}[1][]{\par}{\par}}{}
\providecommand{\newtcolorbox}[2][]{}
\providecommand{\renewtcolorbox}[2][]{}
\providecommand{\tcbset}[1]{}
\providecommand{\tcbox}[2][]{#2}
\makeatother
"""
LATEXML_SIUNITX_FALLBACK_PREAMBLE = r"""
\providecommand{\SI}[3][]{#2\,#3}
\providecommand{\si}[2][]{#2}
\providecommand{\num}[2][]{#2}
\providecommand{\qty}[3][]{#2\,#3}
\providecommand{\SIrange}[4][]{#2--#3\,#4}
\providecommand{\SIlist}[3][]{#2\,#3}
\providecommand{\numrange}[3][]{#2--#3}
\providecommand{\numlist}[2][]{#2}
\providecommand{\micro}{\ensuremath{\mu}}
\providecommand{\second}{s}
\providecommand{\meter}{m}
\providecommand{\metre}{m}
\providecommand{\gram}{g}
\providecommand{\mole}{mol}
\providecommand{\kelvin}{K}
\providecommand{\celsius}{^\circ C}
\providecommand{\angstrom}{\AA}
\providecommand{\electronvolt}{eV}
\providecommand{\atomicmassunit}{amu}
\providecommand{\per}{/}
\providecommand{\squared}{^{2}}
\providecommand{\cubed}{^{3}}
"""
LATEXML_CODE_GENERATED_DIAGRAM_FALLBACK_PREAMBLE = r"""
\providecommand{\usetikzlibrary}[1]{}
\providecommand{\pgfplotsset}[1]{}
\providecommand{\pgfmathsetmacro}[2]{}
\providecommand{\tikzset}[1]{}
\providecommand{\definecolor}[3]{}
\providecommand{\colorlet}[2]{}
"""
LATEXML_SECTION_TOC_FALLBACK_PREAMBLE = r"""
\providecommand{\startcontents}[1][]{}
\providecommand{\stopcontents}[1][]{}
\providecommand{\printcontents}[4][]{}
"""
LATEXML_LISTINGS_FALLBACK_PREAMBLE = r"""
\providecommand{\lstset}[1]{}
\providecommand{\lstdefinestyle}[2]{}
\providecommand{\lstinputlisting}[2][]{\mbox{Code listing}}
"""
LATEXML_PACKAGE_FALLBACK_PREAMBLES = {
    "algorithmic-environment": LATEXML_ALGORITHMIC_FALLBACK_PREAMBLE,
    "tcolorbox-environment": LATEXML_TCOLORBOX_FALLBACK_PREAMBLE,
    "siunitx-commands": LATEXML_SIUNITX_FALLBACK_PREAMBLE,
    "code-generated-diagram": LATEXML_CODE_GENERATED_DIAGRAM_FALLBACK_PREAMBLE,
    "section-toc-layout": LATEXML_SECTION_TOC_FALLBACK_PREAMBLE,
    "listings-environment": LATEXML_LISTINGS_FALLBACK_PREAMBLE,
}
LATEXML_CODE_GENERATED_DIAGRAM_ENVIRONMENTS = (
    "tikzpicture",
    "circuitikz",
    "axis",
    "blochsphere",
)
LATEXML_CODE_LISTING_ENVIRONMENTS = ("lstlisting", "code")
LATEXML_LAYOUT_CLASS_PREAMBLE = r"""
\usepackage{amsmath,amsfonts,amssymb}
\makeatletter
\newenvironment{keywords}{\par}{\par}
\newenvironment{highlights}{\par}{\par}
\providecommand{\shorttitle}[1]{}
\providecommand{\shortauthors}[1]{}
\providecommand{\cortext}[2][]{}
\providecommand{\ead}[1]{}
\providecommand{\credit}[1]{}
\providecommand{\fntext}[2][]{}
\providecommand{\tnotetext}[2][]{}
\providecommand{\tnotemark}[1][]{}
\providecommand{\fnmark}[1][]{}
\providecommand{\cormark}[1][]{}
\providecommand{\sep}{; }
\providecommand{\affiliation}[2][]{}
\providecommand{\address}{\@ifnextchar[{\BilinCASAddressWith}{\BilinCASAddressWithout}}
\def\BilinCASAddressWith[#1]#2{}
\def\BilinCASAddressWithout#1{}
\let\BilinArticleTitle\title
\renewcommand{\title}{\@ifnextchar[{\BilinCASTitleWith}{\BilinCASTitleWithout}}
\def\BilinCASTitleWith[#1]#2{\BilinArticleTitle{#2}}
\def\BilinCASTitleWithout#1{\BilinArticleTitle{#1}}
\let\BilinArticleAuthor\author
\renewcommand{\author}{\@ifnextchar[{\BilinCASAuthorWithAffil}{\BilinCASAuthorWithoutAffil}}
\def\BilinCASAuthorWithAffil[#1]#2{\@ifnextchar[{\BilinCASAuthorWithMeta{#2}}{\BilinArticleAuthor{#2}}}
\def\BilinCASAuthorWithoutAffil#1{\@ifnextchar[{\BilinCASAuthorWithMeta{#1}}{\BilinArticleAuthor{#1}}}
\def\BilinCASAuthorWithMeta#1[#2]{\BilinArticleAuthor{#1}}
\makeatother
"""
LATEXML_MEMOIR_CLASS_PREAMBLE = r"""
\makeatletter
\providecommand{\maketitlehooka}{}
\providecommand{\maketitlehookb}{}
\providecommand{\maketitlehookc}{}
\providecommand{\maketitlehookd}{}
\providecommand{\sloppybottom}{}
\providecommand{\flushbottom}{}
\providecommand{\printpartname}{\partname}
\providecommand{\printpartnum}{\thepart}
\providecommand{\printparttitle}[1]{#1}
\providecommand{\beforepartskip}{}
\providecommand{\midpartskip}{}
\providecommand{\afterpartskip}{}
\providecommand{\@pnumwidth}{1.55em}
\providecommand{\@tocrmarg}{2.55em}
\providecommand{\@dotsep}{4.5}
\@ifundefined{droptitle}{\newlength{\droptitle}}{}
\@ifundefined{cftbeforechapterskip}{\newlength{\cftbeforechapterskip}}{}
\@ifundefined{cftbeforepartskip}{\newlength{\cftbeforepartskip}}{}
\@ifundefined{startcontents}{\newcommand{\startcontents}[1][]{}}{}
\@ifundefined{stopcontents}{\newcommand{\stopcontents}[1][]{}}{}
\@ifundefined{printcontents}{\newcommand{\printcontents}[4][]{}}{}
\providecommand{\pretitle}[1]{}
\providecommand{\posttitle}[1]{}
\providecommand{\preauthor}[1]{}
\providecommand{\postauthor}[1]{}
\providecommand{\predate}[1]{}
\providecommand{\postdate}[1]{}
\providecommand{\maxtocdepth}[1]{}
\newcommand{\BilinMemoirUnit}[2][]{\chapter{#2}}
\AtBeginDocument{\let\unit\BilinMemoirUnit}
\makeatother
"""


class ParseFailure(Exception):
    def __init__(self, code: str, message: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}

    def to_error_info(self) -> ParseErrorInfo:
        return ParseErrorInfo(code=self.code, message=self.message, details=self.details)


@dataclass(frozen=True)
class CommandTimeoutBudget:
    soft_seconds: float
    idle_seconds: float
    hard_seconds: float
    source_bytes: int = 0
    tex_file_count: int = 0
    graphic_file_count: int = 0
    structure_unit_count: int = 0
    split_level: str | None = None
    document_class: str | None = None


@dataclass(frozen=True)
class ParserProfile:
    source_root: str | None = None
    main_tex_file: str | None = None
    entry_file: str | None = None
    document_command: str | None = None
    document_class: str | None = None
    packages: tuple[str, ...] = ()
    disabled_packages: tuple[str, ...] = ()
    compatibility_rules: tuple[str, ...] = ()
    main_candidates: tuple[dict[str, Any], ...] = ()
    has_bbl: bool = False
    has_bib: bool = False
    has_tikz: bool = False
    has_qcircuit: bool = False
    has_tcolorbox: bool = False
    has_algorithmic: bool = False
    has_siunitx: bool = False
    has_glossaries: bool = False
    has_multiple_main_candidates: bool = False
    is_legacy_arxiv: bool = False

    def to_json(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class ParserDiagnostic:
    stage: str
    code: str
    message: str
    command: tuple[str, ...] = ()
    log_path: str | None = None
    first_error: str | None = None
    log_excerpt: str | None = None
    profile: ParserProfile | None = None
    compatibility_rules: tuple[str, ...] = ()
    entry_path: str | None = None
    diagnostics_path: str | None = None
    suggestion: str | None = None

    def to_json(self) -> dict[str, Any]:
        payload = asdict(self)
        if self.profile is not None:
            payload["profile"] = self.profile.to_json()
        return payload


@dataclass(frozen=True)
class ParserPreparation:
    source_archive: Path
    unpack_dir: Path
    main_tex: Path
    latexml_entry: Path
    profile: ParserProfile


async def parse_article_revision(
    library: Library,
    revision_id: str,
    progress: ParseProgressCallback | None = None,
) -> dict[str, Any]:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Article revision not found: {revision_id}"
        raise ParseFailure("not_found:article_revision", msg)
    bundle_path = Path(revision.bundle_path)
    manifest = read_manifest(bundle_path) or empty_manifest(revision)
    previous_errors = list(manifest.errors)
    manifest.parse_status = "running"
    manifest.errors = []
    manifest.generated_artifacts.pop("parse_error_log", None)
    write_manifest(bundle_path, manifest)
    await mark_revision_status(library, revision.id, "parsing")

    stage = "source_intake"
    profile: ParserProfile | None = None
    try:
        await emit_parse_progress(progress, "source_unpack", "解包源文件", 0.08)
        source_archive, unpack_dir = prepare_latexml_source_intake(bundle_path)
        stage = "preflight_classification"
        preparation = prepare_latexml_preflight(source_archive, unpack_dir)
        main_tex = preparation.main_tex
        latexml_entry = preparation.latexml_entry
        profile = preparation.profile
        manifest.main_tex_file = str(main_tex.relative_to(unpack_dir))
        manifest.metadata["parser_profile"] = profile.to_json()
        manifest.metadata["latexml_compatibility_rules"] = list(profile.compatibility_rules)

        stage = "dependency_check"
        await emit_parse_progress(progress, "dependency_check", "依赖检查", 0.2)
        latexml = shutil.which("latexml")
        latexmlpost = shutil.which("latexmlpost")
        if not latexml or not latexmlpost:
            missing = "latexml" if not latexml else "latexmlpost"
            raise ParseFailure(
                "missing_dependency:latexml",
                f"{missing} was not found on PATH. Install LaTeXML to parse TeX sources.",
                {
                    "missing_tool": missing,
                    "doctor_command": "bilin doctor",
                    "install_hint": (
                        "Install LaTeXML so both latexml and latexmlpost are on PATH. "
                        "Without it, TeX parsing fails explicitly; Markdown imports and PDF "
                        "save-only imports still work."
                    ),
                },
            )

        stage = "latexml_execution"
        document_dir = bundle_path / "document"
        logs_dir = bundle_path / "logs"
        document_dir.mkdir(parents=True, exist_ok=True)
        logs_dir.mkdir(parents=True, exist_ok=True)
        xml_path = document_dir / "latexml.xml"
        html_path = document_dir / "latexml.html"
        resume_from_html = should_resume_parse_from_html(previous_errors, html_path)
        resume_from_latexmlpost = should_resume_parse_from_latexmlpost(previous_errors, xml_path)
        previous_latexmlpost_timeout = previous_failure_was_latexmlpost_timeout(previous_errors)
        latexml_command = [latexml, "--includestyles"]
        for search_path in _latexml_search_paths(unpack_dir, main_tex.parent):
            latexml_command.extend(["--path", str(search_path)])
        latexml_command.extend(["--destination", str(xml_path), latexml_entry.name])
        latexmlpost_command = [
            latexmlpost,
            "--verbose",
            "--format=html5",
            "--xsltparameter=SIMPLIFY_HTML:true",
            "--destination",
            str(html_path),
            str(xml_path),
        ]
        split_dir = document_dir / LATEXML_SPLIT_OUTPUT_DIR
        split_index_path = split_dir / "index.html"
        split_level = preferred_latexml_split_level(profile, main_tex)
        latexmlpost_split_command = [
            latexmlpost,
            "--verbose",
            "--format=html5",
            "--xsltparameter=SIMPLIFY_HTML:true",
            "--split",
            f"--splitat={split_level}",
            "--splitnaming=id",
            "--navigationtoc=none",
            "--destination",
            str(split_index_path),
            str(xml_path),
        ]
        manifest.latexml_command = latexml_command + ["&&"] + latexmlpost_command
        manifest.metadata["latexml_entry_file"] = str(latexml_entry.relative_to(unpack_dir))
        manifest.metadata["latexml_disabled_packages"] = sorted(LATEXML_DISABLED_PACKAGES)
        manifest.metadata["latexml_binding_dir"] = str(_latexml_binding_dir())
        manifest.metadata["latexml_split_level"] = split_level
        manifest.tool_versions = {
            "latexml": detect_version(latexml),
            "latexmlpost": detect_version(latexmlpost),
        }
        latexml_timeout = estimate_latexml_timeout_budget(
            unpack_dir,
            main_tex,
            "latexml",
            profile=profile,
        )
        latexmlpost_timeout = estimate_latexml_timeout_budget(
            unpack_dir,
            main_tex,
            "latexmlpost",
            profile=profile,
        )
        manifest.metadata["latexml_timeout_seconds"] = {
            "latexml": asdict(latexml_timeout),
            "latexmlpost": asdict(latexmlpost_timeout),
        }

        if resume_from_html:
            manifest.metadata["parse_resume_from"] = "html_normalization"
        else:
            if resume_from_latexmlpost:
                manifest.metadata["parse_resume_from"] = "latexmlpost_execution"
                await emit_parse_progress(
                    progress,
                    "latexmlpost_execution",
                    "从失败阶段继续：渲染 HTML",
                    0.6,
                )
            else:
                await emit_parse_progress(progress, "latexml_execution", "执行 LaTeXML", 0.35)
                await run_command(
                    latexml_command,
                    cwd=latexml_entry.parent,
                    log_path=logs_dir / "latexml.log",
                    timeout_budget=latexml_timeout,
                    activity_paths=[xml_path],
                )
            stage = "latexmlpost_execution"
            if should_split_latexmlpost_by_default(
                profile,
                main_tex,
                latexmlpost_timeout,
            ) or (resume_from_latexmlpost and previous_latexmlpost_timeout):
                await emit_parse_progress(
                    progress,
                    "latexmlpost_split_execution",
                    (
                        "从失败阶段继续：按章节渲染 HTML"
                        if resume_from_latexmlpost
                        else "按章节渲染 HTML"
                    ),
                    0.6,
                )
                try:
                    await run_latexmlpost_split(
                        latexmlpost_split_command,
                        cwd=main_tex.parent,
                        log_path=logs_dir / "latexmlpost-split.log",
                        timeout_budget=latexmlpost_timeout,
                        split_index_path=split_index_path,
                        html_path=html_path,
                    )
                    manifest.metadata["latexmlpost_mode"] = (
                        "split_after_retry" if resume_from_latexmlpost else "split"
                    )
                except ParseFailure as exc:
                    if exc.code != "latexml_timeout":
                        raise
                    await emit_parse_progress(
                        progress,
                        "latexml_xml_recovery",
                        "latexmlpost 仍超时，使用 XML 快速恢复",
                        0.72,
                    )
                    latexml_xml_to_html(xml_path, html_path)
                    mark_latexml_xml_recovery_manifest(manifest, exc.details)
            else:
                await emit_parse_progress(
                    progress,
                    "latexmlpost_execution",
                    "执行 latexmlpost",
                    0.6,
                )
                try:
                    await run_command(
                        latexmlpost_command,
                        cwd=main_tex.parent,
                        log_path=logs_dir / "latexmlpost.log",
                        timeout_budget=latexmlpost_timeout,
                        activity_paths=[html_path],
                    )
                    manifest.metadata["latexmlpost_mode"] = "single"
                except ParseFailure as exc:
                    if exc.code != "latexml_timeout":
                        raise
                    await emit_parse_progress(
                        progress,
                        "latexmlpost_split_execution",
                        "latexmlpost 超时，按章节渲染 HTML",
                        0.65,
                    )
                    manifest.metadata["latexmlpost_single_timeout"] = exc.details
                    try:
                        await run_latexmlpost_split(
                            latexmlpost_split_command,
                            cwd=main_tex.parent,
                            log_path=logs_dir / "latexmlpost-split.log",
                            timeout_budget=latexmlpost_timeout,
                            split_index_path=split_index_path,
                            html_path=html_path,
                        )
                    except ParseFailure as split_exc:
                        if split_exc.code != "latexml_timeout":
                            split_exc.details.setdefault(
                                "single_latexmlpost_timeout",
                                exc.details,
                            )
                            raise split_exc from exc
                        await emit_parse_progress(
                            progress,
                            "latexml_xml_recovery",
                            "latexmlpost 仍超时，使用 XML 快速恢复",
                            0.72,
                        )
                        latexml_xml_to_html(xml_path, html_path)
                        mark_latexml_xml_recovery_manifest(manifest, split_exc.details)
                    else:
                        manifest.metadata["latexmlpost_mode"] = "split_after_timeout"
        stage = "html_normalization"
        await emit_parse_progress(progress, "html_normalization", "规范化 HTML", 0.78)
        blocks, assets = normalize_latexml_html(
            html_path,
            revision.id,
            bundle_path=bundle_path,
            source_root=unpack_dir,
        )
        source_md = render_source_markdown(blocks)
        await emit_parse_progress(progress, "document_write", "写入文档", 0.9)
        manifest.parse_status = "parsed"
        manifest.generated_artifacts.update(
            {
                "latexml_xml": str(xml_path),
                "latexml_html": str(html_path),
            }
        )
        await replace_document(library, revision, manifest, blocks, assets, source_md)
        return {
            "article_revision_id": revision.id,
            "document_path": str(document_dir / "document.json"),
            "source_md_path": str(document_dir / "source.md"),
            "block_count": len(blocks),
            "asset_count": len(assets),
        }
    except ParseFailure as exc:
        failure = enrich_parse_failure(bundle_path, exc, stage=stage, profile=profile)
        manifest.parse_status = "failed"
        manifest.errors = [failure.to_error_info()]
        error_log = write_parse_failure_log(bundle_path, failure)
        manifest.generated_artifacts["parse_error_log"] = str(error_log)
        if "diagnostics_path" in failure.details:
            manifest.generated_artifacts["parser_diagnostics"] = str(
                failure.details["diagnostics_path"]
            )
        await mark_revision_status(library, revision.id, "parse_failed", manifest)
        raise failure from exc
    except Exception as exc:
        failure = enrich_parse_failure(
            bundle_path,
            ParseFailure("parse_failed", str(exc), {"type": type(exc).__name__}),
            stage=stage,
            profile=profile,
        )
        manifest.parse_status = "failed"
        manifest.errors = [failure.to_error_info()]
        error_log = write_parse_failure_log(bundle_path, failure)
        manifest.generated_artifacts["parse_error_log"] = str(error_log)
        if "diagnostics_path" in failure.details:
            manifest.generated_artifacts["parser_diagnostics"] = str(
                failure.details["diagnostics_path"]
            )
        await mark_revision_status(library, revision.id, "parse_failed", manifest)
        raise failure from exc


async def emit_parse_progress(
    progress: ParseProgressCallback | None,
    stage: str,
    message: str,
    value: float,
) -> None:
    if progress is not None:
        await progress(stage, message, value)


def write_parse_failure_log(bundle_path: Path, failure: ParseFailure) -> Path:
    logs_dir = bundle_path / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    path = logs_dir / "parse-error.json"
    path.write_text(
        json.dumps(
            {
                "code": failure.code,
                "message": failure.message,
                "details": failure.details,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    return path


def enrich_parse_failure(
    bundle_path: Path,
    failure: ParseFailure,
    *,
    stage: str,
    profile: ParserProfile | None = None,
) -> ParseFailure:
    log_path_value = failure.details.get("log_path")
    log_path = Path(log_path_value) if isinstance(log_path_value, str) else None
    first_error, log_excerpt = summarize_latexml_log(log_path) if log_path else (None, None)
    diagnostic_path = parser_diagnostics_path(bundle_path)
    diagnostic = ParserDiagnostic(
        stage=str(failure.details.get("stage") or stage),
        code=failure.code,
        message=failure.message,
        command=tuple(str(value) for value in failure.details.get("command", ()) or ()),
        log_path=str(log_path) if log_path else None,
        first_error=first_error,
        log_excerpt=log_excerpt,
        profile=profile,
        compatibility_rules=profile.compatibility_rules if profile else (),
        entry_path=_diagnostic_entry_path(bundle_path, profile),
        diagnostics_path=str(diagnostic_path),
        suggestion=_parse_failure_suggestion(failure.code, first_error, profile),
    )
    diagnostic_path.parent.mkdir(parents=True, exist_ok=True)
    diagnostic_path.write_text(
        json.dumps(diagnostic.to_json(), indent=2, sort_keys=True),
        encoding="utf-8",
    )
    details = dict(failure.details)
    details.update(
        {
            "stage": diagnostic.stage,
            "diagnostics_path": str(diagnostic_path),
            "profile": profile.to_json() if profile else None,
            "compatibility_rules": list(diagnostic.compatibility_rules),
        }
    )
    if diagnostic.first_error:
        details["first_error"] = diagnostic.first_error
    if diagnostic.log_excerpt:
        details["log_excerpt"] = diagnostic.log_excerpt
    if diagnostic.entry_path:
        details["entry_path"] = diagnostic.entry_path
    if diagnostic.suggestion:
        details["suggestion"] = diagnostic.suggestion
    return ParseFailure(failure.code, failure.message, details)


def parser_diagnostics_path(bundle_path: Path) -> Path:
    return bundle_path / "logs" / "parser-diagnostics.json"


def summarize_latexml_log(log_path: Path) -> tuple[str | None, str | None]:
    if not log_path.exists():
        return None, None
    text = log_path.read_text(encoding="utf-8", errors="replace")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    first_error = next(
        (
            line
            for line in lines
            if line.startswith(("Fatal:", "Error:")) or "Fatal:" in line or "Error:" in line
        ),
        None,
    )
    interesting = [
        line
        for line in lines
        if line.startswith(("Fatal:", "Error:", "Warning:"))
        or "Fatal:" in line
        or "Error:" in line
        or "Warning:" in line
    ]
    excerpt_lines = interesting[:8] if interesting else lines[-12:]
    return first_error, "\n".join(excerpt_lines) if excerpt_lines else None


def _diagnostic_entry_path(bundle_path: Path, profile: ParserProfile | None) -> str | None:
    if profile is None or profile.entry_file is None:
        return None
    return str(bundle_path / "source" / "unpacked" / profile.entry_file)


def _parse_failure_suggestion(
    code: str,
    first_error: str | None,
    profile: ParserProfile | None,
) -> str:
    if code == "missing_dependency:latexml":
        return (
            "Install LaTeXML and confirm both latexml and latexmlpost are visible in bilin doctor."
        )
    if code == "missing_main_tex":
        return (
            "Inspect the source package for the real TeX entry file and add a main-file "
            "fixture if detection is ambiguous."
        )
    if first_error:
        if "undefined" in first_error:
            return (
                "Add a conservative compatibility rule, source transform, or local LaTeXML "
                "binding for the first undefined macro or environment."
            )
        if "too_many_errors" in first_error:
            return (
                "Inspect the earliest error before too_many_errors and reduce it to a fixture "
                "before adding another shim."
            )
    if profile and profile.has_tikz:
        return (
            "TikZ content should remain a controlled-render asset path; avoid guessing diagram "
            "semantics in the reader."
        )
    return (
        "Inspect parser-diagnostics.json, the generated entry file, and the command log before "
        "changing compatibility rules."
    )


def prepare_latexml_source_intake(bundle_path: Path) -> tuple[Path, Path]:
    source_archive = _find_source_archive(bundle_path)
    unpack_dir = bundle_path / "source" / "unpacked"
    safe_unpack(source_archive, unpack_dir)
    return source_archive, unpack_dir


def prepare_latexml_preflight(source_archive: Path, unpack_dir: Path) -> ParserPreparation:
    main_tex = find_main_tex(unpack_dir)
    profile = build_parser_profile(unpack_dir, main_tex)
    prepare_latexml_side_sources(unpack_dir, main_tex)
    latexml_entry = prepare_latexml_entry(main_tex)
    profile = build_parser_profile(unpack_dir, main_tex, latexml_entry)
    return ParserPreparation(
        source_archive=source_archive,
        unpack_dir=unpack_dir,
        main_tex=main_tex,
        latexml_entry=latexml_entry,
        profile=profile,
    )


async def diagnose_parse_revision(library: Library, revision_id: str) -> dict[str, Any]:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Article revision not found: {revision_id}"
        raise ParseFailure("not_found:article_revision", msg)
    bundle_path = Path(revision.bundle_path)
    manifest = read_manifest(bundle_path)
    unpack_dir = bundle_path / "source" / "unpacked"
    main_tex = _diagnostic_main_tex(unpack_dir, manifest)
    entry_file = unpack_dir / LATEXML_ENTRY_FILE
    profile = build_parser_profile(
        unpack_dir,
        main_tex=main_tex,
        entry_file=entry_file if entry_file.exists() else None,
    )
    stored_diagnostics = _read_json_file(parser_diagnostics_path(bundle_path))
    parse_error = (
        _read_json_file(bundle_path / "logs" / "parse-error.json")
        if manifest and manifest.generated_artifacts.get("parse_error_log")
        else None
    )
    latexml_first_error, latexml_excerpt = summarize_latexml_log(
        bundle_path / "logs" / "latexml.log"
    )
    latexmlpost_first_error, latexmlpost_excerpt = summarize_latexml_log(
        bundle_path / "logs" / "latexmlpost.log"
    )
    return {
        "article_revision_id": revision.id,
        "bundle_path": str(bundle_path),
        "parse_status": manifest.parse_status if manifest else revision.status,
        "manifest_error": manifest.errors[0].model_dump(mode="json")
        if manifest and manifest.errors
        else None,
        "profile": profile.to_json(),
        "stored_diagnostics": stored_diagnostics,
        "parse_error": parse_error,
        "logs": {
            "latexml": {
                "path": str(bundle_path / "logs" / "latexml.log"),
                "first_error": latexml_first_error,
                "excerpt": latexml_excerpt,
            },
            "latexmlpost": {
                "path": str(bundle_path / "logs" / "latexmlpost.log"),
                "first_error": latexmlpost_first_error,
                "excerpt": latexmlpost_excerpt,
            },
        },
    }


def _diagnostic_main_tex(unpack_dir: Path, manifest: Any) -> Path | None:
    if manifest is not None and manifest.main_tex_file:
        candidate = unpack_dir / str(manifest.main_tex_file)
        if candidate.exists():
            return candidate
    try:
        return find_main_tex(unpack_dir)
    except ParseFailure:
        return None


def _read_json_file(path: Path) -> Any:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def safe_unpack(source_archive: Path, destination: Path, max_bytes: int = 200_000_000) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)
    try:
        with tarfile.open(source_archive, "r:*") as archive:
            total = 0
            for member in archive.getmembers():
                if not _is_safe_member(member.name):
                    raise ParseFailure(
                        "unsafe_archive:path_traversal",
                        f"Unsafe path: {member.name}",
                    )
                total += max(member.size, 0)
                if total > max_bytes:
                    raise ParseFailure(
                        "unsafe_archive:too_large",
                        "Source archive exceeds size limit.",
                    )
            archive.extractall(destination, filter="data")
            return
    except tarfile.TarError:
        pass

    if zipfile.is_zipfile(source_archive):
        total = 0
        with zipfile.ZipFile(source_archive) as archive:
            for member in archive.infolist():
                if not _is_safe_member(member.filename):
                    raise ParseFailure(
                        "unsafe_archive:path_traversal",
                        f"Unsafe path: {member.filename}",
                    )
                total += member.file_size
                if total > max_bytes:
                    raise ParseFailure(
                        "unsafe_archive:too_large",
                        "Source archive exceeds size limit.",
                    )
            archive.extractall(destination)
            return

    try:
        with gzip.open(source_archive, "rb") as source:
            content = source.read(max_bytes + 1)
    except OSError as exc:
        raise ParseFailure(
            "unsupported_source_archive",
            "Source package is not a tar, zip, or gzip single TeX file.",
        ) from exc
    if len(content) > max_bytes:
        raise ParseFailure("unsafe_archive:too_large", "Source file exceeds size limit.")
    (destination / "main.tex").write_bytes(content)


def find_main_tex(unpack_dir: Path) -> Path:
    scored = _scored_main_tex_candidates(unpack_dir)
    if not scored:
        raise ParseFailure("missing_main_tex", "No TeX-like main file found in source package.")
    if scored[0][0] < 20:
        raise ParseFailure(
            "missing_main_tex",
            "Could not identify a main TeX file with documentclass/documentstyle "
            "and begin{document}.",
        )
    return scored[0][1]


def _scored_main_tex_candidates(unpack_dir: Path) -> list[tuple[int, Path]]:
    candidates = sorted(path for path in unpack_dir.rglob("*") if _is_tex_main_candidate(path))
    scored: list[tuple[int, Path]] = []
    for candidate in candidates:
        text = candidate.read_text(encoding="utf-8", errors="ignore")
        scored.append((score_main_tex_candidate(candidate, text), candidate))
    scored.sort(key=lambda item: (-item[0], len(str(item[1]))))
    return scored


def _is_tex_main_candidate(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.name == LATEXML_ENTRY_FILE:
        return False
    suffix = path.suffix.casefold()
    if suffix in TEX_MAIN_FILE_SUFFIXES:
        return True
    if suffix in TEX_SIDE_FILE_SUFFIXES or suffix in LATEX_GRAPHIC_SUFFIXES:
        return False
    if suffix:
        return False
    return _safe_file_size(path) <= TEX_CANDIDATE_READ_LIMIT_BYTES and _looks_like_tex_file(path)


def _looks_like_tex_file(path: Path) -> bool:
    try:
        sample = path.read_text(encoding="utf-8", errors="ignore")[:12_000]
    except OSError:
        return False
    return any(
        marker in sample
        for marker in (
            "\\documentclass",
            "\\documentstyle",
            "\\begin{document}",
            "\\input{",
            "\\include{",
        )
    )


def score_main_tex_candidate(path: Path, text: str) -> int:
    score = 0
    has_document_command = bool(re.search(r"\\(?:documentclass|documentstyle)\b", text))
    has_begin_document = "\\begin{document}" in text
    if "\\documentclass" in text:
        score += 12
    if "\\documentstyle" in text:
        score += 12
    if has_begin_document:
        score += 12
    lower_stem = path.stem.casefold()
    lower_name = path.name.casefold()
    if lower_stem in TEX_MAIN_FILE_NAME_HINTS:
        score += 4
    if re.fullmatch(r"\d{7}(?:v\d+)?", lower_name):
        score += 4
    suffix = path.suffix.casefold()
    if suffix == ".tex":
        score += 2
    elif suffix in {".ltx", ".latex"} or not suffix:
        score += 1
    for marker in ("\\title", "\\author", "\\maketitle", "\\abstract", "\\bibliography"):
        if marker in text:
            score += 1
    if not (has_document_command and has_begin_document):
        score -= 20
    return score


def build_parser_profile(
    unpack_dir: Path,
    main_tex: Path | None = None,
    entry_file: Path | None = None,
) -> ParserProfile:
    scored_candidates = _scored_main_tex_candidates(unpack_dir) if unpack_dir.exists() else []
    selected_main = main_tex
    if selected_main is None and scored_candidates and scored_candidates[0][0] >= 20:
        selected_main = scored_candidates[0][1]
    source_files = _profile_source_files(unpack_dir)
    source_text_by_path = {
        path: path.read_text(encoding="utf-8", errors="ignore") for path in source_files
    }
    main_text = (
        selected_main.read_text(encoding="utf-8", errors="ignore")
        if selected_main is not None and selected_main.exists()
        else ""
    )
    all_source_text = "\n".join(source_text_by_path.values())
    packages = tuple(sorted(_source_package_names(all_source_text)))
    disabled_packages = tuple(
        package for package in packages if package in LATEXML_DISABLED_PACKAGES
    )
    document_command, document_class = _document_command_profile(main_text)
    compatibility_rules = _profile_compatibility_rules(
        packages=packages,
        source_text=all_source_text,
        document_class=document_class,
        source_root=unpack_dir,
        main_tex=selected_main,
    )
    candidate_records = tuple(
        {
            "path": _relative_path_or_str(path, unpack_dir),
            "score": score,
        }
        for score, path in scored_candidates[:8]
    )
    has_package = set(packages).__contains__
    return ParserProfile(
        source_root=str(unpack_dir),
        main_tex_file=_relative_path_or_str(selected_main, unpack_dir) if selected_main else None,
        entry_file=_relative_path_or_str(entry_file, unpack_dir) if entry_file else None,
        document_command=document_command,
        document_class=document_class,
        packages=packages,
        disabled_packages=disabled_packages,
        compatibility_rules=compatibility_rules,
        main_candidates=candidate_records,
        has_bbl=any(path.suffix.casefold() == ".bbl" for path in source_files),
        has_bib=any(path.suffix.casefold() == ".bib" for path in source_files),
        has_tikz=has_package("tikz")
        or has_package("pgfplots")
        or "\\begin{tikzpicture}" in all_source_text,
        has_qcircuit=has_package("qcircuit") or "\\Qcircuit" in all_source_text,
        has_tcolorbox=has_package("tcolorbox") or "\\newtcolorbox" in all_source_text,
        has_algorithmic=(
            has_package("algpseudocodex")
            or has_package("algorithmic")
            or has_package("algorithmicx")
            or "\\begin{algorithmic}" in all_source_text
        ),
        has_siunitx=has_package("siunitx"),
        has_glossaries=bool({"glossaries", "glossaries-extra", "mfirstuc"} & set(packages)),
        has_multiple_main_candidates=sum(1 for score, _path in scored_candidates if score >= 20)
        > 1,
        is_legacy_arxiv=_is_legacy_latex_source(selected_main, main_text),
    )


def _profile_source_files(unpack_dir: Path) -> list[Path]:
    if not unpack_dir.exists():
        return []
    files: list[Path] = []
    for path in sorted(unpack_dir.rglob("*")):
        if not path.is_file() or path.name == LATEXML_ENTRY_FILE:
            continue
        suffix = path.suffix.casefold()
        if suffix in TEX_MAIN_FILE_SUFFIXES | TEX_SIDE_FILE_SUFFIXES | {".cls"}:
            files.append(path)
            continue
        if not suffix and _looks_like_tex_file(path):
            files.append(path)
    return files


def _source_package_names(source: str) -> set[str]:
    package_pattern = re.compile(
        r"\\(?:usepackage|RequirePackage)"
        r"(?:\s*\[[^\]]*\])*"
        r"\s*\{(?P<packages>[^{}]+)\}",
    )
    packages: set[str] = set()
    for match in package_pattern.finditer(source):
        if _is_tex_comment_position(source, match.start()):
            continue
        packages.update(
            package.strip() for package in match.group("packages").split(",") if package.strip()
        )
    return packages


def _document_command_profile(source: str) -> tuple[str | None, str | None]:
    match = _first_uncommented_latex_match(
        r"\\(?P<command>documentclass|documentstyle)"
        r"(?:\s*\[[^\]]*\])?"
        r"\s*\{(?P<class_name>[^{}]+)\}",
        source,
    )
    if match is None:
        return None, None
    return f"\\{match.group('command')}", match.group("class_name").strip()


def _profile_compatibility_rules(
    *,
    packages: tuple[str, ...],
    source_text: str,
    document_class: str | None,
    source_root: Path,
    main_tex: Path | None,
) -> tuple[str, ...]:
    rules: set[str] = set()
    for package in packages:
        policy = LATEXML_PACKAGE_POLICIES.get(package)
        if policy and policy.get("disable_for_latexml"):
            rules.add(f"package:{package}:{policy.get('fallback', 'none')}")
    if document_class and _latexml_document_class_replacement(document_class):
        rules.add(f"documentclass:{document_class}")
    if main_tex is not None and _source_has_available_bbl_fallback(
        source_text,
        main_tex.parent,
        main_tex.stem,
    ):
        rules.add("bibliography:bbl_fallback")
    if "\\documentstyle" in source_text:
        rules.add("legacy:documentstyle")
    return tuple(sorted(rules))


def _source_has_available_bbl_fallback(source: str, source_dir: Path, main_stem: str) -> bool:
    bibliography_pattern = re.compile(r"\\bibliography\s*\{(?P<names>[^{}]+)\}")
    for match in bibliography_pattern.finditer(source):
        names = [name.strip() for name in match.group("names").split(",") if name.strip()]
        if not names:
            continue
        for name in names:
            if (
                _resolve_available_bbl_reference(name, source_dir, main_stem, len(names))
                is not None
            ):
                return True
    return False


def _is_legacy_latex_source(main_tex: Path | None, main_text: str) -> bool:
    if "\\documentstyle" in main_text:
        return True
    if main_tex is None:
        return False
    suffix = main_tex.suffix.casefold()
    return suffix in {".ltx", ".latex"} or not suffix


def _relative_path_or_str(path: Path | None, root: Path) -> str | None:
    if path is None:
        return None
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def prepare_latexml_entry(main_tex: Path) -> Path:
    source = main_tex.read_text(encoding="utf-8", errors="ignore")
    prepared = prepare_latexml_source(source)
    prepared = replace_available_bbl_bibliographies(prepared, main_tex.parent, main_tex.stem)
    entry = main_tex.parent / LATEXML_ENTRY_FILE
    entry.write_text(prepared, encoding="utf-8")
    return entry


def replace_available_bbl_bibliographies(
    source: str,
    source_dir: Path,
    main_stem: str | None = None,
) -> str:
    bibliography_pattern = re.compile(r"\\bibliography\s*\{(?P<names>[^{}]+)\}")

    def replace(match: re.Match[str]) -> str:
        names = [name.strip() for name in match.group("names").split(",") if name.strip()]
        if not names:
            return match.group(0)
        inputs: list[str] = []
        for name in names:
            bbl_reference = _resolve_available_bbl_reference(
                name,
                source_dir,
                main_stem,
                len(names),
            )
            if bbl_reference is None:
                return match.group(0)
            inputs.append(rf"\input{{{bbl_reference.as_posix()}}}")
        return "\n".join(inputs)

    return bibliography_pattern.sub(replace, source)


def _resolve_available_bbl_reference(
    bibliography_name: str,
    source_dir: Path,
    main_stem: str | None,
    bibliography_count: int,
) -> Path | None:
    if Path(bibliography_name).suffix:
        exact_reference = Path(bibliography_name).with_suffix(".bbl")
    else:
        exact_reference = Path(f"{bibliography_name}.bbl")
    if (source_dir / exact_reference).exists():
        return exact_reference

    if bibliography_count != 1:
        return None

    if main_stem:
        main_reference = Path(f"{main_stem}.bbl")
        if (source_dir / main_reference).exists():
            return main_reference

    bbl_references = sorted(
        path.relative_to(source_dir)
        for path in source_dir.glob("*.bbl")
        if path.name != LATEXML_ENTRY_FILE
    )
    return bbl_references[0] if len(bbl_references) == 1 else None


def prepare_latexml_side_sources(unpack_dir: Path, main_tex: Path) -> None:
    source_suffixes = TEX_MAIN_FILE_SUFFIXES | {".sty"}
    for path in unpack_dir.rglob("*"):
        if not path.is_file() or path == main_tex or path.name == LATEXML_ENTRY_FILE:
            continue
        if path.suffix.casefold() not in source_suffixes:
            continue
        original = path.read_text(encoding="utf-8", errors="ignore")
        prepared = prepare_latexml_included_source(original)
        if prepared != original:
            path.write_text(prepared, encoding="utf-8")


def prepare_latexml_source(source: str) -> str:
    source = prepare_latexml_included_source(source)
    source = _replace_latexml_layout_document_classes(source)
    if _source_needs_layout_class_preamble(source):
        source = _strip_layout_author_metadata_options(source)
    if source.startswith("% Bilin LaTeXML parser entry"):
        return source
    source = _inject_latexml_compatibility_preamble(source)
    return "% Bilin LaTeXML parser entry. Original source is left untouched.\n" + source


def prepare_latexml_included_source(source: str) -> str:
    source = _disable_latexml_incompatible_packages(source)
    source = _rename_latexml_trivlist_environment(source)
    if _source_disables_latexml_package(source, "tcolorbox"):
        source = _replace_latexml_tcolorbox_definitions(source)
    source = _replace_latexml_code_listings(source)
    return _replace_latexml_code_generated_diagrams(source)


def _inject_latexml_compatibility_preamble(source: str) -> str:
    if "Bilin LaTeXML compatibility shims" in source:
        return source
    preamble_parts = [
        LATEXML_COMPATIBILITY_PREAMBLE.strip(),
        LATEXML_CITATION_FALLBACK_PREAMBLE.strip(),
    ]
    preamble_parts.extend(_latexml_package_fallback_preambles(source))
    if _source_needs_layout_class_preamble(source):
        preamble_parts.append(LATEXML_LAYOUT_CLASS_PREAMBLE.strip())
    if _source_replaces_latexml_document_class(source, "memoir"):
        preamble_parts.append(LATEXML_MEMOIR_CLASS_PREAMBLE.strip())
    preamble = "% Bilin LaTeXML compatibility shims.\n" + "\n".join(preamble_parts)
    document_command = _first_uncommented_latex_match(
        r"\\(?:documentclass|documentstyle)(?:\s*\[[^\]]*\])?\s*\{[^{}]+\}",
        source,
    )
    if document_command is None:
        return preamble + "\n" + source
    insert_at = document_command.end()
    return source[:insert_at] + "\n" + preamble + source[insert_at:]


def _latexml_package_fallback_preambles(source: str) -> list[str]:
    preambles: list[str] = []
    seen: set[str] = set()
    for package, policy in LATEXML_PACKAGE_POLICIES.items():
        if not _source_disables_latexml_package(source, package):
            continue
        fallback = str(policy.get("fallback", "none"))
        if fallback in seen:
            continue
        fallback_preamble = LATEXML_PACKAGE_FALLBACK_PREAMBLES.get(fallback)
        if fallback_preamble:
            preambles.append(fallback_preamble.strip())
            seen.add(fallback)
    return preambles


def _replace_latexml_layout_document_classes(source: str) -> str:
    document_class_pattern = re.compile(
        r"(?P<command>\\documentclass)"
        r"(?P<options>\s*\[[^\]]*\])?"
        r"\s*\{(?P<class_name>[^{}]+)\}",
        re.MULTILINE,
    )

    match = _first_uncommented_latex_match(document_class_pattern, source)
    if match is None:
        return source
    class_name = match.group("class_name").strip()
    replacement_class = _latexml_document_class_replacement(class_name)
    if replacement_class is None:
        return source
    options = match.group("options") or ""
    option_note = f" {options.strip()}" if options else ""
    replacement = (
        f"\\documentclass{{{replacement_class}}}"
        f"% Bilin replaced layout document class for LaTeXML: {class_name}{option_note}"
    )
    return source[: match.start()] + replacement + source[match.end() :]


def _first_uncommented_latex_match(
    pattern: str | re.Pattern[str],
    source: str,
) -> re.Match[str] | None:
    compiled = re.compile(pattern, re.MULTILINE) if isinstance(pattern, str) else pattern
    for match in compiled.finditer(source):
        if not _is_tex_comment_position(source, match.start()):
            return match
    return None


def _is_tex_comment_position(source: str, index: int) -> bool:
    line_start = source.rfind("\n", 0, index) + 1
    prefix = source[line_start:index]
    position = prefix.find("%")
    while position != -1:
        if not _is_escaped_tex_percent(prefix, position):
            return True
        position = prefix.find("%", position + 1)
    return False


def _is_escaped_tex_percent(prefix: str, percent_index: int) -> bool:
    backslash_count = 0
    cursor = percent_index - 1
    while cursor >= 0 and prefix[cursor] == "\\":
        backslash_count += 1
        cursor -= 1
    return backslash_count % 2 == 1


def _latexml_document_class_replacement(class_name: str) -> str | None:
    if class_name in LATEXML_LAYOUT_ONLY_DOCUMENT_CLASSES:
        return "article"
    return LATEXML_KOMA_DOCUMENT_CLASS_REPLACEMENTS.get(class_name)


def _source_needs_layout_class_preamble(source: str) -> bool:
    return any(
        _source_replaces_latexml_document_class(source, class_name)
        for class_name in LATEXML_CAS_DOCUMENT_CLASSES
    )


def _source_replaces_latexml_document_class(source: str, class_name: str) -> bool:
    return f"Bilin replaced layout document class for LaTeXML: {class_name}" in source


def _source_disables_latexml_package(source: str, package: str) -> bool:
    return bool(re.search(rf"Bilin disabled for LaTeXML: .*\b{re.escape(package)}\b", source))


def _strip_layout_author_metadata_options(source: str) -> str:
    parts: list[str] = []
    cursor = 0
    search_from = 0
    while True:
        start = source.find(r"\author", search_from)
        if start == -1:
            parts.append(source[cursor:])
            return "".join(parts)
        position = _skip_tex_whitespace(source, start + len(r"\author"))
        if position < len(source) and source[position] == "[":
            option_end = _find_balanced_optional_end(source, position)
            if option_end is None:
                parts.append(source[cursor:])
                return "".join(parts)
            position = _skip_tex_whitespace(source, option_end + 1)
        if position >= len(source) or source[position] != "{":
            search_from = start + len(r"\author")
            continue
        author_end = _find_balanced_group_end(source, position)
        if author_end is None:
            parts.append(source[cursor:])
            return "".join(parts)
        metadata_start = _skip_tex_whitespace(source, author_end + 1)
        if metadata_start >= len(source) or source[metadata_start] != "[":
            search_from = author_end + 1
            continue
        metadata_end = _find_balanced_optional_end(source, metadata_start)
        if metadata_end is None:
            parts.append(source[cursor:])
            return "".join(parts)
        metadata = source[metadata_start + 1 : metadata_end]
        if not _is_layout_author_metadata_option(metadata):
            search_from = metadata_start + 1
            continue
        parts.append(source[cursor:metadata_start])
        cursor = metadata_end + 1
        search_from = cursor


def _skip_tex_whitespace(source: str, position: int) -> int:
    while position < len(source) and source[position] in " \t\r\n":
        position += 1
    return position


def _find_balanced_optional_end(source: str, option_start: int) -> int | None:
    depth = 0
    escaped = False
    for index in range(option_start, len(source)):
        character = source[index]
        if escaped:
            escaped = False
            continue
        if character == "\\":
            escaped = True
            continue
        if character == "[":
            depth += 1
            continue
        if character == "]":
            depth -= 1
            if depth == 0:
                return index
    return None


def _is_layout_author_metadata_option(value: str) -> bool:
    keys = _layout_author_metadata_keys(value)
    return keys is not None and keys.issubset(LATEXML_LAYOUT_AUTHOR_METADATA_KEYS)


def _layout_author_metadata_keys(value: str) -> set[str] | None:
    entries = [
        entry.strip() for entry in re.split(r",\s*(?=[a-zA-Z][\w-]*\s*=)", value) if entry.strip()
    ]
    keys: set[str] = set()
    for entry in entries:
        match = re.match(r"^(?P<key>[a-zA-Z][\w-]*)\s*=", entry)
        if not match:
            return None
        keys.add(match.group("key").lower())
    return keys or None


def _replace_latexml_tcolorbox_definitions(source: str) -> str:
    command_pattern = re.compile(r"\\(?:new|renew)tcolorbox\b")
    parts: list[str] = []
    cursor = 0
    search_from = 0
    while True:
        match = command_pattern.search(source, search_from)
        if match is None:
            parts.append(source[cursor:])
            return "".join(parts)
        if _is_tex_comment_position(source, match.start()):
            search_from = match.end()
            continue
        parsed = _parse_tcolorbox_definition(source, match.end())
        if parsed is None:
            search_from = match.end()
            continue
        environment_name, argument_spec, definition_end = parsed
        parts.append(source[cursor : match.start()])
        parts.append(_latexml_tcolorbox_environment_stub(environment_name, argument_spec))
        cursor = definition_end
        search_from = definition_end


def _parse_tcolorbox_definition(source: str, position: int) -> tuple[str, str, int] | None:
    cursor = _skip_tex_whitespace(source, position)
    if cursor < len(source) and source[cursor] == "[":
        option_end = _find_balanced_optional_end(source, cursor)
        if option_end is None:
            return None
        cursor = _skip_tex_whitespace(source, option_end + 1)
    if cursor >= len(source) or source[cursor] != "{":
        return None
    name_end = _find_balanced_group_end(source, cursor)
    if name_end is None:
        return None
    environment_name = source[cursor + 1 : name_end].strip()
    if not re.fullmatch(r"[A-Za-z@][A-Za-z0-9@_-]*", environment_name):
        return None
    cursor = _skip_tex_whitespace(source, name_end + 1)
    argument_options: list[str] = []
    while cursor < len(source) and source[cursor] == "[":
        option_end = _find_balanced_optional_end(source, cursor)
        if option_end is None:
            return None
        argument_options.append(source[cursor + 1 : option_end])
        cursor = _skip_tex_whitespace(source, option_end + 1)
    if cursor >= len(source) or source[cursor] != "{":
        return None
    body_end = _find_balanced_group_end(source, cursor)
    if body_end is None:
        return None
    return environment_name, _latexml_tcolorbox_argument_spec(argument_options), body_end + 1


def _latexml_tcolorbox_argument_spec(argument_options: list[str]) -> str:
    if not argument_options:
        return ""
    argument_count = argument_options[0].strip()
    if not re.fullmatch(r"[1-9]", argument_count):
        return ""
    argument_spec = f"[{argument_count}]"
    if len(argument_options) > 1:
        argument_spec += f"[{argument_options[1]}]"
    return argument_spec


def _latexml_tcolorbox_environment_stub(environment_name: str, argument_spec: str) -> str:
    return (
        "\\makeatletter\n"
        f"\\@ifundefined{{{environment_name}}}"
        f"{{\\newenvironment{{{environment_name}}}{argument_spec}{{\\par}}{{\\par}}}}"
        f"{{\\renewenvironment{{{environment_name}}}{argument_spec}{{\\par}}{{\\par}}}}"
        "\n\\makeatother\n"
    )


def _replace_latexml_code_generated_diagrams(source: str) -> str:
    source = _replace_tex_command_balanced_group(
        source,
        command=r"\Qcircuit",
        replacement=r"\mbox{Quantum circuit diagram}",
    )
    for environment_name in LATEXML_CODE_GENERATED_DIAGRAM_ENVIRONMENTS:
        source = _replace_tex_environment(
            source,
            environment_name=environment_name,
            replacement=rf"\mbox{{{environment_name} diagram}}",
        )
    return source


def _replace_latexml_code_listings(source: str) -> str:
    source = _replace_tex_command_balanced_group(
        source,
        command=r"\lstinputlisting",
        replacement=r"\mbox{Code listing}",
    )
    for environment_name in LATEXML_CODE_LISTING_ENVIRONMENTS:
        source = _replace_tex_environment(
            source,
            environment_name=environment_name,
            replacement=r"\mbox{Code listing}",
        )
    return source


def _rename_latexml_trivlist_environment(source: str) -> str:
    return _rename_tex_environment(source, from_name="trivlist", to_name="itemize")


def _rename_tex_environment(source: str, *, from_name: str, to_name: str) -> str:
    marker_pattern = re.compile(
        rf"\\(?P<kind>begin|end)\s*\{{{re.escape(from_name)}\}}",
    )
    parts: list[str] = []
    cursor = 0
    for match in marker_pattern.finditer(source):
        if _is_tex_comment_position(source, match.start()):
            continue
        parts.append(source[cursor : match.start()])
        parts.append(rf"\{match.group('kind')}{{{to_name}}}")
        cursor = match.end()
    if not parts:
        return source
    parts.append(source[cursor:])
    return "".join(parts)


def _replace_tex_environment(
    source: str,
    *,
    environment_name: str,
    replacement: str,
) -> str:
    begin_pattern = re.compile(
        rf"\\begin\s*\{{{re.escape(environment_name)}\}}(?:\s*\[[^\]]*\])*",
    )
    marker_pattern = re.compile(
        rf"\\(?P<kind>begin|end)\s*\{{{re.escape(environment_name)}\}}",
    )
    parts: list[str] = []
    cursor = 0
    while True:
        begin_match = begin_pattern.search(source, cursor)
        if begin_match is None:
            parts.append(source[cursor:])
            return "".join(parts)
        if _is_tex_comment_position(source, begin_match.start()):
            parts.append(source[cursor : begin_match.end()])
            cursor = begin_match.end()
            continue
        environment_end = _find_tex_environment_end(
            source,
            marker_pattern,
            begin_match.end(),
        )
        if environment_end is None:
            parts.append(source[cursor:])
            return "".join(parts)
        parts.append(source[cursor : begin_match.start()])
        parts.append(replacement)
        cursor = environment_end


def _find_tex_environment_end(
    source: str,
    marker_pattern: re.Pattern[str],
    search_start: int,
) -> int | None:
    depth = 1
    for match in marker_pattern.finditer(source, search_start):
        if _is_tex_comment_position(source, match.start()):
            continue
        if match.group("kind") == "begin":
            depth += 1
            continue
        depth -= 1
        if depth == 0:
            return match.end()
    return None


def _replace_tex_command_balanced_group(source: str, *, command: str, replacement: str) -> str:
    parts: list[str] = []
    cursor = 0
    while True:
        start = source.find(command, cursor)
        if start == -1:
            parts.append(source[cursor:])
            return "".join(parts)
        group_start = source.find("{", start + len(command))
        if group_start == -1:
            parts.append(source[cursor:])
            return "".join(parts)
        group_end = _find_balanced_group_end(source, group_start)
        if group_end is None:
            parts.append(source[cursor:])
            return "".join(parts)
        parts.append(source[cursor:start])
        parts.append(replacement)
        cursor = group_end + 1


def _find_balanced_group_end(source: str, group_start: int) -> int | None:
    depth = 0
    escaped = False
    for index in range(group_start, len(source)):
        character = source[index]
        if escaped:
            escaped = False
            continue
        if character == "\\":
            escaped = True
            continue
        if character == "{":
            depth += 1
            continue
        if character == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def _latexml_search_paths(unpack_dir: Path, main_tex_parent: Path) -> list[Path]:
    paths: list[Path] = []
    for candidate in (_latexml_binding_dir(), unpack_dir, main_tex_parent):
        if candidate.exists() and candidate not in paths:
            paths.append(candidate)
    return paths


def _latexml_binding_dir() -> Path:
    return Path(__file__).parent / "latexml_bindings"


def _disable_latexml_incompatible_packages(source: str) -> str:
    package_pattern = re.compile(
        r"(?P<command>\\(?:usepackage|RequirePackage))"
        r"(?P<options>(?:\s*\[[^\]]*\])*)"
        r"\s*\{(?P<packages>[^{}]+)\}",
    )

    def replace(match: re.Match[str]) -> str:
        packages = [package.strip() for package in match.group("packages").split(",")]
        disabled = [package for package in packages if package in LATEXML_DISABLED_PACKAGES]
        if not disabled:
            return match.group(0)
        kept = [package for package in packages if package not in LATEXML_DISABLED_PACKAGES]
        disabled_note = ", ".join(disabled)
        if kept:
            return (
                f"{match.group('command')}{match.group('options')}"
                f"{{{','.join(kept)}}}% Bilin disabled for LaTeXML: {disabled_note}"
            )
        return f"% Bilin disabled for LaTeXML: {match.group(0)}"

    return package_pattern.sub(replace, source)


def preferred_latexml_split_level(profile: ParserProfile, main_tex: Path) -> str:
    document_class = (profile.document_class or "").casefold()
    if document_class in LATEXML_CHAPTER_SPLIT_DOCUMENT_CLASSES:
        return "chapter"
    if source_has_chapters(main_tex):
        return "chapter"
    return "section"


def should_resume_parse_from_html(errors: list[ParseErrorInfo], html_path: Path) -> bool:
    if not html_path.exists():
        return False
    return previous_failure_stage(errors) == "html_normalization"


def should_resume_parse_from_latexmlpost(errors: list[ParseErrorInfo], xml_path: Path) -> bool:
    if not xml_path.exists():
        return False
    return previous_failure_stage(errors) in {
        "latexmlpost_execution",
        "latexmlpost_split_execution",
        "html_normalization",
    }


def previous_failure_was_latexmlpost_timeout(errors: list[ParseErrorInfo]) -> bool:
    error = errors[0] if errors else None
    if error is None:
        return False
    details = error.details if isinstance(error.details, dict) else {}
    timed_out_at_latexmlpost = error.code == "latexml_timeout" and previous_failure_stage(
        errors
    ) in {
        "latexmlpost_execution",
        "latexmlpost_split_execution",
    }
    return timed_out_at_latexmlpost or details.get("single_latexmlpost_timeout") is not None


def previous_failure_stage(errors: list[ParseErrorInfo]) -> str | None:
    error = errors[0] if errors else None
    if error is None or not isinstance(error.details, dict):
        return None
    stage = error.details.get("stage")
    return stage if isinstance(stage, str) and stage else None


def should_split_latexmlpost_by_default(
    profile: ParserProfile,
    main_tex: Path,
    timeout_budget: CommandTimeoutBudget | None = None,
) -> bool:
    if preferred_latexml_split_level(profile, main_tex) == "chapter":
        return True
    if timeout_budget is not None:
        if timeout_budget.source_bytes >= LATEXML_LARGE_SOURCE_SPLIT_BYTES:
            return True
        if timeout_budget.tex_file_count >= LATEXML_LARGE_SOURCE_SPLIT_TEX_FILES:
            return True
    return source_section_count(main_tex) >= LATEXML_LARGE_SOURCE_SPLIT_SECTIONS


def source_has_chapters(main_tex: Path) -> bool:
    return source_chapter_count(main_tex) > 0


def source_chapter_count(main_tex: Path) -> int:
    sample = latex_structure_sample(main_tex)
    return len(re.findall(r"(?<!\\)\\chapter\*?\s*(?:\[[^\]]*\])?\s*\{", sample))


def source_section_count(main_tex: Path) -> int:
    sample = latex_structure_sample(main_tex)
    return len(
        re.findall(
            r"(?<!\\)\\(?:section|subsection|subsubsection)\*?\s*(?:\[[^\]]*\])?\s*\{",
            sample,
        )
    )


def latex_structure_sample(
    main_tex: Path,
    *,
    max_files: int = 64,
    max_bytes: int = 4_000_000,
) -> str:
    root = main_tex.parent.resolve()
    pending = [main_tex]
    seen: set[Path] = set()
    parts: list[str] = []
    total_bytes = 0
    while pending and len(seen) < max_files and total_bytes < max_bytes:
        path = pending.pop(0).resolve()
        if path in seen:
            continue
        try:
            if not path.is_file() or not path.is_relative_to(root):
                continue
        except ValueError:
            continue
        seen.add(path)
        try:
            remaining = max_bytes - total_bytes
            text = path.read_text(encoding="utf-8", errors="ignore")[:remaining]
        except OSError:
            continue
        total_bytes += len(text.encode("utf-8", errors="ignore"))
        parts.append(text)
        for include_name in latex_include_names(text):
            include_path = latex_include_path(include_name, path.parent, root)
            if include_path is not None and include_path not in seen:
                pending.append(include_path)
    return "\n".join(parts)


def latex_include_names(source: str) -> list[str]:
    return [
        match.group("name").strip()
        for match in re.finditer(
            r"(?<!\\)\\(?:input|include)\s*\{(?P<name>[^{}]+)\}",
            source,
        )
        if match.group("name").strip()
    ]


def latex_include_path(name: str, current_dir: Path, root: Path) -> Path | None:
    normalized = name.strip().replace("\\", "/")
    relative = Path(normalized)
    if not normalized or relative.is_absolute() or ".." in relative.parts:
        return None
    candidate = current_dir / relative
    candidates = [candidate] if candidate.suffix else [candidate, candidate.with_suffix(".tex")]
    for item in candidates:
        path = item.resolve()
        try:
            if path.is_file() and path.is_relative_to(root):
                return path
        except ValueError:
            continue
    return None


async def run_latexmlpost_split(
    command: list[str],
    *,
    cwd: Path,
    log_path: Path,
    timeout_budget: CommandTimeoutBudget,
    split_index_path: Path,
    html_path: Path,
) -> list[Path]:
    if split_index_path.parent.exists():
        shutil.rmtree(split_index_path.parent)
    split_index_path.parent.mkdir(parents=True, exist_ok=True)
    await run_command(
        command,
        cwd=cwd,
        log_path=log_path,
        timeout_budget=timeout_budget,
        activity_paths=[split_index_path.parent],
    )
    return combine_latexml_split_html(split_index_path, html_path)


def combine_latexml_split_html(split_index_path: Path, html_path: Path) -> list[Path]:
    page_paths = ordered_latexml_split_page_paths(split_index_path)
    if not page_paths and split_index_path.exists():
        page_paths = [split_index_path]
    if not page_paths:
        raise ParseFailure(
            "latexml_split_empty",
            "LaTeXML split postprocessing produced no HTML pages.",
            {"split_index_path": str(split_index_path)},
        )

    body_fragments: list[str] = []
    content_paths = (
        [split_index_path, *page_paths]
        if split_index_path.exists() and page_paths[0] != split_index_path
        else page_paths
    )
    for page_path in content_paths:
        root = parse_latexml_html(page_path)
        rewrite_latexml_split_asset_references(root, page_path, html_path)
        content = first_descendant_with_class(root, "ltx_page_content")
        if content is None:
            content = _first_descendant(root, {"body"})
        if content is None:
            content = root
        fragment = element_inner_html(content).strip()
        if fragment:
            body_fragments.append(fragment)

    if not body_fragments:
        raise ParseFailure(
            "latexml_split_empty",
            "LaTeXML split postprocessing produced no recognizable HTML body content.",
            {
                "split_index_path": str(split_index_path),
                "page_count": len(page_paths),
            },
        )

    html_path.parent.mkdir(parents=True, exist_ok=True)
    html_path.write_text(
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '<meta charset="UTF-8">\n'
        "<title>LaTeXML split document</title>\n"
        "</head>\n"
        "<body>\n"
        '<article class="ltx_document ltx_split_document">\n'
        + "\n".join(body_fragments)
        + "\n</article>\n"
        "</body>\n"
        "</html>\n",
        encoding="utf-8",
    )
    return page_paths


def mark_latexml_xml_recovery_manifest(manifest: Any, timeout_details: dict[str, Any]) -> None:
    manifest.metadata["latexmlpost_split_timeout"] = timeout_details
    manifest.metadata["latexmlpost_mode"] = LATEXML_XML_RECOVERY_MODE
    manifest.metadata["parse_fidelity"] = LATEXML_XML_RECOVERY_FIDELITY
    manifest.metadata["parse_recovery"] = {
        "stage": "latexml_xml_recovery",
        "reason": "latexmlpost_timeout",
        "fidelity": LATEXML_XML_RECOVERY_FIDELITY,
        "message": (
            "latexmlpost timed out; Bilin recovered readable document structure from LaTeXML XML."
        ),
    }


def latexml_xml_to_html(xml_path: Path, html_path: Path) -> None:
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError as exc:
        raise ParseFailure(
            "latexml_xml_recovery_failed",
            "LaTeXML XML recovery could not parse the generated XML.",
            {"xml_path": str(xml_path), "type": type(exc).__name__, "message": str(exc)},
        ) from exc
    body = latexml_xml_block_children_to_html(root, level=1)
    if not body.strip():
        raise ParseFailure(
            "latexml_xml_recovery_empty",
            "LaTeXML XML recovery produced no recognizable document content.",
            {"xml_path": str(xml_path)},
        )
    html_path.parent.mkdir(parents=True, exist_ok=True)
    html_path.write_text(
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '<meta charset="UTF-8">\n'
        "<title>LaTeXML XML recovery</title>\n"
        "</head>\n"
        "<body>\n"
        '<article class="ltx_document ltx_xml_recovery_document">\n' + body + "\n</article>\n"
        "</body>\n"
        "</html>\n",
        encoding="utf-8",
    )


def latexml_xml_block_children_to_html(element: Any, level: int) -> str:
    return "".join(latexml_xml_block_to_html(child, level) for child in list(element))


def latexml_xml_block_to_html(element: Any, level: int) -> str:
    tag = _local_name(element.tag)
    if tag in {"resource", "tags", "toccaption", "pagination", "xmath", "error"}:
        return ""
    if tag == "title":
        heading = min(max(level, 1), 6)
        return f"<h{heading}>{latexml_xml_inline_children_to_html(element)}</h{heading}>\n"
    if tag == "creator":
        text = latexml_xml_inline_children_to_html(element).strip()
        return f'<p class="ltx_creator">{text}</p>\n' if text else ""
    if tag == "abstract":
        title = escape(element.attrib.get("name") or "Abstract")
        return (
            f'<section class="ltx_abstract"><h2>{title}</h2>\n'
            + latexml_xml_block_children_to_html(element, level + 1)
            + "</section>\n"
        )
    if tag in {"part", "chapter", "section", "subsection", "subsubsection", "paragraph"}:
        if tag == "chapter" and latexml_xml_is_generated_contents_chapter(element):
            return ""
        heading_level = {
            "part": 1,
            "chapter": 1,
            "section": 2,
            "subsection": 3,
            "subsubsection": 4,
            "paragraph": 5,
        }[tag]
        return (
            f'<section class="ltx_{tag}">\n'
            + latexml_xml_block_children_to_html(element, heading_level)
            + "</section>\n"
        )
    if tag == "para":
        return latexml_xml_para_to_html(element)
    if tag == "p":
        text = latexml_xml_inline_children_to_html(element).strip()
        return f"<p>{text}</p>\n" if text else ""
    if tag in {"equation", "equationgroup"}:
        tex = _extract_math_tex(element) or latexml_xml_inline_children_to_html(element)
        tex = tex.strip()
        if not tex:
            return ""
        return latexml_xml_math_to_html(tex, display="block") + "\n"
    if tag == "math":
        tex = _extract_single_math_tex(element) or _clean_text(element)
        tex = tex.strip()
        if not tex:
            return ""
        display = "block" if element.attrib.get("mode") == "display" else "inline"
        if display == "block":
            return latexml_xml_math_to_html(tex, display="block") + "\n"
        return f"<p>{latexml_xml_math_to_html(tex, display='inline')}</p>\n"
    if tag in {"theorem", "proof", "note"}:
        return (
            f'<section class="ltx_{tag}">\n'
            + latexml_xml_block_children_to_html(element, level + 1)
            + "</section>\n"
        )
    if tag in {"itemize", "enumerate"}:
        list_tag = "ol" if tag == "enumerate" else "ul"
        items = "".join(latexml_xml_block_to_html(child, level) for child in list(element))
        return f"<{list_tag}>{items}</{list_tag}>\n" if items else ""
    if tag == "item":
        content = latexml_xml_mixed_content_to_html(element, level).strip()
        return f"<li>{content}</li>\n" if content else ""
    if tag == "bibliography":
        items = "".join(latexml_xml_block_to_html(child, level) for child in list(element))
        return f'<ul class="ltx_biblist">{items}</ul>\n' if items else ""
    if tag == "bibitem":
        content = latexml_xml_mixed_content_to_html(element, level).strip()
        return f'<li class="ltx_bibitem">{content}</li>\n' if content else ""
    if tag == "figure":
        content = latexml_xml_mixed_content_to_html(element, level).strip()
        return f"<figure>{content}</figure>\n" if content else ""
    if tag in {"caption", "toccaption"}:
        content = latexml_xml_inline_children_to_html(element).strip()
        return f"<figcaption>{content}</figcaption>\n" if content else ""
    if tag in {"tabular", "table"}:
        content = latexml_xml_mixed_content_to_html(element, level).strip()
        return f"<table>{content}</table>\n" if content else ""

    block_children = latexml_xml_block_children_to_html(element, level)
    if block_children.strip():
        return block_children
    text = latexml_xml_inline_children_to_html(element).strip()
    return f"<p>{text}</p>\n" if text else ""


def latexml_xml_is_generated_contents_chapter(element: Any) -> bool:
    title = ""
    for child in list(element):
        if _local_name(child.tag) == "title":
            title = _clean_text(child)
            break
    if title.casefold() != "contents":
        return False
    return any(_local_name(candidate.tag) == "error" for candidate in element.iter())


def latexml_xml_para_to_html(element: Any) -> str:
    block_parts: list[str] = []
    inline_parts: list[str] = []
    if element.text and element.text.strip():
        inline_parts.append(escape(element.text))
    for child in list(element):
        tag = _local_name(child.tag)
        if tag in {"p", "equation", "equationgroup"}:
            if inline_parts:
                text = "".join(inline_parts).strip()
                if text:
                    block_parts.append(f"<p>{text}</p>\n")
                inline_parts = []
            block_parts.append(latexml_xml_block_to_html(child, 1))
        else:
            inline_parts.append(latexml_xml_inline_to_html(child))
        if child.tail:
            inline_parts.append(escape(child.tail))
    if inline_parts:
        text = "".join(inline_parts).strip()
        if text:
            block_parts.append(f"<p>{text}</p>\n")
    return "".join(block_parts)


def latexml_xml_mixed_content_to_html(element: Any, level: int) -> str:
    parts: list[str] = []
    if element.text:
        parts.append(escape(element.text))
    for child in list(element):
        tag = _local_name(child.tag)
        if tag == "toccaption":
            if child.tail:
                parts.append(escape(child.tail))
            continue
        if tag in {
            "title",
            "caption",
            "para",
            "p",
            "equation",
            "equationgroup",
            "itemize",
            "enumerate",
            "figure",
            "bibliography",
        }:
            parts.append(latexml_xml_block_to_html(child, level))
        else:
            parts.append(latexml_xml_inline_to_html(child))
        if child.tail:
            parts.append(escape(child.tail))
    return "".join(parts)


def latexml_xml_inline_children_to_html(element: Any) -> str:
    parts: list[str] = []
    if element.text:
        parts.append(escape(element.text))
    for child in list(element):
        parts.append(latexml_xml_inline_to_html(child))
        if child.tail:
            parts.append(escape(child.tail))
    return "".join(parts)


def latexml_xml_inline_to_html(element: Any) -> str:
    tag = _local_name(element.tag)
    if tag in {"xmath", "tags", "tag", "resource", "pagination"}:
        return ""
    if tag == "error":
        text = _clean_text(element).strip()
        return "" if text.startswith("\\@") else escape(text)
    if tag == "break":
        return " "
    if tag == "math":
        tex = (
            _extract_single_math_tex(element) or element.attrib.get("text") or _clean_text(element)
        )
        tex = tex.strip()
        if not tex:
            return ""
        return latexml_xml_math_to_html(tex, display="inline")
    if tag in {"emph", "text"}:
        return f"<span>{latexml_xml_inline_children_to_html(element)}</span>"
    if tag in {"ref", "cite"}:
        text = latexml_xml_inline_children_to_html(element).strip() or element.attrib.get(
            "labelref"
        )
        return escape(text or "")
    return latexml_xml_inline_children_to_html(element)


def latexml_xml_math_to_html(tex: str, *, display: str) -> str:
    escaped_tex = escape(tex, quote=False)
    return (
        f'<math display="{escape(display, quote=True)}" '
        f'tex="{escape(tex, quote=True)}">{escaped_tex}</math>'
    )


def ordered_latexml_split_page_paths(split_index_path: Path) -> list[Path]:
    if not split_index_path.exists():
        return []
    try:
        root = parse_latexml_html(split_index_path)
    except Exception:
        return []

    split_dir = split_index_path.parent
    paths: list[Path] = []
    seen: set[Path] = set()

    def append_href(href: str | None) -> None:
        page_path = split_href_to_page_path(href, split_dir, split_index_path)
        if page_path is None or page_path in seen:
            return
        seen.add(page_path)
        paths.append(page_path)

    for candidate in root.iter():
        if _local_name(candidate.tag) == "a":
            append_href(candidate.attrib.get("href"))
    if not paths:
        for candidate in root.iter():
            if _local_name(candidate.tag) == "link":
                append_href(candidate.attrib.get("href"))
    if paths:
        return paths
    return sorted(path for path in split_dir.glob("*.html") if path != split_index_path)


def split_href_to_page_path(
    href: str | None,
    split_dir: Path,
    split_index_path: Path,
) -> Path | None:
    if not href:
        return None
    parsed = urlparse(href)
    if parsed.scheme or parsed.netloc:
        return None
    raw_path = unquote(parsed.path)
    if raw_path in {"", ".", "./"}:
        return None
    relative = Path(raw_path)
    if relative.is_absolute() or ".." in relative.parts:
        return None
    page_path = (split_dir / relative).resolve()
    split_root = split_dir.resolve()
    if not page_path.is_relative_to(split_root):
        return None
    if page_path == split_index_path.resolve() or page_path.suffix.casefold() != ".html":
        return None
    return page_path if page_path.exists() else None


def rewrite_latexml_split_asset_references(root: Any, page_path: Path, html_path: Path) -> None:
    split_dir = page_path.parent.resolve()
    for candidate in root.iter():
        if _local_name(candidate.tag) not in {"img", "image", "object"}:
            continue
        for key in ("src", "data", "href", "{http://www.w3.org/1999/xlink}href"):
            value = candidate.attrib.get(key)
            asset_path = split_asset_reference_path(value, split_dir)
            if asset_path is None:
                continue
            candidate.attrib[key] = Path(os.path.relpath(asset_path, html_path.parent)).as_posix()
            break


def split_asset_reference_path(reference: str | None, split_dir: Path) -> Path | None:
    if not reference:
        return None
    parsed = urlparse(reference)
    if parsed.scheme or parsed.netloc:
        return None
    raw_path = unquote(parsed.path)
    if not raw_path:
        return None
    relative = Path(raw_path)
    if relative.is_absolute() or ".." in relative.parts or relative.suffix.casefold() == ".html":
        return None
    candidate = (split_dir / relative).resolve()
    split_root = split_dir.resolve()
    if candidate.is_file() and candidate.is_relative_to(split_root):
        return candidate
    return None


def first_descendant_with_class(element: Any, class_name: str) -> Any | None:
    for candidate in element.iter():
        classes = candidate.attrib.get("class", "").split()
        if class_name in classes:
            return candidate
    return None


def element_inner_html(element: Any) -> str:
    parts: list[str] = []
    if element.text and element.text.strip():
        parts.append(escape(element.text))
    for child in list(element):
        parts.append(_element_to_html(child))
    return "".join(parts)


def estimate_latexml_timeout_budget(
    unpack_dir: Path,
    main_tex: Path,
    command_name: str,
    *,
    profile: ParserProfile | None = None,
) -> CommandTimeoutBudget:
    source_bytes = 0
    tex_file_count = 0
    graphic_file_count = 0
    for path in unpack_dir.rglob("*"):
        if not path.is_file():
            continue
        suffix = path.suffix.casefold()
        if suffix in TEX_MAIN_FILE_SUFFIXES | TEX_SIDE_FILE_SUFFIXES:
            tex_file_count += 1
            source_bytes += _safe_file_size(path)
        elif suffix in LATEX_GRAPHIC_SUFFIXES:
            graphic_file_count += 1

    source_bytes = max(source_bytes, _safe_file_size(main_tex))
    source_mib = source_bytes / 1_048_576
    document_class = (profile.document_class if profile else None) or None
    split_level = preferred_latexml_split_level(profile or ParserProfile(), main_tex)
    structure_unit_count = (
        source_chapter_count(main_tex)
        if split_level == "chapter"
        else source_section_count(main_tex)
    )
    is_book_like = split_level == "chapter"
    is_large_document = (
        is_book_like
        or source_bytes >= LATEXML_LARGE_SOURCE_SPLIT_BYTES
        or tex_file_count >= LATEXML_LARGE_SOURCE_SPLIT_TEX_FILES
        or structure_unit_count >= LATEXML_LARGE_SOURCE_SPLIT_SECTIONS
    )
    if command_name == "latexmlpost":
        estimated = (
            max(90.0, LATEXML_BASE_TIMEOUT_SECONDS * 0.55)
            + source_mib * 90.0
            + min(900.0, tex_file_count * 3.0 + graphic_file_count * 8.0)
            + structure_unit_count * (45.0 if is_book_like else 18.0)
        )
    else:
        estimated = (
            LATEXML_BASE_TIMEOUT_SECONDS
            + source_mib * 240.0
            + min(1800.0, tex_file_count * 8.0 + graphic_file_count * 15.0)
            + structure_unit_count * (90.0 if is_book_like else 30.0)
        )
    if is_book_like:
        estimated *= LATEXML_BOOK_TIMEOUT_MULTIPLIER
    soft_floor = 60.0
    hard_floor = 0.0
    if is_book_like:
        soft_floor = LATEXML_BOOK_SOFT_TIMEOUT_FLOOR_SECONDS
        hard_floor = LATEXML_BOOK_HARD_TIMEOUT_FLOOR_SECONDS
    elif is_large_document:
        soft_floor = LATEXML_LARGE_DOCUMENT_SOFT_TIMEOUT_FLOOR_SECONDS
        hard_floor = LATEXML_LARGE_DOCUMENT_HARD_TIMEOUT_FLOOR_SECONDS
    soft_seconds = max(soft_floor, min(estimated, LATEXML_MAX_TIMEOUT_SECONDS))
    hard_seconds = max(
        soft_seconds + LATEXML_IDLE_TIMEOUT_SECONDS,
        min(soft_seconds * 3.0, LATEXML_MAX_TIMEOUT_SECONDS),
        hard_floor,
    )
    hard_seconds = min(max(hard_seconds, soft_seconds), LATEXML_MAX_TIMEOUT_SECONDS)
    return CommandTimeoutBudget(
        soft_seconds=soft_seconds,
        idle_seconds=LATEXML_IDLE_TIMEOUT_SECONDS,
        hard_seconds=hard_seconds,
        source_bytes=source_bytes,
        tex_file_count=tex_file_count,
        graphic_file_count=graphic_file_count,
        structure_unit_count=structure_unit_count,
        split_level=split_level,
        document_class=document_class,
    )


def _safe_file_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


async def run_command(
    command: list[str],
    cwd: Path,
    log_path: Path,
    timeout_budget: CommandTimeoutBudget | None = None,
    activity_paths: list[Path] | None = None,
) -> None:
    budget = timeout_budget or CommandTimeoutBudget(
        soft_seconds=LATEXML_BASE_TIMEOUT_SECONDS,
        idle_seconds=LATEXML_IDLE_TIMEOUT_SECONDS,
        hard_seconds=LATEXML_MAX_TIMEOUT_SECONDS,
    )
    process = await asyncio.create_subprocess_exec(
        *command,
        cwd=str(cwd),
        env=_parser_subprocess_env(),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        start_new_session=True,
    )
    stdout_chunks: list[bytes] = []
    stderr_chunks: list[bytes] = []
    last_activity = monotonic()
    started_at = last_activity
    file_activity = _activity_file_state(activity_paths or [])

    def mark_activity() -> None:
        nonlocal last_activity
        last_activity = monotonic()

    async def read_stream(stream: asyncio.StreamReader | None, chunks: list[bytes]) -> None:
        if stream is None:
            return
        while chunk := await stream.read(8192):
            chunks.append(chunk)
            mark_activity()

    stdout_task = asyncio.create_task(read_stream(process.stdout, stdout_chunks))
    stderr_task = asyncio.create_task(read_stream(process.stderr, stderr_chunks))
    wait_task = asyncio.create_task(process.wait())
    timeout_failure: ParseFailure | None = None
    check_interval = min(1.0, max(0.05, budget.idle_seconds / 4))
    try:
        while not wait_task.done():
            await asyncio.sleep(check_interval)
            if wait_task.done():
                break
            current_file_activity = _activity_file_state(activity_paths or [])
            if current_file_activity != file_activity:
                file_activity = current_file_activity
                mark_activity()
            now = monotonic()
            elapsed = now - started_at
            idle_for = now - last_activity
            if elapsed > budget.hard_seconds:
                timeout_failure = _timeout_failure(
                    command,
                    log_path,
                    "hard",
                    elapsed,
                    idle_for,
                    budget,
                )
                await _terminate_process_tree(process)
                break
            if elapsed > budget.soft_seconds and idle_for > budget.idle_seconds:
                timeout_failure = _timeout_failure(
                    command,
                    log_path,
                    "idle",
                    elapsed,
                    idle_for,
                    budget,
                )
                await _terminate_process_tree(process)
                break
        await asyncio.gather(wait_task, return_exceptions=True)
    finally:
        await asyncio.gather(stdout_task, stderr_task, return_exceptions=True)

    stdout = b"".join(stdout_chunks)
    stderr = b"".join(stderr_chunks)
    _write_command_log(log_path, command, budget, timeout_failure, stdout, stderr)
    if timeout_failure is not None:
        raise timeout_failure
    if process.returncode != 0:
        raise ParseFailure(
            "latexml_failed",
            f"Command failed with exit code {process.returncode}: {' '.join(command)}",
            {"log_path": str(log_path), "returncode": process.returncode, "command": command},
        )


def _parser_subprocess_env() -> dict[str, str]:
    env = dict(os.environ)
    proxy_names = (
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
    )
    for name in proxy_names:
        env.pop(name, None)
    return env


def _activity_file_state(paths: list[Path]) -> tuple[tuple[str, int, int], ...]:
    state: list[tuple[str, int, int]] = []
    for path in paths:
        if path.is_dir():
            file_count = 0
            total_size = 0
            latest_mtime = 0
            try:
                descendants = path.rglob("*")
                for descendant in descendants:
                    if not descendant.is_file():
                        continue
                    stat = descendant.stat()
                    file_count += 1
                    total_size += stat.st_size
                    latest_mtime = max(latest_mtime, stat.st_mtime_ns)
            except OSError:
                continue
            state.append((str(path), file_count + total_size, latest_mtime))
            continue
        try:
            stat = path.stat()
        except OSError:
            continue
        state.append((str(path), stat.st_size, stat.st_mtime_ns))
    return tuple(state)


def _timeout_failure(
    command: list[str],
    log_path: Path,
    reason: str,
    elapsed_seconds: float,
    idle_seconds: float,
    budget: CommandTimeoutBudget,
) -> ParseFailure:
    return ParseFailure(
        "latexml_timeout",
        (
            f"Command timed out by {reason} limit after {elapsed_seconds:.1f}s "
            f"(idle {idle_seconds:.1f}s): {' '.join(command)}"
        ),
        {
            "log_path": str(log_path),
            "command": command,
            "timeout_reason": reason,
            "elapsed_seconds": round(elapsed_seconds, 3),
            "idle_seconds": round(idle_seconds, 3),
            "timeout_budget": asdict(budget),
        },
    )


async def _terminate_process_tree(process: asyncio.subprocess.Process) -> None:
    if not _has_posix_process_group_kill():
        if _is_windows_platform() and _run_windows_taskkill(process.pid):
            try:
                await asyncio.wait_for(process.wait(), timeout=5)
                return
            except TimeoutError:
                pass
        await _terminate_direct_process(process)
        return

    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        process.terminate()
    try:
        await asyncio.wait_for(process.wait(), timeout=5)
        return
    except TimeoutError:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    except OSError:
        process.kill()
    await process.wait()


async def _terminate_direct_process(process: asyncio.subprocess.Process) -> None:
    try:
        process.terminate()
    except ProcessLookupError:
        return
    try:
        await asyncio.wait_for(process.wait(), timeout=5)
        return
    except TimeoutError:
        pass
    try:
        process.kill()
    except ProcessLookupError:
        return
    await process.wait()


def _has_posix_process_group_kill() -> bool:
    return hasattr(os, "killpg")


def _is_windows_platform() -> bool:
    return os.name == "nt"


def _run_windows_taskkill(pid: int) -> bool:
    try:
        completed = subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(pid)],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return completed.returncode == 0


def _write_command_log(
    log_path: Path,
    command: list[str],
    budget: CommandTimeoutBudget,
    timeout_failure: ParseFailure | None,
    stdout: bytes,
    stderr: bytes,
) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    header = {
        "command": command,
        "timeout_budget": asdict(budget),
        "timeout_error": timeout_failure.details if timeout_failure else None,
    }
    log_path.write_bytes(
        json.dumps(header, indent=2, sort_keys=True).encode("utf-8")
        + b"\n--- STDOUT ---\n"
        + stdout
        + b"\n--- STDERR ---\n"
        + stderr
    )


def normalize_latexml_html(
    html_path: Path,
    revision_id: str,
    bundle_path: Path | None = None,
    source_root: Path | None = None,
) -> tuple[list[DocumentBlock], list[AssetRecord]]:
    root = parse_latexml_html(html_path)
    _hydrate_missing_graphics_from_latexml_xml(root, html_path.with_suffix(".xml"))
    body = _first_descendant(root, {"body"})
    if body is None:
        body = root
    builder = _DocumentBuilder(
        revision_id,
        html_path=html_path,
        bundle_path=bundle_path,
        source_root=source_root,
    )
    builder.walk(body)
    if not builder.blocks:
        raise ParseFailure("empty_document", "LaTeXML produced no recognizable document blocks.")
    return builder.blocks, builder.assets


def parse_latexml_html(html_path: Path) -> Any:
    try:
        return ET.parse(html_path).getroot()
    except ET.ParseError:
        parser = _HtmlTreeParser()
        parser.feed(html_path.read_text(encoding="utf-8", errors="replace"))
        parser.close()
        return parser.root


def _hydrate_missing_graphics_from_latexml_xml(root: Any, xml_path: Path) -> None:
    graphic_records = _latexml_graphics_index(xml_path)
    if not graphic_records:
        return
    for candidate in root.iter():
        tag = _local_name(candidate.tag)
        if tag not in {"img", "image", "object"}:
            continue
        if _image_reference(candidate):
            continue
        identifier = _element_identifier(candidate)
        if not identifier:
            continue
        record = graphic_records.get(identifier)
        if not record:
            continue
        candidate.attrib["src"] = record.reference
        if record.display_width_pt is not None:
            _merge_width_style(candidate, record.display_width_pt)


class _LatexmlGraphicRecord:
    def __init__(self, reference: str, display_width_pt: float | None) -> None:
        self.reference = reference
        self.display_width_pt = display_width_pt


def _latexml_graphics_index(xml_path: Path) -> dict[str, _LatexmlGraphicRecord]:
    if not xml_path.exists():
        return {}
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError:
        return {}
    records: dict[str, _LatexmlGraphicRecord] = {}
    for candidate in root.iter():
        if _local_name(candidate.tag) != "graphics":
            continue
        identifier = _element_identifier(candidate)
        reference = _latexml_graphic_reference(candidate)
        if not identifier or not reference:
            continue
        records[identifier] = _LatexmlGraphicRecord(
            reference=reference,
            display_width_pt=_graphics_option_width_pt(candidate.attrib.get("options")),
        )
    return records


def _latexml_graphic_reference(element: Any) -> str | None:
    for key in ("graphic", "candidates"):
        value = element.attrib.get(key)
        if not value:
            continue
        reference = value.split()[0].strip()
        if reference:
            return reference.removeprefix("./")
    return None


def _graphics_option_width_pt(options: str | None) -> float | None:
    if not options:
        return None
    match = re.search(r"(?:^|,)\s*width\s*=\s*([0-9.]+)\s*pt\b", options)
    if not match:
        return None
    value = float(match.group(1))
    return value if value > 0 else None


def _element_identifier(element: Any) -> str | None:
    for key in ("id", "xml:id", "{http://www.w3.org/XML/1998/namespace}id"):
        value = element.attrib.get(key)
        if value:
            return value
    return None


def _image_reference(element: Any) -> str | None:
    for key in ("src", "data", "href", "{http://www.w3.org/1999/xlink}href"):
        value = element.attrib.get(key)
        if value:
            return value.strip()
    return None


def _merge_width_style(element: Any, width_pt: float) -> None:
    style = element.attrib.get("style", "").strip()
    width_style = f"width:{width_pt:g}pt;"
    if re.search(r"\bwidth\s*:", style, flags=re.IGNORECASE):
        return
    element.attrib["style"] = f"{style.rstrip(';')};{width_style}" if style else width_style


class HtmlElement:
    def __init__(self, tag: str, attrib: dict[str, str] | None = None) -> None:
        self.tag = tag
        self.attrib = attrib or {}
        self.text: str | None = None
        self.tail: str | None = None
        self.children: list[HtmlElement] = []

    def __iter__(self):
        return iter(self.children)

    def append(self, child: HtmlElement) -> None:
        self.children.append(child)

    def iter(self):
        yield self
        for child in self.children:
            yield from child.iter()

    def itertext(self):
        if self.text:
            yield self.text
        for child in self.children:
            yield from child.itertext()
            if child.tail:
                yield child.tail

    def to_html(self, include_tail: bool = False) -> str:
        attrs = "".join(
            f' {escape(key, quote=True)}="{escape(value, quote=True)}"'
            for key, value in sorted(self.attrib.items())
        )
        text = escape(self.text or "", quote=False)
        children = "".join(child.to_html(include_tail=True) for child in self.children)
        if self.tag in HTML_VOID_TAGS and not text and not children:
            rendered = f"<{self.tag}{attrs}>"
        else:
            rendered = f"<{self.tag}{attrs}>{text}{children}</{self.tag}>"
        if include_tail and self.tail:
            rendered += escape(self.tail, quote=False)
        return rendered


class _HtmlTreeParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.root = HtmlElement("document")
        self.stack: list[HtmlElement] = [self.root]

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        element = HtmlElement(
            tag.lower(),
            {key.lower(): value or "" for key, value in attrs},
        )
        self.stack[-1].append(element)
        if element.tag == "br":
            element.tail = " "
        if element.tag not in HTML_VOID_TAGS:
            self.stack.append(element)

    def handle_startendtag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        self.stack[-1].append(
            HtmlElement(
                tag.lower(),
                {key.lower(): value or "" for key, value in attrs},
            )
        )

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                return

    def handle_data(self, data: str) -> None:
        self._append_text(data)

    def handle_entityref(self, name: str) -> None:
        self._append_text(unescape(f"&{name};"))

    def handle_charref(self, name: str) -> None:
        self._append_text(unescape(f"&#{name};"))

    def _append_text(self, data: str) -> None:
        if not data:
            return
        current = self.stack[-1]
        if current.children:
            last_child = current.children[-1]
            last_child.tail = (last_child.tail or "") + data
        else:
            current.text = (current.text or "") + data


def render_source_markdown(blocks: list[DocumentBlock]) -> str:
    lines: list[str] = []
    for block in blocks:
        if block.block_type == "section":
            level = int(block.metadata.get("level", 2))
            lines.extend([f"{'#' * min(max(level, 1), 6)} {block.source_markdown}", ""])
        elif block.block_type == "equation":
            lines.extend(["$$", block.source_markdown, "$$", ""])
        else:
            lines.extend([block.source_markdown, ""])
    return "\n".join(lines).strip() + "\n"


class _DocumentBuilder:
    def __init__(
        self,
        revision_id: str,
        html_path: Path,
        bundle_path: Path | None = None,
        source_root: Path | None = None,
    ) -> None:
        self.revision_id = revision_id
        self.html_path = html_path
        self.bundle_path = bundle_path
        self.source_root = source_root
        self.blocks: list[DocumentBlock] = []
        self.assets: list[AssetRecord] = []
        self.section_count = 0
        self.paragraph_count = 0
        self.equation_count = 0
        self.figure_count = 0
        self.table_count = 0
        self.algorithm_count = 0
        self.list_count = 0

    def walk(self, element: ET.Element) -> None:
        tag = _local_name(element.tag)
        if _is_latexml_generated_navigation(element):
            return
        if _is_algorithm_container(element):
            self.add_environment(element, "algorithm")
            return
        if _is_latexml_bibliography_list(element):
            self.add_bibliography_list(element)
            return
        if _is_latexml_bibliography_item(element):
            self.add_bibliography_item(element)
            return
        if _is_latexml_list_container(element):
            self.add_list(element)
            return
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self.add_section(element, tag)
            return
        if tag == "p":
            text = _markdown_text(element)
            if text:
                self.paragraph_count += 1
                if not _is_latexml_metadata_only_paragraph(text):
                    references = _references(element)
                    self.add_block(
                        "paragraph",
                        f"p-{self.paragraph_count:04d}",
                        text,
                        metadata={"references": references} if references else None,
                    )
            return
        if tag == "math" and element.attrib.get("display") == "block":
            self.add_equation(element)
            return
        if tag == "figure" and _is_equation_container(element):
            self.add_equation(element)
            return
        if tag == "figure":
            self.add_environment(element, _latexml_environment_kind(element))
            return
        if tag == "table" and _is_equation_container(element):
            self.add_equation(element)
            return
        if tag == "table":
            self.add_environment(element, "table")
            return
        for child in list(element):
            self.walk(child)

    def add_section(self, element: ET.Element, tag: str) -> None:
        text = _clean_text(element)
        if not text:
            return
        self.section_count += 1
        level = int(tag[1])
        self.add_block(
            "section",
            f"sec-{self.section_count:03d}",
            text,
            metadata={"level": level, "label": _label(element)},
        )

    def add_equation(self, element: ET.Element) -> None:
        tex = _extract_math_tex(element) or _clean_text(element)
        if not tex:
            return
        self.equation_count += 1
        equation_numbers = _equation_numbers(element)
        metadata: dict[str, Any] = {
            "label": _label(element),
            "display": "block",
            "tex": tex,
            "html_fragment": _html_fragment(element),
        }
        if equation_numbers:
            metadata["equation_number"] = equation_numbers[0]
            metadata["equation_numbers"] = equation_numbers
        self.add_block(
            "equation",
            f"eq-{self.equation_count:04d}",
            tex,
            source_latex=tex,
            metadata=metadata,
        )

    def add_environment(self, element: ET.Element, kind: str) -> None:
        if kind == "figure":
            self.figure_count += 1
            index = self.figure_count
            prefix = "fig"
        elif kind == "algorithm":
            self.algorithm_count += 1
            index = self.algorithm_count
            prefix = "alg"
        else:
            self.table_count += 1
            index = self.table_count
            prefix = "tbl"
        caption = _caption_text(element) or _clean_text(element) or f"{kind.title()} {index}"
        label = _label(element)
        asset_id = f"{prefix}-{index:04d}"
        source_path, web_path, asset_metadata = self.copy_environment_assets(element, asset_id)
        html_fragment = _html_fragment(element)
        if html_fragment:
            asset_metadata["html_fragment"] = html_fragment
        self.assets.append(
            make_asset(
                self.revision_id,
                asset_id=asset_id,
                kind=kind,
                caption=caption,
                label=label,
                source_path=source_path,
                web_path=web_path,
                metadata=asset_metadata,
            )
        )
        self.add_block(
            kind,
            asset_id,
            f"**{kind.title()} {index}.** {caption}",
            metadata={
                "label": label,
                "asset_id": asset_id,
                "html_fragment": html_fragment,
                "asset_source": source_path,
            },
        )

    def add_list(self, element: ET.Element) -> None:
        markdown, item_count = _list_markdown(element)
        if not markdown:
            return
        self.list_count += 1
        references = _references(element)
        self.add_block(
            "list",
            f"lst-{self.list_count:04d}",
            markdown,
            metadata={
                "list_kind": _list_kind(element),
                "item_count": item_count,
                **({"references": references} if references else {}),
            },
        )

    def add_bibliography_list(self, element: ET.Element) -> None:
        items = _direct_bibliography_items(element)
        lines = [
            f"- {markdown}" for item in items if (markdown := _bibliography_item_markdown(item))
        ]
        if not lines:
            return
        self.list_count += 1
        references = _references(element)
        bibliography_ids = [item_id for item in items if (item_id := item.attrib.get("id"))]
        self.add_block(
            "list",
            f"lst-{self.list_count:04d}",
            "\n".join(lines),
            metadata={
                "list_kind": "bibliography",
                "item_count": len(lines),
                "bibliography_ids": bibliography_ids,
                **({"references": references} if references else {}),
            },
        )

    def add_bibliography_item(self, element: ET.Element) -> None:
        markdown = _bibliography_item_markdown(element)
        if not markdown:
            return
        self.list_count += 1
        references = _references(element)
        self.add_block(
            "list",
            f"lst-{self.list_count:04d}",
            f"- {markdown}",
            metadata={
                "list_kind": "bibliography",
                "item_count": 1,
                **(
                    {"bibliography_ids": [element.attrib["id"]]} if element.attrib.get("id") else {}
                ),
                **({"references": references} if references else {}),
            },
        )

    def copy_environment_assets(
        self,
        element: ET.Element,
        asset_id: str,
    ) -> tuple[str | None, str | None, dict[str, Any]]:
        references = _asset_references(element)
        metadata: dict[str, Any] = _environment_image_layout_metadata(element, len(references))
        file_layout_metadata = _environment_image_file_layout_metadata(element, references)
        if not references:
            generated_kind = _code_generated_asset_kind(element)
            if generated_kind:
                metadata["asset_resolution"] = "requires_controlled_render"
                metadata["generated_asset_kind"] = generated_kind
                metadata["render_tools"] = {
                    "tectonic": bool(shutil.which("tectonic")),
                    "pdflatex": bool(shutil.which("pdflatex")),
                    "magick": bool(shutil.which("magick")),
                }
            return None, None, metadata
        if self.bundle_path is None:
            metadata["original_reference"] = references[0]
            if len(references) > 1:
                metadata["original_references"] = references
            resolved_asset_files = []
            resolved_primary_source_path: Path | None = None
            for index, reference in enumerate(references, start=1):
                source_path = _resolve_local_asset_reference(
                    reference,
                    html_path=self.html_path,
                    source_root=self.source_root,
                )
                resolved_file_metadata: dict[str, Any] = {
                    "original_reference": reference,
                    "index": index,
                }
                if index - 1 < len(file_layout_metadata):
                    resolved_file_metadata.update(file_layout_metadata[index - 1])
                if source_path is None:
                    resolved_file_metadata["asset_resolution"] = "missing"
                else:
                    resolved_file_metadata["asset_resolution"] = "resolved"
                    resolved_file_metadata["source_path"] = str(source_path)
                    if resolved_primary_source_path is None:
                        resolved_primary_source_path = source_path
                resolved_asset_files.append(resolved_file_metadata)
            metadata["asset_files"] = resolved_asset_files
            metadata["asset_resolution"] = "resolved" if resolved_primary_source_path else "missing"
            source_path_text = (
                str(resolved_primary_source_path) if resolved_primary_source_path else None
            )
            return source_path_text, None, metadata
        assets_dir = self.bundle_path / "assets"
        assets_dir.mkdir(parents=True, exist_ok=True)
        asset_files: list[dict[str, Any]] = []
        primary_source_path: Path | None = None
        primary_web_path: Path | None = None
        for index, reference in enumerate(references, start=1):
            source_path = _resolve_local_asset_reference(
                reference,
                html_path=self.html_path,
                source_root=self.source_root,
            )
            file_metadata: dict[str, Any] = {"original_reference": reference, "index": index}
            if index - 1 < len(file_layout_metadata):
                file_metadata.update(file_layout_metadata[index - 1])
            if source_path is None:
                file_metadata["asset_resolution"] = "missing"
                asset_files.append(file_metadata)
                continue
            file_asset_id = asset_id if index == 1 else f"{asset_id}-{index}"
            web_path = prepare_web_asset(source_path, assets_dir, file_asset_id, file_metadata)
            asset_files.append(
                {
                    **file_metadata,
                    "source_path": str(source_path),
                    "web_path": str(web_path) if web_path else None,
                }
            )
            if primary_source_path is None:
                primary_source_path = source_path
                primary_web_path = web_path
        metadata["original_reference"] = references[0]
        if len(references) > 1:
            metadata["original_references"] = references
        metadata["asset_files"] = asset_files
        if primary_source_path is None:
            metadata["asset_resolution"] = "missing"
            return None, None, metadata
        primary_file = next(
            (item for item in asset_files if item.get("source_path") == str(primary_source_path)),
            asset_files[0],
        )
        metadata.update(
            {
                key: value
                for key, value in primary_file.items()
                if key not in {"index", "source_path", "web_path"}
            }
        )
        web_path_text = str(primary_web_path) if primary_web_path else None
        return str(primary_source_path), web_path_text, metadata

    def add_block(
        self,
        block_type: str,
        local_uid: str,
        source_markdown: str,
        source_latex: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        structural_path = f"{len(self.blocks) + 1:05d}"
        self.blocks.append(
            make_block(
                self.revision_id,
                block_uid=local_uid,
                structural_path=structural_path,
                block_type=block_type,
                source_markdown=source_markdown,
                source_latex=source_latex,
                metadata=metadata,
            )
        )


def _is_safe_member(name: str) -> bool:
    path = Path(name)
    return not path.is_absolute() and ".." not in path.parts


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def _clean_text(element: Any) -> str:
    return " ".join("".join(element.itertext()).split())


def _is_latexml_metadata_only_paragraph(value: str) -> bool:
    normalized = _collapse_markdown_whitespace(value)
    groups = re.findall(r"\[\s*([^\[\]]+)\s*\]", normalized)
    if not groups:
        return False
    remainder = re.sub(r"\[\s*[^\[\]]+\s*\]", "", normalized).strip()
    return not remainder and all(_is_layout_author_metadata_option(group) for group in groups)


def _markdown_text(element: Any, *, preserve_blocks: bool = False) -> str:
    html = _prepare_latexml_html_for_markdown(
        _clean_latexml_html_fragment(_element_to_html(element))
    )
    markdown = convert(html, options=MARKDOWN_CONVERSION_OPTIONS)
    if preserve_blocks:
        return _clean_latexml_markdown_artifacts(
            _compact_markdown_block(markdown),
            preserve_blocks=True,
        )
    return _clean_latexml_markdown_artifacts(_collapse_markdown_whitespace(markdown))


def _markdown_text_inner(element: Any) -> str:
    parts: list[str] = [element.text or ""]
    for child in list(element):
        tag = _local_name(child.tag)
        child_text = _markdown_text_inner(child)
        if _is_citation_element(child):
            parts.append(_citation_markdown_text(child))
        elif tag == "a":
            parts.append(_markdown_link_text(child, child_text))
        elif tag == "br":
            parts.append(" ")
        elif tag == "math":
            math_text = _extract_math_tex(child)
            parts.append(_inline_math_markdown(math_text) if math_text else _clean_text(child))
        else:
            parts.append(child_text)
        parts.append(child.tail or "")
    return "".join(parts)


def _collapse_markdown_whitespace(text: str) -> str:
    normalized = " ".join(text.split())
    return normalized.replace(" ]", "]").replace("[ ", "[").replace(" )", ")").replace("( ", "(")


def _markdown_link_text(element: Any, child_text: str) -> str:
    href = element.attrib.get("href")
    if not href or not child_text.strip():
        return child_text
    label = _collapse_markdown_whitespace(child_text)
    if label.startswith("[") and label.endswith("]"):
        label = label[1:-1]
    if _is_bibliography_href(href):
        label = _compact_citation_label(label)
    return f"[{label}]({href})"


def _is_bibliography_href(href: str) -> bool:
    return href.startswith("#bib.") or href.startswith("#bib:")


def _is_citation_element(element: Any) -> bool:
    class_name = str(element.attrib.get("class", "")).lower()
    return _local_name(element.tag) == "cite" or "ltx_cite" in class_name


def _citation_markdown_text(element: Any) -> str:
    parts: list[str] = [_citation_wrapper_text(element.text or "")]
    for child in list(element):
        tag = _local_name(child.tag)
        child_text = _markdown_text_inner(child)
        if _is_citation_element(child):
            parts.append(_citation_markdown_text(child))
        elif tag == "a":
            parts.append(_markdown_link_text(child, child_text))
        else:
            parts.append(child_text)
        parts.append(_citation_wrapper_text(child.tail or ""))
    return _clean_latexml_markdown_artifacts("".join(parts))


def _citation_wrapper_text(value: str) -> str:
    return value.replace("[", "").replace("]", "")


def _inline_math_markdown(value: str) -> str:
    escaped = value.replace("$", r"\$")
    return f"${escaped}$"


def _clean_latexml_markdown_artifacts(value: str, *, preserve_blocks: bool = False) -> str:
    cleaned = _strip_undefined_citeauthor(value)
    cleaned = _expand_markdown_autolinks(cleaned)
    cleaned = _link_bare_urls(cleaned)
    cleaned = re.sub(
        r"\[([^\]]*?\(\d{4}[a-z]?\)[^\]]*?)\]\((#bib\.[^)]+)\)",
        lambda match: f"[{_compact_citation_label(match.group(1))}]({match.group(2)})",
        cleaned,
    )
    if preserve_blocks:
        cleaned = re.sub(r"[ \t]+([,.;:])", r"\1", cleaned)
        cleaned = "\n".join(
            re.sub(r"(?<=\S)[ \t]{2,}", " ", line).rstrip() for line in cleaned.splitlines()
        )
        return cleaned.strip()
    cleaned = re.sub(r"\s+([,.;:])", r"\1", cleaned)
    cleaned = re.sub(r"\s{2,}", " ", cleaned)
    return cleaned.strip()


def _strip_undefined_citeauthor(value: str) -> str:
    cleaned = re.sub(
        r"\\citeauthor\*?(?:\s*\[[^\]]*\])*\s*\{?[\w:./-]+\}?\s*",
        "",
        value,
    )
    return re.sub(
        r"\b(?P<key>[A-Za-z0-9][\w:./-]*[0-9][\w:./-]*)\s+\[(?P=key)\]",
        r"[\g<key>]",
        cleaned,
    )


def _expand_markdown_autolinks(value: str) -> str:
    return re.sub(
        r"<(https?://[^<>\s]+)>",
        lambda match: f"[{match.group(1)}]({match.group(1)})",
        value,
    )


def _link_bare_urls(value: str) -> str:
    protected_links: list[str] = []

    def stash_link(match: re.Match[str]) -> str:
        protected_links.append(match.group(0))
        return f"\u0000BILIN_LINK_{len(protected_links) - 1}\u0000"

    protected = re.sub(r"\[[^\]]+\]\(https?://[^)\s]+\)", stash_link, value)

    def replace(match: re.Match[str]) -> str:
        url = match.group(0)
        trailing = ""
        while url and url[-1] in ".,;:":
            trailing = url[-1] + trailing
            url = url[:-1]
        return f"[{url}]({url}){trailing}" if url else match.group(0)

    linked = re.sub(r"(?<!\]\()https?://[^\s<>)\]]+", replace, protected)
    for index, link in enumerate(protected_links):
        linked = linked.replace(f"\u0000BILIN_LINK_{index}\u0000", link)
    return linked


def _compact_citation_label(label: str) -> str:
    normalized = _collapse_markdown_whitespace(label.replace("\xa0", " "))
    if re.fullmatch(r"\d+[a-z]?", normalized):
        return normalized
    match = re.match(r"(.+?\(\d{4}[a-z]?\))", normalized)
    if match:
        normalized = match.group(1)
    normalized = re.sub(r"\s*\((\d{4}[a-z]?)\)", r" (\1)", normalized)
    return normalized


def _compact_markdown_block(markdown: str) -> str:
    lines = [line.rstrip() for line in markdown.replace("\r\n", "\n").split("\n")]
    compacted: list[str] = []
    previous_blank = False
    for line in lines:
        is_blank = not line.strip()
        if is_blank:
            previous_blank = True
            continue
        if previous_blank and compacted and not _is_markdown_list_line(line):
            compacted.append("")
        compacted.append(line)
        previous_blank = False
    return "\n".join(compacted).strip()


def _is_markdown_list_line(line: str) -> bool:
    return bool(re.match(r"^\s*(?:[-+*]|\d+[.)])\s+", line))


def _prepare_latexml_html_for_markdown(html: str) -> str:
    without_markers = re.sub(
        r"<span\b(?=[^>]*\bclass=(?P<quote>['\"])[^'\"]*"
        r"(?:ltx_tag_item|ltx_itemmarker|ltx_tag_note)[^'\"]*(?P=quote))[^>]*>.*?</span>",
        "",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )
    without_note_marks = re.sub(
        r"<(?P<tag>span|sup)\b(?=[^>]*\bclass=(?P<quote>['\"])[^'\"]*"
        r"ltx_note_mark[^'\"]*(?P=quote))[^>]*>.*?</(?P=tag)>",
        "",
        without_markers,
        flags=re.IGNORECASE | re.DOTALL,
    )
    without_footnote_wrappers = _inline_latexml_footnotes(without_note_marks)
    normalized_missing_citations = _normalize_missing_latexml_citations(without_footnote_wrappers)
    without_cite_brackets = re.sub(
        r"(<cite\b[^>]*>)\s*\[",
        r"\1",
        normalized_missing_citations,
        flags=re.IGNORECASE,
    )
    without_cite_brackets = re.sub(
        r"\]\s*(</cite>)",
        r"\1",
        without_cite_brackets,
        flags=re.IGNORECASE,
    )
    without_link_brackets = re.sub(
        r"(<a\b[^>]*>)\s*\[([^\]]+)\]\s*(</a>)",
        r"\1\2\3",
        without_cite_brackets,
        flags=re.IGNORECASE | re.DOTALL,
    )
    return re.sub(
        r"<math\b(?P<attrs>[^>]*)>(?P<body>.*?)</math>",
        _math_html_to_markdown,
        without_link_brackets,
        flags=re.IGNORECASE | re.DOTALL,
    )


def _normalize_missing_latexml_citations(html: str) -> str:
    cite_pattern = re.compile(
        r"<cite\b(?P<attrs>[^>]*)>(?P<body>.*?)</cite>",
        flags=re.IGNORECASE | re.DOTALL,
    )

    def replace(match: re.Match[str]) -> str:
        body = match.group("body")
        if re.search(r"<a\b[^>]*\bhref=(?P<quote>['\"])#bib[.:]", body, re.IGNORECASE):
            return match.group(0)
        if not re.search(r"\bltx_missing_citation\b|\bltx_ref_self\b", body):
            return match.group(0)
        label = _missing_latexml_citation_label(body)
        if not label:
            return match.group(0)
        return f"[{escape(label, quote=False)}]"

    return cite_pattern.sub(replace, html)


def _missing_latexml_citation_label(body: str) -> str:
    text = re.sub(r"<[^>]+>", "", body)
    return humanize_missing_citation_text(unescape(text))


def _inline_latexml_footnotes(html: str) -> str:
    footnote_pattern = re.compile(
        r"<span\b(?=[^>]*\bclass=(?P<quote1>['\"])[^'\"]*"
        r"ltx_note[^'\"]*ltx_role_footnote[^'\"]*(?P=quote1))[^>]*>\s*"
        r"<span\b(?=[^>]*\bclass=(?P<quote2>['\"])[^'\"]*"
        r"ltx_note_outer[^'\"]*(?P=quote2))[^>]*>\s*"
        r"<span\b(?=[^>]*\bclass=(?P<quote3>['\"])[^'\"]*"
        r"ltx_note_content[^'\"]*(?P=quote3))[^>]*>"
        r"(?P<content>.*?)</span>\s*</span>\s*</span>",
        flags=re.IGNORECASE | re.DOTALL,
    )

    def replace(match: re.Match[str]) -> str:
        content = re.sub(r"\s+", " ", match.group("content")).strip()
        content = content.removesuffix(".").strip()
        return f" ({content})" if content else ""

    return footnote_pattern.sub(replace, html)


def _math_html_to_markdown(match: re.Match[str]) -> str:
    attrs = match.group("attrs")
    display = _html_attr(attrs, "display") == "block"
    alttext = _html_attr(attrs, "alttext") or _html_attr(attrs, "tex")
    tex = _normalize_math_tex(unescape(alttext)) if alttext else ""
    if not tex:
        body = match.group("body")
        annotation = re.search(
            r"<annotation\b[^>]*\bencoding=(?P<quote>['\"])[^'\"]*tex[^'\"]*(?P=quote)[^>]*>"
            r"(?P<tex>.*?)</annotation>",
            body,
            flags=re.IGNORECASE | re.DOTALL,
        )
        tex = _normalize_math_tex(unescape(annotation.group("tex"))) if annotation else ""
    if not tex:
        return ""
    markdown_tex = _escape_math_tex_for_markdown_html(tex)
    return f"\n\n$$\n{markdown_tex}\n$$\n\n" if display else f"${markdown_tex}$"


def _escape_math_tex_for_markdown_html(tex: str) -> str:
    escaped = escape(tex.replace("$", r"\$"), quote=False)
    return escaped


def _html_attr(attrs: str, name: str) -> str | None:
    match = re.search(
        rf"\b{re.escape(name)}\s*=\s*(?P<quote>['\"])(?P<value>.*?)(?P=quote)",
        attrs,
        flags=re.IGNORECASE | re.DOTALL,
    )
    return match.group("value") if match else None


def _is_latexml_list_container(element: Any) -> bool:
    tag = _local_name(element.tag)
    class_name = element.attrib.get("class", "").lower()
    if "ltx_biblist" in class_name:
        return False
    if tag in {"ul", "ol", "dl"}:
        return True
    return any(token in class_name for token in ("ltx_itemize", "ltx_enumerate", "ltx_description"))


def _is_latexml_bibliography_list(element: Any) -> bool:
    tag = _local_name(element.tag)
    class_name = element.attrib.get("class", "").lower()
    return tag in {"ul", "ol", "dl"} and "ltx_biblist" in class_name


def _is_latexml_bibliography_item(element: Any) -> bool:
    tag = _local_name(element.tag)
    class_name = element.attrib.get("class", "").lower()
    return tag == "li" and "ltx_bibitem" in class_name


def _is_latexml_generated_navigation(element: Any) -> bool:
    tag = _local_name(element.tag)
    class_name = element.attrib.get("class", "").lower()
    if tag not in {"nav", "div", "section", "ol", "ul"}:
        return False
    return any(
        token in class_name
        for token in (
            "ltx_toc",
            "ltx_toclist",
            "ltx_list_toc",
            "ltx_list_lot",
            "ltx_list_lof",
        )
    )


def _is_latexml_list_item(element: Any) -> bool:
    tag = _local_name(element.tag)
    class_name = element.attrib.get("class", "").lower()
    if "ltx_bibitem" in class_name:
        return False
    return tag in {"li", "dt", "dd"} or "ltx_item" in class_name.split()


def _direct_bibliography_items(element: Any) -> list[Any]:
    return [child for child in list(element) if _is_latexml_bibliography_item(child)]


def _bibliography_item_markdown(element: Any) -> str:
    parts: list[str] = []
    if element.text and element.text.strip():
        parts.append(element.text)
    for child in list(element):
        if _is_latexml_bibliography_label(child):
            if child.tail and child.tail.strip():
                parts.append(child.tail)
            continue
        text = _markdown_text(child)
        if text:
            parts.append(text)
        if child.tail and child.tail.strip():
            parts.append(child.tail)
    content = _clean_latexml_markdown_artifacts(_collapse_markdown_whitespace(" ".join(parts)))
    if not content:
        return ""
    label = _bibliography_item_label(element)
    item_id = element.attrib.get("id")
    if not label or not item_id:
        return content
    escaped_label = label.replace("[", r"\[").replace("]", r"\]")
    return f"[\\[{escaped_label}\\]](#{item_id}) {content}".strip()


def _is_latexml_bibliography_label(element: Any) -> bool:
    class_name = element.attrib.get("class", "").lower()
    return "ltx_tag_bibitem" in class_name


def _bibliography_item_label(element: Any) -> str:
    for child in element.iter():
        if not _is_latexml_bibliography_label(child):
            continue
        return _clean_text(child).strip().strip("[]")
    return ""


def _is_latexml_list_marker(element: Any) -> bool:
    class_name = element.attrib.get("class", "").lower()
    return "ltx_tag_item" in class_name or "ltx_itemmarker" in class_name


def _list_kind(element: Any) -> str:
    tag = _local_name(element.tag)
    class_name = element.attrib.get("class", "").lower()
    if tag == "ol" or "ltx_enumerate" in class_name:
        return "ordered"
    if tag == "dl" or "ltx_description" in class_name:
        return "description"
    return "unordered"


def _list_markdown(element: Any) -> tuple[str, int]:
    item_count = len(_direct_list_items(element))
    return _markdown_text(element, preserve_blocks=True), item_count


def _list_markdown_lines(element: Any, depth: int = 0) -> list[str]:
    lines: list[str] = []
    kind = _list_kind(element)
    for index, item in enumerate(_direct_list_items(element), start=1):
        content = _list_item_content_markdown(item)
        indent = "  " * depth
        prefix = f"{index}. " if kind == "ordered" else "- "
        if kind == "description":
            prefix = "- "
        if content:
            lines.append(f"{indent}{prefix}{content}")
        else:
            lines.append(f"{indent}{prefix}".rstrip())
        for nested in _direct_child_lists(item):
            lines.extend(_list_markdown_lines(nested, depth + 1))
    return lines


def _direct_list_items(element: Any) -> list[Any]:
    return [child for child in list(element) if _is_latexml_list_item(child)]


def _direct_child_lists(element: Any) -> list[Any]:
    return [child for child in list(element) if _is_latexml_list_container(child)]


def _list_item_content_markdown(element: Any) -> str:
    parts: list[str] = []
    if element.text and element.text.strip():
        parts.append(element.text)
    for child in list(element):
        if _is_latexml_list_container(child) or _is_latexml_list_marker(child):
            if child.tail and child.tail.strip():
                parts.append(child.tail)
            continue
        text = _markdown_text(child)
        if text:
            parts.append(text)
        if child.tail and child.tail.strip():
            parts.append(child.tail)
    return _clean_latexml_markdown_artifacts(_collapse_markdown_whitespace(" ".join(parts)))


def _first_descendant(element: Any, tags: set[str]) -> Any | None:
    for candidate in element.iter():
        if _local_name(candidate.tag) in tags:
            return candidate
    return None


def _caption_text(element: Any) -> str | None:
    for candidate in element.iter():
        tag = _local_name(candidate.tag)
        class_name = candidate.attrib.get("class", "")
        if tag in {"figcaption", "caption"} or "caption" in class_name.lower():
            text = _markdown_text(candidate)
            if text:
                return _strip_caption_markdown_decorations(_strip_latexml_caption_tag(text))
    return None


def _latexml_environment_kind(element: Any) -> str:
    if _is_algorithm_container(element):
        return "algorithm"
    if _is_table_figure(element):
        return "table"
    caption_kind = _caption_tag_kind(element)
    if caption_kind in {"figure", "table", "algorithm"}:
        return caption_kind
    return "table" if _is_table_figure(element) else "figure"


def _caption_tag_kind(element: Any) -> str | None:
    for candidate in element.iter():
        class_name = candidate.attrib.get("class", "").lower()
        if "ltx_tag_algorithm" in class_name:
            return "algorithm"
        if "ltx_tag_table" in class_name:
            return "table"
        if "ltx_tag_figure" in class_name:
            return "figure"
    text = _caption_text_without_tag_stripping(element)
    if text and re.match(r"^\s*table\s+\d+", text, flags=re.IGNORECASE):
        return "table"
    if text and re.match(r"^\s*algorithm\s+\d+", text, flags=re.IGNORECASE):
        return "algorithm"
    if text and re.match(r"^\s*figure\s+\d+", text, flags=re.IGNORECASE):
        return "figure"
    return None


def _caption_text_without_tag_stripping(element: Any) -> str | None:
    for candidate in element.iter():
        tag = _local_name(candidate.tag)
        class_name = candidate.attrib.get("class", "")
        if tag in {"figcaption", "caption"} or "caption" in class_name.lower():
            text = _markdown_text(candidate)
            if text:
                return text
    return None


def _strip_latexml_caption_tag(text: str) -> str:
    return re.sub(
        r"^\s*(?:figure|fig\.|table|algorithm|alg\.)\s+\d+[.:]\s*",
        "",
        text,
        flags=re.IGNORECASE,
    )


def _strip_caption_markdown_decorations(text: str) -> str:
    stripped = text.strip()
    for marker in ("**", "*", "__", "_"):
        if (
            stripped.startswith(marker)
            and stripped.endswith(marker)
            and len(stripped) > len(marker) * 2
        ):
            return stripped[len(marker) : -len(marker)].strip()
    return stripped


def _is_table_figure(element: Any) -> bool:
    class_name = element.attrib.get("class", "").lower()
    return "ltx_table" in class_name


def _is_algorithm_container(element: Any) -> bool:
    tag = _local_name(element.tag)
    if tag not in {"figure", "table", "div"}:
        return False
    class_name = element.attrib.get("class", "").lower()
    if (
        "ltx_algorithm" in class_name
        or "ltx_float_algorithm" in class_name
        or "algorithm" in class_name.split()
    ):
        return True
    caption = _direct_caption_text_without_tag_stripping(element)
    return bool(caption and re.match(r"^\s*algorithm\s+\d+", caption, flags=re.IGNORECASE))


def _is_equation_container(element: Any) -> bool:
    class_name = element.attrib.get("class", "").lower()
    equation_classes = (
        "ltx_equation",
        "ltx_equationgroup",
        "ltx_eqn_table",
        "ltx_eqn_align",
    )
    if any(token in class_name for token in equation_classes):
        return True
    for child in element.iter():
        if child is element:
            continue
        child_class = child.attrib.get("class", "").lower()
        if any(token in child_class for token in equation_classes):
            return True
    return False


def _direct_caption_text_without_tag_stripping(element: Any) -> str | None:
    for child in list(element):
        tag = _local_name(child.tag)
        class_name = child.attrib.get("class", "")
        if tag in {"figcaption", "caption"} or "caption" in class_name.lower():
            text = _markdown_text(child)
            if text:
                return text
    return None


def _extract_math_tex(element: Any) -> str | None:
    if _local_name(element.tag) == "math":
        return _extract_single_math_tex(element)
    rows = _extract_math_rows(element)
    if rows:
        if len(rows) == 1 and len(rows[0]) == 1:
            return rows[0][0]
        formatted_rows = [" ".join(_deduplicate_latex_values(row)) for row in rows]
        formatted_rows = _deduplicate_latex_values(formatted_rows)
        return "\\begin{aligned}\n" + " \\\\\n".join(formatted_rows) + "\n\\end{aligned}"
    values = [_extract_single_math_tex(candidate) for candidate in element.iter()]
    values = [value for value in values if value]
    if values:
        return " ".join(_deduplicate_latex_values(values))
    return None


def _extract_math_rows(element: Any) -> list[list[str]]:
    rows: list[list[str]] = []
    for row in element.iter():
        if _local_name(row.tag) != "tr":
            continue
        row_values = [
            value
            for value in (_extract_single_math_tex(candidate) for candidate in row.iter())
            if value
        ]
        row_values = _deduplicate_latex_values(row_values)
        if row_values:
            rows.append(row_values)
    if rows:
        return rows
    value = _extract_single_math_tex(element)
    return [[value]] if value else []


def _deduplicate_latex_values(values: list[str]) -> list[str]:
    deduplicated: list[str] = []
    previous_key = ""
    for value in values:
        key = _latex_value_key(value)
        if not key or key == previous_key:
            previous_key = key
            continue
        deduplicated.append(value)
        previous_key = key
    if len(deduplicated) % 2 == 0 and deduplicated:
        midpoint = len(deduplicated) // 2
        left = [_latex_value_key(value) for value in deduplicated[:midpoint]]
        right = [_latex_value_key(value) for value in deduplicated[midpoint:]]
        if left == right:
            return deduplicated[:midpoint]
    return deduplicated


def _latex_value_key(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _extract_single_math_tex(element: Any) -> str | None:
    if _local_name(element.tag) != "math":
        return None
    for candidate in element.iter():
        if _local_name(candidate.tag) == "annotation":
            encoding = candidate.attrib.get("encoding", "")
            if "tex" in encoding.lower():
                text = _normalize_math_tex(_clean_text(candidate))
                if text:
                    return text
    alttext = element.attrib.get("alttext") or element.attrib.get("tex")
    return _normalize_math_tex(alttext) if alttext else None


def _normalize_math_tex(value: str) -> str:
    normalized = value.replace("%\r\n", "").replace("%\n", "").replace("\\displaystyle", "")
    normalized = _normalize_legacy_text_font_commands(normalized)
    normalized = _apply_latex_command_group_rules(normalized)
    normalized = _replace_latex_command_group(
        normalized,
        "pmatrix",
        lambda body: rf"\begin{{pmatrix}}{body}\end{{pmatrix}}",
    )
    normalized = _replace_latex_command_group(
        normalized,
        "textsc",
        lambda body: rf"\text{{{body.upper()}}}",
    )
    normalized = _replace_latex_command_group(normalized, "mbox", _normalize_mbox_command)
    normalized = _strip_raisebox_wrappers(normalized)
    normalized = re.sub(r"\\coloneqq\b", ":=", normalized)
    normalized = re.sub(r"\\eqqcolon\b", r"\\mathrel{=:}", normalized)
    normalized = re.sub(
        r"\\buildrel\s*\{([^{}]+)\}\s*\\over\s*\{([^{}]+)\}",
        r"\\overset{\1}{\2}",
        normalized,
    )
    normalized = re.sub(
        r"\\expectationvalue\s*\{((?:[^{}]|\{[^{}]*\})+)\}",
        r"\\left\\langle \1 \\right\\rangle",
        normalized,
    )
    normalized = re.sub(
        r"(\\begin\{(?:[pbvVB]?matrix|smallmatrix|matrix)\})\s*\[[^\]]+\]",
        r"\1",
        normalized,
    )
    normalized = re.sub(r"(\\begin\{array\})\s*\[\]\s*(\{[^}]+\})", r"\1\2", normalized)
    normalized = re.sub(
        r"\\begin\{(?:split|eqnarray\*?|IEEEeqnarray\*?)\}", r"\\begin{aligned}", normalized
    )
    normalized = re.sub(
        r"\\end\{(?:split|eqnarray\*?|IEEEeqnarray\*?)\}", r"\\end{aligned}", normalized
    )
    normalized = re.sub(r"\\begin\{(?:equation|equation\*)\}", "", normalized)
    normalized = re.sub(r"\\end\{(?:equation|equation\*)\}", "", normalized)
    normalized = re.sub(
        r"\\(big|Big|bigg|Bigg)([lrm]?)\s*\{\s*(\\?[{}()[\]|.])\s*\}",
        r"\\\1\2\3",
        normalized,
    )
    normalized = re.sub(r"\{\\rm\s+([^{}]+)\}", r"\\mathrm{\1}", normalized)
    normalized = re.sub(r"\\mspace\s*\{[^{}]*\}", "", normalized)
    normalized = re.sub(r"\\strut\b", "", normalized)
    normalized = re.sub(r"\\xspace\b|\\protect\b", "", normalized)
    normalized = re.sub(r"\\(?:label|vref|pageref|autoref|cref|Cref)\s*\{[^{}]*\}", "", normalized)
    normalized = re.sub(r"\\eqref\s*\{[^{}]*\}", r"(\text{?})", normalized)
    normalized = re.sub(r"\\ref\s*\{[^{}]*\}", r"\text{?}", normalized)
    normalized = re.sub(r"\\iddots\b", r"\\ddots", normalized)
    normalized = re.sub(r"\\hline\s*\\cr\s*(?:\\\\\s*(?:\[[^\]]+\])?)?", r"\\\\", normalized)
    normalized = re.sub(r"\\(?:cline|cmidrule)\s*(?:\[[^\]]+\])?\s*\{[^{}]*\}", "", normalized)
    normalized = re.sub(r"\\vline\b", "|", normalized)
    normalized = re.sub(r"\\hfill\b|\\dotfill\b|\\hrulefill\b", "", normalized)
    normalized = re.sub(r"\\\\\s*\[[^\]]+\]", r"\\\\", normalized)
    normalized = normalized.replace("\\cr", r"\\")
    normalized = re.sub(r"\\(?:no)?pagebreak\s*(?:\[[^\]]+\])?", "", normalized)
    normalized = re.sub(r"\\(?:linebreak|break)\s*(?:\[[^\]]+\])?", "", normalized)
    normalized = re.sub(r"\\\\\s*\\\\", r"\\\\", normalized)
    return normalized.strip()


def _apply_latex_command_group_rules(value: str) -> str:
    normalized = value
    for rule in LATEX_COMPATIBILITY_COMMAND_GROUP_RULES:
        group_count = int(rule["group_count"])
        for command in rule["commands"]:
            normalized = _replace_latex_command_groups(
                normalized,
                command,
                group_count,
                lambda groups, rule=rule: _render_latex_command_rule(rule, groups),
            )
    if LATEX_COMPATIBILITY_SINGLE_TOKEN_COMMANDS:
        commands = "|".join(
            re.escape(command) for command in LATEX_COMPATIBILITY_SINGLE_TOKEN_COMMANDS
        )
        normalized = re.sub(
            rf"\\(?:{commands})\s+([A-Za-z0-9])",
            r"\\mathbb{\1}",
            normalized,
        )
    return normalized


def _render_latex_command_rule(rule: dict[str, Any], groups: list[str]) -> str:
    strategy = rule["strategy"]
    if strategy == "template":
        return _render_latex_template(rule["replacement"], groups)
    if strategy == "unwrap":
        return groups[0]
    if strategy == "keep_arg":
        return groups[int(rule["keep_arg_index"])]
    return "\\" + str(rule["commands"][0]) + "".join(f"{{{group}}}" for group in groups)


def _render_latex_template(template: str, groups: list[str]) -> str:
    rendered = template
    for index, group in enumerate(groups, start=1):
        rendered = rendered.replace(f"#{index}", group)
    return rendered


def _normalize_legacy_text_font_commands(value: str) -> str:
    def replace_text(match: re.Match[str]) -> str:
        text_command = LEGACY_TEXT_FONT_COMMANDS[match.group("command")][0]
        return rf"\{text_command}{{{match.group('body').strip()}}}"

    def replace_group(match: re.Match[str]) -> str:
        math_command = LEGACY_TEXT_FONT_COMMANDS[match.group("command")][1]
        return rf"\{math_command}{{{match.group('body').strip()}}}"

    normalized = re.sub(
        r"\\text\{\s*\\(?P<command>bf|it|rm|sf|sl|tt)\s+(?P<body>[^{}]+)\}",
        replace_text,
        value,
    )
    return re.sub(
        r"\{\\(?P<command>bf|it|rm|sf|sl|tt)\s+(?P<body>[^{}]+)\}",
        replace_group,
        normalized,
    )


def _replace_latex_command_group(
    value: str,
    command: str,
    replace: Any,
) -> str:
    marker = f"\\{command}"
    parts: list[str] = []
    index = 0
    while index < len(value):
        if value.startswith(marker, index) and not _is_latex_command_char(
            value[index + len(marker) : index + len(marker) + 1]
        ):
            group_start = _skip_spaces(value, index + len(marker))
            parsed = _read_latex_braced_group(value, group_start)
            if parsed is not None:
                body, end = parsed
                parts.append(replace(body))
                index = end
                continue
        parts.append(value[index])
        index += 1
    return "".join(parts)


def _replace_latex_command_groups(
    value: str,
    command: str,
    group_count: int,
    replace: Any,
) -> str:
    marker = f"\\{command}"
    parts: list[str] = []
    index = 0
    while index < len(value):
        if value.startswith(marker, index) and not _is_latex_command_char(
            value[index + len(marker) : index + len(marker) + 1]
        ):
            cursor = _skip_spaces(value, index + len(marker))
            groups: list[str] = []
            for _ in range(group_count):
                parsed = _read_latex_braced_group(value, cursor)
                if parsed is None:
                    break
                groups.append(parsed[0])
                cursor = _skip_spaces(value, parsed[1])
            if len(groups) == group_count:
                parts.append(replace(groups))
                index = cursor
                continue
        parts.append(value[index])
        index += 1
    return "".join(parts)


def _strip_raisebox_wrappers(value: str) -> str:
    marker = "\\raisebox"
    parts: list[str] = []
    index = 0
    while index < len(value):
        if value.startswith(marker, index) and not _is_latex_command_char(
            value[index + len(marker) : index + len(marker) + 1]
        ):
            cursor = _skip_spaces(value, index + len(marker))
            height = _read_latex_braced_group(value, cursor)
            if height is not None:
                cursor = _skip_optional_latex_groups(value, height[1])
                body = _read_latex_braced_group(value, cursor)
                if body is not None:
                    parts.append(_strip_math_delimiters(body[0]))
                    index = body[1]
                    continue
        parts.append(value[index])
        index += 1
    return "".join(parts)


def _normalize_mbox_command(body: str) -> str:
    if not body:
        return ""
    segments = _split_latex_dollar_segments(body)
    rendered: list[str] = []
    for text, is_math in segments:
        if not text:
            continue
        if is_math:
            rendered.append(text)
        else:
            rendered.append(rf"\text{{{text}}}")
    return "".join(rendered)


def _split_latex_dollar_segments(value: str) -> list[tuple[str, bool]]:
    segments: list[tuple[str, bool]] = []
    start = 0
    in_math = False
    index = 0
    while index < len(value):
        if value[index] == "$" and (index == 0 or value[index - 1] != "\\"):
            segments.append((value[start:index], in_math))
            in_math = not in_math
            start = index + 1
        index += 1
    segments.append((value[start:], in_math))
    return segments


def _strip_math_delimiters(value: str) -> str:
    stripped = value.strip()
    if stripped.startswith("$") and stripped.endswith("$") and len(stripped) >= 2:
        return stripped[1:-1]
    return stripped


def _read_latex_braced_group(value: str, open_index: int) -> tuple[str, int] | None:
    if open_index >= len(value) or value[open_index] != "{":
        return None
    depth = 0
    index = open_index
    while index < len(value):
        char = value[index]
        if char == "\\":
            index += 2
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return value[open_index + 1 : index], index + 1
        index += 1
    return None


def _skip_optional_latex_groups(value: str, index: int) -> int:
    cursor = _skip_spaces(value, index)
    while cursor < len(value) and value[cursor] == "[":
        end = value.find("]", cursor + 1)
        if end < 0:
            return cursor
        cursor = _skip_spaces(value, end + 1)
    return cursor


def _skip_spaces(value: str, index: int) -> int:
    while index < len(value) and value[index].isspace():
        index += 1
    return index


def _is_latex_command_char(value: str) -> bool:
    return bool(value) and (value[0].isalpha() or value[0] == "@")


def _asset_references(element: Any) -> list[str]:
    references: list[str] = []
    for candidate in element.iter():
        tag = _local_name(candidate.tag)
        if tag in {"img", "image", "object"}:
            for key in ("src", "data", "href", "{http://www.w3.org/1999/xlink}href"):
                value = candidate.attrib.get(key)
                if value:
                    references.append(value.strip())
                    break
    return references


def _environment_image_layout_metadata(element: Any, reference_count: int) -> dict[str, Any]:
    image_records = _image_element_records(element)
    panel_widths = _image_panel_widths_pt(element) or _style_widths_pt(element)
    image_count = max(reference_count, len(image_records))
    metadata: dict[str, Any] = {}
    first_image = image_records[0] if image_records else {}
    first_width = _numeric_dict_value(first_image, "width")
    first_height = _numeric_dict_value(first_image, "height")
    max_panel_width = max(panel_widths) if panel_widths else None
    total_panel_width = sum(panel_widths) if panel_widths else None
    has_flex_layout = _has_latexml_flex_layout(element)
    display_width = total_panel_width if image_count > 1 and has_flex_layout else max_panel_width
    if display_width is None and first_width is not None:
        display_width = first_width

    if image_count:
        metadata["image_count"] = image_count
    if first_width is not None:
        metadata["image_width"] = first_width
        metadata["width"] = first_width
    if first_height is not None:
        metadata["image_height"] = first_height
        metadata["height"] = first_height
    if max_panel_width is not None:
        metadata["max_panel_width_pt"] = round(max_panel_width, 3)
    if total_panel_width is not None:
        metadata["total_panel_width_pt"] = round(total_panel_width, 3)
    if display_width is not None:
        metadata["display_width_pt"] = round(display_width, 3)
    if has_flex_layout:
        metadata["has_flex_layout"] = True
    article_layout = _article_layout_from_image_metrics(
        image_count=image_count,
        has_flex_layout=has_flex_layout,
        max_panel_width_pt=max_panel_width,
        width=first_width,
        height=first_height,
    )
    if article_layout:
        metadata["article_layout"] = article_layout
    return metadata


def _environment_image_file_layout_metadata(
    element: Any,
    references: list[str],
) -> list[dict[str, Any]]:
    if not references:
        return []
    image_records = _image_element_records(element)
    panel_widths = _image_panel_widths_pt(element) or _style_widths_pt(element)
    parent_metadata = _environment_image_layout_metadata(element, len(references))
    parent_layout = parent_metadata.get("article_layout")
    records: list[dict[str, Any]] = []
    for index, reference in enumerate(references):
        image_record = image_records[index] if index < len(image_records) else {}
        panel_width = panel_widths[index] if index < len(panel_widths) else None
        file_metadata: dict[str, Any] = {}
        width = _numeric_dict_value(image_record, "width")
        height = _numeric_dict_value(image_record, "height")
        if width is not None:
            file_metadata["width"] = width
            file_metadata["image_width"] = width
        if height is not None:
            file_metadata["height"] = height
            file_metadata["image_height"] = height
        if panel_width is not None:
            file_metadata["panel_width_pt"] = round(panel_width, 3)
            file_metadata["display_width_pt"] = round(panel_width, 3)
            file_metadata["max_panel_width_pt"] = round(panel_width, 3)
        group_width = parent_metadata.get("total_panel_width_pt") or parent_metadata.get(
            "display_width_pt"
        )
        if isinstance(group_width, (int, float)) and group_width > 0:
            file_metadata["subfigure_group_width_pt"] = round(float(group_width), 3)
            file_metadata["subfigure_count"] = len(references)
        if isinstance(parent_layout, str):
            file_metadata["article_layout"] = parent_layout
        if image_record.get("reference") == reference:
            file_metadata["layout_reference_matched"] = True
        return_reference = image_record.get("reference")
        if isinstance(return_reference, str) and return_reference != reference:
            file_metadata["layout_reference"] = return_reference
        records.append(file_metadata)
    return records


def _image_element_records(element: Any) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for candidate in element.iter():
        tag = _local_name(candidate.tag)
        if tag not in {"img", "image", "object"}:
            continue
        reference = None
        for key in ("src", "data", "href", "{http://www.w3.org/1999/xlink}href"):
            value = candidate.attrib.get(key)
            if value:
                reference = value.strip()
                break
        record: dict[str, Any] = {}
        width = _numeric_attribute(candidate, "width")
        height = _numeric_attribute(candidate, "height")
        if reference:
            record["reference"] = reference
        if width is not None:
            record["width"] = width
        if height is not None:
            record["height"] = height
        records.append(record)
    return records


def _style_widths_pt(element: Any) -> list[float]:
    widths: list[float] = []
    for candidate in element.iter():
        value = _style_width_pt(candidate.attrib.get("style"))
        if value is not None:
            widths.append(value)
    return widths


def _image_panel_widths_pt(element: Any) -> list[float]:
    widths: list[float] = []

    def visit(candidate: Any, inherited_width: float | None) -> None:
        own_width = _style_width_pt(candidate.attrib.get("style"))
        panel_width = own_width if own_width is not None else inherited_width
        tag = _local_name(candidate.tag)
        if tag in {"img", "image", "object"}:
            if panel_width is not None:
                widths.append(panel_width)
            return
        for child in list(candidate):
            visit(child, panel_width)

    visit(element, None)
    return widths


def _style_width_pt(style: str | None) -> float | None:
    if not style:
        return None
    match = re.search(r"\bwidth\s*:\s*([0-9.]+)\s*pt\b", style, flags=re.IGNORECASE)
    if not match:
        return None
    value = float(match.group(1))
    return value if value > 0 else None


def _has_latexml_flex_layout(element: Any) -> bool:
    for candidate in element.iter():
        class_name = candidate.attrib.get("class", "").lower()
        if re.search(r"\bltx_flex_(?:figure|cell|size_)", class_name):
            return True
    return False


def _article_layout_from_image_metrics(
    *,
    image_count: int,
    has_flex_layout: bool,
    max_panel_width_pt: float | None,
    width: float | None,
    height: float | None,
) -> str | None:
    if image_count > 1 or has_flex_layout:
        return "multi-panel"
    if max_panel_width_pt is not None:
        return "double-column" if max_panel_width_pt >= 330 else "single-column"
    if width and height and width / height >= 1.45:
        return "double-column"
    return None


def _numeric_attribute(element: Any, attribute: str) -> float | None:
    value = element.attrib.get(attribute)
    if not value:
        return None
    match = re.match(r"\s*([0-9.]+)", value)
    if not match:
        return None
    parsed = float(match.group(1))
    return parsed if parsed > 0 else None


def _numeric_dict_value(record: dict[str, Any], key: str) -> float | None:
    value = record.get(key)
    return float(value) if isinstance(value, (int, float)) and value > 0 else None


def _code_generated_asset_kind(element: Any) -> str | None:
    haystack_parts: list[str] = []
    for candidate in element.iter():
        for key in ("class", "data-bilin-render", "data-render-kind", "alttext"):
            value = candidate.attrib.get(key)
            if value:
                haystack_parts.append(value)
    haystack_parts.append(_clean_text(element))
    haystack = " ".join(haystack_parts).lower()
    if "pgfplots" in haystack or "axis}" in haystack:
        return "pgfplots"
    if "tikz" in haystack:
        return "tikz"
    if "pstricks" in haystack or "pspicture" in haystack:
        return "pstricks"
    return None


def _resolve_local_asset_reference(
    reference: str,
    html_path: Path,
    source_root: Path | None,
) -> Path | None:
    parsed = urlparse(reference)
    if parsed.scheme or parsed.netloc:
        return None
    raw_path = unquote(parsed.path)
    if not raw_path:
        return None
    relative = Path(raw_path)
    roots = [html_path.parent.resolve()]
    if source_root is not None:
        roots.append(source_root.resolve())
    if relative.is_absolute():
        candidates = _asset_reference_candidates(relative)
    elif ".." in relative.parts:
        return None
    else:
        candidates = []
        for root in roots:
            candidates.extend(_asset_reference_candidates(root / relative))
    for candidate in candidates:
        if candidate.is_file() and any(candidate.is_relative_to(root) for root in roots):
            return candidate
    return None


def _asset_reference_candidates(path: Path) -> list[Path]:
    candidates = [path.resolve()]
    if path.suffix:
        return candidates
    for suffix in LATEX_GRAPHIC_SUFFIXES:
        candidates.append(path.with_suffix(suffix).resolve())
    return candidates


def prepare_web_asset(
    source_path: Path,
    assets_dir: Path,
    asset_id: str,
    metadata: dict[str, Any],
) -> Path | None:
    suffix = source_path.suffix.lower()
    if suffix in WEB_ASSET_SUFFIXES:
        web_path = assets_dir / f"{asset_id}{suffix}"
        shutil.copy2(source_path, web_path)
        metadata["asset_resolution"] = "copied"
        metadata["web_asset_kind"] = suffix.lstrip(".")
        return web_path
    if suffix in CONVERTIBLE_ASSET_SUFFIXES:
        return convert_asset_to_png(source_path, assets_dir / f"{asset_id}.png", metadata)
    web_path = assets_dir / f"{asset_id}{suffix or '.asset'}"
    shutil.copy2(source_path, web_path)
    metadata["asset_resolution"] = "copied_unclassified"
    metadata["web_asset_kind"] = suffix.lstrip(".") if suffix else "unknown"
    return web_path


def convert_asset_to_png(
    source_path: Path,
    output_path: Path,
    metadata: dict[str, Any],
) -> Path | None:
    magick = shutil.which("magick")
    gs = shutil.which("gs")
    if not magick:
        metadata["asset_resolution"] = "missing_dependency"
        metadata["missing_tool"] = "magick"
        metadata["desired_output"] = str(output_path)
        return None
    if not gs:
        metadata["asset_resolution"] = "missing_dependency"
        metadata["missing_tool"] = "gs"
        metadata["desired_output"] = str(output_path)
        return None
    command = [magick, "-density", "180", f"{source_path}[0]", "-quality", "92", str(output_path)]
    metadata["converter_command"] = command
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        metadata["asset_resolution"] = "conversion_failed"
        metadata["conversion_error"] = str(exc)
        return None
    if completed.returncode != 0:
        metadata["asset_resolution"] = "conversion_failed"
        metadata["conversion_returncode"] = completed.returncode
        metadata["conversion_stderr"] = completed.stderr[-1000:]
        return None
    if not output_path.exists():
        metadata["asset_resolution"] = "conversion_failed"
        metadata["conversion_error"] = "Converter completed without producing output."
        return None
    metadata["asset_resolution"] = "converted"
    metadata["web_asset_kind"] = "png"
    return output_path


def _references(element: ET.Element) -> list[dict[str, str]]:
    references: list[dict[str, str]] = []
    for candidate in element.iter():
        if _local_name(candidate.tag) != "a":
            continue
        href = candidate.attrib.get("href")
        text = _clean_text(candidate)
        if href:
            references.append({"href": href, "text": text})
    return references


def _html_fragment(element: Any) -> str:
    html = _element_to_html(element)
    return _clean_latexml_html_fragment(html)


def _element_to_html(element: Any) -> str:
    if isinstance(element, HtmlElement):
        return element.to_html()
    return ET.tostring(element, encoding="unicode", method="html")


def _clean_latexml_html_fragment(html: str) -> str:
    cleaned = re.sub(
        r"<tr\b[^>]*>\s*(?:<t[dh]\b[^>]*>\s*(?:<span\b[^>]*>\s*)?"
        r"\\(?:toprule|midrule|bottomrule|cmidrule)(?:\s*\{[^}]*\}|\s*\([^)]*\)|\s*\[[^\]]*\])?"
        r"\s*(?:</span>)?\s*</t[dh]>\s*)+</tr>",
        "",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )
    cleaned = re.sub(
        r"(?:<span\b[^>]*>\s*)?\\(?:toprule|midrule|bottomrule|cmidrule)"
        r"(?:\s*\{[^}]*\}|\s*\([^)]*\)|\s*\[[^\]]*\])?\s*(?:</span>)?",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )
    return cleaned


def _label(element: ET.Element) -> str | None:
    for key in ("id", "label"):
        value = element.attrib.get(key)
        if value:
            return value
    return None


def _equation_numbers(element: ET.Element) -> list[str]:
    numbers: list[str] = []
    for candidate in element.iter():
        class_name = candidate.attrib.get("class", "").lower()
        classes = class_name.split()
        if "ltx_eqn_eqno" not in classes and "ltx_tag_equation" not in classes:
            continue
        text = _clean_text(candidate)
        if text and text not in numbers:
            numbers.append(text)
    return numbers


def _find_source_archive(bundle_path: Path) -> Path:
    original = bundle_path / "original"
    for candidate in (original / "source.tar", original / "source.zip", original / "source.gz"):
        if candidate.exists():
            return candidate
    matches = sorted(original.glob("source.*"))
    if matches:
        return matches[0]
    raise ParseFailure("missing_source_archive", "No source archive found in article bundle.")
