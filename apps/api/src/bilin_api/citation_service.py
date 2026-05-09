from __future__ import annotations

import re
from html import unescape
from pathlib import Path
from urllib.parse import quote, urlencode

import httpx

from bilin_api.article_store import get_article_revision
from bilin_api.arxiv import resolve_arxiv_metadata, search_arxiv_latest_by_title
from bilin_api.repositories import create_job
from bilin_api.schemas import (
    ArticleCitations,
    CitationArxivCandidate,
    CitationEntry,
    CitationLibraryImportRequest,
    CitationLibraryImportResult,
    CitationScholarResult,
    JobType,
    Library,
    ScholarSearchResult,
)

_SCHOLAR_CACHE: dict[str, CitationScholarResult] = {}


async def get_article_citations(library: Library, revision_id: str) -> ArticleCitations:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        raise ValueError(f"Article revision not found: {revision_id}")
    html_path = Path(revision.bundle_path) / "document" / "latexml.html"
    if not html_path.exists():
        return ArticleCitations(article_revision_id=revision_id, citations=[])
    html = html_path.read_text(encoding="utf-8", errors="replace")
    return ArticleCitations(
        article_revision_id=revision_id,
        citations=extract_latexml_citations(html),
    )


async def lookup_citation_scholar(
    library: Library,
    revision_id: str,
    citation_id: str,
    *,
    client: httpx.AsyncClient | None = None,
) -> CitationScholarResult:
    citation = await citation_by_id(library, revision_id, citation_id)
    cached = _SCHOLAR_CACHE.get(citation.scholar_query)
    if cached is not None:
        return cached
    result = await search_google_scholar(citation, client=client)
    _SCHOLAR_CACHE[citation.scholar_query] = result
    return result


async def queue_citation_library_import(
    library: Library,
    revision_id: str,
    citation_id: str,
    request: CitationLibraryImportRequest,
    *,
    client: httpx.AsyncClient | None = None,
) -> CitationLibraryImportResult:
    citation = await citation_by_id(library, revision_id, citation_id)
    candidate = await resolve_citation_arxiv_candidate(citation, client=client)
    if candidate is None:
        raise ValueError(f"No arXiv paper could be resolved for citation: {citation_id}")
    if request.translate_after_import and not request.provider_profile_id:
        raise ValueError("A provider profile is required to import and translate.")
    payload: dict[str, object] = {
        "library_id": library.id,
        "arxiv_id": candidate.arxiv_id,
        "version": None,
        "download_pdf": request.download_pdf,
        "parse_after_import": True,
        "source": "citation",
        "source_article_revision_id": revision_id,
        "source_citation_id": citation_id,
    }
    if request.translate_after_import:
        payload["translate_after_parse"] = {
            "target_language": request.target_language,
            "provider_profile_id": request.provider_profile_id,
            "model": request.model,
            "force": False,
            "block_uids": None,
            "custom_prompt": None,
        }
    job = await create_job(JobType.import_arxiv, payload=payload)
    return CitationLibraryImportResult(
        citation_id=citation_id,
        candidate=candidate,
        job=job,
        translate_after_import=request.translate_after_import,
    )


async def citation_by_id(library: Library, revision_id: str, citation_id: str) -> CitationEntry:
    citations = await get_article_citations(library, revision_id)
    citation = next((item for item in citations.citations if item.id == citation_id), None)
    if citation is None:
        raise ValueError(f"Citation not found: {citation_id}")
    return citation


async def resolve_citation_arxiv_candidate(
    citation: CitationEntry,
    *,
    client: httpx.AsyncClient | None = None,
) -> CitationArxivCandidate | None:
    if citation.arxiv_id:
        metadata = await resolve_arxiv_metadata(citation.arxiv_id, client=client)
        return CitationArxivCandidate(
            citation_id=citation.id,
            arxiv_id=metadata.concrete_id,
            title=metadata.title,
            abs_url=metadata.abs_url,
            source="citation",
        )
    metadata = await search_arxiv_latest_by_title(citation.title, client=client)
    if metadata is None:
        return None
    return CitationArxivCandidate(
        citation_id=citation.id,
        arxiv_id=metadata.concrete_id,
        title=metadata.title,
        abs_url=metadata.abs_url,
        source="arxiv_search",
    )


async def search_google_scholar(
    citation: CitationEntry,
    *,
    client: httpx.AsyncClient | None = None,
) -> CitationScholarResult:
    active_client = client or httpx.AsyncClient(timeout=12, follow_redirects=True)
    should_close = client is None
    try:
        try:
            response = await active_client.get(
                citation.scholar_url,
                headers={
                    "User-Agent": (
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/124.0 Safari/537.36"
                    ),
                    "Accept-Language": "en-US,en;q=0.9",
                },
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            semantic_result = await search_semantic_scholar(citation, active_client)
            if semantic_result is not None:
                return CitationScholarResult(
                    citation_id=citation.id,
                    query=citation.scholar_query,
                    scholar_url=citation.scholar_url,
                    first_result=semantic_result,
                    status="ok",
                    message="Google Scholar blocked preview; showing Semantic Scholar fallback.",
                )
            return CitationScholarResult(
                citation_id=citation.id,
                query=citation.scholar_query,
                scholar_url=citation.scholar_url,
                first_result=None,
                status="unavailable",
                message=scholar_unavailable_message(exc),
            )
        first_result = first_scholar_result(response.text)
        if first_result is None:
            first_result = await search_semantic_scholar(citation, active_client)
        return CitationScholarResult(
            citation_id=citation.id,
            query=citation.scholar_query,
            scholar_url=citation.scholar_url,
            first_result=first_result,
            status="ok" if first_result else "unavailable",
            message=None if first_result else "No readable citation preview was returned.",
        )
    finally:
        if should_close:
            await active_client.aclose()


def extract_latexml_citations(html: str) -> list[CitationEntry]:
    entries: list[CitationEntry] = []
    for match in re.finditer(
        r"(?P<open><li\b[^>]*\bclass=(?P<quote>['\"])[^'\"]*\bltx_bibitem\b"
        r"[^'\"]*(?P=quote)[^>]*>)"
        r"(?P<body>.*?)</li>",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    ):
        citation_id = html_attr(match.group("open"), "id")
        if not citation_id:
            continue
        body = match.group("body")
        blocks = bib_blocks(body)
        raw_text = clean_html_text(body)
        title = citation_title(blocks, raw_text)
        if not title:
            continue
        authors = blocks[0] if blocks else None
        label = citation_label(body, citation_id, len(entries) + 1)
        query = scholar_query(title, authors)
        entries.append(
            CitationEntry(
                id=citation_id,
                label=label,
                title=title,
                raw_text=raw_text,
                authors=authors,
                year=citation_year(raw_text),
                arxiv_id=citation_arxiv_id(raw_text),
                scholar_query=query,
                scholar_url=google_scholar_url(query),
                metadata={"bib_blocks": blocks},
            )
        )
    return entries


def first_scholar_result(html: str) -> ScholarSearchResult | None:
    title_match = re.search(
        r"<h3\b[^>]*class=(?P<quote>['\"])[^'\"]*\bgs_rt\b[^'\"]*(?P=quote)[^>]*>"
        r".*?<a\b[^>]*href=(?P<hquote>['\"])(?P<href>.*?)(?P=hquote)[^>]*>"
        r"(?P<title>.*?)</a>.*?</h3>",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not title_match:
        return None
    snippet_window = html[title_match.end() : title_match.end() + 4000]
    snippet_match = re.search(
        r"<div\b[^>]*class=(?P<quote>['\"])[^'\"]*\bgs_rs\b[^'\"]*(?P=quote)[^>]*>"
        r"(?P<snippet>.*?)</div>",
        snippet_window,
        flags=re.IGNORECASE | re.DOTALL,
    )
    title = clean_html_text(title_match.group("title"))
    url = unescape(title_match.group("href"))
    snippet = clean_html_text(snippet_match.group("snippet")) if snippet_match else None
    if title and url:
        return ScholarSearchResult(title=title, url=url, snippet=snippet or None)
    return None


async def search_semantic_scholar(
    citation: CitationEntry,
    client: httpx.AsyncClient,
) -> ScholarSearchResult | None:
    try:
        response = await client.get(
            "https://api.semanticscholar.org/graph/v1/paper/search",
            params={
                "query": citation.scholar_query,
                "limit": 1,
                "fields": "title,url,abstract,year,authors,paperId",
            },
            headers={"User-Agent": "Ilios local citation preview"},
        )
        response.raise_for_status()
    except httpx.HTTPError:
        return None
    payload = response.json()
    data = payload.get("data")
    if not isinstance(data, list) or not data:
        return None
    first = data[0]
    if not isinstance(first, dict):
        return None
    title = str(first.get("title") or "").strip()
    if not title:
        return None
    url = str(first.get("url") or "").strip()
    paper_id = str(first.get("paperId") or "").strip()
    if not url and paper_id:
        url = f"https://www.semanticscholar.org/paper/{quote(paper_id)}"
    if not url:
        return None
    snippet = str(first.get("abstract") or "").strip() or None
    if snippet and len(snippet) > 360:
        snippet = f"{snippet[:357].rstrip()}..."
    return ScholarSearchResult(
        title=title,
        url=url,
        snippet=snippet,
        source="semantic_scholar",
    )


def scholar_unavailable_message(exc: httpx.HTTPError) -> str:
    if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code in {403, 429}:
        return "Google Scholar blocked automated preview. Open the Scholar link directly."
    return "Google Scholar preview is unavailable. Open the Scholar link directly."


def bib_blocks(html: str) -> list[str]:
    return [
        clean_html_text(match.group("body"))
        for match in re.finditer(
            r"<span\b[^>]*class=(?P<quote>['\"])[^'\"]*\bltx_bibblock\b[^'\"]*(?P=quote)[^>]*>"
            r"(?P<body>.*?)</span>",
            html,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if clean_html_text(match.group("body"))
    ]


def citation_title(blocks: list[str], raw_text: str) -> str:
    if len(blocks) >= 2:
        return blocks[1].rstrip(".")
    cleaned = re.sub(r"^\[\d+\]\s*", "", raw_text).strip()
    parts = [part.strip() for part in re.split(r"\.\s+", cleaned) if part.strip()]
    return parts[1] if len(parts) > 1 else (parts[0] if parts else "")


def citation_label(html: str, citation_id: str, fallback_index: int | None = None) -> str:
    match = re.search(
        r"<span\b[^>]*class=(?P<quote>['\"])[^'\"]*\bltx_tag_bibitem\b[^'\"]*(?P=quote)[^>]*>"
        r"(?P<label>.*?)</span>",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )
    label = clean_html_text(match.group("label")) if match else ""
    if label:
        stripped = label.strip("[]")
        if re.fullmatch(r"\d+[a-z]?", stripped):
            return stripped
    fallback = re.search(r"(\d+)$", citation_id)
    if fallback:
        return fallback.group(1)
    return str(fallback_index) if fallback_index is not None else citation_id


def citation_year(raw_text: str) -> str | None:
    matches = re.findall(r"\b(19\d{2}|20\d{2})\b", raw_text)
    return matches[-1] if matches else None


def citation_arxiv_id(raw_text: str) -> str | None:
    match = re.search(r"\barXiv:?\s*([a-z\-]+/\d{7}|\d{4}\.\d{4,5}(?:v\d+)?)\b", raw_text, re.I)
    return match.group(1) if match else None


def scholar_query(title: str, authors: str | None) -> str:
    if authors:
        first_author = re.split(r",|\band\b", authors, maxsplit=1)[0].strip()
        if first_author:
            return f"{title} {first_author}"
    return title


def google_scholar_url(query: str) -> str:
    return f"https://scholar.google.com/scholar?{urlencode({'q': query})}"


def html_attr(attrs: str, name: str) -> str | None:
    match = re.search(rf"\b{name}\s*=\s*(['\"])(.*?)\1", attrs, flags=re.IGNORECASE | re.DOTALL)
    return unescape(match.group(2)) if match else None


def clean_html_text(html: str) -> str:
    without_tags = re.sub(r"<[^>]+>", " ", html)
    return re.sub(r"\s+", " ", unescape(without_tags)).strip()


def clear_scholar_cache() -> None:
    _SCHOLAR_CACHE.clear()
