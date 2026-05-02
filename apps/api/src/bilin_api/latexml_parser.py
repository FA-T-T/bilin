from __future__ import annotations

import asyncio
import gzip
import json
import shutil
import subprocess
import tarfile
import xml.etree.ElementTree as ET
import zipfile
from html import escape, unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

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
from bilin_api.doctor import detect_version
from bilin_api.schemas import AssetRecord, DocumentBlock, Library, ParseErrorInfo

WEB_ASSET_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
CONVERTIBLE_ASSET_SUFFIXES = {".pdf", ".eps"}
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


class ParseFailure(Exception):
    def __init__(self, code: str, message: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}

    def to_error_info(self) -> ParseErrorInfo:
        return ParseErrorInfo(code=self.code, message=self.message, details=self.details)


async def parse_article_revision(library: Library, revision_id: str) -> dict[str, Any]:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        msg = f"Article revision not found: {revision_id}"
        raise ParseFailure("not_found:article_revision", msg)
    bundle_path = Path(revision.bundle_path)
    manifest = read_manifest(bundle_path) or empty_manifest(revision)
    manifest.parse_status = "running"
    manifest.errors = []
    write_manifest(bundle_path, manifest)
    await mark_revision_status(library, revision.id, "parsing")

    try:
        source_archive = _find_source_archive(bundle_path)
        unpack_dir = bundle_path / "source" / "unpacked"
        safe_unpack(source_archive, unpack_dir)
        main_tex = find_main_tex(unpack_dir)
        manifest.main_tex_file = str(main_tex.relative_to(unpack_dir))

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

        document_dir = bundle_path / "document"
        logs_dir = bundle_path / "logs"
        document_dir.mkdir(parents=True, exist_ok=True)
        logs_dir.mkdir(parents=True, exist_ok=True)
        xml_path = document_dir / "latexml.xml"
        html_path = document_dir / "latexml.html"
        latexml_command = [latexml, "--destination", str(xml_path), main_tex.name]
        latexmlpost_command = [latexmlpost, "--destination", str(html_path), str(xml_path)]
        manifest.latexml_command = latexml_command + ["&&"] + latexmlpost_command
        manifest.tool_versions = {
            "latexml": detect_version(latexml),
            "latexmlpost": detect_version(latexmlpost),
        }

        await run_command(latexml_command, cwd=main_tex.parent, log_path=logs_dir / "latexml.log")
        await run_command(
            latexmlpost_command,
            cwd=main_tex.parent,
            log_path=logs_dir / "latexmlpost.log",
        )
        blocks, assets = normalize_latexml_html(
            html_path,
            revision.id,
            bundle_path=bundle_path,
            source_root=unpack_dir,
        )
        source_md = render_source_markdown(blocks)
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
        manifest.parse_status = "failed"
        manifest.errors = [exc.to_error_info()]
        error_log = write_parse_failure_log(bundle_path, exc)
        manifest.generated_artifacts["parse_error_log"] = str(error_log)
        await mark_revision_status(library, revision.id, "parse_failed", manifest)
        raise
    except Exception as exc:
        failure = ParseFailure("parse_failed", str(exc), {"type": type(exc).__name__})
        manifest.parse_status = "failed"
        manifest.errors = [failure.to_error_info()]
        error_log = write_parse_failure_log(bundle_path, failure)
        manifest.generated_artifacts["parse_error_log"] = str(error_log)
        await mark_revision_status(library, revision.id, "parse_failed", manifest)
        raise failure from exc


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
    candidates = sorted(unpack_dir.rglob("*.tex"))
    if not candidates:
        raise ParseFailure("missing_main_tex", "No .tex file found in source package.")
    scored: list[tuple[int, Path]] = []
    for candidate in candidates:
        text = candidate.read_text(encoding="utf-8", errors="ignore")
        score = 0
        if "\\documentclass" in text:
            score += 10
        if "\\begin{document}" in text:
            score += 10
        if candidate.name.lower() in {"main.tex", "paper.tex", "article.tex", "ms.tex"}:
            score += 2
        scored.append((score, candidate))
    scored.sort(key=lambda item: (-item[0], len(str(item[1]))))
    if scored[0][0] < 20:
        raise ParseFailure(
            "missing_main_tex",
            "Could not identify a main TeX file with documentclass and begin{document}.",
        )
    return scored[0][1]


async def run_command(command: list[str], cwd: Path, log_path: Path) -> None:
    process = await asyncio.create_subprocess_exec(
        *command,
        cwd=str(cwd),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=120)
    log_path.write_bytes(stdout + b"\n--- STDERR ---\n" + stderr)
    if process.returncode != 0:
        raise ParseFailure(
            "latexml_failed",
            f"Command failed with exit code {process.returncode}: {' '.join(command)}",
            {"log_path": str(log_path), "returncode": process.returncode},
        )


def normalize_latexml_html(
    html_path: Path,
    revision_id: str,
    bundle_path: Path | None = None,
    source_root: Path | None = None,
) -> tuple[list[DocumentBlock], list[AssetRecord]]:
    root = parse_latexml_html(html_path)
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

    def walk(self, element: ET.Element) -> None:
        tag = _local_name(element.tag)
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self.add_section(element, tag)
            return
        if tag == "p":
            text = _markdown_text(element)
            if text:
                self.paragraph_count += 1
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
        if tag == "figure":
            self.add_environment(element, "table" if _is_table_figure(element) else "figure")
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
        self.add_block(
            "equation",
            f"eq-{self.equation_count:04d}",
            tex,
            source_latex=tex,
            metadata={
                "label": _label(element),
                "display": "block",
                "tex": tex,
                "html_fragment": _html_fragment(element),
            },
        )

    def add_environment(self, element: ET.Element, kind: str) -> None:
        if kind == "figure":
            self.figure_count += 1
            index = self.figure_count
            prefix = "fig"
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

    def copy_environment_assets(
        self,
        element: ET.Element,
        asset_id: str,
    ) -> tuple[str | None, str | None, dict[str, Any]]:
        references = _asset_references(element)
        metadata: dict[str, Any] = {}
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


def _markdown_text(element: Any) -> str:
    return _collapse_markdown_whitespace(_markdown_text_inner(element))


def _markdown_text_inner(element: Any) -> str:
    parts: list[str] = [element.text or ""]
    for child in list(element):
        tag = _local_name(child.tag)
        child_text = _markdown_text_inner(child)
        if tag == "a":
            href = child.attrib.get("href")
            if href and child_text.strip():
                label = _collapse_markdown_whitespace(child_text)
                if label.startswith("[") and label.endswith("]"):
                    label = label[1:-1]
                parts.append(f"[{label}]({href})")
            else:
                parts.append(child_text)
        elif tag == "br":
            parts.append(" ")
        elif tag == "math":
            parts.append(_extract_math_tex(child) or _clean_text(child))
        else:
            parts.append(child_text)
        parts.append(child.tail or "")
    return "".join(parts)


def _collapse_markdown_whitespace(text: str) -> str:
    normalized = " ".join(text.split())
    return normalized.replace(" ]", "]").replace("[ ", "[").replace(" )", ")").replace("( ", "(")


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
                return text
    return None


def _is_table_figure(element: Any) -> bool:
    class_name = element.attrib.get("class", "").lower()
    if "ltx_table" in class_name:
        return True
    for child in element.iter():
        if child is not element and _local_name(child.tag) == "table":
            return True
    return False


def _extract_math_tex(element: Any) -> str | None:
    for candidate in element.iter():
        if _local_name(candidate.tag) == "annotation":
            encoding = candidate.attrib.get("encoding", "")
            if "tex" in encoding.lower():
                text = _clean_text(candidate)
                if text:
                    return text
    alttext = element.attrib.get("alttext") or element.attrib.get("tex")
    return alttext.strip() if alttext else None


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
        candidates = [relative.resolve()]
    elif ".." in relative.parts:
        return None
    else:
        candidates = [(root / relative).resolve() for root in roots]
    for candidate in candidates:
        if candidate.is_file() and any(candidate.is_relative_to(root) for root in roots):
            return candidate
    return None


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
    if isinstance(element, HtmlElement):
        return element.to_html()
    return ET.tostring(element, encoding="unicode", method="html")


def _label(element: ET.Element) -> str | None:
    for key in ("id", "label"):
        value = element.attrib.get(key)
        if value:
            return value
    return None


def _find_source_archive(bundle_path: Path) -> Path:
    original = bundle_path / "original"
    for candidate in (original / "source.tar", original / "source.zip", original / "source.gz"):
        if candidate.exists():
            return candidate
    matches = sorted(original.glob("source.*"))
    if matches:
        return matches[0]
    raise ParseFailure("missing_source_archive", "No source archive found in article bundle.")
