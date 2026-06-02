from __future__ import annotations

import re
from html import unescape
from pathlib import Path
from urllib.parse import quote, urlencode

import httpx

from bilin_api.article_store import get_article_revision
from bilin_api.arxiv import ArxivMetadata, resolve_arxiv_metadata, search_arxiv_latest_by_title
from bilin_api.citation_keys import (
    humanize_citation_key,
    missing_citation_id,
    normalize_citation_key,
    parse_author_year_citation_key,
)
from bilin_api.repositories import create_import_arxiv_job_if_absent
from bilin_api.schemas import (
    ArticleCitations,
    CitationArxivCandidate,
    CitationEntry,
    CitationLibraryImportRequest,
    CitationLibraryImportResult,
    CitationScholarResult,
    Library,
    ScholarSearchResult,
)

_SCHOLAR_CACHE: dict[str, CitationScholarResult] = {}
_ARXIV_CANDIDATE_CACHE: dict[str, CitationArxivCandidate | None] = {}
_ARXIV_METADATA_CACHE: dict[str, dict[str, object]] = {}


async def get_article_citations(library: Library, revision_id: str) -> ArticleCitations:
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        raise ValueError(f"Article revision not found: {revision_id}")
    bundle_path = Path(revision.bundle_path)
    html_path = bundle_path / "document" / "latexml.html"
    citations: list[CitationEntry] = []
    if html_path.exists():
        html = html_path.read_text(encoding="utf-8", errors="replace")
        citations = extract_latexml_citations(html)
    return ArticleCitations(
        article_revision_id=revision_id,
        citations=merge_citation_entries(
            citations, extract_source_bibliography_citations(bundle_path)
        ),
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
    arxiv_metadata = cached_arxiv_metadata(candidate.arxiv_id)
    if arxiv_metadata is not None:
        payload["arxiv_metadata"] = arxiv_metadata
    job, _created = await create_import_arxiv_job_if_absent(payload)
    return CitationLibraryImportResult(
        citation_id=citation_id,
        candidate=candidate,
        job=job,
        translate_after_import=request.translate_after_import,
    )


async def citation_by_id(library: Library, revision_id: str, citation_id: str) -> CitationEntry:
    citations = await get_article_citations(library, revision_id)
    normalized_id = citation_id.removeprefix("#").strip()
    citation = next(
        (item for item in citations.citations if normalized_id in citation_entry_aliases(item)),
        None,
    )
    if citation is None:
        raise ValueError(f"Citation not found: {citation_id}")
    return citation


async def resolve_citation_arxiv_candidate(
    citation: CitationEntry,
    *,
    client: httpx.AsyncClient | None = None,
) -> CitationArxivCandidate | None:
    cache_key = citation_arxiv_candidate_cache_key(citation)
    if cache_key in _ARXIV_CANDIDATE_CACHE:
        cached = _ARXIV_CANDIDATE_CACHE[cache_key]
        return (
            cached.model_copy(update={"citation_id": citation.id})
            if cached is not None
            else None
        )
    if citation.arxiv_id:
        metadata = await resolve_arxiv_metadata(citation.arxiv_id, client=client)
        cache_arxiv_metadata(metadata)
        candidate = CitationArxivCandidate(
            citation_id=citation.id,
            arxiv_id=metadata.concrete_id,
            title=metadata.title,
            abs_url=metadata.abs_url,
            source="citation_arxiv_id",
        )
        _ARXIV_CANDIDATE_CACHE[cache_key] = candidate
        return candidate
    metadata = await search_arxiv_latest_by_title(citation.title, client=client)
    if metadata is None:
        _ARXIV_CANDIDATE_CACHE[cache_key] = None
        return None
    cache_arxiv_metadata(metadata)
    candidate = CitationArxivCandidate(
        citation_id=citation.id,
        arxiv_id=metadata.concrete_id,
        title=metadata.title,
        abs_url=metadata.abs_url,
        source="arxiv_search",
    )
    _ARXIV_CANDIDATE_CACHE[cache_key] = candidate
    return candidate


def citation_arxiv_candidate_cache_key(citation: CitationEntry) -> str:
    if citation.arxiv_id:
        return f"id:{citation.arxiv_id.strip().casefold()}"
    return f"title:{' '.join(citation.title.split()).casefold()}"


def cache_arxiv_metadata(metadata: ArxivMetadata) -> None:
    _ARXIV_METADATA_CACHE[metadata.concrete_id.casefold()] = metadata.to_json()


def cached_arxiv_metadata(arxiv_id: str) -> dict[str, object] | None:
    return _ARXIV_METADATA_CACHE.get(arxiv_id.casefold())


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
        authors = citation_authors(blocks)
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
                doi=citation_doi(raw_text),
                url=citation_url(raw_text),
                source="latexml",
                citation_key=citation_key_from_id(citation_id),
                scholar_query=query,
                scholar_url=google_scholar_url(query),
                metadata={
                    "source": "latexml",
                    "bib_blocks": blocks,
                    "aliases": citation_id_aliases(citation_id, label=label),
                },
            )
        )
    entries.extend(missing_latexml_citation_entries(html, entries))
    return entries


def merge_citation_entries(
    primary: list[CitationEntry],
    fallback: list[CitationEntry],
) -> list[CitationEntry]:
    entries = list(primary)
    seen: dict[str, CitationEntry] = {}
    for entry in entries:
        for alias in citation_entry_aliases(entry):
            seen.setdefault(alias, entry)
    for entry in fallback:
        matching = next(
            (seen[alias] for alias in citation_entry_aliases(entry) if alias in seen), None
        )
        if matching is not None:
            merge_citation_metadata(matching, entry)
            for alias in citation_entry_aliases(matching) | citation_entry_aliases(entry):
                seen.setdefault(alias, matching)
            continue
        entries.append(entry)
        for alias in citation_entry_aliases(entry):
            seen.setdefault(alias, entry)
    return entries


def merge_citation_metadata(primary: CitationEntry, fallback: CitationEntry) -> None:
    aliases = citation_entry_aliases(primary) | citation_entry_aliases(fallback)
    metadata = dict(primary.metadata)
    metadata["aliases"] = sorted(aliases)
    primary.metadata = metadata
    if not primary.citation_key or re.fullmatch(r"bib\d+[a-z]?", primary.citation_key):
        primary.citation_key = fallback.citation_key or primary.citation_key
    for field in ("authors", "year", "arxiv_id", "doi", "url"):
        if getattr(primary, field) is None and getattr(fallback, field) is not None:
            setattr(primary, field, getattr(fallback, field))


def extract_source_bibliography_citations(bundle_path: Path) -> list[CitationEntry]:
    source_dir = bundle_path / "source" / "unpacked"
    if not source_dir.exists():
        return []
    bbl_entries = extract_bbl_citations(source_dir)
    if bbl_entries:
        return bbl_entries
    return extract_bib_citations(source_dir)


def extract_bbl_citations(source_dir: Path) -> list[CitationEntry]:
    entries: list[CitationEntry] = []
    for path in sorted(source_dir.rglob("*.bbl")):
        if path.name.startswith("__bilin_"):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        entries.extend(extract_bbl_citations_from_text(text, source_path=path, offset=len(entries)))
    return entries


def extract_bbl_citations_from_text(
    text: str,
    *,
    source_path: Path | None = None,
    offset: int = 0,
) -> list[CitationEntry]:
    matches = list(
        re.finditer(
            r"\\bibitem(?:\s*\[(?P<label>[^\]]+)\])?\s*\{(?P<key>[^{}]+)\}",
            text,
            flags=re.DOTALL,
        )
    )
    entries: list[CitationEntry] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        raw_body = re.sub(r"\\end\{thebibliography\}.*$", "", text[start:end], flags=re.DOTALL)
        raw_text = clean_latex_text(raw_body)
        if not raw_text:
            continue
        blocks = reference_text_parts(raw_text)
        title = citation_title(blocks, raw_text)
        if not title:
            continue
        authors = citation_authors(blocks)
        key = clean_citation_key(match.group("key"))
        label = clean_latex_text(match.group("label") or "") or str(offset + len(entries) + 1)
        entries.append(
            build_citation_entry(
                citation_id=bibliography_entry_id(key),
                label=label.strip("[]"),
                title=title,
                raw_text=raw_text,
                authors=authors,
                source="bbl",
                source_path=source_path,
                citation_key=key,
            )
        )
    return entries


def extract_bib_citations(source_dir: Path) -> list[CitationEntry]:
    entries: list[CitationEntry] = []
    for path in sorted(source_dir.rglob("*.bib")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for entry in parse_bibtex_entries(text, source_path=path, offset=len(entries)):
            entries.append(entry)
    return entries


def parse_bibtex_entries(
    text: str,
    *,
    source_path: Path | None = None,
    offset: int = 0,
) -> list[CitationEntry]:
    entries: list[CitationEntry] = []
    for kind, key, body in iter_bibtex_entry_bodies(text):
        if kind.casefold() in {"comment", "preamble", "string"}:
            continue
        fields = parse_bibtex_fields(body)
        title = clean_latex_text(fields.get("title", ""))
        if not title:
            continue
        authors = clean_latex_text(fields.get("author", "")) or None
        raw_text = ". ".join(
            part
            for part in (
                authors,
                title,
                clean_latex_text(fields.get("journal", "") or fields.get("booktitle", "")),
                clean_latex_text(fields.get("year", "")),
            )
            if part
        )
        entry = build_citation_entry(
            citation_id=bibliography_entry_id(clean_citation_key(key)),
            label=str(offset + len(entries) + 1),
            title=title,
            raw_text=raw_text,
            authors=authors,
            source="bib",
            source_path=source_path,
            citation_key=clean_citation_key(key),
            doi=clean_latex_text(fields.get("doi", "")) or None,
            url=clean_latex_text(fields.get("url", "")) or None,
        )
        year = clean_latex_text(fields.get("year", ""))
        entry.year = year or entry.year
        arxiv_id = bibtex_arxiv_id(fields)
        entry.arxiv_id = arxiv_id or entry.arxiv_id
        entries.append(entry)
    return entries


def missing_latexml_citation_entries(
    html: str,
    existing_entries: list[CitationEntry],
) -> list[CitationEntry]:
    entries: list[CitationEntry] = []
    seen_ids = {entry.id for entry in existing_entries}
    seen_keys: set[str] = set()
    for match in re.finditer(
        r"<span\b(?=[^>]*\bclass=(?P<quote>['\"])[^'\"]*\bltx_missing_citation\b"
        r"[^'\"]*(?P=quote))[^>]*>(?P<body>.*?)</span>",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    ):
        key = normalize_citation_key(clean_html_text(match.group("body")))
        if not key or key in seen_keys:
            continue
        citation_id = missing_citation_id(key)
        if citation_id in seen_ids:
            continue
        label = humanize_citation_key(key)
        parsed_key = parse_author_year_citation_key(key)
        authors = parsed_key[0] if parsed_key else None
        year = parsed_key[1] if parsed_key else citation_year(key)
        entries.append(
            CitationEntry(
                id=citation_id,
                label=label,
                title=label,
                raw_text=key,
                authors=authors,
                year=year,
                arxiv_id=None,
                doi=None,
                url=None,
                source="missing_latexml_citation",
                citation_key=key,
                scholar_query=label,
                scholar_url=google_scholar_url(label),
                metadata={
                    "source": "missing_latexml_citation",
                    "citation_key": key,
                    "aliases": citation_id_aliases(citation_id, label=label),
                },
            )
        )
        seen_ids.add(citation_id)
        seen_keys.add(key)
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
    quoted_title = quoted_citation_title(raw_text)
    if quoted_title:
        return quoted_title
    for index, block in enumerate(blocks):
        candidate = normalize_title_candidate(block)
        if index == 0 and len(blocks) > 1 and is_probable_author_block(candidate):
            continue
        if is_probable_citation_title(candidate):
            return candidate
    cleaned = re.sub(r"^\[[^\]]+\]\s*", "", raw_text).strip()
    parts = [part.strip() for part in re.split(r"(?<!\b[A-Z])\.\s+", cleaned) if part.strip()]
    for part in parts:
        candidate = normalize_title_candidate(part)
        if is_probable_citation_title(candidate):
            return candidate
    return normalize_title_candidate(parts[0]) if parts else ""


def citation_authors(blocks: list[str]) -> str | None:
    for block in blocks:
        candidate = normalize_author_candidate(block)
        if is_probable_author_block(candidate):
            return candidate
    return None


def normalize_title_candidate(value: str) -> str:
    candidate = re.sub(r"^\[[^\]]{1,40}\]\s*", "", value).strip()
    candidate = re.sub(r"^[A-Z]\s+(?=[A-Z]\.)", "", candidate)
    candidate = re.sub(
        r"^[A-Z][A-Za-z'’-]+ et al\.\s*\[\d{4}[a-z]?\]\s*",
        "",
        candidate,
    )
    return candidate.strip(" ,;:.")


def normalize_author_candidate(value: str) -> str:
    candidate = re.sub(r"^\[[^\]]{1,40}\]\s*", "", value).strip()
    candidate = re.sub(r"^[A-Z]\s+(?=[A-Z]\.)", "", candidate)
    candidate = re.sub(
        r"^[A-Z][A-Za-z'’-]+ et al\.\s*\[\d{4}[a-z]?\]\s*",
        "",
        candidate,
    )
    return candidate.strip(" ,;")


def is_probable_citation_title(value: str) -> bool:
    if not value or len(value) < 8:
        return False
    if is_probable_author_block(value) or is_probable_venue_block(value):
        return False
    words = re.findall(r"[A-Za-z][A-Za-z0-9'’-]*", value)
    return len(words) >= 2


def is_probable_author_block(value: str) -> bool:
    if not value or len(value) < 4:
        return False
    if is_probable_venue_block(value):
        return False
    if looks_like_author_name_list(value):
        return True
    initials = len(re.findall(r"\b[A-Z]\.", value))
    comma_count = value.count(",")
    has_author_joiner = bool(re.search(r"\b(?:and|et al\.?)\b", value, flags=re.IGNORECASE))
    capitalized_words = re.findall(r"\b[A-Z][A-Za-z'’-]+\b", value)
    title_words = re.findall(
        r"\b(?:a|an|the|of|for|from|with|without|using|towards?|through|near|term|as|in|on|by|to)\b",
        value,
        flags=re.IGNORECASE,
    )
    if initials >= 2 and (comma_count > 0 or has_author_joiner):
        return True
    if comma_count > 0 and len(capitalized_words) >= 2 and len(title_words) <= 2:
        return True
    return bool(has_author_joiner and initials > 0 and len(title_words) <= 2)


def looks_like_author_name_list(value: str) -> bool:
    candidate = value.strip(" ,;.")
    if not candidate or len(candidate) > 180:
        return False
    if re.search(
        r"[:?!]|\b(?:method|learning|network|model|algorithm|translation)\b", candidate, re.I
    ):
        return False
    parts = [
        part.strip()
        for part in re.split(r"\s*,\s*|\s+(?:and|&)\s+", candidate, flags=re.IGNORECASE)
        if part.strip()
    ]
    if not parts:
        return False
    if len(parts) == 1:
        return is_probable_person_name(parts[0])
    return all(is_probable_person_name(part) for part in parts)


def is_probable_person_name(value: str) -> bool:
    candidate = value.strip(" ,;.")
    if not candidate:
        return False
    tokens = re.findall(r"[^\W\d_][\w'’.-]*|[A-Z]\.", candidate, flags=re.UNICODE)
    if len(tokens) < 2 or len(tokens) > 5:
        return False
    particles = {"bin", "da", "de", "del", "der", "di", "du", "la", "le", "van", "von"}
    meaningful = [token for token in tokens if token.casefold().strip(".") not in particles]
    if len(meaningful) < 2:
        return False
    return all(is_name_token(token) for token in meaningful)


def is_name_token(value: str) -> bool:
    token = value.strip()
    return bool(token) and (re.fullmatch(r"[A-Z]\.", token) is not None or token[0].isupper())


def is_probable_venue_block(value: str) -> bool:
    has_archive_or_identifier = bool(
        re.search(r"\b(?:arXiv|CoRR|doi|ISBN|ISSN)\b", value, flags=re.IGNORECASE)
    )
    has_bibliographic_detail = bool(
        re.search(r"\b(?:19|20)\d{2}\b|\b\d+\s*\(|:\d+|pp\.|pages?|vol\.|volume", value)
    )
    has_venue_word = bool(
        re.search(
            r"\b(?:Journal|Proceedings|Conference|"
            r"Transactions|Physical Review|Phys\.|Nature|Science|IEEE|ACM|"
            r"Springer|Elsevier|Wiley)\b",
            value,
            flags=re.IGNORECASE,
        )
    )
    starts_like_venue = bool(
        re.search(
            r"^\s*(?:In\s+)?(?:Proceedings|Proc\.|"
            r"Advances in Neural Information Processing Systems|"
            r"International Conference|Conference|Workshop|Symposium|"
            r"ICLR|ACL|EMNLP|NAACL|NeurIPS|NIPS)\b",
            value,
            flags=re.IGNORECASE,
        )
    )
    return (
        has_archive_or_identifier
        or starts_like_venue
        or (has_venue_word and has_bibliographic_detail)
    )


def quoted_citation_title(raw_text: str) -> str:
    match = re.search(r"[“\"](?P<title>[^”\"]{8,300})[”\"]", raw_text)
    if not match:
        return ""
    return match.group("title").strip().rstrip(".,;:")


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
    matches = re.findall(r"(?<![\d-])(19\d{2}|20\d{2})(?![\d-])", raw_text)
    return matches[-1] if matches else None


def citation_arxiv_id(raw_text: str) -> str | None:
    patterns = [
        r"\barXiv:?\s*([a-z\-]+/\d{7}|\d{4}\.\d{4,5}(?:v\d+)?)\b",
        r"\babs/([a-z\-]+/\d{7}|\d{4}\.\d{4,5}(?:v\d+)?)\b",
    ]
    for pattern in patterns:
        match = re.search(pattern, raw_text, re.I)
        if match:
            return match.group(1)
    return None


def citation_doi(raw_text: str) -> str | None:
    match = re.search(r"\b(10\.\d{4,9}/[-._;()/:A-Z0-9]+)\b", raw_text, re.I)
    if not match:
        return None
    return match.group(1).rstrip(".,;)")


def citation_url(raw_text: str) -> str | None:
    match = re.search(r"\bhttps?://[^\s<>{}\"']+", raw_text)
    if not match:
        return None
    return match.group(0).rstrip(".,;)")


def build_citation_entry(
    *,
    citation_id: str,
    label: str,
    title: str,
    raw_text: str,
    authors: str | None,
    source: str,
    source_path: Path | None,
    citation_key: str | None = None,
    doi: str | None = None,
    url: str | None = None,
) -> CitationEntry:
    query = scholar_query(title, authors)
    metadata: dict[str, object] = {
        "source": source,
        "aliases": citation_id_aliases(citation_id, citation_key, label=label),
    }
    if citation_key:
        metadata["citation_key"] = citation_key
    if source_path is not None:
        metadata["source_path"] = str(source_path)
    inferred_doi = doi or citation_doi(raw_text)
    inferred_url = url or citation_url(raw_text)
    return CitationEntry(
        id=citation_id,
        label=label,
        title=title,
        raw_text=raw_text,
        authors=authors,
        year=citation_year(raw_text),
        arxiv_id=citation_arxiv_id(raw_text),
        doi=inferred_doi,
        url=inferred_url,
        source=source,
        citation_key=citation_key,
        scholar_query=query,
        scholar_url=google_scholar_url(query),
        metadata=metadata,
    )


def scholar_query(title: str, authors: str | None) -> str:
    if authors:
        first_author = normalize_author_candidate(
            re.split(r",|\band\b", authors, maxsplit=1)[0].strip()
        ).rstrip(".")
        if first_author:
            return f"{title} {first_author}"
    return title


def google_scholar_url(query: str) -> str:
    return f"https://scholar.google.com/scholar?{urlencode({'q': query})}"


def reference_text_parts(raw_text: str) -> list[str]:
    return [part.strip() for part in re.split(r"(?<!\b[A-Z])\.\s+", raw_text) if part.strip()]


def clean_citation_key(value: str) -> str:
    return re.sub(r"\s+", "", unescape(value)).strip()


def bibliography_entry_id(citation_key: str) -> str:
    if citation_key.startswith(("bib.", "bib:")):
        return citation_key
    return f"bib:{citation_key}"


def citation_key_from_id(citation_id: str) -> str | None:
    if citation_id.startswith(("bib:", "bib.")):
        return citation_id[4:]
    return None


def citation_entry_aliases(citation: CitationEntry) -> set[str]:
    aliases = set(citation_id_aliases(citation.id, citation.citation_key, label=citation.label))
    metadata_aliases = citation.metadata.get("aliases")
    if isinstance(metadata_aliases, list):
        aliases.update(alias.strip() for alias in metadata_aliases if isinstance(alias, str))
    return {alias for alias in aliases if alias}


def citation_id_aliases(
    citation_id: str,
    citation_key: str | None = None,
    *,
    label: str | None = None,
) -> list[str]:
    aliases = {citation_id}
    if citation_id.startswith("bib:"):
        aliases.add(f"bib.{citation_id[4:]}")
    elif citation_id.startswith("bib."):
        aliases.add(f"bib:{citation_id[4:]}")
    if citation_key:
        aliases.add(citation_key)
        aliases.add(bibliography_entry_id(citation_key))
        aliases.add(f"bib.{citation_key}")
    if label:
        stripped_label = label.strip().strip("[]")
        if re.fullmatch(r"\d+[a-z]?", stripped_label):
            aliases.add(f"bib.bib{stripped_label}")
            aliases.add(f"bib:bib{stripped_label}")
    return sorted(alias for alias in aliases if alias)


def clean_latex_text(value: str) -> str:
    cleaned = re.sub(r"(?<!\\)%[^\n]*(?:\n|$)", " ", value)
    cleaned = re.sub(r"\\(?:newblock|relax|noopsort)\b", " ", cleaned)
    cleaned = re.sub(
        r"\\(?:href|url|doi|arxiv)\s*\{([^{}]*)\}(?:\s*\{([^{}]*)\})?",
        lambda match: match.group(2) or match.group(1),
        cleaned,
        flags=re.IGNORECASE,
    )
    previous = None
    while previous != cleaned:
        previous = cleaned
        cleaned = re.sub(
            r"\\(?:emph|textit|textbf|textrm|textsc|mathrm|mathbf|mathit|mbox)\s*\{([^{}]*)\}",
            r"\1",
            cleaned,
        )
    cleaned = re.sub(r"\\['`\"^~=cHkruv]\s*\{?([A-Za-z])\}?", r"\1", cleaned)
    cleaned = re.sub(r"\\[A-Za-z]+\*?(?:\s*\[[^\]]*\])?", " ", cleaned)
    cleaned = re.sub(r"\\([#$%&_{}])", r"\1", cleaned)
    cleaned = cleaned.replace("~", " ").replace("--", "-")
    cleaned = cleaned.replace("{", "").replace("}", "")
    return re.sub(r"\s+", " ", unescape(cleaned)).strip()


def iter_bibtex_entry_bodies(text: str) -> list[tuple[str, str, str]]:
    entries: list[tuple[str, str, str]] = []
    index = 0
    while True:
        start = text.find("@", index)
        if start < 0:
            return entries
        match = re.match(r"@(?P<kind>[A-Za-z]+)\s*([({])\s*(?P<key>[^,\s{}()]+)\s*,", text[start:])
        if match is None:
            index = start + 1
            continue
        opener = match.group(2)
        closer = "}" if opener == "{" else ")"
        body_start = start + match.end()
        body_end = find_balanced_entry_end(text, body_start, opener, closer)
        if body_end is None:
            index = body_start
            continue
        entries.append((match.group("kind"), match.group("key"), text[body_start:body_end]))
        index = body_end + 1


def find_balanced_entry_end(text: str, body_start: int, opener: str, closer: str) -> int | None:
    depth = 1
    quote_open = False
    index = body_start
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == '"':
            quote_open = not quote_open
        elif not quote_open and char == opener:
            depth += 1
        elif not quote_open and char == closer:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def parse_bibtex_fields(body: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    index = 0
    while index < len(body):
        match = re.search(r"(?P<name>[A-Za-z][\w-]*)\s*=", body[index:])
        if match is None:
            break
        name = match.group("name").casefold()
        value_start = index + match.end()
        value, value_end = read_bibtex_value(body, value_start)
        fields[name] = value
        index = value_end
    return fields


def read_bibtex_value(body: str, start: int) -> tuple[str, int]:
    index = start
    while index < len(body) and body[index].isspace():
        index += 1
    parts: list[str] = []
    while index < len(body):
        char = body[index]
        if char == "{":
            value, index = read_balanced_bibtex_value(body, index, "{", "}")
            parts.append(value)
        elif char == '"':
            value, index = read_balanced_bibtex_value(body, index, '"', '"')
            parts.append(value)
        else:
            match = re.match(r"[^,#\s]+", body[index:])
            if match is None:
                break
            parts.append(match.group(0))
            index += len(match.group(0))
        while index < len(body) and body[index].isspace():
            index += 1
        if index < len(body) and body[index] == "#":
            index += 1
            continue
        break
    while index < len(body) and body[index] != ",":
        index += 1
    return " ".join(parts), index + 1 if index < len(body) else index


def read_balanced_bibtex_value(
    body: str,
    start: int,
    opener: str,
    closer: str,
) -> tuple[str, int]:
    index = start + 1
    depth = 1
    chars: list[str] = []
    while index < len(body):
        char = body[index]
        if char == "\\" and index + 1 < len(body):
            chars.append(char)
            chars.append(body[index + 1])
            index += 2
            continue
        if char == opener and opener != '"':
            depth += 1
        elif char == closer:
            depth -= 1
            if depth == 0:
                return "".join(chars), index + 1
        chars.append(char)
        index += 1
    return "".join(chars), index


def bibtex_arxiv_id(fields: dict[str, str]) -> str | None:
    for key in ("eprint", "arxiv", "arxivid"):
        value = clean_latex_text(fields.get(key, ""))
        if value:
            return value.removeprefix("arXiv:").strip()
    note = clean_latex_text(fields.get("note", ""))
    return citation_arxiv_id(note) if note else None


def html_attr(attrs: str, name: str) -> str | None:
    match = re.search(rf"\b{name}\s*=\s*(['\"])(.*?)\1", attrs, flags=re.IGNORECASE | re.DOTALL)
    return unescape(match.group(2)) if match else None


def clean_html_text(html: str) -> str:
    without_tags = re.sub(r"<[^>]+>", " ", html)
    return re.sub(r"\s+", " ", unescape(without_tags)).strip()


def clear_scholar_cache() -> None:
    _SCHOLAR_CACHE.clear()
    _ARXIV_CANDIDATE_CACHE.clear()
    _ARXIV_METADATA_CACHE.clear()
