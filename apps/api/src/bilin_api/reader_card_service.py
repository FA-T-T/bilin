from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import quote

import httpx

from bilin_api.article_store import (
    archive_reader_card,
    create_reader_card,
    find_reader_card_by_canonical_key,
    find_shared_reader_card,
    get_article_item,
    get_block_by_uid,
    get_reader_card,
    list_blocks,
    list_reader_cards,
    update_reader_card,
)
from bilin_api.llm import LLMClientError, generate_reader_card_markdown
from bilin_api.obsidian_service import save_obsidian_term_cards
from bilin_api.repositories import create_job, get_provider_api_key, get_provider_profile
from bilin_api.schemas import (
    Job,
    JobType,
    Library,
    ReaderCard,
    ReaderCardCreate,
    ReaderCardExtractionRequest,
    ReaderCardExtractionResult,
    ReaderCardGenerationRequest,
    ReaderCardGenerationResult,
    ReaderCardObsidianExportRequest,
    ReaderCardObsidianExportResult,
    ReaderCards,
    ReaderCardSourceType,
    ReaderCardStatus,
    ReaderCardType,
    ReaderCardUpdate,
)

FULL_FORM_ABBREVIATION_PATTERN = re.compile(
    r"\b(?P<full>[A-Z][A-Za-z0-9][A-Za-z0-9 /,\-]{2,120}?)\s*\((?P<abbr>[A-Z][A-Z0-9\-]{1,16})\)"
)
ABBREVIATION_FULL_FORM_PATTERN = re.compile(
    r"\b(?P<abbr>[A-Z][A-Z0-9\-]{1,16})\s*\((?P<full>[A-Z][A-Za-z0-9][A-Za-z0-9 /,\-]{2,120}?)\)"
)
CAPITALIZED_TECH_PATTERN = re.compile(
    r"\b(?:[A-Z][A-Za-z0-9+\-]+)(?:\s+(?:of|and|for|in|with|to|the|[A-Z][A-Za-z0-9+\-]+)){1,5}\b"
)
CAMEL_OR_METHOD_PATTERN = re.compile(r"\b[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]+)+\b")
STANDALONE_ACRONYM_PATTERN = re.compile(r"\b[A-Z][A-Z0-9]{2,12}(?:-[A-Z0-9]{1,8})?\b")
PROTECTED_MARKDOWN_PATTERN = re.compile(
    r"(`[^`]*`|\$\$.*?\$\$|\$[^$]*\$|!\[[^\]]*]\([^)]*\)|\[[^\]]+]\([^)]*\))",
    re.DOTALL,
)
LEADING_NOISE_PATTERN = re.compile(
    r"^(?:and|or|of|for|with|without|using|via|as|in|to|from|by|on|the|a|an|this|that|these|those|our|their)\s+",
    re.IGNORECASE,
)
TRAILING_NOISE_PATTERN = re.compile(
    r"\b(?:and|or|of|for|with|without|using|via|as|in|to|from|by|on|the|a|an)\s*$",
    re.IGNORECASE,
)
CITATION_TOKEN_PATTERN = re.compile(r"^[A-Z][A-Za-z]+[12][0-9]{3}[a-z]?$")
TRAILING_CITATION_TOKENS_PATTERN = re.compile(r"(?:\s+[A-Z][A-Za-z]+[12][0-9]{3}[a-z]?)+$")
CONNECTOR_WORDS = {
    "and",
    "as",
    "by",
    "for",
    "from",
    "in",
    "of",
    "on",
    "the",
    "to",
    "via",
    "with",
    "without",
}
STOP_ACRONYMS = {
    "AND",
    "APPENDIX",
    "ARE",
    "FIG",
    "FOR",
    "FROM",
    "HAS",
    "HAVE",
    "HTTP",
    "HTTPS",
    "IMG",
    "NOT",
    "OUR",
    "SEC",
    "SECTION",
    "TABLE",
    "THE",
    "THIS",
    "THAT",
    "WITH",
}
STOP_TERMS = {
    "This paper",
    "The paper",
    "In this",
    "We",
    "For",
    "This",
    "Figure",
    "Table",
    "Section",
    "Appendix",
}
WIKI_TIMEOUT_SECONDS = 8.0


@dataclass
class ReaderCardCandidate:
    anchor_text: str
    title: str
    anchor_block_uid: str
    abbreviation: str | None = None
    full_form: str | None = None
    candidate_type: str = "term"
    block_uids: set[str] = field(default_factory=set)
    occurrence_count: int = 0

    @property
    def canonical_key(self) -> str:
        return canonical_key_for_term(self.abbreviation, self.full_form or self.title)


@dataclass
class WikiSummary:
    title: str
    body_markdown: str
    source_url: str
    wikidata_id: str | None
    language: str


async def get_article_reader_cards(
    library: Library,
    revision_id: str,
    target_language: str,
) -> ReaderCards:
    return ReaderCards(
        article_revision_id=revision_id,
        target_language=target_language,
        cards=visible_reader_cards(await list_reader_cards(library, revision_id, target_language)),
    )


async def create_manual_reader_card(
    library: Library,
    revision_id: str,
    payload: ReaderCardCreate,
) -> ReaderCard:
    await ensure_article_exists(library, revision_id)
    canonical_key = canonical_key_for_term(
        payload.abbreviation,
        payload.full_form or payload.anchor_text or payload.title,
    )
    return await create_reader_card(
        library,
        revision_id=revision_id,
        card_type=payload.card_type,
        anchor_block_uid=payload.anchor_block_uid,
        anchor_text=payload.anchor_text,
        canonical_key=canonical_key,
        abbreviation=payload.abbreviation,
        full_form=payload.full_form,
        title=payload.title,
        body_markdown=strip_card_body(payload.body_markdown),
        target_language=payload.target_language,
        source_type=payload.source_type,
        source_url=payload.source_url,
        position=payload.position,
        status=payload.status,
        metadata={
            **payload.metadata,
            "user_created": True,
            "user_edited": bool(payload.body_markdown.strip()),
        },
    )


async def update_article_reader_card(
    library: Library,
    revision_id: str,
    card_id: str,
    payload: ReaderCardUpdate,
) -> ReaderCard | None:
    current = await get_reader_card(library, revision_id, card_id)
    if current is None:
        return None
    abbreviation = (
        payload.abbreviation if payload.abbreviation is not None else current.abbreviation
    )
    full_form = payload.full_form if payload.full_form is not None else current.full_form
    title = payload.title if payload.title is not None else current.title
    canonical_key = canonical_key_for_term(abbreviation, full_form or title)
    metadata = {"user_edited": True}
    if payload.metadata is not None:
        metadata.update(payload.metadata)
    return await update_reader_card(
        library,
        revision_id,
        card_id,
        anchor_text=payload.anchor_text,
        abbreviation=payload.abbreviation,
        full_form=payload.full_form,
        title=payload.title,
        body_markdown=(
            strip_card_body(payload.body_markdown) if payload.body_markdown is not None else None
        ),
        source_url=payload.source_url,
        position=payload.position,
        status=payload.status,
        metadata=metadata,
        canonical_key=canonical_key,
    )


async def archive_article_reader_card(
    library: Library,
    revision_id: str,
    card_id: str,
) -> ReaderCard | None:
    return await archive_reader_card(library, revision_id, card_id)


async def extract_article_reader_cards(
    library: Library,
    revision_id: str,
    request: ReaderCardExtractionRequest,
    client: httpx.AsyncClient | None = None,
) -> ReaderCardExtractionResult:
    await ensure_article_exists(library, revision_id)
    existing_cards = await list_reader_cards(library, revision_id, request.target_language)
    if not request.force and has_auto_extraction(existing_cards):
        return ReaderCardExtractionResult(
            article_revision_id=revision_id,
            target_language=request.target_language,
            candidates_created=0,
            existing_candidates=len(existing_cards),
            wiki_cards_created=0,
            cards=existing_cards,
        )

    blocks = await list_blocks(library, revision_id)
    candidates = collect_reader_card_candidates(blocks)[: request.limit]
    cards: list[ReaderCard] = []
    candidates_created = 0
    existing_candidates = 0
    wiki_cards_created = 0

    for candidate in candidates:
        if not candidate.canonical_key:
            continue
        existing = await find_reader_card_by_canonical_key(
            library,
            revision_id,
            candidate.canonical_key,
            request.target_language,
        )
        if existing is not None:
            existing_candidates += 1
            cards.append(existing)
            continue

        shared = await reusable_shared_card(library, candidate, request.target_language)
        if shared is not None:
            cards.append(
                await copy_shared_card(
                    library,
                    revision_id=revision_id,
                    candidate=candidate,
                    target_language=request.target_language,
                    shared=shared,
                )
            )
            candidates_created += 1
            continue

        wiki = None
        if candidate.full_form:
            wiki = await lookup_wikipedia_summary(
                candidate.full_form,
                request.target_language,
                client=client,
            )
        if wiki is not None:
            card = await create_reader_card(
                library,
                revision_id=revision_id,
                card_type=ReaderCardType.term,
                anchor_block_uid=candidate.anchor_block_uid,
                anchor_text=candidate.anchor_text,
                canonical_key=candidate.canonical_key,
                abbreviation=candidate.abbreviation,
                full_form=candidate.full_form,
                title=card_title(candidate),
                body_markdown=wiki.body_markdown,
                target_language=request.target_language,
                source_type=ReaderCardSourceType.wikipedia,
                source_url=wiki.source_url,
                status=ReaderCardStatus.candidate,
                metadata=card_metadata(candidate, "auto_extract")
                | {
                    "wikidata_id": wiki.wikidata_id,
                    "wikipedia_language": wiki.language,
                },
            )
            wiki_cards_created += 1
        else:
            card = await create_reader_card(
                library,
                revision_id=revision_id,
                card_type=ReaderCardType.term,
                anchor_block_uid=candidate.anchor_block_uid,
                anchor_text=candidate.anchor_text,
                canonical_key=candidate.canonical_key,
                abbreviation=candidate.abbreviation,
                full_form=candidate.full_form,
                title=card_title(candidate),
                body_markdown="",
                target_language=request.target_language,
                source_type=ReaderCardSourceType.paper_local,
                status=ReaderCardStatus.candidate,
                metadata=card_metadata(candidate, "auto_extract") | {"requires_generation": True},
            )
        cards.append(card)
        candidates_created += 1

    return ReaderCardExtractionResult(
        article_revision_id=revision_id,
        target_language=request.target_language,
        candidates_created=candidates_created,
        existing_candidates=existing_candidates,
        wiki_cards_created=wiki_cards_created,
        cards=cards,
    )


async def generate_article_reader_card(
    library: Library,
    revision_id: str,
    payload: ReaderCardGenerationRequest,
) -> ReaderCardGenerationResult:
    await ensure_article_exists(library, revision_id)
    block = await get_block_by_uid(library, revision_id, payload.anchor_block_uid)
    if block is None:
        msg = f"Block not found: {payload.anchor_block_uid}"
        raise ValueError(msg)
    title = payload.title or payload.full_form or payload.anchor_text
    canonical_key = canonical_key_for_term(payload.abbreviation, payload.full_form or title)
    existing = await find_reader_card_by_canonical_key(
        library,
        revision_id,
        canonical_key,
        payload.target_language,
    )

    body, native_search_used, source_type = await generated_card_body(
        library,
        revision_id,
        payload,
    )
    metadata = {
        "generation_source": "manual",
        "evidence_block_uids": [payload.anchor_block_uid],
        "ai_generated": source_type != ReaderCardSourceType.wikipedia,
    }
    if source_type == ReaderCardSourceType.ai_search:
        metadata["native_search_used"] = True

    if existing is not None:
        if existing.metadata.get("user_edited"):
            updated = await update_reader_card(
                library,
                revision_id,
                existing.id,
                metadata={
                    "suggested_body_markdown": body,
                    "suggested_source_type": source_type.value,
                    "suggested_at": True,
                },
            )
            card = updated or existing
        else:
            updated = await update_reader_card(
                library,
                revision_id,
                existing.id,
                anchor_text=payload.anchor_text,
                abbreviation=payload.abbreviation,
                full_form=payload.full_form,
                title=title,
                body_markdown=body,
                source_type=source_type,
                status=ReaderCardStatus.pinned,
                metadata=metadata,
                canonical_key=canonical_key,
            )
            if updated is None:
                msg = f"Reader card disappeared during update: {existing.id}"
                raise RuntimeError(msg)
            card = updated
    else:
        card = await create_reader_card(
            library,
            revision_id=revision_id,
            card_type=payload.card_type,
            anchor_block_uid=payload.anchor_block_uid,
            anchor_text=payload.anchor_text,
            canonical_key=canonical_key,
            abbreviation=payload.abbreviation,
            full_form=payload.full_form,
            title=title,
            body_markdown=body,
            target_language=payload.target_language,
            source_type=source_type,
            status=ReaderCardStatus.pinned,
            metadata=metadata,
        )
    return ReaderCardGenerationResult(
        article_revision_id=revision_id,
        card=card,
        native_search_used=native_search_used,
        source_type=source_type,
    )


async def export_reader_cards_to_obsidian(
    library: Library,
    revision_id: str,
    payload: ReaderCardObsidianExportRequest,
) -> ReaderCardObsidianExportResult:
    cards = await list_reader_cards(library, revision_id, payload.target_language)
    if payload.card_ids is not None:
        selected = set(payload.card_ids)
        cards = [card for card in cards if card.id in selected]
    cards = [
        card
        for card in cards
        if card.card_type == ReaderCardType.term
        and card.body_markdown.strip()
        and card.status != ReaderCardStatus.archived
    ]
    result = await save_obsidian_term_cards(library, cards)
    for card in cards:
        await update_reader_card(
            library,
            revision_id,
            card.id,
            status=ReaderCardStatus.exported,
            metadata={"exported_to_obsidian": True},
        )
    return result


async def queue_reader_card_extraction(
    library: Library,
    revision_id: str,
    payload: ReaderCardExtractionRequest | None = None,
) -> Job:
    request = payload or ReaderCardExtractionRequest()
    return await create_job(
        JobType.extract_reader_cards,
        payload={
            "library_id": library.id,
            "article_revision_id": revision_id,
            "request": request.model_dump(mode="json"),
        },
        priority=-5,
    )


async def queue_reader_card_generation(
    library: Library,
    revision_id: str,
    payload: ReaderCardGenerationRequest,
) -> Job:
    return await create_job(
        JobType.generate_reader_card,
        payload={
            "library_id": library.id,
            "article_revision_id": revision_id,
            "request": payload.model_dump(mode="json"),
        },
    )


async def ensure_article_exists(library: Library, revision_id: str) -> None:
    if await get_article_item(library, revision_id) is None:
        msg = f"Article revision not found: {revision_id}"
        raise ValueError(msg)


def has_auto_extraction(cards: list[ReaderCard]) -> bool:
    return any(card.metadata.get("extraction_source") == "auto_extract" for card in cards)


def collect_reader_card_candidates(blocks: list[Any]) -> list[ReaderCardCandidate]:
    candidates: dict[str, ReaderCardCandidate] = {}
    for block in blocks:
        if block.block_type not in {"paragraph", "abstract", "figure", "table"}:
            continue
        text = plain_candidate_text(block.source_markdown)
        for pattern in (FULL_FORM_ABBREVIATION_PATTERN, ABBREVIATION_FULL_FORM_PATTERN):
            for match in pattern.finditer(text):
                full_form = clean_term(match.group("full"))
                abbreviation = clean_abbreviation(match.group("abbr"))
                if not full_form or not abbreviation:
                    continue
                register_candidate(
                    candidates,
                    ReaderCardCandidate(
                        anchor_text=abbreviation,
                        title=full_form,
                        anchor_block_uid=block.block_uid,
                        abbreviation=abbreviation,
                        full_form=full_form,
                        candidate_type="abbreviation_pair",
                        block_uids={block.block_uid},
                        occurrence_count=1,
                    ),
                )
        for match in CAPITALIZED_TECH_PATTERN.finditer(text):
            term = clean_term(match.group(0))
            if not high_value_term(term):
                continue
            register_candidate(
                candidates,
                ReaderCardCandidate(
                    anchor_text=term,
                    title=term,
                    anchor_block_uid=block.block_uid,
                    full_form=term,
                    candidate_type="technical_name",
                    block_uids={block.block_uid},
                    occurrence_count=1,
                ),
            )
        for match in STANDALONE_ACRONYM_PATTERN.finditer(text):
            term = clean_term(match.group(0))
            if not high_value_term(term):
                continue
            register_candidate(
                candidates,
                ReaderCardCandidate(
                    anchor_text=term,
                    title=term,
                    anchor_block_uid=block.block_uid,
                    full_form=term,
                    candidate_type="acronym_or_dataset",
                    block_uids={block.block_uid},
                    occurrence_count=1,
                ),
            )
        for match in CAMEL_OR_METHOD_PATTERN.finditer(text):
            term = clean_term(match.group(0))
            if not high_value_term(term):
                continue
            register_candidate(
                candidates,
                ReaderCardCandidate(
                    anchor_text=term,
                    title=term,
                    anchor_block_uid=block.block_uid,
                    full_form=term,
                    candidate_type="method_name",
                    block_uids={block.block_uid},
                    occurrence_count=1,
                ),
            )
    filtered_candidates = remove_redundant_full_form_candidates(candidates.values())
    filtered_candidates = remove_context_phrase_candidates(filtered_candidates)
    return sorted(
        filtered_candidates,
        key=lambda item: (
            0 if item.abbreviation and item.full_form else 1,
            -item.occurrence_count,
            item.title.casefold(),
        ),
    )


def register_candidate(
    candidates: dict[str, ReaderCardCandidate],
    candidate: ReaderCardCandidate,
) -> None:
    if candidate.title in STOP_TERMS:
        return
    if candidate.candidate_type != "abbreviation_pair" and not high_value_term(
        candidate.full_form or candidate.title
    ):
        return
    key = candidate.canonical_key
    if not key:
        return
    existing = candidates.get(key)
    if existing is None:
        candidates[key] = candidate
        return
    existing.block_uids.update(candidate.block_uids)
    existing.occurrence_count += candidate.occurrence_count
    if not existing.abbreviation and candidate.abbreviation:
        existing.abbreviation = candidate.abbreviation
    if not existing.full_form and candidate.full_form:
        existing.full_form = candidate.full_form


def remove_redundant_full_form_candidates(
    candidates: Any,
) -> list[ReaderCardCandidate]:
    items = list(candidates)
    full_forms_with_abbreviation = {
        normalize_full_form(item.full_form or "")
        for item in items
        if item.abbreviation and item.full_form
    }
    return [
        item
        for item in items
        if item.abbreviation
        or normalize_full_form(item.full_form or item.title) not in full_forms_with_abbreviation
    ]


def remove_context_phrase_candidates(
    candidates: list[ReaderCardCandidate],
) -> list[ReaderCardCandidate]:
    return [item for item in candidates if high_value_term(item.full_form or item.title)]


def visible_reader_cards(cards: list[ReaderCard]) -> list[ReaderCard]:
    visible: list[ReaderCard] = []
    for card in cards:
        if card.metadata.get("extraction_source") != "auto_extract":
            visible.append(card)
            continue
        if card.status != ReaderCardStatus.candidate:
            visible.append(card)
            continue
        if not auto_extracted_card_is_valid(card):
            continue
        visible.append(card)
    return visible


def auto_extracted_card_is_valid(card: ReaderCard) -> bool:
    if card.card_type != ReaderCardType.term:
        return True
    term = card.full_form or card.title
    cleaned = clean_term(term)
    if cleaned != term.strip():
        return False
    return high_value_term(cleaned)


async def reusable_shared_card(
    library: Library,
    candidate: ReaderCardCandidate,
    target_language: str,
) -> ReaderCard | None:
    if not candidate.abbreviation or not candidate.full_form:
        return None
    return await find_shared_reader_card(library, candidate.canonical_key, target_language)


async def copy_shared_card(
    library: Library,
    *,
    revision_id: str,
    candidate: ReaderCardCandidate,
    target_language: str,
    shared: ReaderCard,
) -> ReaderCard:
    return await create_reader_card(
        library,
        revision_id=revision_id,
        card_type=shared.card_type,
        anchor_block_uid=candidate.anchor_block_uid,
        anchor_text=candidate.anchor_text,
        canonical_key=candidate.canonical_key,
        abbreviation=candidate.abbreviation,
        full_form=candidate.full_form,
        title=shared.title,
        body_markdown=shared.body_markdown,
        target_language=target_language,
        source_type=shared.source_type,
        source_url=shared.source_url,
        status=ReaderCardStatus.candidate,
        metadata=card_metadata(candidate, "auto_extract") | {"shared_from_card_id": shared.id},
    )


async def generated_card_body(
    library: Library,
    revision_id: str,
    payload: ReaderCardGenerationRequest,
) -> tuple[str, bool, ReaderCardSourceType]:
    evidence = await card_evidence_markdown(library, revision_id, payload.anchor_block_uid)
    provider = (
        await get_provider_profile(payload.provider_profile_id)
        if payload.provider_profile_id
        else None
    )
    if provider is not None:
        api_key = await get_provider_api_key(provider)
        model = payload.model or provider.default_model
        native_search_used = bool(
            payload.native_search and provider.capabilities.get("native_search")
        )
        if api_key and model:
            try:
                response = await generate_reader_card_markdown(
                    provider,
                    api_key,
                    model,
                    payload.full_form or payload.title or payload.anchor_text,
                    payload.target_language,
                    evidence,
                    native_search=native_search_used,
                )
                source_type = (
                    ReaderCardSourceType.ai_search
                    if native_search_used
                    else ReaderCardSourceType.paper_local
                )
                return strip_card_body(response.text), native_search_used, source_type
            except LLMClientError:
                pass
    return (
        local_card_body(
            payload.full_form or payload.title or payload.anchor_text,
            evidence,
            payload.target_language,
        ),
        False,
        ReaderCardSourceType.paper_local,
    )


async def card_evidence_markdown(library: Library, revision_id: str, block_uid: str) -> str:
    blocks = await list_blocks(library, revision_id)
    index = next((idx for idx, block in enumerate(blocks) if block.block_uid == block_uid), -1)
    if index == -1:
        return ""
    selected = blocks[max(0, index - 1) : min(len(blocks), index + 2)]
    lines = [f"[{block.block_uid}] {block.source_markdown.strip()}" for block in selected]
    return "\n\n".join(line for line in lines if line.strip())


def local_card_body(term: str, evidence: str, target_language: str) -> str:
    snippet = re.sub(r"\s+", " ", evidence).strip()
    if len(snippet) > 220:
        snippet = snippet[:217].rstrip() + "..."
    if target_language.casefold().startswith("zh"):
        return (
            f"{term} 是本文语境中的一个关键概念。根据相邻段落，它主要用于连接论文的"
            "定义、方法或实验表述；当前版本的解释只基于本文内容，需要时可以再用支持"
            "检索的模型生成更完整的卡片。"
        )
    return (
        f"{term} is a key concept in this paper context. The local evidence links it to "
        f"the paper's definitions, method, or experiments; this card is based only on the paper "
        f"context and can be regenerated with a search-capable model when needed. {snippet}"
    ).strip()


def card_title(candidate: ReaderCardCandidate) -> str:
    if candidate.abbreviation and candidate.full_form:
        return f"{candidate.full_form} ({candidate.abbreviation})"
    return candidate.title


def card_metadata(candidate: ReaderCardCandidate, extraction_source: str) -> dict[str, Any]:
    return {
        "extraction_source": extraction_source,
        "candidate_type": candidate.candidate_type,
        "evidence_block_uids": sorted(candidate.block_uids),
        "occurrence_count": candidate.occurrence_count,
    }


async def lookup_wikipedia_summary(
    full_form: str,
    target_language: str,
    client: httpx.AsyncClient | None = None,
) -> WikiSummary | None:
    owns_client = client is None
    active_client = client or httpx.AsyncClient(timeout=WIKI_TIMEOUT_SECONDS)
    try:
        entity = await find_wikidata_entity(active_client, full_form)
        if entity is None:
            return None
        title, lang = wikipedia_title_for_entity(entity, target_language)
        if not title:
            return None
        summary = await wikipedia_summary(active_client, title, lang)
        if summary is None and lang != "en":
            fallback_title, fallback_lang = wikipedia_title_for_entity(entity, "en")
            if fallback_title:
                summary = await wikipedia_summary(active_client, fallback_title, fallback_lang)
        return summary
    except (httpx.HTTPError, KeyError, ValueError, TypeError):
        return None
    finally:
        if owns_client:
            await active_client.aclose()


async def find_wikidata_entity(
    client: httpx.AsyncClient,
    full_form: str,
) -> dict[str, Any] | None:
    search_response = await client.get(
        "https://www.wikidata.org/w/api.php",
        params={
            "action": "wbsearchentities",
            "search": full_form,
            "language": "en",
            "format": "json",
            "limit": 5,
            "type": "item",
        },
    )
    search_response.raise_for_status()
    results = search_response.json().get("search")
    if not isinstance(results, list):
        return None
    ids = [item.get("id") for item in results if isinstance(item, dict) and item.get("id")]
    if not ids:
        return None
    entity_response = await client.get(
        "https://www.wikidata.org/w/api.php",
        params={
            "action": "wbgetentities",
            "ids": "|".join(str(item) for item in ids[:5]),
            "props": "labels|aliases|sitelinks",
            "languages": "en|zh|ja|ko|es|fr|de",
            "format": "json",
        },
    )
    entity_response.raise_for_status()
    entities = entity_response.json().get("entities")
    if not isinstance(entities, dict):
        return None
    for entity_id in ids:
        entity = entities.get(entity_id)
        if isinstance(entity, dict) and entity_matches_full_form(entity, full_form):
            entity["id"] = entity_id
            return entity
    return None


def entity_matches_full_form(entity: dict[str, Any], full_form: str) -> bool:
    expected = normalize_full_form(full_form)
    raw_labels = entity.get("labels")
    labels = raw_labels if isinstance(raw_labels, dict) else {}
    raw_aliases = entity.get("aliases")
    aliases = raw_aliases if isinstance(raw_aliases, dict) else {}
    candidates: list[str] = []
    for value in labels.values():
        if isinstance(value, dict) and isinstance(value.get("value"), str):
            candidates.append(value["value"])
    for values in aliases.values():
        if isinstance(values, list):
            for value in values:
                if isinstance(value, dict) and isinstance(value.get("value"), str):
                    candidates.append(value["value"])
    sitelinks = entity.get("sitelinks")
    if isinstance(sitelinks, dict):
        for value in sitelinks.values():
            if isinstance(value, dict) and isinstance(value.get("title"), str):
                candidates.append(value["title"])
    return any(normalize_full_form(candidate) == expected for candidate in candidates)


def wikipedia_title_for_entity(
    entity: dict[str, Any],
    target_language: str,
) -> tuple[str | None, str]:
    lang = wikipedia_language(target_language)
    raw_sitelinks = entity.get("sitelinks")
    sitelinks = raw_sitelinks if isinstance(raw_sitelinks, dict) else {}
    for active_lang in (lang, "en"):
        site = sitelinks.get(f"{active_lang}wiki")
        if isinstance(site, dict) and isinstance(site.get("title"), str):
            return site["title"], active_lang
    return None, lang


async def wikipedia_summary(
    client: httpx.AsyncClient,
    title: str,
    language: str,
) -> WikiSummary | None:
    response = await client.get(
        f"https://{language}.wikipedia.org/api/rest_v1/page/summary/{quote_wiki_title(title)}",
        headers={"Accept": "application/json"},
    )
    if response.status_code == 404:
        return None
    response.raise_for_status()
    payload = response.json()
    extract = payload.get("extract")
    if not isinstance(extract, str) or not extract.strip():
        return None
    url = None
    content_urls = payload.get("content_urls")
    if isinstance(content_urls, dict):
        desktop = content_urls.get("desktop")
        if isinstance(desktop, dict) and isinstance(desktop.get("page"), str):
            url = desktop["page"]
    if not url:
        url = f"https://{language}.wikipedia.org/wiki/{quote_wiki_title(title)}"
    return WikiSummary(
        title=str(payload.get("title") or title),
        body_markdown=short_summary(extract),
        source_url=url,
        wikidata_id=str(payload.get("wikibase_item")) if payload.get("wikibase_item") else None,
        language=language,
    )


def quote_wiki_title(title: str) -> str:
    return quote(title.replace(" ", "_"), safe="")


def wikipedia_language(target_language: str) -> str:
    normalized = target_language.casefold()
    if normalized.startswith("zh"):
        return "zh"
    return normalized.split("-")[0] or "en"


def plain_candidate_text(markdown: str) -> str:
    plain = PROTECTED_MARKDOWN_PATTERN.sub(" ", markdown)
    plain = re.sub(r"[*_#>|]+", " ", plain)
    return re.sub(r"\s+", " ", plain).strip()


def clean_term(value: str) -> str:
    cleaned = re.sub(r"\s+", " ", value.strip(" \t\r\n.,;:()[]{}"))
    cleaned = TRAILING_CITATION_TOKENS_PATTERN.sub("", cleaned).strip(" \t\r\n.,;:()[]{}")
    previous = None
    while previous != cleaned:
        previous = cleaned
        cleaned = LEADING_NOISE_PATTERN.sub("", cleaned).strip(" \t\r\n.,;:()[]{}")
    cleaned = TRAILING_NOISE_PATTERN.sub("", cleaned).strip(" \t\r\n.,;:()[]{}")
    return cleaned


def clean_abbreviation(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9-]+", "", value.strip()).upper()


def high_value_term(term: str) -> bool:
    term = clean_term(term)
    words = term.split()
    if len(term) < 3 or len(words) > 7 or term in STOP_TERMS:
        return False
    if any(CITATION_TOKEN_PATTERN.fullmatch(word) for word in words):
        return False
    if term.casefold() in {"this paper", "the model", "the authors"}:
        return False
    if starts_or_ends_with_context_word(words):
        return False
    if standalone_acronym(term):
        return True
    if any(char.isdigit() for char in term):
        return True
    if len(words) >= 2:
        if contains_connector_word(words):
            return False
        return all(technical_word_shape(word) for word in words)
    return bool(CAMEL_OR_METHOD_PATTERN.fullmatch(term))


def standalone_acronym(term: str) -> bool:
    if not STANDALONE_ACRONYM_PATTERN.fullmatch(term):
        return False
    return term.upper() not in STOP_ACRONYMS


def starts_or_ends_with_context_word(words: list[str]) -> bool:
    if not words:
        return True
    return words[0].casefold() in CONNECTOR_WORDS or words[-1].casefold() in CONNECTOR_WORDS


def contains_connector_word(words: list[str]) -> bool:
    return any(word.casefold() in CONNECTOR_WORDS for word in words)


def technical_word_shape(word: str) -> bool:
    if standalone_acronym(word):
        return True
    if any(char.isdigit() for char in word):
        return True
    if CAMEL_OR_METHOD_PATTERN.fullmatch(word):
        return True
    return bool(re.fullmatch(r"[A-Z][A-Za-z+\-]{2,}", word))


def canonical_key_for_term(abbreviation: str | None, full_form: str | None) -> str:
    normalized_full = normalize_full_form(full_form or "")
    normalized_abbreviation = clean_abbreviation(abbreviation or "")
    if normalized_abbreviation and normalized_full:
        return f"{normalized_abbreviation}::{normalized_full}"
    if normalized_full:
        return f"term::{normalized_full}"
    return ""


def normalize_full_form(value: str) -> str:
    value = value.casefold()
    value = re.sub(r"[-_/]+", " ", value)
    value = re.sub(r"[^a-z0-9\s]+", "", value)
    tokens = [singularize_token(token) for token in value.split() if token]
    return " ".join(tokens)


def singularize_token(token: str) -> str:
    if len(token) <= 3:
        return token
    if token.endswith("ies"):
        return f"{token[:-3]}y"
    if (
        token.endswith("ses")
        or token.endswith("xes")
        or token.endswith("ches")
        or token.endswith("shes")
    ):
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def short_summary(value: str) -> str:
    text = re.sub(r"\s+", " ", value).strip()
    sentences = re.split(r"(?<=[。.!?])\s+", text)
    summary = " ".join(sentences[:2]).strip() if sentences else text
    if len(summary) > 520:
        summary = summary[:517].rstrip() + "..."
    return strip_card_body(summary)


def strip_card_body(value: str) -> str:
    cleaned = re.sub(r"(?m)^\s*(?:[-*]|\d+[.)])\s+", "", value.strip())
    cleaned = re.sub(r"(?m)^#{1,6}\s+", "", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()
