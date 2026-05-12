from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from html.parser import HTMLParser

import httpx

ARXIV_API_URL = "https://export.arxiv.org/api/query"
ARXIV_SOURCE_URL = "https://arxiv.org/e-print/{idv}"
ARXIV_PDF_URL = "https://arxiv.org/pdf/{idv}.pdf"
OLD_STYLE_ARCHIVE_ALIASES = {
    "condmat": "cond-mat",
    "adaporg": "adap-org",
    "alggeom": "alg-geom",
    "cmplg": "cmp-lg",
    "functan": "funct-an",
    "grqc": "gr-qc",
    "hepex": "hep-ex",
    "heplat": "hep-lat",
    "hepph": "hep-ph",
    "hepth": "hep-th",
    "mathph": "math-ph",
    "nuchex": "nucl-ex",
    "nucth": "nucl-th",
    "patt-sol": "patt-sol",
    "qalg": "q-alg",
    "qbio": "q-bio",
    "qfin": "q-fin",
    "quantph": "quant-ph",
    "solvint": "solv-int",
}


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
    primary_category: str | None
    categories: list[str]
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
            "primary_category": self.primary_category,
            "categories": self.categories,
            "abs_url": self.abs_url,
            "source_url": self.source_url,
            "pdf_url": self.pdf_url,
        }


@dataclass(frozen=True)
class ArxivCategory:
    id: str
    name: str
    group: str
    description: str


def parse_arxiv_identity(value: str, version: str | None = None) -> ArxivIdentity:
    cleaned = value.strip()
    cleaned = cleaned.removeprefix("arXiv:").removeprefix("arxiv:")
    cleaned = cleaned.rstrip("/")
    if "/" in cleaned and ("arxiv.org" in cleaned or cleaned.startswith("abs/")):
        cleaned = cleaned.split("/abs/")[-1]
    if re.fullmatch(r"\d{7}", cleaned):
        msg = (
            f"Invalid arXiv id: {value}. Old-style arXiv ids before 2007 require an archive "
            "prefix, for example cond-mat/9407022, hep-th/9407022, gr-qc/9407022, or "
            "quant-ph/9705052. The bare number is ambiguous."
        )
        raise ValueError(msg)
    cleaned = normalize_old_style_archive_alias(cleaned)
    match = re.fullmatch(r"(?P<bare>(?:[a-z-]+/\d{7})|(?:\d{4}\.\d{4,5}))(?P<v>v\d+)?", cleaned)
    if not match:
        msg = (
            f"Invalid arXiv id: {value}. Use a modern id like 1706.03762, or a complete "
            "old-style id with archive prefix such as cond-mat/9407022."
        )
        raise ValueError(msg)
    parsed_version = version or match.group("v")
    if parsed_version and not parsed_version.startswith("v"):
        parsed_version = f"v{parsed_version}"
    return ArxivIdentity(bare_id=match.group("bare"), version=parsed_version)


def normalize_old_style_archive_alias(value: str) -> str:
    if "/" not in value:
        return value
    archive, suffix = value.split("/", 1)
    normalized_archive = OLD_STYLE_ARCHIVE_ALIASES.get(archive.casefold(), archive)
    return f"{normalized_archive}/{suffix}"


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


async def search_arxiv_latest_by_title(
    title: str,
    client: httpx.AsyncClient | None = None,
) -> ArxivMetadata | None:
    query = " ".join(title.split()).strip()
    if not query:
        return None
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=30)
    try:
        response = await active_client.get(
            ARXIV_API_URL,
            params={
                "search_query": f'ti:"{query}"',
                "start": 0,
                "max_results": 5,
                "sortBy": "submittedDate",
                "sortOrder": "descending",
            },
        )
        response.raise_for_status()
        return best_title_match(response.text, query)
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
    return metadata_from_entry(entry, requested=requested)


def best_title_match(xml_text: str, query: str) -> ArxivMetadata | None:
    root = ET.fromstring(xml_text)
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    entries = root.findall("atom:entry", ns)
    if not entries:
        return None
    candidates = [metadata_from_entry(entry) for entry in entries]
    normalized_query = normalize_title(query)
    for candidate in candidates:
        normalized_title = normalize_title(candidate.title)
        if normalized_query == normalized_title:
            return candidate
    for candidate in candidates:
        normalized_title = normalize_title(candidate.title)
        if normalized_query in normalized_title or normalized_title in normalized_query:
            return candidate
    return candidates[0]


def metadata_from_entry(
    entry: ET.Element,
    requested: ArxivIdentity | None = None,
) -> ArxivMetadata:
    ns = {
        "atom": "http://www.w3.org/2005/Atom",
        "arxiv": "http://arxiv.org/schemas/atom",
    }
    raw_entry_id = _text(entry.find("atom:id", ns))
    concrete_id = _arxiv_id_from_entry_url(raw_entry_id)
    parsed = parse_arxiv_identity(concrete_id)
    version = parsed.version or (requested.version if requested else None) or "v1"
    source_id = f"{parsed.bare_id}{version}"
    title = " ".join(_text(entry.find("atom:title", ns)).split())
    summary = " ".join(_text(entry.find("atom:summary", ns)).split())
    authors = [
        " ".join(_text(author.find("atom:name", ns)).split())
        for author in entry.findall("atom:author", ns)
    ]
    category_terms = [
        category.attrib.get("term", "").strip()
        for category in entry.findall("atom:category", ns)
        if category.attrib.get("term", "").strip()
    ]
    primary_category = None
    primary = entry.find("arxiv:primary_category", ns)
    if primary is not None:
        primary_category = primary.attrib.get("term", "").strip() or None
    return ArxivMetadata(
        bare_id=parsed.bare_id,
        version=version,
        concrete_id=source_id,
        title=title,
        authors=authors,
        summary=summary,
        published=_optional_text(entry.find("atom:published", ns)),
        updated=_optional_text(entry.find("atom:updated", ns)),
        primary_category=primary_category or (category_terms[0] if category_terms else None),
        categories=category_terms,
        abs_url=f"https://arxiv.org/abs/{source_id}",
        source_url=ARXIV_SOURCE_URL.format(idv=source_id),
        pdf_url=ARXIV_PDF_URL.format(idv=source_id),
    )


def _arxiv_id_from_entry_url(value: str) -> str:
    cleaned = value.strip().rstrip("/")
    if "/abs/" in cleaned:
        return cleaned.split("/abs/", 1)[1]
    return cleaned.rsplit("/", 1)[-1]


def normalize_title(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


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


async def search_arxiv(
    search_query: str,
    *,
    start: int = 0,
    max_results: int = 100,
    sort_by: str = "submittedDate",
    sort_order: str = "descending",
    client: httpx.AsyncClient | None = None,
) -> list[ArxivMetadata]:
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=30)
    try:
        response = await active_client.get(
            ARXIV_API_URL,
            params={
                "search_query": search_query,
                "start": start,
                "max_results": max(1, min(max_results, 200)),
                "sortBy": sort_by,
                "sortOrder": sort_order,
            },
        )
        response.raise_for_status()
        return parse_arxiv_search_feed(response.text)
    finally:
        if owns_client:
            await active_client.aclose()


def parse_arxiv_search_feed(xml_text: str) -> list[ArxivMetadata]:
    root = ET.fromstring(xml_text)
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    return [metadata_from_entry(entry) for entry in root.findall("atom:entry", ns)]


async def fetch_arxiv_category_taxonomy(
    client: httpx.AsyncClient | None = None,
) -> list[ArxivCategory]:
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=30, follow_redirects=True)
    try:
        response = await active_client.get("https://arxiv.org/category_taxonomy")
        response.raise_for_status()
        return parse_arxiv_category_taxonomy(response.text)
    finally:
        if owns_client:
            await active_client.aclose()


def parse_arxiv_category_taxonomy(html: str) -> list[ArxivCategory]:
    parser = _ArxivCategoryTaxonomyParser()
    parser.feed(html)
    parser.close()
    return parser.categories


class _ArxivCategoryTaxonomyParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.categories: list[ArxivCategory] = []
        self._active_tag: str | None = None
        self._active_text: list[str] = []
        self._group = ""
        self._pending_category: tuple[str, str] | None = None
        self._pending_description: list[str] = []

    def handle_starttag(self, tag: str, _attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"h2", "h4", "p"}:
            self._active_tag = tag
            self._active_text = []

    def handle_data(self, data: str) -> None:
        if self._active_tag:
            self._active_text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag != self._active_tag:
            return
        text = " ".join("".join(self._active_text).split())
        self._active_tag = None
        self._active_text = []
        if not text:
            return
        if tag == "h2":
            self._flush_pending_category()
            self._group = text
        elif tag == "h4":
            self._flush_pending_category()
            match = re.fullmatch(r"(?P<id>[a-z.-]+(?:\.[A-Z]{2})?) \((?P<name>.+)\)", text)
            if match:
                self._pending_category = (match.group("id"), match.group("name"))
                self._pending_description = []
        elif tag == "p" and self._pending_category:
            self._pending_description.append(text)

    def close(self) -> None:
        self._flush_pending_category()
        super().close()

    def _flush_pending_category(self) -> None:
        if not self._pending_category:
            return
        category_id, name = self._pending_category
        self.categories.append(
            ArxivCategory(
                id=category_id,
                name=name,
                group=self._group,
                description=" ".join(self._pending_description).strip(),
            )
        )
        self._pending_category = None
        self._pending_description = []


def _text(element: ET.Element | None) -> str:
    return "".join(element.itertext()) if element is not None else ""


def _optional_text(element: ET.Element | None) -> str | None:
    value = _text(element).strip()
    return value or None
