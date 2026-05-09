from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    create_translation_variant,
    get_block_by_uid,
    list_article_items,
    list_translation_variants,
    make_block,
    replace_document,
    upsert_arxiv_revision,
)
from bilin_api.credentials import CredentialWriteResult, keychain_provider_key_ref
from bilin_api.llm import LLMClientError, LLMResponse
from bilin_api.repositories import (
    create_library,
    create_provider_profile,
    get_job,
    get_provider_api_key,
    get_provider_profile,
    list_translation_memory_entries,
    update_translation_memory_entry,
)
from bilin_api.schemas import (
    ArticleManifest,
    ArticleTranslationState,
    Library,
    LibraryCreate,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProtocol,
    TranslationBatchRequest,
    TranslationMemoryEntryUpdate,
    TranslationMemoryReviewStatus,
)
from bilin_api.translation_service import (
    clean_translation_markdown,
    queue_article_translation,
    queue_library_missing_translations,
    reset_provider_throttles,
    run_translate_block_job,
    select_article_translation_variant,
    validate_translation_markdown,
)
from bilin_api.worker import run_worker


@pytest.mark.asyncio
async def test_provider_profile_stores_non_library_key_ref(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Local OpenAI Compatible",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="test-model",
        )
    )
    assert provider.key_ref is not None
    assert "test-key" not in provider.model_dump_json()
    assert str(tmp_path) not in provider.key_ref


@pytest.mark.asyncio
async def test_provider_profile_can_use_keychain_reference(
    bilin_home: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _ = bilin_home
    stored: dict[str, str] = {}

    def fake_store_provider_api_key(provider_id: str, api_key: str) -> CredentialWriteResult:
        stored[provider_id] = api_key
        return CredentialWriteResult(
            key_ref=keychain_provider_key_ref(provider_id),
            backend="keychain",
        )

    def fake_read_provider_api_key_from_keychain(provider_id: str) -> str | None:
        return stored.get(provider_id)

    monkeypatch.setattr(
        "bilin_api.repositories.store_provider_api_key",
        fake_store_provider_api_key,
    )
    monkeypatch.setattr(
        "bilin_api.repositories.read_provider_api_key_from_keychain",
        fake_read_provider_api_key_from_keychain,
    )

    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Keychain Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="test-model",
        )
    )

    assert provider.key_ref == keychain_provider_key_ref(provider.id)
    assert await get_provider_api_key(provider) == "test-key"
    assert "test-key" not in provider.model_dump_json()


@pytest.mark.asyncio
async def test_provider_api_key_read_promotes_sqlite_fallback_to_keychain(
    bilin_home: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _ = bilin_home
    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Legacy Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="legacy-key",
            default_model="test-model",
        )
    )
    assert provider.key_ref is not None
    assert provider.key_ref.startswith("app_settings:")

    stored: dict[str, str] = {}

    def fake_store_provider_api_key(provider_id: str, api_key: str) -> CredentialWriteResult:
        stored[provider_id] = api_key
        return CredentialWriteResult(
            key_ref=keychain_provider_key_ref(provider_id),
            backend="keychain",
        )

    monkeypatch.setattr(
        "bilin_api.repositories.store_provider_api_key",
        fake_store_provider_api_key,
    )

    assert await get_provider_api_key(provider) == "legacy-key"
    updated = await get_provider_profile(provider.id)
    assert updated is not None
    assert updated.key_ref == keychain_provider_key_ref(provider.id)
    assert stored[provider.id] == "legacy-key"


@pytest.mark.asyncio
async def test_provider_profile_stores_translation_limits(
    bilin_home: Path,
) -> None:
    _ = bilin_home
    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Limited Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="test-model",
            max_concurrent_requests=2,
            requests_per_minute=120,
        )
    )
    assert provider.max_concurrent_requests == 2
    assert provider.requests_per_minute == 120


@pytest.mark.asyncio
async def test_translation_queue_runs_block_job_and_reuses_cache(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    request = TranslationBatchRequest(
        target_language="zh-CN",
        provider_profile_id=provider.id,
    )
    result = await queue_article_translation(library, revision_id, request)
    assert result.jobs_created == 1
    assert result.skipped_blocks == 1
    queued_item = (await list_article_items(library))[0]
    assert queued_item.translation_status.status == ArticleTranslationState.translating
    assert queued_item.translation_status.translatable_blocks == 1
    assert queued_item.translation_status.queued_jobs == 1
    duplicate = await queue_article_translation(library, revision_id, request)
    assert duplicate.jobs_created == 0
    assert duplicate.existing_jobs == 1

    job = await get_job(result.job_ids[0])
    assert job is not None
    translated = await run_translate_block_job(job, translator=fake_translator)
    assert translated["cache_hit"] is False
    variants = await list_translation_variants(library, revision_id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].raw_markdown == "译文：A paragraph to translate."
    assert variants[0].metadata["block_uid"] == "p-0001"
    translated_item = (await list_article_items(library))[0]
    assert translated_item.translation_status.status == ArticleTranslationState.translated
    assert translated_item.translation_status.translated_blocks == 1

    second = await queue_article_translation(library, revision_id, request)
    assert second.jobs_created == 0
    assert second.cached_blocks == 1


@pytest.mark.asyncio
async def test_library_missing_translation_queue_only_targets_untranslated_blocks(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(
        tmp_path,
        extra_paragraph=True,
    )
    first_block = await get_block_by_uid(library, revision_id, "p-0001")
    assert first_block is not None
    await create_translation_variant(
        library=library,
        block=first_block,
        target_language="zh-CN",
        raw_markdown="已有人类审核译文。",
        provider_profile_id=None,
        model=None,
        glossary_version=None,
        validation_status="ok",
        metadata={
            "block_uid": first_block.block_uid,
            "content_hash": first_block.content_hash,
        },
    )

    result = await queue_library_missing_translations(
        library,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )

    assert result.articles_considered == 1
    assert result.articles_queued == 1
    assert result.jobs_created == 1
    assert result.existing_jobs == 0
    assert len(result.article_results) == 1
    job = await get_job(result.job_ids[0])
    assert job is not None
    assert job.payload["block_uid"] == "p-0002"

    duplicate = await queue_library_missing_translations(
        library,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )
    assert duplicate.jobs_created == 0
    assert duplicate.existing_jobs == 1


@pytest.mark.asyncio
async def test_translation_queue_treats_list_as_one_translatable_block(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(tmp_path, include_list=True)
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )

    jobs = [await get_job(job_id) for job_id in result.job_ids]

    assert result.jobs_created == 2
    assert result.skipped_blocks == 1
    assert any(job and job.payload["block_uid"] == "lst-0001" for job in jobs)


@pytest.mark.asyncio
async def test_translation_validation_status_preserves_bad_model_output(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )
    job = await get_job(result.job_ids[0])
    assert job is not None

    async def empty_translator(
        provider: ProviderProfile,
        api_key: str,
        model: str,
        source_markdown: str,
        target_language: str,
        context_markdown: str,
        custom_prompt: str | None,
    ) -> LLMResponse:
        _ = (
            provider,
            api_key,
            model,
            source_markdown,
            target_language,
            context_markdown,
            custom_prompt,
        )
        return LLMResponse(text="", usage={})

    translated = await run_translate_block_job(job, translator=empty_translator)
    assert translated["validation_status"] == "empty"
    variants = await list_translation_variants(library, revision_id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].raw_markdown == ""
    assert variants[0].validation_status == "empty"


@pytest.mark.asyncio
async def test_invalid_translation_variant_marks_article_failed_without_failed_job(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library, _provider, revision_id = await prepare_translation_fixture(tmp_path)
    block = await get_block_by_uid(library, revision_id, "p-0001")
    assert block is not None
    await create_translation_variant(
        library=library,
        block=block,
        target_language="zh-CN",
        raw_markdown="",
        provider_profile_id=None,
        model=None,
        glossary_version=None,
        validation_status="empty",
        metadata={"block_uid": block.block_uid, "content_hash": block.content_hash},
    )

    article = (await list_article_items(library, "zh-CN"))[0]
    assert article.translation_status.status == ArticleTranslationState.failed
    assert article.translation_status.translated_blocks == 0
    assert article.translation_status.failed_jobs == 1


def test_translation_validation_rejects_unchanged_source() -> None:
    source = "Execution Model. GPUs load inputs from HBM."

    assert validate_translation_markdown(source, source) == "unchanged_source"


def test_translation_cleaner_removes_source_prefix() -> None:
    source = "Execution Model. GPUs load inputs from HBM."
    raw = f"{source}\n\n执行模型。GPU 会从 HBM 加载输入。"

    assert clean_translation_markdown(source, raw) == "执行模型。GPU 会从 HBM 加载输入。"
    assert validate_translation_markdown(source, clean_translation_markdown(source, raw)) == "ok"


@pytest.mark.asyncio
async def test_custom_prompt_retranslation_reaches_worker_payload(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(
            target_language="zh-CN",
            provider_profile_id=provider.id,
            custom_prompt="Use compact academic Chinese.",
            force=True,
        ),
    )
    job = await get_job(result.job_ids[0])
    assert job is not None
    assert job.payload["force"] is True
    assert job.payload["custom_prompt"] == "Use compact academic Chinese."

    async def custom_translator(
        provider: ProviderProfile,
        api_key: str,
        model: str,
        source_markdown: str,
        target_language: str,
        context_markdown: str,
        custom_prompt: str | None,
    ) -> LLMResponse:
        _ = (provider, api_key, model, source_markdown, target_language, context_markdown)
        assert custom_prompt == "Use compact academic Chinese."
        return LLMResponse(text="紧凑学术译文。", usage={})

    translated = await run_translate_block_job(job, translator=custom_translator)
    assert translated["cache_hit"] is False
    variants = await list_translation_variants(library, revision_id, "zh-CN")
    assert variants[0].raw_markdown == "紧凑学术译文。"


@pytest.mark.asyncio
async def test_translation_variant_selection_marks_previous_variant_default(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )
    job = await get_job(result.job_ids[0])
    assert job is not None
    await run_translate_block_job(job, translator=fake_translator)
    first_variant = (await list_translation_variants(library, revision_id, "zh-CN"))[0]
    block = await get_block_by_uid(library, revision_id, "p-0001")
    assert block is not None
    second_variant = await create_translation_variant(
        library=library,
        block=block,
        target_language="zh-CN",
        raw_markdown="第二版译文。",
        provider_profile_id=provider.id,
        model="mock-model",
        glossary_version="glossary:none",
        metadata={"block_uid": "p-0001"},
    )
    assert second_variant.is_default is True

    selected = await select_article_translation_variant(library, revision_id, first_variant.id)
    assert selected is not None
    assert selected.is_default is True
    variants = await list_translation_variants(library, revision_id, "zh-CN")
    defaults = {variant.id for variant in variants if variant.is_default}
    assert defaults == {first_variant.id}


@pytest.mark.asyncio
async def test_translation_memory_requires_review_before_cross_article_reuse(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    first_library, first_provider, first_revision_id = await prepare_translation_fixture(
        tmp_path / "first"
    )
    first_result = await queue_article_translation(
        first_library,
        first_revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=first_provider.id),
    )
    first_job = await get_job(first_result.job_ids[0])
    assert first_job is not None
    await run_translate_block_job(first_job, translator=fake_translator)
    pending_entries = await list_translation_memory_entries(
        target_language="zh-CN",
        review_status=TranslationMemoryReviewStatus.pending,
    )
    assert len(pending_entries) == 1
    assert pending_entries[0].reuse_enabled is False

    second_library, second_provider, second_revision_id = await prepare_translation_fixture(
        tmp_path / "second"
    )
    second_result = await queue_article_translation(
        second_library,
        second_revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=second_provider.id),
    )
    second_job = await get_job(second_result.job_ids[0])
    assert second_job is not None

    async def second_translator(
        provider: ProviderProfile,
        api_key: str,
        model: str,
        source_markdown: str,
        target_language: str,
        context_markdown: str,
        custom_prompt: str | None,
    ) -> LLMResponse:
        _ = (
            provider,
            api_key,
            model,
            source_markdown,
            target_language,
            context_markdown,
            custom_prompt,
        )
        return LLMResponse(text="第二篇译文。", usage={})

    translated = await run_translate_block_job(second_job, translator=second_translator)
    assert translated.get("cache_hit") is not True
    variants = await list_translation_variants(second_library, second_revision_id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].raw_markdown == "第二篇译文。"

    approved = await update_translation_memory_entry(
        pending_entries[0].id,
        TranslationMemoryEntryUpdate(
            review_status=TranslationMemoryReviewStatus.approved,
            reuse_enabled=True,
        ),
    )
    assert approved is not None
    assert approved.review_status == TranslationMemoryReviewStatus.approved
    assert approved.reuse_enabled is True

    third_library, third_provider, third_revision_id = await prepare_translation_fixture(
        tmp_path / "third"
    )
    third_result = await queue_article_translation(
        third_library,
        third_revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=third_provider.id),
    )
    third_job = await get_job(third_result.job_ids[0])
    assert third_job is not None

    async def unavailable_translator(*args, **kwargs):  # type: ignore[no-untyped-def]
        _ = (args, kwargs)
        raise AssertionError("approved translation memory should avoid the provider call")

    translated = await run_translate_block_job(third_job, translator=unavailable_translator)
    assert translated["cache_hit"] is True
    assert translated["cache_source"] == "translation_memory"
    variants = await list_translation_variants(third_library, third_revision_id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].raw_markdown == "译文：A paragraph to translate."
    assert variants[0].metadata["cache_source"] == "translation_memory"


@pytest.mark.asyncio
async def test_worker_completes_translate_block_with_mocked_translator(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )

    async def fake_worker_translator(*args, **kwargs):  # type: ignore[no-untyped-def]
        return await fake_translator(*args, **kwargs)

    monkeypatch.setattr("bilin_api.translation_service.translate_markdown", fake_worker_translator)
    await run_worker(once=True)
    variants = await list_translation_variants(library, revision_id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].raw_markdown.startswith("译文：")


@pytest.mark.asyncio
async def test_worker_retries_transient_translation_errors(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )
    calls = 0

    async def flaky_translator(*args, **kwargs):  # type: ignore[no-untyped-def]
        nonlocal calls
        calls += 1
        if calls == 1:
            raise LLMClientError("Server error '503 Service Unavailable'")
        return await fake_translator(*args, **kwargs)

    monkeypatch.setattr("bilin_api.translation_service.translate_markdown", flaky_translator)
    await run_worker(once=True)

    assert calls == 2
    job = await get_job(result.job_ids[0])
    assert job is not None
    assert job.attempts == 2
    assert job.status == "succeeded"
    assert job.error is None
    variants = await list_translation_variants(library, revision_id, "zh-CN")
    assert len(variants) == 1


@pytest.mark.asyncio
async def test_worker_marks_invalid_translation_output_failed_not_translated(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _ = bilin_home
    library, provider, revision_id = await prepare_translation_fixture(tmp_path)
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )

    async def empty_translator(*args, **kwargs):  # type: ignore[no-untyped-def]
        _ = (args, kwargs)
        return LLMResponse(text="", usage={})

    monkeypatch.setattr("bilin_api.translation_service.translate_markdown", empty_translator)
    await run_worker(once=True)

    job = await get_job(result.job_ids[0])
    assert job is not None
    assert job.status == "failed"
    assert job.attempts == 3
    assert job.error is not None
    assert job.error["code"] == "translation_validation_failed"
    assert job.error["validation_status"] == "empty"
    assert job.error["block_uid"] == "p-0001"

    variants = await list_translation_variants(library, revision_id, "zh-CN")
    assert variants
    assert all(variant.validation_status == "empty" for variant in variants)

    article = (await list_article_items(library, "zh-CN"))[0]
    assert article.translation_status.status == ArticleTranslationState.failed
    assert article.translation_status.translated_blocks == 0
    assert article.translation_status.failed_jobs == 1


@pytest.mark.asyncio
async def test_translation_jobs_respect_provider_concurrency_limit(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    reset_provider_throttles()
    library, provider, revision_id = await prepare_translation_fixture(
        tmp_path,
        extra_paragraph=True,
        max_concurrent_requests=1,
    )
    result = await queue_article_translation(
        library,
        revision_id,
        TranslationBatchRequest(target_language="zh-CN", provider_profile_id=provider.id),
    )
    assert result.jobs_created == 2
    jobs = [await get_job(job_id) for job_id in result.job_ids]
    assert all(job is not None for job in jobs)

    in_flight = 0
    max_in_flight = 0

    async def tracked_translator(
        provider: ProviderProfile,
        api_key: str,
        model: str,
        source_markdown: str,
        target_language: str,
        context_markdown: str,
        custom_prompt: str | None,
    ) -> LLMResponse:
        nonlocal in_flight, max_in_flight
        _ = (provider, api_key, model, target_language, context_markdown, custom_prompt)
        in_flight += 1
        max_in_flight = max(max_in_flight, in_flight)
        await asyncio.sleep(0.01)
        in_flight -= 1
        return LLMResponse(text=f"译文：{source_markdown}", usage={"total_tokens": 12})

    await asyncio.gather(
        *(run_translate_block_job(job, translator=tracked_translator) for job in jobs if job)
    )
    assert max_in_flight == 1


@pytest.mark.asyncio
async def test_replace_document_preserves_translation_variants_for_stable_block_uids(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library = await create_library(
        LibraryCreate(name="Reparse", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00001", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Reparse fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    old_block = make_block(
        revision.id,
        block_uid="p-0001",
        structural_path="00001",
        block_type="paragraph",
        source_markdown="A paragraph with stale inline math.",
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        [old_block],
        [],
        old_block.source_markdown,
    )
    stored_old_block = await get_block_by_uid(library, revision.id, "p-0001")
    assert stored_old_block is not None
    await create_translation_variant(
        library,
        stored_old_block,
        target_language="zh-CN",
        provider_profile_id=None,
        model=None,
        raw_markdown="已有译文",
        validation_status="ok",
        glossary_version=None,
        is_default=True,
    )

    new_block = make_block(
        revision.id,
        block_uid="p-0001",
        structural_path="00001",
        block_type="paragraph",
        source_markdown="A paragraph with fixed inline math $x_1$.",
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        [new_block],
        [],
        new_block.source_markdown,
    )

    stored_new_block = await get_block_by_uid(library, revision.id, "p-0001")
    assert stored_new_block is not None
    assert stored_new_block.id == stored_old_block.id
    assert stored_new_block.source_markdown == "A paragraph with fixed inline math $x_1$."
    variants = await list_translation_variants(library, revision.id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].block_id == stored_old_block.id
    assert variants[0].raw_markdown == "已有译文"


@pytest.mark.asyncio
async def test_replace_document_rehomes_translation_variants_when_block_uid_shifts_by_hash(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library = await create_library(
        LibraryCreate(name="Reparse shifted", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00001", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Reparse shifted fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    old_blocks = [
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00001",
            block_type="paragraph",
            source_markdown="Intro.",
        ),
        make_block(
            revision.id,
            block_uid="p-0002",
            structural_path="00002",
            block_type="paragraph",
            source_markdown="Abstract body.",
        ),
        make_block(
            revision.id,
            block_uid="p-0003",
            structural_path="00003",
            block_type="paragraph",
            source_markdown="Next body.",
        ),
    ]
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        old_blocks,
        [],
        "\n\n".join(block.source_markdown for block in old_blocks),
    )
    stored_old_body = await get_block_by_uid(library, revision.id, "p-0002")
    assert stored_old_body is not None
    await create_translation_variant(
        library,
        stored_old_body,
        target_language="zh-CN",
        provider_profile_id=None,
        model=None,
        raw_markdown="摘要正文译文",
        validation_status="ok",
        glossary_version=None,
        is_default=True,
        metadata={
            "block_uid": stored_old_body.block_uid,
            "content_hash": stored_old_body.content_hash,
            "context_hash": "ctx",
        },
    )

    new_blocks = [
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00001",
            block_type="paragraph",
            source_markdown="Intro.",
        ),
        make_block(
            revision.id,
            block_uid="p-0002",
            structural_path="00002",
            block_type="paragraph",
            source_markdown="**Abstract**",
        ),
        make_block(
            revision.id,
            block_uid="p-0003",
            structural_path="00003",
            block_type="paragraph",
            source_markdown="Abstract body.",
        ),
        make_block(
            revision.id,
            block_uid="p-0004",
            structural_path="00004",
            block_type="paragraph",
            source_markdown="Next body.",
        ),
    ]
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        new_blocks,
        [],
        "\n\n".join(block.source_markdown for block in new_blocks),
    )

    stored_new_body = await get_block_by_uid(library, revision.id, "p-0003")
    assert stored_new_body is not None
    variants = await list_translation_variants(library, revision.id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].block_id == stored_new_body.id
    assert variants[0].raw_markdown == "摘要正文译文"
    assert variants[0].metadata["block_uid"] == "p-0003"
    assert variants[0].metadata["content_hash"] == stored_new_body.content_hash


@pytest.mark.asyncio
async def test_list_translation_variants_keeps_stable_block_uid_after_reparse(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    _ = bilin_home
    library = await create_library(
        LibraryCreate(name="Reparse stale", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00001", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Reparse stale fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    old_block = make_block(
        revision.id,
        block_uid="p-0001",
        structural_path="00001",
        block_type="paragraph",
        source_markdown="Old body.",
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        [old_block],
        [],
        old_block.source_markdown,
    )
    stored_old_block = await get_block_by_uid(library, revision.id, "p-0001")
    assert stored_old_block is not None
    await create_translation_variant(
        library,
        stored_old_block,
        target_language="zh-CN",
        provider_profile_id=None,
        model=None,
        raw_markdown="旧译文",
        validation_status="ok",
        glossary_version=None,
        is_default=True,
        metadata={
            "block_uid": stored_old_block.block_uid,
            "content_hash": stored_old_block.content_hash,
        },
    )

    new_block = make_block(
        revision.id,
        block_uid="p-0001",
        structural_path="00001",
        block_type="paragraph",
        source_markdown="New body.",
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        [new_block],
        [],
        new_block.source_markdown,
    )

    variants = await list_translation_variants(library, revision.id, "zh-CN")
    assert len(variants) == 1
    assert variants[0].block_id == stored_old_block.id
    assert variants[0].raw_markdown == "旧译文"


async def prepare_translation_fixture(
    tmp_path: Path,
    *,
    extra_paragraph: bool = False,
    include_list: bool = False,
    max_concurrent_requests: int = 1,
) -> tuple[Library, ProviderProfile, str]:
    library = await create_library(
        LibraryCreate(name="Translate", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00001", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Translation fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    blocks = [
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00001",
            block_type="paragraph",
            source_markdown="A paragraph to translate.",
        ),
        make_block(
            revision.id,
            block_uid="eq-0001",
            structural_path="00002",
            block_type="equation",
            source_markdown="E=mc^2",
        ),
    ]
    if extra_paragraph:
        blocks.append(
            make_block(
                revision.id,
                block_uid="p-0002",
                structural_path="00003",
                block_type="paragraph",
                source_markdown="A second paragraph to translate.",
            )
        )
    if include_list:
        blocks.append(
            make_block(
                revision.id,
                block_uid="lst-0001",
                structural_path=f"{len(blocks) + 1:05d}",
                block_type="list",
                source_markdown="- First list item.\n- Second list item.",
            )
        )
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        blocks,
        [],
        "A paragraph to translate.\n",
    )
    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Mock Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="mock-model",
            max_concurrent_requests=max_concurrent_requests,
        )
    )
    return library, provider, revision.id


async def fake_translator(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    source_markdown: str,
    target_language: str,
    context_markdown: str,
    custom_prompt: str | None,
) -> LLMResponse:
    assert provider.name == "Mock Provider"
    assert api_key == "test-key"
    assert model == "mock-model"
    assert target_language == "zh-CN"
    assert custom_prompt is None
    assert "E=mc^2" in context_markdown
    return LLMResponse(text=f"译文：{source_markdown}", usage={"total_tokens": 12})
