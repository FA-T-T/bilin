from __future__ import annotations

import asyncio
import gzip
import json
import re
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


def _markdown_text(element: Any) -> str:
    return _collapse_markdown_whitespace(_markdown_text_inner(element))


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
    return f"[{label}]({href})"


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
    return "".join(parts)


def _citation_wrapper_text(value: str) -> str:
    return value.replace("[", "").replace("]", "")


def _inline_math_markdown(value: str) -> str:
    escaped = value.replace("$", r"\$")
    return f"${escaped}$"


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
                return _strip_latexml_caption_tag(text)
    return None


def _latexml_environment_kind(element: Any) -> str:
    caption_kind = _caption_tag_kind(element)
    if caption_kind in {"figure", "table"}:
        return caption_kind
    return "table" if _is_table_figure(element) else "figure"


def _caption_tag_kind(element: Any) -> str | None:
    for candidate in element.iter():
        class_name = candidate.attrib.get("class", "").lower()
        if "ltx_tag_table" in class_name:
            return "table"
        if "ltx_tag_figure" in class_name:
            return "figure"
    text = _caption_text_without_tag_stripping(element)
    if text and re.match(r"^\s*table\s+\d+", text, flags=re.IGNORECASE):
        return "table"
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
    return re.sub(r"^\s*(?:figure|fig\.|table)\s+\d+[.:]\s*", "", text, flags=re.IGNORECASE)


def _is_table_figure(element: Any) -> bool:
    class_name = element.attrib.get("class", "").lower()
    return "ltx_table" in class_name


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


def _extract_math_tex(element: Any) -> str | None:
    if _local_name(element.tag) == "math":
        return _extract_single_math_tex(element)
    rows = _extract_math_rows(element)
    if rows:
        if len(rows) == 1 and len(rows[0]) == 1:
            return rows[0][0]
        formatted_rows = [" ".join(row) for row in rows]
        return "\\begin{aligned}\n" + " \\\\\n".join(formatted_rows) + "\n\\end{aligned}"
    values = [_extract_single_math_tex(candidate) for candidate in element.iter()]
    values = [value for value in values if value]
    if values:
        return " ".join(values)
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
        if row_values:
            rows.append(row_values)
    if rows:
        return rows
    value = _extract_single_math_tex(element)
    return [[value]] if value else []


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
    return value.replace("%\r\n", "").replace("%\n", "").replace("\\displaystyle", "").strip()


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
