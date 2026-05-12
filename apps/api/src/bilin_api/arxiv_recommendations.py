from __future__ import annotations

import asyncio
import hashlib
import json
import re
import shutil
from collections import Counter
from datetime import UTC, date, datetime, timedelta
from typing import Any

import httpx

from bilin_api.article_store import list_article_items
from bilin_api.arxiv import (
    ArxivMetadata,
    fetch_arxiv_category_taxonomy,
    search_arxiv,
)
from bilin_api.database import init_global_db, open_db, utc_now
from bilin_api.llm import (
    LLMClientError,
    complete_anthropic,
    complete_openai,
    target_language_display_name,
)
from bilin_api.repositories import get_provider_api_key, get_provider_profile
from bilin_api.schemas import (
    ArxivCategory,
    ArxivCategoryListResult,
    ArxivRecommendationEngine,
    ArxivRecommendationItem,
    ArxivRecommendationPreferences,
    ArxivRecommendationPreferencesUpdate,
    ArxivRecommendationRequest,
    ArxivRecommendationResult,
    Library,
    ProviderProfile,
    ProviderProtocol,
)

TAXONOMY_CACHE_KEY = "arxiv:category-taxonomy"
RECOMMENDATION_CACHE_PREFIX = "arxiv:recommendation-cache:"
RECOMMENDATION_CACHE_VERSION = 4
RECOMMENDATION_TRANSLATION_CACHE_PREFIX = "arxiv:recommendation-translation-cache:"
RECOMMENDATION_TRANSLATION_CACHE_VERSION = 1
PREFERENCES_PREFIX = "arxiv:recommendation-preferences:"
DEFAULT_CATEGORIES = ["cs.LG", "cs.CL", "stat.ML", "quant-ph"]
DAILY_FALLBACK_DAYS = 7
PROVIDER_ENRICHMENT_BATCH_SIZE = 5
LOCAL_CLI_ENRICHMENT_LIMIT = 24
STOPWORDS = {
    "a",
    "an",
    "are",
    "as",
    "at",
    "be",
    "been",
    "being",
    "by",
    "can",
    "could",
    "did",
    "do",
    "does",
    "done",
    "the",
    "and",
    "or",
    "not",
    "of",
    "on",
    "in",
    "is",
    "it",
    "its",
    "we",
    "our",
    "for",
    "with",
    "from",
    "that",
    "this",
    "these",
    "those",
    "their",
    "there",
    "where",
    "which",
    "while",
    "than",
    "then",
    "such",
    "using",
    "via",
    "through",
    "between",
    "under",
    "over",
    "after",
    "before",
    "within",
    "into",
    "towards",
    "toward",
    "based",
    "also",
    "only",
    "both",
    "each",
    "more",
    "most",
    "less",
    "least",
    "many",
    "some",
    "any",
    "one",
    "two",
    "three",
    "four",
    "five",
    "first",
    "second",
    "third",
    "paper",
    "papers",
    "article",
    "articles",
    "work",
    "study",
    "studies",
    "show",
    "shows",
    "shown",
    "present",
    "presents",
    "propose",
    "proposes",
    "proposed",
    "new",
    "novel",
    "model",
    "models",
    "method",
    "methods",
    "approach",
    "approaches",
    "framework",
    "frameworks",
    "system",
    "systems",
    "result",
    "results",
    "analysis",
    "data",
    "number",
    "learning",
}
GENERIC_SEED_TERMS = {
    "algorithm",
    "algorithms",
    "application",
    "applications",
    "classical",
    "compute",
    "computer",
    "computers",
    "computing",
    "gate",
    "gates",
    "measurement",
    "measurements",
    "operator",
    "operators",
    "optimization",
    "pauli",
    "problem",
    "problems",
    "qubit",
    "qubits",
    "quantum",
    "state",
    "states",
    "variational",
    "vqe",
}
CATEGORY_TEXT_HINTS: dict[str, dict[str, float]] = {
    "quant-ph": {
        "quantum": 3.0,
        "qubit": 2.0,
        "qubits": 2.0,
        "pauli": 2.5,
        "hamiltonian": 2.0,
        "eigensolver": 2.5,
        "vqe": 3.0,
        "measurement": 1.5,
        "measurements": 1.5,
        "shot": 1.5,
        "shots": 1.5,
        "circuit": 1.0,
        "circuits": 1.0,
    },
    "cs.LG": {
        "machine learning": 3.0,
        "deep learning": 3.0,
        "reinforcement learning": 3.0,
        "neural": 2.0,
        "representation learning": 2.0,
    },
    "cs.CL": {
        "language model": 3.0,
        "large language model": 3.0,
        "natural language": 3.0,
        "translation": 2.0,
        "text generation": 2.0,
    },
    "cs.IR": {
        "retrieval": 3.0,
        "search": 1.5,
        "ranking": 1.5,
        "recommendation": 2.0,
        "recommender": 2.0,
    },
    "stat.ML": {
        "bayesian": 2.0,
        "statistical learning": 3.0,
        "estimator": 2.0,
        "variance": 1.5,
        "regression": 1.5,
    },
}


async def get_arxiv_categories(
    *,
    refresh: bool = False,
    client: httpx.AsyncClient | None = None,
) -> ArxivCategoryListResult:
    cached = await _get_app_setting(TAXONOMY_CACHE_KEY)
    if cached and not refresh and not _is_expired(cached.get("expires_at")):
        cached_categories = [
            ArxivCategory.model_validate(item) for item in cached.get("categories", [])
        ]
        return ArxivCategoryListResult(
            categories=cached_categories,
            cached=True,
            updated_at=_parse_dt(cached.get("updated_at")),
        )

    categories = [
        ArxivCategory(
            id=category.id,
            name=category.name,
            group=category.group,
            description=category.description,
        )
        for category in await fetch_arxiv_category_taxonomy(client)
    ]
    now = utc_now()
    await _set_app_setting(
        TAXONOMY_CACHE_KEY,
        {
            "categories": [category.model_dump(mode="json") for category in categories],
            "updated_at": now,
            "expires_at": (datetime.now(UTC) + timedelta(days=7)).isoformat(),
        },
    )
    return ArxivCategoryListResult(categories=categories, cached=False, updated_at=_parse_dt(now))


async def get_arxiv_recommendation_preferences(
    library: Library,
) -> ArxivRecommendationPreferences:
    raw = await _get_app_setting(_preferences_key(library.id))
    if raw:
        categories = _dedupe_clean(raw.get("categories") or [], max_items=80, category=True)
        keywords = _dedupe_clean(raw.get("keywords") or [], max_items=80, category=False)
        updated_at = raw.get("updated_at")
        refresh_repaired_categories = bool(raw.get("repaired_from_low_signal_seed"))
        seed_categories: list[str] = []
        seed_keywords: list[str] = []
        if _looks_like_buggy_seed_keywords(keywords) or refresh_repaired_categories:
            seed_categories, seed_keywords = await infer_library_recommendation_seed(library)
        repaired = False
        if _looks_like_buggy_seed_keywords(keywords):
            keywords = seed_keywords
            repaired = True
        if refresh_repaired_categories and seed_categories and categories != seed_categories:
            categories = seed_categories
            repaired = True
        if repaired:
            updated_at = utc_now()
            await _set_app_setting(
                _preferences_key(library.id),
                {
                    "categories": categories,
                    "keywords": keywords,
                    "updated_at": updated_at,
                    "repaired_from_low_signal_seed": True,
                },
            )
        return ArxivRecommendationPreferences(
            library_id=library.id,
            categories=categories,
            keywords=keywords,
            updated_at=_parse_dt(updated_at),
        )
    seed_categories, seed_keywords = await infer_library_recommendation_seed(library)
    return ArxivRecommendationPreferences(
        library_id=library.id,
        categories=seed_categories,
        keywords=seed_keywords,
        updated_at=None,
    )


async def update_arxiv_recommendation_preferences(
    library: Library,
    payload: ArxivRecommendationPreferencesUpdate,
) -> ArxivRecommendationPreferences:
    categories = _dedupe_clean(payload.categories, max_items=80, category=True)
    keywords = _dedupe_clean(payload.keywords, max_items=80, category=False)
    now = utc_now()
    await _set_app_setting(
        _preferences_key(library.id),
        {"categories": categories, "keywords": keywords, "updated_at": now},
    )
    return ArxivRecommendationPreferences(
        library_id=library.id,
        categories=categories,
        keywords=keywords,
        updated_at=_parse_dt(now),
    )


async def daily_arxiv_recommendations(
    library: Library,
    request: ArxivRecommendationRequest,
    *,
    client: httpx.AsyncClient | None = None,
) -> ArxivRecommendationResult:
    preferences = await get_arxiv_recommendation_preferences(library)
    categories = _dedupe_clean(
        request.categories if request.categories is not None else preferences.categories,
        max_items=80,
        category=True,
    )
    keywords = _dedupe_clean(
        request.keywords if request.keywords is not None else preferences.keywords,
        max_items=80,
        category=False,
    )
    if not categories and not keywords:
        categories = DEFAULT_CATEGORIES
    requested_submitted_on = request.submitted_on or date.today().isoformat()
    final_cache_key = _recommendation_cache_key(
        library.id,
        request,
        categories,
        keywords,
        requested_submitted_on,
    )
    final_cached = await _get_app_setting(final_cache_key)
    if final_cached and not request.refresh and not _is_expired(final_cached.get("expires_at")):
        cached_result = ArxivRecommendationResult.model_validate(final_cached["result"])
        cached_result.cached = True
        await _apply_cached_recommendation_translations(
            cached_result.items,
            cached_result.target_language,
        )
        await _store_recommendation_translation_cache(
            cached_result.items,
            cached_result.target_language,
        )
        return cached_result

    library_items = await list_article_items(library, request.target_language)
    library_profile = _library_profile(library_items)
    candidate_cache_key = _recommendation_candidate_cache_key(
        library.id,
        request,
        categories,
        keywords,
        requested_submitted_on,
    )
    candidate_cached = await _get_app_setting(candidate_cache_key)
    if (
        candidate_cached
        and not request.refresh
        and not _is_expired(candidate_cached.get("expires_at"))
    ):
        base_result = ArxivRecommendationResult.model_validate(candidate_cached["result"])
        base_result.cached = True
    else:
        submitted_on, candidates = await _search_daily_candidates(
            categories,
            keywords,
            requested_submitted_on,
            max_results=request.max_results,
            allow_fallback=request.submitted_on is None,
            client=client,
        )
        message = None
        if submitted_on != requested_submitted_on:
            message = (
                f"No arXiv submissions matched the current window around {requested_submitted_on}; "
                f"showing the latest available window anchored at {submitted_on}."
            )
        existing_ids = {
            item.family.external_id
            for item in library_items
            if item.family.source == "arxiv" and item.family.external_id
        }
        ranked = _rank_candidates(candidates, library_profile, keywords, categories, existing_ids)
        base_result = ArxivRecommendationResult(
            library_id=library.id,
            target_language=request.target_language,
            submitted_on=submitted_on,
            categories=categories,
            keywords=keywords,
            engine_requested=ArxivRecommendationEngine.heuristic,
            engine_used=ArxivRecommendationEngine.heuristic,
            cached=False,
            generated_at=datetime.now(UTC),
            items=ranked,
            message=message,
        )
        await _set_app_setting(
            candidate_cache_key,
            {
                "result": base_result.model_dump(mode="json"),
                "expires_at": (datetime.now(UTC) + timedelta(hours=12)).isoformat(),
            },
        )

    result = base_result.model_copy(deep=True)
    result.target_language = request.target_language
    result.engine_requested = request.engine
    await _apply_cached_recommendation_translations(result.items, request.target_language)

    if request.engine != ArxivRecommendationEngine.heuristic:
        result = await _try_enrich_with_model(result, request, library_profile)
    await _store_recommendation_translation_cache(result.items, request.target_language)

    await _set_app_setting(
        final_cache_key,
        {
            "result": result.model_dump(mode="json"),
            "expires_at": (datetime.now(UTC) + timedelta(hours=12)).isoformat(),
        },
    )
    return result


async def infer_library_recommendation_seed(library: Library) -> tuple[list[str], list[str]]:
    items = await list_article_items(library)
    category_counter: Counter[str] = Counter()
    texts: list[str] = []
    for item in items:
        metadata = item.family.metadata or {}
        manifest_metadata = item.manifest.arxiv_metadata if item.manifest else {}
        categories = metadata.get("categories") or manifest_metadata.get("categories") or []
        primary = metadata.get("primary_category") or manifest_metadata.get("primary_category")
        if isinstance(primary, str) and primary:
            category_counter[primary] += 2
        if isinstance(categories, list):
            category_counter.update(
                category for category in categories if isinstance(category, str)
            )
        text = " ".join(
            part
            for part in [
                item.family.title or "",
                str(metadata.get("summary") or manifest_metadata.get("summary") or ""),
            ]
            if part
        )
        if text:
            texts.append(text)
    categories = [category for category, _ in category_counter.most_common(8)]
    if not categories:
        categories = _infer_categories_from_texts(texts) or DEFAULT_CATEGORIES[:]
    keywords = _extract_seed_keywords(texts, max_items=8)
    return categories, keywords


async def _search_daily_candidates(
    categories: list[str],
    keywords: list[str],
    submitted_on: str,
    *,
    max_results: int,
    allow_fallback: bool,
    client: httpx.AsyncClient | None,
) -> tuple[str, list[ArxivMetadata]]:
    requested_day = date.fromisoformat(submitted_on)
    candidate_days = [requested_day]
    if allow_fallback:
        candidate_days.extend(
            requested_day - timedelta(days=offset) for offset in range(1, DAILY_FALLBACK_DAYS + 1)
        )
    for candidate_day in candidate_days:
        query = _build_arxiv_query(categories, keywords, candidate_day.isoformat())
        candidates = await search_arxiv(query, max_results=max_results, client=client)
        if candidates or not allow_fallback:
            return candidate_day.isoformat(), candidates
    return submitted_on, []


def build_arxiv_recommendation_prompt(
    result: ArxivRecommendationResult,
    library_profile: dict[str, Any],
    *,
    items: list[ArxivRecommendationItem] | None = None,
    batch_index: int | None = None,
    total_batches: int | None = None,
) -> tuple[str, str]:
    target_label = target_language_display_name(result.target_language)
    system_prompt = (
        "You are helping a researcher browse new arXiv submissions inside a local-first paper "
        "reader. Use only the supplied title, authors, categories, abstract, and local-library "
        "signals. Do not invent claims, code links, citations, metrics, or external facts. "
        f"Write all translated titles, summaries, and reasons in {target_label}. Return only a "
        "valid JSON object, formatted with double-quoted keys and string values. Do not wrap it "
        "in Markdown and do not include any prose before or after the JSON."
    )
    active_items = items if items is not None else result.items[:LOCAL_CLI_ENRICHMENT_LIMIT]
    compact_items = [
        {
            "arxiv_id": item.arxiv_id,
            "title": item.title,
            "authors": item.authors[:8],
            "categories": item.categories,
            "abstract": item.original_summary,
            "heuristic_reasons": item.score_reasons,
        }
        for item in active_items
    ]
    user_prompt = json.dumps(
        {
            "task": (
                "For each item, produce title_target_language, summary_target_language, and "
                "recommendation_reason. The summary must be 2-4 compact sentences in the target "
                "language. The reason must be one short sentence tied to the library profile, "
                "category, or keyword match. Return exactly one object for every supplied "
                "arxiv_id, keep each arxiv_id unchanged, and do not add IDs that are not present "
                "in this batch."
            ),
            "target_language": result.target_language,
            "batch": (
                {"index": batch_index, "total": total_batches}
                if batch_index is not None and total_batches is not None
                else None
            ),
            "library_profile": library_profile,
            "items": compact_items,
            "required_json_shape": {
                "items": [
                    {
                        "arxiv_id": "paper id",
                        "title_target_language": "translated title",
                        "summary_target_language": "target-language abstract summary",
                        "recommendation_reason": "short target-language reason",
                    }
                ]
            },
            "required_arxiv_ids": [item["arxiv_id"] for item in compact_items],
        },
        ensure_ascii=False,
    )
    return system_prompt, user_prompt


async def _try_enrich_with_model(
    result: ArxivRecommendationResult,
    request: ArxivRecommendationRequest,
    library_profile: dict[str, Any],
) -> ArxivRecommendationResult:
    try:
        missing_items = _items_missing_recommendation_translation(result.items)
        if not missing_items:
            result.engine_used = request.engine
            return result
        if request.engine == ArxivRecommendationEngine.provider:
            enrichments, batch_warnings = await _run_provider_enrichment_batches(
                result,
                request,
                library_profile,
                missing_items,
            )
            _apply_enrichments(result.items, enrichments)
            result.engine_used = ArxivRecommendationEngine.provider
            if batch_warnings:
                result.message = _append_message(
                    result.message,
                    "Provider enrichment completed with "
                    f"{len(batch_warnings)} batch warning(s): {'; '.join(batch_warnings[:3])}",
                )
            return result
        elif request.engine in {
            ArxivRecommendationEngine.claude_cli,
            ArxivRecommendationEngine.codex_cli,
        }:
            system_prompt, user_prompt = build_arxiv_recommendation_prompt(
                result,
                library_profile,
                items=missing_items,
            )
            text = await _run_local_cli_enrichment(request.engine, system_prompt, user_prompt)
            engine_used = request.engine
        else:
            return result
        enrichments = _parse_enrichment_json(text)
        _apply_enrichments(result.items, enrichments)
        result.engine_used = engine_used
    except (LLMClientError, ValueError, TimeoutError, RuntimeError) as exc:
        result.message = f"Model enrichment failed; showing heuristic recommendations. {exc}"
    return result


async def _run_provider_enrichment_batches(
    result: ArxivRecommendationResult,
    request: ArxivRecommendationRequest,
    library_profile: dict[str, Any],
    items: list[ArxivRecommendationItem] | None = None,
) -> tuple[dict[str, dict[str, str]], list[str]]:
    if not request.provider_profile_id:
        msg = "Provider recommendation requires provider_profile_id."
        raise ValueError(msg)
    provider = await get_provider_profile(request.provider_profile_id)
    if provider is None:
        msg = f"Provider profile not found: {request.provider_profile_id}"
        raise ValueError(msg)
    api_key = await get_provider_api_key(provider)
    if not api_key:
        msg = f"Provider profile has no API key: {provider.id}"
        raise ValueError(msg)
    model = request.model or provider.default_model
    if not model:
        msg = "Provider recommendation requires a model or provider default_model."
        raise ValueError(msg)

    active_items = items if items is not None else result.items
    batches = list(_chunks(active_items, PROVIDER_ENRICHMENT_BATCH_SIZE))
    enrichments: dict[str, dict[str, str]] = {}
    warnings: list[str] = []
    for batch_index, batch in enumerate(batches, start=1):
        system_prompt, user_prompt = build_arxiv_recommendation_prompt(
            result,
            library_profile,
            items=batch,
            batch_index=batch_index,
            total_batches=len(batches),
        )
        try:
            text = await _complete_provider_enrichment(
                provider,
                api_key,
                model,
                system_prompt,
                user_prompt,
            )
            batch_enrichments = _parse_enrichment_json(text)
        except ValueError as exc:
            warnings.append(f"batch {batch_index}/{len(batches)} JSON parse failed: {exc}")
            continue
        expected_ids = {item.arxiv_id for item in batch}
        returned_ids = set(batch_enrichments)
        missing_ids = expected_ids - returned_ids
        extra_ids = returned_ids - expected_ids
        if missing_ids:
            warnings.append(
                f"batch {batch_index}/{len(batches)} missed {', '.join(sorted(missing_ids))}"
            )
        if extra_ids:
            warnings.append(
                f"batch {batch_index}/{len(batches)} returned unexpected "
                f"{', '.join(sorted(extra_ids))}"
            )
        enrichments.update(
            {
                arxiv_id: enrichment
                for arxiv_id, enrichment in batch_enrichments.items()
                if arxiv_id in expected_ids
            }
        )
    if not enrichments and warnings:
        msg = "Provider enrichment batches failed. " + "; ".join(warnings[:3])
        raise ValueError(msg)
    return enrichments, warnings


async def _complete_provider_enrichment(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    system_prompt: str,
    user_prompt: str,
) -> str:
    if provider.protocol == ProviderProtocol.anthropic_compatible:
        response = await complete_anthropic(provider, api_key, model, system_prompt, user_prompt)
    else:
        response = await complete_openai(provider, api_key, model, system_prompt, user_prompt)
    return response.text


async def _run_local_cli_enrichment(
    engine: ArxivRecommendationEngine,
    system_prompt: str,
    user_prompt: str,
) -> str:
    binary = "claude" if engine == ArxivRecommendationEngine.claude_cli else "codex"
    path = shutil.which(binary)
    if not path:
        msg = f"{binary} CLI is not available on PATH."
        raise RuntimeError(msg)
    prompt = f"{system_prompt}\n\n{user_prompt}"
    args = [path, "-p", prompt] if binary == "claude" else [path, "exec", prompt]
    process = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=120)
    except TimeoutError:
        process.kill()
        raise
    if process.returncode != 0:
        detail = stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(detail or f"{binary} CLI exited with {process.returncode}.")
    return stdout.decode("utf-8", errors="replace")


def _parse_enrichment_json(text: str) -> dict[str, dict[str, str]]:
    cleaned = text.strip()
    fence_match = re.search(r"```(?:json)?\s*(?P<body>\{.*?\})\s*```", cleaned, flags=re.S)
    if fence_match:
        cleaned = fence_match.group("body")
    else:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start >= 0 and end > start:
            cleaned = cleaned[start : end + 1]
    payload = json.loads(cleaned)
    items = payload.get("items")
    if not isinstance(items, list):
        msg = "Recommendation enrichment JSON must contain an items list."
        raise ValueError(msg)
    result: dict[str, dict[str, str]] = {}
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("arxiv_id"), str):
            continue
        result[item["arxiv_id"]] = {
            key: value
            for key in [
                "title_target_language",
                "summary_target_language",
                "recommendation_reason",
            ]
            if isinstance((value := item.get(key)), str) and value.strip()
        }
    return result


def _apply_enrichments(
    items: list[ArxivRecommendationItem],
    enrichments: dict[str, dict[str, str]],
) -> None:
    for item in items:
        enrichment = enrichments.get(item.arxiv_id)
        if not enrichment:
            continue
        if "title_target_language" in enrichment:
            item.title_target_language = enrichment["title_target_language"]
        if "summary_target_language" in enrichment:
            item.summary_target_language = enrichment["summary_target_language"]
        if "recommendation_reason" in enrichment:
            item.recommendation_reason = enrichment["recommendation_reason"]


def _items_missing_recommendation_translation(
    items: list[ArxivRecommendationItem],
) -> list[ArxivRecommendationItem]:
    return [
        item for item in items if not item.title_target_language or not item.summary_target_language
    ]


async def _apply_cached_recommendation_translations(
    items: list[ArxivRecommendationItem],
    target_language: str,
) -> None:
    for item in _items_missing_recommendation_translation(items):
        cached = await _get_app_setting(
            _recommendation_translation_cache_key(item, target_language)
        )
        if not cached or _is_expired(cached.get("expires_at")):
            continue
        translation = cached.get("translation")
        if not isinstance(translation, dict):
            continue
        if not item.title_target_language and isinstance(
            title := translation.get("title_target_language"),
            str,
        ):
            item.title_target_language = title
        if not item.summary_target_language and isinstance(
            summary := translation.get("summary_target_language"),
            str,
        ):
            item.summary_target_language = summary


async def _store_recommendation_translation_cache(
    items: list[ArxivRecommendationItem],
    target_language: str,
) -> None:
    expires_at = (datetime.now(UTC) + timedelta(days=180)).isoformat()
    for item in items:
        translation = {
            key: value
            for key, value in {
                "title_target_language": item.title_target_language,
                "summary_target_language": item.summary_target_language,
            }.items()
            if isinstance(value, str) and value.strip()
        }
        if not translation:
            continue
        await _set_app_setting(
            _recommendation_translation_cache_key(item, target_language),
            {
                "translation": translation,
                "expires_at": expires_at,
            },
        )


def _append_message(current: str | None, addition: str) -> str:
    if not current:
        return addition
    return f"{current} {addition}"


def _chunks(items: list[ArxivRecommendationItem], size: int) -> list[list[ArxivRecommendationItem]]:
    return [items[index : index + size] for index in range(0, len(items), size)]


def _rank_candidates(
    candidates: list[ArxivMetadata],
    library_profile: dict[str, Any],
    keywords: list[str],
    categories: list[str],
    existing_ids: set[str],
) -> list[ArxivRecommendationItem]:
    library_terms = set(library_profile.get("top_terms") or [])
    selected_categories = set(categories)
    normalized_keywords = [_normalize_keyword(keyword) for keyword in keywords]
    ranked: list[ArxivRecommendationItem] = []
    for candidate in candidates:
        text = f"{candidate.title} {candidate.summary}".casefold()
        candidate_tokens = set(_tokens(text))
        score = 0.0
        reasons: list[str] = []
        category_overlap = selected_categories.intersection(candidate.categories)
        if candidate.primary_category in selected_categories:
            score += 1.6
            reasons.append(f"primary category {candidate.primary_category}")
        if category_overlap:
            score += min(len(category_overlap), 4) * 0.35
            reasons.append("category overlap")
        keyword_hits = [keyword for keyword in normalized_keywords if keyword and keyword in text]
        if keyword_hits:
            score += min(len(keyword_hits), 6) * 0.8
            reasons.append(f"keyword match: {', '.join(keyword_hits[:3])}")
        term_overlap = library_terms.intersection(candidate_tokens)
        if term_overlap:
            score += min(len(term_overlap), 12) * 0.12
            reasons.append("similar to library terms")
        if candidate.bare_id in existing_ids:
            score -= 5.0
            status = "in_library"
        else:
            status = "new"
        ranked.append(
            ArxivRecommendationItem(
                arxiv_id=candidate.concrete_id,
                bare_id=candidate.bare_id,
                version=candidate.version,
                title=candidate.title,
                authors=candidate.authors,
                original_summary=candidate.summary,
                primary_category=candidate.primary_category,
                categories=candidate.categories,
                published=candidate.published,
                updated=candidate.updated,
                abs_url=candidate.abs_url,
                pdf_url=candidate.pdf_url,
                source_url=candidate.source_url,
                score=round(score, 4),
                score_reasons=reasons[:4],
                status=status,
                is_in_library=candidate.bare_id in existing_ids,
            )
        )
    return sorted(ranked, key=lambda item: (item.is_in_library, -item.score, item.updated or ""))


def _library_profile(items: list[Any]) -> dict[str, Any]:
    category_counter: Counter[str] = Counter()
    token_counter: Counter[str] = Counter()
    for item in items:
        metadata = item.family.metadata or {}
        manifest_metadata = item.manifest.arxiv_metadata if item.manifest else {}
        for source in (metadata, manifest_metadata):
            categories = source.get("categories")
            if isinstance(categories, list):
                category_counter.update(
                    category for category in categories if isinstance(category, str)
                )
            primary = source.get("primary_category")
            if isinstance(primary, str):
                category_counter[primary] += 2
            summary = source.get("summary")
            if isinstance(summary, str):
                token_counter.update(_tokens(summary))
        if item.family.title:
            token_counter.update(_tokens(item.family.title))
    return {
        "top_categories": [category for category, _ in category_counter.most_common(12)],
        "top_terms": [token for token, _ in token_counter.most_common(40)],
        "paper_count": len(items),
    }


def _build_arxiv_query(categories: list[str], keywords: list[str], submitted_on: str) -> str:
    day = date.fromisoformat(submitted_on)
    start = day - timedelta(days=2)
    end = day + timedelta(days=1)
    parts = [f"submittedDate:[{start:%Y%m%d}0000 TO {end:%Y%m%d}2359]"]
    if categories:
        category_query = " OR ".join(f"cat:{category}" for category in categories)
        parts.append(f"({category_query})")
    clean_keywords = [_normalize_keyword(keyword) for keyword in keywords]
    clean_keywords = [keyword for keyword in clean_keywords if keyword]
    if clean_keywords and not categories:
        keyword_query = " OR ".join(f'all:"{keyword}"' for keyword in clean_keywords[:12])
        parts.append(f"({keyword_query})")
    return " AND ".join(parts)


def _recommendation_cache_key(
    library_id: str,
    request: ArxivRecommendationRequest,
    categories: list[str],
    keywords: list[str],
    submitted_on: str,
) -> str:
    raw = json.dumps(
        {
            "library_id": library_id,
            "cache_version": RECOMMENDATION_CACHE_VERSION,
            "target_language": request.target_language,
            "submitted_on": submitted_on,
            "categories": categories,
            "keywords": keywords,
            "max_results": request.max_results,
            "engine": request.engine.value,
            "provider_profile_id": request.provider_profile_id,
            "model": request.model,
        },
        sort_keys=True,
    )
    return f"{RECOMMENDATION_CACHE_PREFIX}{hashlib.sha256(raw.encode('utf-8')).hexdigest()}"


def _recommendation_candidate_cache_key(
    library_id: str,
    request: ArxivRecommendationRequest,
    categories: list[str],
    keywords: list[str],
    submitted_on: str,
) -> str:
    raw = json.dumps(
        {
            "library_id": library_id,
            "cache_version": RECOMMENDATION_CACHE_VERSION,
            "cache_kind": "candidates",
            "target_language": request.target_language,
            "submitted_on": submitted_on,
            "categories": categories,
            "keywords": keywords,
            "max_results": request.max_results,
        },
        sort_keys=True,
    )
    return f"{RECOMMENDATION_CACHE_PREFIX}{hashlib.sha256(raw.encode('utf-8')).hexdigest()}"


def _recommendation_translation_cache_key(
    item: ArxivRecommendationItem,
    target_language: str,
) -> str:
    raw = json.dumps(
        {
            "cache_version": RECOMMENDATION_TRANSLATION_CACHE_VERSION,
            "target_language": target_language,
            "arxiv_id": item.arxiv_id,
            "title": item.title,
            "summary": item.original_summary,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return (
        f"{RECOMMENDATION_TRANSLATION_CACHE_PREFIX}"
        f"{hashlib.sha256(raw.encode('utf-8')).hexdigest()}"
    )


async def _get_app_setting(key: str) -> dict[str, Any] | None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        cursor = await conn.execute("SELECT value_json FROM app_settings WHERE key = ?", (key,))
        row = await cursor.fetchone()
    return json.loads(row["value_json"]) if row else None


async def _set_app_setting(key: str, value: dict[str, Any]) -> None:
    db_path = await init_global_db()
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO app_settings(key, value_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json,
                                          updated_at = excluded.updated_at
            """,
            (key, json.dumps(value), utc_now()),
        )
        await conn.commit()


def _preferences_key(library_id: str) -> str:
    return f"{PREFERENCES_PREFIX}{library_id}"


def _is_expired(value: Any) -> bool:
    parsed = _parse_dt(value)
    return parsed is None or parsed <= datetime.now(UTC)


def _parse_dt(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    return datetime.fromisoformat(value)


def _dedupe_clean(values: list[str] | None, *, max_items: int, category: bool) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values or []:
        cleaned = value.strip()
        if not cleaned:
            continue
        cleaned = cleaned if category else _normalize_keyword(cleaned)
        key = cleaned.casefold()
        if key in seen:
            continue
        seen.add(key)
        result.append(cleaned)
        if len(result) >= max_items:
            break
    return result


def _normalize_keyword(value: str) -> str:
    return " ".join(value.strip().casefold().split())


def _tokens(text: str) -> list[str]:
    return [
        token for token in _raw_terms(text) if token not in GENERIC_SEED_TERMS and len(token) >= 4
    ]


def _extract_seed_keywords(texts: list[str], *, max_items: int) -> list[str]:
    phrase_counter: Counter[str] = Counter()
    token_counter: Counter[str] = Counter()
    for text in texts:
        for sequence in _term_sequences(text):
            token_counter.update(
                token for token in sequence if token not in GENERIC_SEED_TERMS and len(token) >= 4
            )
            for width in (3, 2):
                if len(sequence) < width:
                    continue
                for index in range(len(sequence) - width + 1):
                    phrase_tokens = sequence[index : index + width]
                    if not _is_seed_phrase(phrase_tokens):
                        continue
                    phrase_counter[" ".join(phrase_tokens)] += 1

    selected: list[str] = []
    seen_tokens: set[str] = set()
    for phrase, _ in sorted(
        phrase_counter.items(),
        key=lambda item: (-item[1], -len(item[0].split()), item[0]),
    ):
        phrase_tokens = set(phrase.split())
        if phrase_tokens.issubset(seen_tokens):
            continue
        selected.append(phrase)
        seen_tokens.update(phrase_tokens)
        if len(selected) >= max_items:
            return selected

    for token, _ in token_counter.most_common(max_items * 2):
        if token in seen_tokens:
            continue
        selected.append(token)
        seen_tokens.add(token)
        if len(selected) >= max_items:
            break
    return selected


def _is_seed_phrase(tokens: list[str]) -> bool:
    if len(tokens) < 2:
        return False
    distinctive = [token for token in tokens if token not in GENERIC_SEED_TERMS and len(token) >= 4]
    if not distinctive:
        return False
    return not (tokens[0] in GENERIC_SEED_TERMS and tokens[-1] in GENERIC_SEED_TERMS)


def _looks_like_buggy_seed_keywords(keywords: list[str]) -> bool:
    if not keywords:
        return False
    if any(keyword in STOPWORDS for keyword in keywords):
        return True
    low_signal = [keyword for keyword in keywords if _is_low_signal_keyword(keyword)]
    return len(keywords) >= 6 and len(low_signal) / len(keywords) >= 0.75


def _infer_categories_from_texts(texts: list[str], *, max_items: int = 8) -> list[str]:
    if not texts:
        return []
    corpus = " ".join(text.casefold() for text in texts)
    scores: dict[str, float] = {}
    for category, hints in CATEGORY_TEXT_HINTS.items():
        for hint, weight in hints.items():
            matches = _count_hint_matches(corpus, hint)
            if matches:
                scores[category] = scores.get(category, 0.0) + matches * weight
    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    return [category for category, score in ranked[:max_items] if score >= 3.0]


def _count_hint_matches(corpus: str, hint: str) -> int:
    escaped = re.escape(hint).replace(r"\ ", r"\s+")
    return len(re.findall(rf"(?<![a-z0-9]){escaped}(?![a-z0-9])", corpus))


def _is_low_signal_keyword(keyword: str) -> bool:
    terms = _raw_terms(keyword)
    return not terms or all(term in GENERIC_SEED_TERMS for term in terms)


def _term_sequences(text: str) -> list[list[str]]:
    sequences: list[list[str]] = []
    current: list[str] = []
    for token in re.findall(r"[a-zA-Z][a-zA-Z0-9-]{1,}", text.casefold()):
        if token in STOPWORDS or token.isdigit():
            if current:
                sequences.append(current)
                current = []
            continue
        current.append(token)
    if current:
        sequences.append(current)
    return sequences


def _raw_terms(text: str) -> list[str]:
    return [
        token
        for token in re.findall(r"[a-zA-Z][a-zA-Z0-9-]{2,}", text.casefold())
        if token not in STOPWORDS and not token.isdigit()
    ]
