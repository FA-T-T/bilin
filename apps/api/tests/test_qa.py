from __future__ import annotations

from pathlib import Path

import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    list_chat_messages,
    make_block,
    replace_document,
    search_blocks,
    upsert_arxiv_revision,
)
from bilin_api.llm import LLMResponse
from bilin_api.note_service import create_note_patch_from_chat_message
from bilin_api.qa_service import (
    ask_article_question,
    prepare_question_context,
    retrieve_evidence_blocks,
    stream_question_answer_events,
)
from bilin_api.repositories import create_library, create_provider_profile
from bilin_api.schemas import (
    ArticleManifest,
    ChatAskRequest,
    ChatToNotePatchRequest,
    Library,
    LibraryCreate,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProtocol,
)


@pytest.mark.asyncio
async def test_article_question_answering_retrieves_and_saves_chat(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_qa_fixture(tmp_path)
    request = ChatAskRequest(
        question="Why is parameter shift useful?",
        provider_profile_id=provider.id,
        current_block_uid="p-0002",
    )
    evidence = await retrieve_evidence_blocks(library, revision_id, request)
    assert [block.block_uid for block, _ in evidence][0] == "p-0002"

    result = await ask_article_question(
        library,
        revision_id,
        request,
        answerer=fake_answerer,
    )
    assert result.assistant_message.content.startswith("It estimates gradients")
    assert "p-0002" in result.assistant_message.source_refs
    messages = await list_chat_messages(library, revision_id)
    assert [message.role for message in messages] == ["user", "assistant"]


@pytest.mark.asyncio
async def test_native_search_external_citations_are_normalized_and_saved(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_qa_fixture(
        tmp_path,
        capabilities={"native_search": True},
    )
    result = await ask_article_question(
        library,
        revision_id,
        ChatAskRequest(
            question="What external source supports this?",
            provider_profile_id=provider.id,
            current_block_uid="p-0001",
            native_search=True,
        ),
        answerer=fake_native_search_answerer,
    )

    assert result.native_search_used is True
    assert result.external_refs[0].title == "External gradient note"
    assert result.external_refs[0].url == "https://example.com/gradient"
    assert result.external_refs[0].arxiv_id == "2401.00003"
    assert result.external_refs[0].model == "mock-model"
    assert result.external_refs[0].retrieved_at
    messages = await list_chat_messages(library, revision_id)
    assistant = messages[-1]
    assert assistant.external_refs[0].source == "external_native_search"
    assert assistant.metadata["evidence_policy"] == "external_native_search_allowed"


@pytest.mark.asyncio
async def test_stream_question_answer_events_save_after_completion(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_qa_fixture(tmp_path)
    request = ChatAskRequest(
        question="Why is parameter shift useful?",
        provider_profile_id=provider.id,
        current_block_uid="p-0002",
    )
    context = await prepare_question_context(library, revision_id, request)
    events = stream_question_answer_events(
        library,
        revision_id,
        request,
        context,
        answerer=fake_answerer,
    )

    first_event = await anext(events)
    assert first_event.startswith("event: evidence")
    assert await list_chat_messages(library, revision_id) == []

    remaining_events = [event async for event in events]
    assert any(event.startswith("event: delta") for event in remaining_events)
    assert remaining_events[-1].startswith("event: done")
    messages = await list_chat_messages(library, revision_id)
    assert [message.role for message in messages] == ["user", "assistant"]


@pytest.mark.asyncio
async def test_chat_answer_can_create_note_patch_candidate(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_qa_fixture(tmp_path)
    result = await ask_article_question(
        library,
        revision_id,
        ChatAskRequest(
            question="Why is parameter shift useful?",
            provider_profile_id=provider.id,
            current_block_uid="p-0002",
        ),
        answerer=fake_answerer,
    )
    patch = await create_note_patch_from_chat_message(
        library,
        revision_id,
        result.assistant_message.id,
        ChatToNotePatchRequest(title="Parameter shift note"),
    )

    assert patch is not None
    assert patch.status == "proposed"
    assert patch.source_refs == ["p-0002", "p-0001"]
    assert "It estimates gradients" in patch.patch_markdown
    assert patch.metadata["chat_message_id"] == result.assistant_message.id


@pytest.mark.asyncio
async def test_fts_search_indexes_replaced_document(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, _, revision_id = await prepare_qa_fixture(tmp_path)
    matches = await search_blocks(library, revision_id, "Hamiltonian gradients", limit=3)
    assert matches
    assert matches[0][0].block_uid in {"p-0001", "p-0002"}


@pytest.mark.asyncio
async def test_native_search_requires_provider_capability(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_qa_fixture(tmp_path)
    with pytest.raises(ValueError, match="Native search"):
        await ask_article_question(
            library,
            revision_id,
            ChatAskRequest(
                question="Find external evidence.",
                provider_profile_id=provider.id,
                native_search=True,
            ),
            answerer=fake_answerer,
        )


async def prepare_qa_fixture(
    tmp_path: Path,
    *,
    capabilities: dict[str, object] | None = None,
) -> tuple[Library, ProviderProfile, str]:
    library = await create_library(
        LibraryCreate(name="QA", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00003", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00003",
        version="v1",
        title="QA fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    blocks = [
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00001",
            block_type="paragraph",
            source_markdown="Hamiltonian simulation uses gradients in variational circuits.",
        ),
        make_block(
            revision.id,
            block_uid="p-0002",
            structural_path="00002",
            block_type="paragraph",
            source_markdown="The parameter shift rule estimates gradients from shifted circuits.",
        ),
    ]
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        blocks,
        [],
        "\n\n".join(block.source_markdown for block in blocks),
    )
    provider = await create_provider_profile(
        ProviderProfileCreate(
            name="Mock QA Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="mock-model",
            capabilities=capabilities or {},
        )
    )
    return library, provider, revision.id


async def fake_answerer(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    question: str,
    evidence_markdown: str,
    native_search: bool,
) -> LLMResponse:
    assert provider.name == "Mock QA Provider"
    assert api_key == "test-key"
    assert model == "mock-model"
    assert "parameter shift rule" in evidence_markdown
    assert "Why is parameter shift useful?" in question
    assert native_search is False
    return LLMResponse(
        text="It estimates gradients from shifted circuits [p-0002].",
        usage={"total_tokens": 20},
    )


async def fake_native_search_answerer(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    question: str,
    evidence_markdown: str,
    native_search: bool,
) -> LLMResponse:
    assert provider.name == "Mock QA Provider"
    assert api_key == "test-key"
    assert model == "mock-model"
    assert "external source" in question
    assert "Hamiltonian" in evidence_markdown
    assert native_search is True
    return LLMResponse(
        text="The paper evidence is local [p-0001], with external context available.",
        raw={
            "citations": [
                {
                    "title": "External gradient note",
                    "url": "https://example.com/gradient",
                    "arxiv_id": "2401.00003",
                    "snippet": "A raw external citation snippet.",
                }
            ]
        },
        usage={"total_tokens": 30},
    )
