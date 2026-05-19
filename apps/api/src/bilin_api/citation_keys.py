from __future__ import annotations

import re

_AUTHOR_YEAR_KEY_RE = re.compile(
    r"^(?P<authors>[A-Za-z][A-Za-z0-9.-]*(?:_[A-Za-z][A-Za-z0-9.-]*)*)"
    r":\s*(?P<year>19\d{2}|20\d{2})(?P<suffix>[a-z]?)$"
)
_AUTHOR_YEAR_KEY_IN_TEXT_RE = re.compile(
    r"(?<![A-Za-z0-9_.-])"
    r"(?P<authors>[A-Za-z][A-Za-z0-9.-]*(?:_[A-Za-z][A-Za-z0-9.-]*)*)"
    r":\s*(?P<year>19\d{2}|20\d{2})(?P<suffix>[a-z]?)"
    r"(?![A-Za-z0-9_.-])"
)


def parse_author_year_citation_key(key: str) -> tuple[str, str] | None:
    match = _AUTHOR_YEAR_KEY_RE.fullmatch(normalize_citation_key(key))
    if not match:
        return None
    return humanize_citation_authors(match.group("authors")), (
        match.group("year") + match.group("suffix")
    )


def humanize_citation_key(key: str) -> str:
    parsed = parse_author_year_citation_key(key)
    if parsed is None:
        return normalize_citation_key(key)
    authors, year = parsed
    return f"{authors} {year}"


def humanize_missing_citation_text(text: str) -> str:
    normalized = " ".join(text.replace("\xa0", " ").split())
    if normalized.startswith("[") and normalized.endswith("]"):
        normalized = normalized[1:-1].strip()
    normalized = re.sub(r"\s+([,.;:])", r"\1", normalized)
    normalized = re.sub(r"([,;:])(?=\S)", r"\1 ", normalized)

    def replace(match: re.Match[str]) -> str:
        authors = humanize_citation_authors(match.group("authors"))
        return f"{authors} {match.group('year')}{match.group('suffix')}"

    return re.sub(r"\s{2,}", " ", _AUTHOR_YEAR_KEY_IN_TEXT_RE.sub(replace, normalized)).strip()


def humanize_citation_authors(authors_key: str) -> str:
    parts = [part.strip() for part in authors_key.split("_") if part.strip()]
    if not parts:
        return authors_key
    if len(parts) == 1:
        return parts[0]
    if len(parts) == 2:
        return f"{parts[0]} and {parts[1]}"
    return f"{parts[0]} et al."


def missing_citation_id(key: str) -> str:
    slug = normalize_citation_key(key).replace(":", "-").replace(" ", "")
    slug = re.sub(r"[^A-Za-z0-9_.-]+", "-", slug).strip("-")
    return f"missing.{slug or 'citation'}"


def normalize_citation_key(key: str) -> str:
    return re.sub(r"\s+", " ", key.replace("\xa0", " ")).strip()
