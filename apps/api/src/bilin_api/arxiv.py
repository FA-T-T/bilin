from __future__ import annotations

import asyncio
import email.utils
import json
import os
import re
import xml.etree.ElementTree as ET
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from time import monotonic, time

import httpx

from bilin_api.database import init_global_db, open_db, utc_now

ArxivApiParams = Mapping[str, str | int | float | bool | None]

ARXIV_API_URL = "https://export.arxiv.org/api/query"
ARXIV_SOURCE_URL = "https://arxiv.org/e-print/{idv}"
ARXIV_PDF_URL = "https://arxiv.org/pdf/{idv}.pdf"
ARXIV_RATE_LIMIT_SETTING_KEY = "network.arxiv.last_request_at"
DEFAULT_ARXIV_API_INTERVAL_SECONDS = 3.0
DEFAULT_ARXIV_API_RETRIES = 2
DEFAULT_ARXIV_API_TIMEOUT_SECONDS = 120.0
DEFAULT_ARXIV_DOWNLOAD_TIMEOUT_SECONDS = 300.0
MAX_RETRY_AFTER_SECONDS = 60.0
RETRYABLE_ARXIV_STATUS_CODES = {429, 500, 502, 503, 504}
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


class ArxivFetchError(RuntimeError):
    pass


_ARXIV_REQUEST_LOCK = asyncio.Lock()
_LAST_ARXIV_REQUEST_AT = 0.0


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


def arxiv_metadata_from_json(data: Mapping[str, object]) -> ArxivMetadata:
    return ArxivMetadata(
        bare_id=required_string(data, "bare_id"),
        version=required_string(data, "version"),
        concrete_id=required_string(data, "concrete_id"),
        title=required_string(data, "title"),
        authors=string_list(data.get("authors")),
        summary=required_string(data, "summary"),
        published=optional_string(data.get("published")),
        updated=optional_string(data.get("updated")),
        primary_category=optional_string(data.get("primary_category")),
        categories=string_list(data.get("categories")),
        abs_url=required_string(data, "abs_url"),
        source_url=required_string(data, "source_url"),
        pdf_url=required_string(data, "pdf_url"),
    )


def required_string(data: Mapping[str, object], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str):
        msg = f"Invalid cached arXiv metadata field: {key}"
        raise ValueError(msg)
    return value


def optional_string(value: object) -> str | None:
    return value if isinstance(value, str) and value else None


def string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


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
    active_client = client or httpx.AsyncClient(timeout=arxiv_api_timeout_seconds())
    try:
        response = await get_arxiv_api_response(
            active_client,
            params={"id_list": id_for_query},
        )
        response.raise_for_status()
        return parse_arxiv_atom(response.text, requested=identity)
    except httpx.HTTPError as exc:
        raise ArxivFetchError(
            http_error_message("arXiv metadata request", id_for_query, exc)
        ) from exc
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
    active_client = client or httpx.AsyncClient(timeout=arxiv_api_timeout_seconds())
    try:
        response = await get_arxiv_api_response(
            active_client,
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
    except httpx.HTTPError as exc:
        raise ArxivFetchError(http_error_message("arXiv title search", query, exc)) from exc
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
    active_client = client or httpx.AsyncClient(
        timeout=arxiv_download_timeout_seconds(),
        follow_redirects=True,
    )
    try:
        response = await get_arxiv_download_response(active_client, url)
        response.raise_for_status()
        return response.content
    except httpx.HTTPError as exc:
        raise ArxivFetchError(http_error_message("arXiv download", url, exc)) from exc
    finally:
        if owns_client:
            await active_client.aclose()


def http_error_message(action: str, target: str, exc: httpx.HTTPError) -> str:
    if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code == 429:
        retry_after = exc.response.headers.get("Retry-After")
        retry_text = f" Retry after {retry_after} seconds." if retry_after else ""
        return (
            f"{action} was rate limited by arXiv for {target}: HTTP 429."
            f"{retry_text} Try again later."
        )
    detail = str(exc).strip()
    suffix = f": {detail}" if detail else "."
    return f"{action} failed for {target}: {type(exc).__name__}{suffix}"


async def get_arxiv_api_response(
    client: httpx.AsyncClient,
    *,
    params: ArxivApiParams,
) -> httpx.Response:
    attempts = arxiv_request_attempts()
    response: httpx.Response | None = None
    last_error: httpx.TransportError | None = None
    for attempt in range(attempts):
        await wait_for_arxiv_api_slot()
        try:
            response = await client.get(ARXIV_API_URL, params=params)
        except httpx.TransportError as exc:
            last_error = exc
            if attempt >= attempts - 1:
                raise
            await sleep_for_arxiv_retry(None, attempt)
            continue
        if not should_retry_arxiv_response(response) or attempt >= attempts - 1:
            return response
        await sleep_for_arxiv_retry(response, attempt)
    if last_error is not None:
        raise last_error
    if response is None:
        msg = "arXiv API request did not produce a response."
        raise RuntimeError(msg)
    return response


async def get_arxiv_download_response(
    client: httpx.AsyncClient,
    url: str,
) -> httpx.Response:
    attempts = arxiv_request_attempts()
    response: httpx.Response | None = None
    last_error: httpx.TransportError | None = None
    for attempt in range(attempts):
        await wait_for_arxiv_request_slot()
        try:
            response = await client.get(url)
        except httpx.TransportError as exc:
            last_error = exc
            if attempt >= attempts - 1:
                raise
            await sleep_for_arxiv_retry(None, attempt)
            continue
        if not should_retry_arxiv_response(response) or attempt >= attempts - 1:
            return response
        await sleep_for_arxiv_retry(response, attempt)
    if last_error is not None:
        raise last_error
    if response is None:
        msg = "arXiv download request did not produce a response."
        raise RuntimeError(msg)
    return response


async def wait_for_arxiv_api_slot() -> None:
    await wait_for_arxiv_request_slot()


async def wait_for_arxiv_request_slot() -> None:
    interval = arxiv_request_interval_seconds()
    if interval <= 0:
        return
    try:
        await wait_for_persistent_arxiv_request_slot(interval)
    except Exception:
        await wait_for_process_arxiv_request_slot(interval)


async def wait_for_persistent_arxiv_request_slot(interval: float) -> None:
    while True:
        db_path = await init_global_db()
        async with open_db(db_path) as conn:
            await conn.execute("BEGIN IMMEDIATE")
            cursor = await conn.execute(
                "SELECT value_json FROM app_settings WHERE key = ?",
                (ARXIV_RATE_LIMIT_SETTING_KEY,),
            )
            row = await cursor.fetchone()
            last_request_at = arxiv_last_request_at(row["value_json"] if row else None)
            now = time()
            wait_seconds = interval - (now - last_request_at)
            if wait_seconds <= 0:
                await conn.execute(
                    """
                    INSERT INTO app_settings(key, value_json, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                      value_json = excluded.value_json,
                      updated_at = excluded.updated_at
                    """,
                    (ARXIV_RATE_LIMIT_SETTING_KEY, json.dumps(now), utc_now()),
                )
                await conn.commit()
                return
            await conn.commit()
        await asyncio.sleep(wait_seconds)


def arxiv_last_request_at(value_json: str | None) -> float:
    if not value_json:
        return 0.0
    try:
        value = json.loads(value_json)
    except json.JSONDecodeError:
        return 0.0
    return value if isinstance(value, (int, float)) and value > 0 else 0.0


async def wait_for_process_arxiv_request_slot(interval: float) -> None:
    global _LAST_ARXIV_REQUEST_AT  # noqa: PLW0603

    async with _ARXIV_REQUEST_LOCK:
        elapsed = monotonic() - _LAST_ARXIV_REQUEST_AT
        wait_seconds = interval - elapsed
        if wait_seconds > 0:
            await asyncio.sleep(wait_seconds)
        _LAST_ARXIV_REQUEST_AT = monotonic()


def arxiv_request_interval_seconds() -> float:
    return env_float("BILIN_ARXIV_REQUEST_INTERVAL_SECONDS", arxiv_api_interval_seconds())


def arxiv_api_interval_seconds() -> float:
    return env_float("BILIN_ARXIV_API_INTERVAL_SECONDS", DEFAULT_ARXIV_API_INTERVAL_SECONDS)


def arxiv_api_retries() -> int:
    return max(0, int(env_float("BILIN_ARXIV_API_RETRIES", DEFAULT_ARXIV_API_RETRIES)))


def arxiv_api_timeout_seconds() -> float:
    return env_float("BILIN_ARXIV_API_TIMEOUT_SECONDS", DEFAULT_ARXIV_API_TIMEOUT_SECONDS)


def arxiv_download_timeout_seconds() -> float:
    return env_float(
        "BILIN_ARXIV_DOWNLOAD_TIMEOUT_SECONDS",
        DEFAULT_ARXIV_DOWNLOAD_TIMEOUT_SECONDS,
    )


def arxiv_request_retries() -> int:
    return max(0, int(env_float("BILIN_ARXIV_RETRIES", arxiv_api_retries())))


def arxiv_request_attempts() -> int:
    return arxiv_request_retries() + 1


def should_retry_arxiv_response(response: httpx.Response) -> bool:
    return response.status_code in RETRYABLE_ARXIV_STATUS_CODES


async def sleep_for_arxiv_retry(response: httpx.Response | None, attempt: int) -> None:
    delay = arxiv_retry_delay(response, attempt)
    if delay > 0:
        await asyncio.sleep(delay)


def arxiv_retry_delay(response: httpx.Response | None, attempt: int) -> float:
    retry_after = parse_retry_after(response.headers.get("Retry-After")) if response else None
    if retry_after is not None:
        return retry_after
    return min(MAX_RETRY_AFTER_SECONDS, arxiv_request_interval_seconds() * (2**attempt))


def parse_retry_after(value: str | None) -> float | None:
    if not value:
        return None
    try:
        seconds = float(value)
    except ValueError:
        try:
            retry_at = email.utils.parsedate_to_datetime(value)
        except (TypeError, ValueError):
            return None
        if retry_at.tzinfo is None:
            retry_at = retry_at.replace(tzinfo=UTC)
        seconds = (retry_at - datetime.now(UTC)).total_seconds()
    return min(MAX_RETRY_AFTER_SECONDS, max(0.0, seconds))


def env_float(name: str, fallback: float) -> float:
    value = os.getenv(name)
    if value is None:
        return fallback
    try:
        parsed = float(value)
    except ValueError:
        return fallback
    return parsed if parsed >= 0 else fallback


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
    active_client = client or httpx.AsyncClient(timeout=arxiv_api_timeout_seconds())
    try:
        response = await get_arxiv_api_response(
            active_client,
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
    except httpx.HTTPError as exc:
        raise ArxivFetchError(http_error_message("arXiv search", search_query, exc)) from exc
    finally:
        if owns_client:
            await active_client.aclose()


def parse_arxiv_search_feed(xml_text: str) -> list[ArxivMetadata]:
    root = ET.fromstring(xml_text)
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    return [metadata_from_entry(entry) for entry in root.findall("atom:entry", ns)]


def _text(element: ET.Element | None) -> str:
    return "".join(element.itertext()) if element is not None else ""


def _optional_text(element: ET.Element | None) -> str | None:
    value = _text(element).strip()
    return value or None
