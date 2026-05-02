from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass

import httpx

ARXIV_API_URL = "https://export.arxiv.org/api/query"
ARXIV_SOURCE_URL = "https://arxiv.org/e-print/{idv}"
ARXIV_PDF_URL = "https://arxiv.org/pdf/{idv}.pdf"


@dataclass(frozen=True)
class ArxivIdentity:
    bare_id: str
    version: str | None

    @property
    def concrete_id(self) -> str:
        return f"{self.bare_id}{self.version or ''}"


@dataclass(frozen=True)
class ArxivMetadata:
    bare_id: str
    version: str
    concrete_id: str
    title: str
    authors: list[str]
    summary: str
    published: str | None
    updated: str | None
    abs_url: str
    source_url: str
    pdf_url: str

    def to_json(self) -> dict:
        return {
            "bare_id": self.bare_id,
            "version": self.version,
            "concrete_id": self.concrete_id,
            "title": self.title,
            "authors": self.authors,
            "summary": self.summary,
            "published": self.published,
            "updated": self.updated,
            "abs_url": self.abs_url,
            "source_url": self.source_url,
            "pdf_url": self.pdf_url,
        }


def parse_arxiv_identity(value: str, version: str | None = None) -> ArxivIdentity:
    cleaned = value.strip()
    cleaned = cleaned.removeprefix("arXiv:").removeprefix("arxiv:")
    cleaned = cleaned.rstrip("/")
    if "/" in cleaned and ("arxiv.org" in cleaned or cleaned.startswith("abs/")):
        cleaned = cleaned.split("/abs/")[-1]
    match = re.fullmatch(r"(?P<bare>(?:[a-z-]+/\d{7})|(?:\d{4}\.\d{4,5}))(?P<v>v\d+)?", cleaned)
    if not match:
        msg = f"Invalid arXiv id: {value}"
        raise ValueError(msg)
    parsed_version = version or match.group("v")
    if parsed_version and not parsed_version.startswith("v"):
        parsed_version = f"v{parsed_version}"
    return ArxivIdentity(bare_id=match.group("bare"), version=parsed_version)


async def resolve_arxiv_metadata(
    arxiv_id: str,
    version: str | None = None,
    client: httpx.AsyncClient | None = None,
) -> ArxivMetadata:
    identity = parse_arxiv_identity(arxiv_id, version)
    id_for_query = identity.concrete_id if identity.version else identity.bare_id
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=30)
    try:
        response = await active_client.get(ARXIV_API_URL, params={"id_list": id_for_query})
        response.raise_for_status()
        return parse_arxiv_atom(response.text, requested=identity)
    finally:
        if owns_client:
            await active_client.aclose()


def parse_arxiv_atom(xml_text: str, requested: ArxivIdentity) -> ArxivMetadata:
    root = ET.fromstring(xml_text)
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    entry = root.find("atom:entry", ns)
    if entry is None:
        msg = f"arXiv returned no entry for {requested.concrete_id}"
        raise ValueError(msg)
    raw_entry_id = _text(entry.find("atom:id", ns))
    concrete_id = raw_entry_id.rstrip("/").split("/")[-1]
    parsed = parse_arxiv_identity(concrete_id)
    version = parsed.version or requested.version or "v1"
    source_id = f"{parsed.bare_id}{version}"
    title = " ".join(_text(entry.find("atom:title", ns)).split())
    summary = " ".join(_text(entry.find("atom:summary", ns)).split())
    authors = [
        " ".join(_text(author.find("atom:name", ns)).split())
        for author in entry.findall("atom:author", ns)
    ]
    return ArxivMetadata(
        bare_id=parsed.bare_id,
        version=version,
        concrete_id=source_id,
        title=title,
        authors=authors,
        summary=summary,
        published=_optional_text(entry.find("atom:published", ns)),
        updated=_optional_text(entry.find("atom:updated", ns)),
        abs_url=f"https://arxiv.org/abs/{source_id}",
        source_url=ARXIV_SOURCE_URL.format(idv=source_id),
        pdf_url=ARXIV_PDF_URL.format(idv=source_id),
    )


async def download_bytes(url: str, client: httpx.AsyncClient | None = None) -> bytes:
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=120, follow_redirects=True)
    try:
        response = await active_client.get(url)
        response.raise_for_status()
        return response.content
    finally:
        if owns_client:
            await active_client.aclose()


def _text(element: ET.Element | None) -> str:
    return "".join(element.itertext()) if element is not None else ""


def _optional_text(element: ET.Element | None) -> str | None:
    value = _text(element).strip()
    return value or None
