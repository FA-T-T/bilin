from __future__ import annotations

import re
from dataclasses import dataclass, field

from bilin_api.article_store import (
    create_glossary_term,
    find_glossary_term_by_source,
    list_blocks,
    list_glossary_terms,
    list_translation_variants,
    sha256_text,
    update_glossary_term,
)
from bilin_api.schemas import (
    ArticleGlossary,
    DocumentBlock,
    GlossaryExtractionRequest,
    GlossaryExtractionResult,
    GlossaryTerm,
    GlossaryTermCreate,
    GlossaryTermUpdate,
    Library,
)

ABBREVIATION_PATTERN = re.compile(
    r"\b([A-Z][A-Za-z][A-Za-z0-9 -]{2,80}?)\s+\(([A-Z][A-Z0-9-]{1,12})\)"
)
CAPITALIZED_PHRASE_PATTERN = re.compile(
    r"\b(?:[A-Z][A-Za-z0-9-]+)(?:\s+(?:of|and|for|in|with|to|the|[A-Z][A-Za-z0-9-]+)){1,5}\b"
)
TECHNICAL_PHRASE_PATTERN = re.compile(r"\b[a-zA-Z][a-zA-Z0-9-]+(?:\s+[a-zA-Z][a-zA-Z0-9-]+){1,4}\b")
PROTECTED_INLINE_PATTERN = re.compile(r"(`[^`]*`|\$\$.*?\$\$|\$[^$]*\$)", re.DOTALL)
STOPWORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "by",
    "can",
    "for",
    "from",
    "in",
    "is",
    "it",
    "of",
    "on",
    "or",
    "that",
    "the",
    "this",
    "to",
    "we",
    "with",
}
MIN_OCCURRENCES = 2


@dataclass
class Candidate:
    source_term: str
    phrase_type: str
    block_uids: set[str] = field(default_factory=set)
    occurrence_count: int = 0
    acronym: str | None = None


async def get_article_glossary(
    library: Library,
    revision_id: str,
    target_language: str,
) -> ArticleGlossary:
    terms = await list_glossary_terms(
        library,
        revision_id=revision_id,
        target_language=target_language,
        scope="article",
    )
    active_terms = [term for term in terms if term.status == "active" and term.target_term.strip()]
    return ArticleGlossary(
        article_revision_id=revision_id,
        target_language=target_language,
        active_version=glossary_version(active_terms),
        terms=terms,
        affected_block_uids=await affected_translation_block_uids(
            library,
            revision_id,
            target_language,
            active_terms,
        ),
    )


async def extract_article_glossary_candidates(
    library: Library,
    revision_id: str,
    request: GlossaryExtractionRequest,
) -> GlossaryExtractionResult:
    blocks = await list_blocks(library, revision_id)
    candidates = sorted(
        collect_candidates(blocks).values(),
        key=lambda item: (-item.occurrence_count, item.source_term.casefold()),
    )
    created: list[GlossaryTerm] = []
    existing_candidates = 0
    for candidate in candidates[: request.limit]:
        existing = await find_glossary_term_by_source(
            library,
            revision_id,
            candidate.source_term,
            request.target_language,
        )
        if existing is not None:
            existing_candidates += 1
            created.append(existing)
            continue
        created.append(
            await create_glossary_term(
                library=library,
                scope="article",
                source_term=candidate.source_term,
                target_term="",
                language_direction=f"en->{request.target_language}",
                status="candidate",
                metadata={
                    "article_revision_id": revision_id,
                    "target_language": request.target_language,
                    "phrase_type": candidate.phrase_type,
                    "occurrence_count": candidate.occurrence_count,
                    "block_uids": sorted(candidate.block_uids),
                    "acronym": candidate.acronym,
                    "case_sensitive": False,
                    "preserve_source": False,
                    "source": "rule-based",
                },
            )
        )
    return GlossaryExtractionResult(
        article_revision_id=revision_id,
        target_language=request.target_language,
        candidates_created=len(created) - existing_candidates,
        existing_candidates=existing_candidates,
        terms=created,
    )


async def create_article_glossary_term(
    library: Library,
    revision_id: str,
    payload: GlossaryTermCreate,
) -> GlossaryTerm:
    target_language = target_language_from_direction(payload.language_direction)
    existing = await find_glossary_term_by_source(
        library,
        revision_id,
        payload.source_term,
        target_language,
    )
    metadata = {
        "article_revision_id": revision_id,
        "target_language": target_language,
        "case_sensitive": False,
        "preserve_source": False,
    }
    metadata.update(payload.metadata)
    if existing is not None:
        updated = await update_glossary_term(
            library,
            existing.id,
            target_term=payload.target_term,
            status=payload.status,
            metadata=metadata,
        )
        if updated is None:
            msg = f"Glossary term not found after update: {existing.id}"
            raise ValueError(msg)
        return updated
    return await create_glossary_term(
        library=library,
        scope="article",
        source_term=payload.source_term,
        target_term=payload.target_term,
        language_direction=payload.language_direction,
        status=payload.status,
        metadata=metadata,
    )


async def update_article_glossary_term(
    library: Library,
    revision_id: str,
    term_id: str,
    payload: GlossaryTermUpdate,
) -> GlossaryTerm | None:
    metadata = payload.metadata.copy() if payload.metadata is not None else {}
    metadata["article_revision_id"] = revision_id
    return await update_glossary_term(
        library,
        term_id,
        target_term=payload.target_term,
        status=payload.status,
        metadata=metadata,
    )


async def active_article_glossary_terms(
    library: Library,
    revision_id: str,
    target_language: str,
) -> list[GlossaryTerm]:
    terms = await list_glossary_terms(
        library,
        revision_id=revision_id,
        target_language=target_language,
        status="active",
        scope="article",
    )
    return [term for term in terms if term.target_term.strip()]


async def active_article_glossary_version(
    library: Library,
    revision_id: str,
    target_language: str,
) -> str:
    return glossary_version(
        await active_article_glossary_terms(library, revision_id, target_language)
    )


async def glossary_context_markdown(
    library: Library,
    revision_id: str,
    target_language: str,
) -> str:
    terms = await active_article_glossary_terms(library, revision_id, target_language)
    if not terms:
        return ""
    lines = [
        f"- {term.source_term} => {term.target_term}"
        for term in sorted(terms, key=lambda item: item.source_term.casefold())
    ]
    return "Active glossary:\n" + "\n".join(lines)


def apply_glossary_to_markdown(markdown: str, terms: list[GlossaryTerm]) -> str:
    active_terms = [term for term in terms if term.status == "active" and term.target_term.strip()]
    if not active_terms:
        return markdown
    chunks = PROTECTED_INLINE_PATTERN.split(markdown)
    rendered: list[str] = []
    for index, chunk in enumerate(chunks):
        if index % 2 == 1:
            rendered.append(chunk)
            continue
        rendered.append(apply_glossary_to_plain_text(chunk, active_terms))
    return "".join(rendered)


def apply_glossary_to_plain_text(text: str, terms: list[GlossaryTerm]) -> str:
    rendered = text
    for term in sorted(terms, key=lambda item: len(item.source_term), reverse=True):
        replacements = replacement_sources(term)
        for source in replacements:
            if not source:
                continue
            flags = 0 if term.metadata.get("case_sensitive") else re.IGNORECASE
            pattern = re.compile(
                rf"(?<![\w-]){re.escape(source)}(?![\w-])",
                flags,
            )
            rendered = pattern.sub(term.target_term, rendered)
    return rendered


def glossary_version(terms: list[GlossaryTerm]) -> str:
    active = [
        {
            "source_term": term.source_term,
            "target_term": term.target_term,
            "language_direction": term.language_direction,
            "updated_at": term.updated_at.isoformat()
            if hasattr(term.updated_at, "isoformat")
            else str(term.updated_at),
        }
        for term in sorted(terms, key=lambda item: item.source_term.casefold())
        if term.status == "active" and term.target_term.strip()
    ]
    if not active:
        return "glossary:none"
    return "glossary:" + sha256_text(repr(active))[:16]


async def affected_translation_block_uids(
    library: Library,
    revision_id: str,
    target_language: str,
    active_terms: list[GlossaryTerm],
) -> list[str]:
    if not active_terms:
        return []
    blocks = await list_blocks(library, revision_id)
    block_by_id = {block.id: block for block in blocks}
    current_version = glossary_version(active_terms)
    variants = await list_translation_variants(library, revision_id, target_language)
    affected: list[str] = []
    for variant in variants:
        if not variant.is_default or variant.glossary_version == current_version:
            continue
        block = block_by_id.get(variant.block_id)
        if block and block_matches_terms(block, active_terms):
            affected.append(block.block_uid)
    return sorted(set(affected))


def collect_candidates(blocks: list[DocumentBlock]) -> dict[str, Candidate]:
    candidates: dict[str, Candidate] = {}
    for block in blocks:
        if block.block_type not in {"paragraph", "section"}:
            continue
        text = strip_markdown_noise(block.source_markdown)
        collect_abbreviations(text, block, candidates)
        collect_capitalized_phrases(text, block, candidates)
        collect_repeated_phrases(text, block, candidates)
    return {
        key: candidate
        for key, candidate in candidates.items()
        if candidate.occurrence_count >= MIN_OCCURRENCES or candidate.acronym is not None
    }


def collect_abbreviations(
    text: str,
    block: DocumentBlock,
    candidates: dict[str, Candidate],
) -> None:
    for match in ABBREVIATION_PATTERN.finditer(text):
        phrase = clean_candidate(match.group(1))
        acronym = match.group(2)
        if is_candidate_phrase(phrase):
            add_candidate(candidates, phrase, "abbreviation", block.block_uid, acronym)


def collect_capitalized_phrases(
    text: str,
    block: DocumentBlock,
    candidates: dict[str, Candidate],
) -> None:
    for match in CAPITALIZED_PHRASE_PATTERN.finditer(text):
        phrase = clean_candidate(match.group(0))
        if is_candidate_phrase(phrase):
            add_candidate(candidates, phrase, "proper_noun", block.block_uid)


def collect_repeated_phrases(
    text: str,
    block: DocumentBlock,
    candidates: dict[str, Candidate],
) -> None:
    tokens = re.findall(r"[A-Za-z][A-Za-z0-9-]*", text)
    for size in range(2, 5):
        for start in range(0, max(0, len(tokens) - size + 1)):
            phrase = clean_candidate(" ".join(tokens[start : start + size]))
            if is_candidate_phrase(phrase) and not phrase.istitle():
                add_candidate(candidates, phrase, "noun_phrase", block.block_uid)
    for match in TECHNICAL_PHRASE_PATTERN.finditer(text):
        phrase = clean_candidate(match.group(0))
        if is_candidate_phrase(phrase) and not phrase.istitle():
            add_candidate(candidates, phrase, "noun_phrase", block.block_uid)


def add_candidate(
    candidates: dict[str, Candidate],
    phrase: str,
    phrase_type: str,
    block_uid: str,
    acronym: str | None = None,
) -> None:
    key = " ".join(phrase.casefold().split())
    candidate = candidates.setdefault(key, Candidate(source_term=phrase, phrase_type=phrase_type))
    candidate.occurrence_count += 1
    candidate.block_uids.add(block_uid)
    if acronym:
        candidate.acronym = acronym
        candidate.phrase_type = "abbreviation"


def block_matches_terms(block: DocumentBlock, terms: list[GlossaryTerm]) -> bool:
    text = strip_markdown_noise(block.source_markdown)
    return any(matches_term(text, term) for term in terms)


def matches_term(text: str, term: GlossaryTerm) -> bool:
    flags = 0 if term.metadata.get("case_sensitive") else re.IGNORECASE
    pattern = re.compile(rf"(?<![\w-]){re.escape(term.source_term)}(?![\w-])", flags)
    return pattern.search(text) is not None


def replacement_sources(term: GlossaryTerm) -> list[str]:
    sources = [term.source_term]
    previous = term.metadata.get("previous_target_terms")
    if isinstance(previous, list):
        sources.extend(str(item) for item in previous if isinstance(item, str))
    return sources


def strip_markdown_noise(markdown: str) -> str:
    text = PROTECTED_INLINE_PATTERN.sub(" ", markdown)
    text = re.sub(r"\[[^\]]+\]\([^)]+\)", " ", text)
    text = re.sub(r"[#*_>{}\[\](),.;:!?]", " ", text)
    return " ".join(text.split())


def clean_candidate(value: str) -> str:
    return " ".join(value.replace("\n", " ").strip(" -_:;,.()[]{}").split())


def is_candidate_phrase(value: str) -> bool:
    words = [word for word in re.split(r"\s+", value) if word]
    if len(words) < 2 or len(words) > 6:
        return False
    if len(value) < 4 or len(value) > 100:
        return False
    lowered = [word.casefold().strip("-") for word in words]
    if all(word in STOPWORDS for word in lowered):
        return False
    if lowered[0] in STOPWORDS or lowered[-1] in STOPWORDS:
        return False
    alpha_words = [word for word in lowered if re.search(r"[a-z]", word)]
    return len(alpha_words) >= 2


def target_language_from_direction(language_direction: str) -> str:
    if "->" in language_direction:
        return language_direction.rsplit("->", maxsplit=1)[1]
    return language_direction


def default_language_direction(target_language: str) -> str:
    return f"en->{target_language}"
