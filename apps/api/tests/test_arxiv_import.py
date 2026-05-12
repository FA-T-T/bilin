from __future__ import annotations

import io
import json
import tarfile
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
import pytest

from bilin_api.article_store import (
    archive_article_revision,
    delete_article_revision,
    list_article_items,
    read_manifest,
    upsert_arxiv_revision,
)
from bilin_api.arxiv import (
    metadata_from_entry,
    parse_arxiv_category_taxonomy,
    parse_arxiv_identity,
)
from bilin_api.arxiv_recommendations import (
    _extract_seed_keywords,
    _looks_like_buggy_seed_keywords,
    _run_provider_enrichment_batches,
    _search_daily_candidates,
    daily_arxiv_recommendations,
    infer_library_recommendation_seed,
)
from bilin_api.importer import import_arxiv, import_local_file
from bilin_api.repositories import create_library, list_jobs
from bilin_api.schemas import (
    ArxivRecommendationEngine,
    ArxivRecommendationItem,
    ArxivRecommendationRequest,
    ArxivRecommendationResult,
    ImportArxivRequest,
    ImportLocalKind,
    JobType,
    LibraryCreate,
    ProviderProfile,
    ProviderProtocol,
)

ATOM_RESPONSE = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>https://arxiv.org/abs/2401.00001v2</id>
    <updated>2024-01-03T00:00:00Z</updated>
    <published>2024-01-01T00:00:00Z</published>
    <title> A Minimal Bilin Test Paper </title>
    <summary> A compact abstract. </summary>
    <author><name>Ada Lovelace</name></author>
    <author><name>Grace Hopper</name></author>
  </entry>
</feed>
"""


def test_parse_arxiv_identity_accepts_urls_and_versions() -> None:
    identity = parse_arxiv_identity("https://arxiv.org/abs/2401.00001v2")
    assert identity.bare_id == "2401.00001"
    assert identity.version == "v2"
    assert parse_arxiv_identity("2401.00001", "3").concrete_id == "2401.00001v3"
    assert parse_arxiv_identity("quant-ph/9705052").bare_id == "quant-ph/9705052"
    assert parse_arxiv_identity("https://arxiv.org/abs/cond-mat/9407022v1").concrete_id == (
        "cond-mat/9407022v1"
    )
    assert parse_arxiv_identity("condmat/9407022").bare_id == "cond-mat/9407022"


def test_parse_arxiv_identity_rejects_ambiguous_old_style_bare_number() -> None:
    with pytest.raises(ValueError, match="archive prefix"):
        parse_arxiv_identity("9407022")


def test_metadata_from_entry_preserves_old_style_archive_prefix() -> None:
    entry = httpx.Response(
        200,
        text="""<entry xmlns="http://www.w3.org/2005/Atom">
          <id>https://arxiv.org/abs/quant-ph/9705052v1</id>
          <title>Old Style Quantum Paper</title>
          <summary>Abstract.</summary>
          <author><name>A. Researcher</name></author>
        </entry>""",
    )
    root = ET.fromstring(entry.text)

    metadata = metadata_from_entry(root)

    assert metadata.bare_id == "quant-ph/9705052"
    assert metadata.concrete_id == "quant-ph/9705052v1"
    assert metadata.source_url == "https://arxiv.org/e-print/quant-ph/9705052v1"


def test_metadata_from_entry_reads_arxiv_categories() -> None:
    root = ET.fromstring(
        """<entry xmlns="http://www.w3.org/2005/Atom"
             xmlns:arxiv="http://arxiv.org/schemas/atom">
          <id>https://arxiv.org/abs/2401.00001v1</id>
          <title>Category Paper</title>
          <summary>Abstract.</summary>
          <author><name>A. Researcher</name></author>
          <arxiv:primary_category term="cs.LG" scheme="http://arxiv.org/schemas/atom"/>
          <category term="cs.LG" scheme="http://arxiv.org/schemas/atom"/>
          <category term="stat.ML" scheme="http://arxiv.org/schemas/atom"/>
        </entry>"""
    )

    metadata = metadata_from_entry(root)

    assert metadata.primary_category == "cs.LG"
    assert metadata.categories == ["cs.LG", "stat.ML"]


def test_parse_arxiv_category_taxonomy_extracts_groups_and_descriptions() -> None:
    categories = parse_arxiv_category_taxonomy(
        """
        <h2>Computer Science</h2>
        <h4>cs.LG (Machine Learning)</h4>
        <p>Papers on all aspects of machine learning research.</p>
        <h4>cs.CL (Computation and Language)</h4>
        <p>Covers natural language processing.</p>
        """
    )

    assert [category.id for category in categories] == ["cs.LG", "cs.CL"]
    assert categories[0].group == "Computer Science"
    assert categories[1].description == "Covers natural language processing."


def test_recommendation_seed_keywords_skip_low_signal_quantum_words() -> None:
    keywords = _extract_seed_keywords(
        [
            (
                "Quantum variational measurements are based on Pauli operators, VQE gates, "
                "and two computer experiments. Measurement allocation for Hamiltonian "
                "simulation improves Pauli grouping and error mitigation."
            ),
            (
                "Adaptive shot allocation for quantum chemistry and Hamiltonian simulation "
                "reduces estimator variance."
            ),
        ],
        max_items=8,
    )

    low_signal = {
        "quantum",
        "are",
        "number",
        "variational",
        "measurements",
        "operators",
        "pauli",
        "computing",
        "gates",
        "vqe",
        "computer",
        "two",
    }
    assert low_signal.isdisjoint(keywords)
    assert any(
        keyword in keywords
        for keyword in [
            "measurement allocation",
            "hamiltonian simulation",
            "error mitigation",
            "pauli grouping",
            "shot allocation",
        ]
    )


def test_recommendation_preferences_detect_old_buggy_keyword_seed() -> None:
    assert _looks_like_buggy_seed_keywords(
        [
            "quantum",
            "are",
            "number",
            "variational",
            "measurements",
            "operators",
            "pauli",
            "computing",
            "gates",
            "vqe",
            "computer",
            "two",
        ]
    )
    assert not _looks_like_buggy_seed_keywords(["vqe", "pauli grouping"])


@pytest.mark.asyncio
async def test_daily_arxiv_recommendations_rank_and_keep_abstract_only(
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Papers", path=str(tmp_path / "library")),
    )
    atom = """<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>https://arxiv.org/abs/2605.00001v1</id>
        <updated>2026-05-11T00:00:00Z</updated>
        <published>2026-05-11T00:00:00Z</published>
        <title> Graph Retrieval for Local Paper Libraries </title>
        <summary> A compact abstract about retrieval and library-aware ranking. </summary>
        <author><name>Ada Lovelace</name></author>
        <arxiv:primary_category term="cs.IR" scheme="http://arxiv.org/schemas/atom"/>
        <category term="cs.IR" scheme="http://arxiv.org/schemas/atom"/>
      </entry>
    </feed>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        assert "cat%3Acs.IR" in str(request.url) or "cat:cs.IR" in str(request.url)
        return httpx.Response(200, text=atom)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await daily_arxiv_recommendations(
            library,
            ArxivRecommendationRequest(
                categories=["cs.IR"],
                keywords=["retrieval"],
                submitted_on="2026-05-11",
                engine=ArxivRecommendationEngine.heuristic,
            ),
            client=client,
        )

    assert result.items[0].arxiv_id == "2605.00001v1"
    assert result.items[0].original_summary.startswith("A compact abstract")
    assert result.items[0].summary_target_language is None
    assert result.items[0].score > 0


@pytest.mark.asyncio
async def test_recommendation_seed_infers_quant_ph_from_legacy_metadata(
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Measurements", path=str(tmp_path / "library")),
    )
    await upsert_arxiv_revision(
        library,
        "1908.06942",
        "v3",
        "Efficient quantum measurement of Pauli operators in finite sampling error",
        tmp_path / "library" / "articles" / "arxiv" / "1908.06942" / "v3",
        {
            "summary": (
                "Estimating expectation values of Hamiltonians in the variational quantum "
                "eigensolver requires Pauli grouping, quantum measurements, and shot allocation. "
                "Future research should not be mistaken for an IR signal."
            )
        },
    )

    categories, keywords = await infer_library_recommendation_seed(library)

    assert categories[0] == "quant-ph"
    assert "quant-ph" in categories
    assert "cs.IR" not in categories
    assert "finite sampling error" in keywords


@pytest.mark.asyncio
async def test_daily_candidate_search_falls_back_to_recent_available_window() -> None:
    empty_feed = """<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"></feed>
    """
    fallback_feed = """<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>https://arxiv.org/abs/2605.08082v1</id>
        <updated>2026-05-08T17:59:40Z</updated>
        <published>2026-05-08T17:59:40Z</published>
        <title> Advances in quantum learning theory with bosonic systems </title>
        <summary> A compact quant-ph abstract. </summary>
        <author><name>Ada Lovelace</name></author>
        <arxiv:primary_category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
        <category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
      </entry>
    </feed>
    """
    seen_urls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        seen_urls.append(url)
        assert "cat%3Aquant-ph" in url or "cat:quant-ph" in url
        assert "all%3A%22measurement%22" not in url
        if "202605080000" in url:
            return httpx.Response(200, text=fallback_feed)
        return httpx.Response(200, text=empty_feed)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        submitted_on, candidates = await _search_daily_candidates(
            ["quant-ph"],
            ["measurement"],
            "2026-05-11",
            max_results=10,
            allow_fallback=True,
            client=client,
        )

    assert submitted_on == "2026-05-10"
    assert len(seen_urls) == 2
    assert candidates[0].concrete_id == "2605.08082v1"


@pytest.mark.asyncio
async def test_provider_recommendation_enrichment_batches_articles_by_five(monkeypatch) -> None:
    now = datetime.now(UTC)
    provider = ProviderProfile(
        id="provider-1",
        name="Mock Provider",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://provider.test/v1",
        key_ref=None,
        default_model="mock-model",
        created_at=now,
        updated_at=now,
    )
    result = ArxivRecommendationResult(
        library_id="library-1",
        target_language="zh-CN",
        submitted_on="2026-05-11",
        categories=["quant-ph"],
        keywords=["measurement"],
        engine_requested=ArxivRecommendationEngine.provider,
        engine_used=ArxivRecommendationEngine.heuristic,
        generated_at=now,
        items=[make_recommendation_item(index) for index in range(12)],
    )
    request = ArxivRecommendationRequest(
        engine=ArxivRecommendationEngine.provider,
        provider_profile_id=provider.id,
        model="mock-model",
        target_language="zh-CN",
    )
    prompts: list[dict[str, Any]] = []

    async def fake_get_provider_profile(provider_id: str) -> ProviderProfile | None:
        assert provider_id == provider.id
        return provider

    async def fake_get_provider_api_key(active_provider: ProviderProfile) -> str:
        assert active_provider.id == provider.id
        return "test-key"

    async def fake_complete_provider_enrichment(
        active_provider: ProviderProfile,
        api_key: str,
        model: str,
        system_prompt: str,
        user_prompt: str,
    ) -> str:
        assert active_provider.id == provider.id
        assert api_key == "test-key"
        assert model == "mock-model"
        assert "Return only a valid JSON object" in system_prompt
        payload = json.loads(user_prompt)
        prompts.append(payload)
        items = payload["items"]
        assert isinstance(items, list)
        assert payload["required_arxiv_ids"] == [item["arxiv_id"] for item in items]
        assert "required_json_shape" in payload
        return json.dumps(
            {
                "items": [
                    {
                        "arxiv_id": item["arxiv_id"],
                        "title_target_language": f"标题 {item['arxiv_id']}",
                        "summary_target_language": f"摘要 {item['arxiv_id']}",
                        "recommendation_reason": f"理由 {item['arxiv_id']}",
                    }
                    for item in items
                ]
            },
            ensure_ascii=False,
        )

    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations.get_provider_profile",
        fake_get_provider_profile,
    )
    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations.get_provider_api_key",
        fake_get_provider_api_key,
    )
    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations._complete_provider_enrichment",
        fake_complete_provider_enrichment,
    )

    enrichments, warnings = await _run_provider_enrichment_batches(
        result,
        request,
        {"top_categories": ["quant-ph"], "top_terms": ["measurement"], "paper_count": 5},
    )

    assert [len(prompt["items"]) for prompt in prompts] == [5, 5, 2]
    assert [prompt["batch"] for prompt in prompts] == [
        {"index": 1, "total": 3},
        {"index": 2, "total": 3},
        {"index": 3, "total": 3},
    ]
    assert warnings == []
    assert len(enrichments) == 12
    assert enrichments["2605.00000v1"]["title_target_language"] == "标题 2605.00000v1"


@pytest.mark.asyncio
async def test_switching_provider_engine_reuses_cached_candidate_list(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Provider Cache", path=str(tmp_path / "library")),
    )
    now = datetime.now(UTC)
    provider = ProviderProfile(
        id="provider-1",
        name="Mock Provider",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://provider.test/v1",
        key_ref=None,
        default_model="mock-model",
        created_at=now,
        updated_at=now,
    )
    atom = """<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>https://arxiv.org/abs/2605.00001v1</id>
        <updated>2026-05-11T00:00:00Z</updated>
        <published>2026-05-11T00:00:00Z</published>
        <title> Quantum Measurement Candidate </title>
        <summary> A compact abstract about quantum measurement grouping. </summary>
        <author><name>Ada Lovelace</name></author>
        <arxiv:primary_category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
        <category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
      </entry>
    </feed>
    """
    arxiv_searches = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal arxiv_searches
        arxiv_searches += 1
        if arxiv_searches > 1:
            raise AssertionError("engine switch should reuse cached candidates")
        return httpx.Response(200, text=atom)

    async def fake_get_provider_profile(provider_id: str) -> ProviderProfile | None:
        assert provider_id == provider.id
        return provider

    async def fake_get_provider_api_key(active_provider: ProviderProfile) -> str:
        assert active_provider.id == provider.id
        return "test-key"

    async def fake_complete_provider_enrichment(
        active_provider: ProviderProfile,
        api_key: str,
        model: str,
        _system_prompt: str,
        user_prompt: str,
    ) -> str:
        assert active_provider.id == provider.id
        assert api_key == "test-key"
        assert model == "mock-model"
        payload = json.loads(user_prompt)
        return json.dumps(
            {
                "items": [
                    {
                        "arxiv_id": item["arxiv_id"],
                        "title_target_language": "量子测量候选文章",
                        "summary_target_language": "这是一篇关于量子测量分组的候选文章。",
                        "recommendation_reason": "它匹配当前文库的测量主题。",
                    }
                    for item in payload["items"]
                ]
            },
            ensure_ascii=False,
        )

    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations.get_provider_profile",
        fake_get_provider_profile,
    )
    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations.get_provider_api_key",
        fake_get_provider_api_key,
    )
    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations._complete_provider_enrichment",
        fake_complete_provider_enrichment,
    )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        heuristic_result = await daily_arxiv_recommendations(
            library,
            ArxivRecommendationRequest(
                categories=["quant-ph"],
                keywords=["measurement"],
                submitted_on="2026-05-11",
                engine=ArxivRecommendationEngine.heuristic,
                refresh=True,
            ),
            client=client,
        )
        provider_result = await daily_arxiv_recommendations(
            library,
            ArxivRecommendationRequest(
                categories=["quant-ph"],
                keywords=["measurement"],
                submitted_on="2026-05-11",
                engine=ArxivRecommendationEngine.provider,
                provider_profile_id=provider.id,
                model="mock-model",
            ),
            client=client,
        )

    assert arxiv_searches == 1
    assert heuristic_result.items[0].arxiv_id == provider_result.items[0].arxiv_id
    assert provider_result.engine_used == ArxivRecommendationEngine.provider
    assert provider_result.items[0].title_target_language == "量子测量候选文章"


@pytest.mark.asyncio
async def test_recommendation_translation_cache_survives_refresh(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch,
) -> None:
    library = await create_library(
        LibraryCreate(name="Translation Cache", path=str(tmp_path / "library")),
    )
    now = datetime.now(UTC)
    provider = ProviderProfile(
        id="provider-1",
        name="Mock Provider",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://provider.test/v1",
        key_ref=None,
        default_model="mock-model",
        created_at=now,
        updated_at=now,
    )
    atom = """<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:arxiv="http://arxiv.org/schemas/atom">
      <entry>
        <id>https://arxiv.org/abs/2605.00002v1</id>
        <updated>2026-05-11T00:00:00Z</updated>
        <published>2026-05-11T00:00:00Z</published>
        <title> Cached Translation Candidate </title>
        <summary> A compact abstract that should not be translated twice. </summary>
        <author><name>Ada Lovelace</name></author>
        <arxiv:primary_category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
        <category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
      </entry>
    </feed>
    """
    provider_calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text=atom)

    async def fake_get_provider_profile(provider_id: str) -> ProviderProfile | None:
        assert provider_id == provider.id
        return provider

    async def fake_get_provider_api_key(active_provider: ProviderProfile) -> str:
        assert active_provider.id == provider.id
        return "test-key"

    async def fake_complete_provider_enrichment(
        active_provider: ProviderProfile,
        api_key: str,
        model: str,
        _system_prompt: str,
        user_prompt: str,
    ) -> str:
        nonlocal provider_calls
        provider_calls += 1
        assert active_provider.id == provider.id
        assert api_key == "test-key"
        assert model == "mock-model"
        payload = json.loads(user_prompt)
        return json.dumps(
            {
                "items": [
                    {
                        "arxiv_id": item["arxiv_id"],
                        "title_target_language": "已缓存标题",
                        "summary_target_language": "已缓存摘要。",
                        "recommendation_reason": "首次生成的推荐理由。",
                    }
                    for item in payload["items"]
                ]
            },
            ensure_ascii=False,
        )

    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations.get_provider_profile",
        fake_get_provider_profile,
    )
    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations.get_provider_api_key",
        fake_get_provider_api_key,
    )
    monkeypatch.setattr(
        "bilin_api.arxiv_recommendations._complete_provider_enrichment",
        fake_complete_provider_enrichment,
    )

    request = ArxivRecommendationRequest(
        categories=["quant-ph"],
        submitted_on="2026-05-11",
        engine=ArxivRecommendationEngine.provider,
        provider_profile_id=provider.id,
        model="mock-model",
        refresh=True,
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        first = await daily_arxiv_recommendations(library, request, client=client)
        second = await daily_arxiv_recommendations(library, request, client=client)

    assert provider_calls == 1
    assert first.items[0].title_target_language == "已缓存标题"
    assert first.items[0].summary_target_language == "已缓存摘要。"
    assert second.items[0].title_target_language == "已缓存标题"
    assert second.items[0].summary_target_language == "已缓存摘要。"
    assert second.engine_used == ArxivRecommendationEngine.provider


@pytest.mark.asyncio
async def test_import_arxiv_writes_bundle_manifest_and_parse_job(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Papers", path=str(tmp_path / "library")),
    )
    source_bytes = make_source_tar()

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "export.arxiv.org/api/query" in url:
            return httpx.Response(200, text=ATOM_RESPONSE)
        if "arxiv.org/e-print/2401.00001v2" in url:
            return httpx.Response(200, content=source_bytes)
        if "arxiv.org/pdf/2401.00001v2.pdf" in url:
            return httpx.Response(200, content=b"%PDF-1.7\n")
        return httpx.Response(404)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await import_arxiv(
            library,
            ImportArxivRequest(arxiv_id="2401.00001", parse_after_import=True),
            client,
        )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.library_id == library.id
    assert result.parse_job_id is not None
    assert (bundle_path / "original" / "source.tar").read_bytes() == source_bytes
    assert (bundle_path / "original" / "paper.pdf").read_bytes().startswith(b"%PDF")
    assert manifest.arxiv_id == "2401.00001v2"
    assert manifest.source_fingerprint is not None
    assert manifest.pdf_fingerprint is not None
    assert manifest.generated_artifacts["source_archive"] == "original/source.tar"

    articles = await list_article_items(library)
    assert len(articles) == 1
    assert articles[0].family.external_id == "2401.00001"
    assert articles[0].article_revision.id == result.article_revision_id
    jobs = await list_jobs()
    assert any(job.type == JobType.parse_article for job in jobs)


@pytest.mark.asyncio
async def test_import_local_tex_archive_writes_source_and_parse_job(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Uploads", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="paper.tar.gz",
        content=make_source_tar(),
        kind=ImportLocalKind.tex_archive,
        parse_after_import=True,
    )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.source_kind == ImportLocalKind.tex_archive
    assert result.parse_job_id is not None
    assert (bundle_path / "original" / "source.gz").exists()
    assert manifest.source == "upload"
    assert manifest.metadata["source_kind"] == "tex_archive"
    assert manifest.generated_artifacts["source_archive"] == "original/source.gz"

    jobs = await list_jobs()
    assert any(job.type == JobType.parse_article for job in jobs)


@pytest.mark.asyncio
async def test_import_local_markdown_creates_weak_document(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Markdown", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="note.md",
        content=b"# Title\n\nFirst paragraph.\n\n## Method\n\nSecond paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=True,
    )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.parse_job_id is None
    assert manifest.parse_status == "parsed"
    assert (bundle_path / "document" / "document.json").exists()
    assert (
        (bundle_path / "document" / "source.md").read_text(encoding="utf-8").startswith("# Title")
    )

    articles = await list_article_items(library)
    assert articles[0].article_revision.status == "parsed"
    assert articles[0].block_count == 4


@pytest.mark.asyncio
async def test_archive_and_delete_article_revision_keep_or_remove_cache(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Actions", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="note.md",
        content=b"# Title\n\nFirst paragraph.",
        kind=ImportLocalKind.markdown,
        parse_after_import=True,
    )
    bundle_path = Path(result.bundle_path)
    assert bundle_path.exists()

    archived = await archive_article_revision(library, result.article_revision_id)
    assert archived is not None
    assert archived.article_revision.status == "archived"
    assert bundle_path.exists()

    deleted = await delete_article_revision(library, result.article_revision_id)
    assert deleted is not None
    assert deleted.article_revision_id == result.article_revision_id
    assert deleted.deleted_cache is True
    assert deleted.removed_family is True
    assert not bundle_path.exists()
    assert await list_article_items(library) == []


@pytest.mark.asyncio
async def test_import_local_pdf_is_save_only(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="PDF", path=str(tmp_path / "library")),
    )
    result = await import_local_file(
        library,
        file_name="paper.pdf",
        content=b"%PDF-1.7\n",
        kind=ImportLocalKind.pdf,
        parse_after_import=True,
    )

    bundle_path = Path(result.bundle_path)
    manifest = read_manifest(bundle_path)
    assert manifest is not None
    assert result.parse_job_id is None
    assert (bundle_path / "original" / "paper.pdf").read_bytes().startswith(b"%PDF")
    assert not (bundle_path / "document" / "document.json").exists()
    assert manifest.parse_status == "not_started"
    assert manifest.generated_artifacts["pdf"] == "original/paper.pdf"


def make_source_tar() -> bytes:
    content = (
        rb"\documentclass{article}"
        rb"\begin{document}"
        rb"Hello Bilin."
        rb"\end{document}"
    )
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        info = tarfile.TarInfo("paper/main.tex")
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))
    return buffer.getvalue()


def make_recommendation_item(index: int) -> ArxivRecommendationItem:
    arxiv_id = f"2605.{index:05d}v1"
    return ArxivRecommendationItem(
        arxiv_id=arxiv_id,
        bare_id=arxiv_id.removesuffix("v1"),
        version="v1",
        title=f"Quantum measurement test paper {index}",
        authors=["Ada Lovelace"],
        original_summary=f"Abstract for paper {index} about measurement grouping.",
        primary_category="quant-ph",
        categories=["quant-ph"],
        published="2026-05-11T00:00:00Z",
        updated="2026-05-11T00:00:00Z",
        abs_url=f"https://arxiv.org/abs/{arxiv_id}",
        pdf_url=f"https://arxiv.org/pdf/{arxiv_id}.pdf",
        source_url=f"https://arxiv.org/e-print/{arxiv_id}",
        score=1.0,
        score_reasons=["keyword match: measurement"],
    )
