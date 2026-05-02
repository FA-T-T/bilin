from __future__ import annotations

from pathlib import Path

import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    create_chat_message,
    make_block,
    replace_document,
    upsert_arxiv_revision,
)
from bilin_api.llm import LLMResponse
from bilin_api.note_service import (
    accept_article_note_patch,
    create_user_note_template,
    generate_article_note_patch,
    get_article_note_patches,
    update_article_note_patch,
)
from bilin_api.repositories import create_library, create_provider_profile
from bilin_api.schemas import (
    ArticleManifest,
    Library,
    LibraryCreate,
    NotePatchGenerateRequest,
    NotePatchUpdate,
    NoteTemplateCreate,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProtocol,
)


@pytest.mark.asyncio
async def test_generate_accept_and_write_lecture_note_patch(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_note_fixture(tmp_path)
    await create_chat_message(
        library,
        revision_id,
        role="assistant",
        content="The method depends on a parameter-shift estimator.",
        source_refs=["p-0001"],
    )

    result = await generate_article_note_patch(
        library,
        revision_id,
        NotePatchGenerateRequest(
            provider_profile_id=provider.id,
            template_id="deep_reading",
            max_blocks=2,
            include_chat_history=True,
        ),
        generator=fake_note_generator,
    )

    assert result.patch.status == "proposed"
    assert result.patch.title == "精读模板"
    assert "p-0001" in result.patch.source_refs
    assert result.patch.metadata["template_id"] == "deep_reading"
    patches = await get_article_note_patches(library, revision_id)
    assert [patch.id for patch in patches.patches] == [result.patch.id]

    accepted = await accept_article_note_patch(library, result.patch.id)
    assert accepted is not None
    assert accepted.status == "accepted"
    notes_path = Path(str(accepted.metadata["notes_path"]))
    assert notes_path.exists()
    notes_markdown = notes_path.read_text(encoding="utf-8")
    assert "# Lecture Notes" in notes_markdown
    assert f"<!-- bilin-note-patch:{accepted.id} -->" in notes_markdown
    assert "This paper studies gradient estimation" in notes_markdown
    assert "`p-0001`" in notes_markdown


@pytest.mark.asyncio
async def test_generate_note_patch_rejects_unknown_template(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_note_fixture(tmp_path)
    with pytest.raises(ValueError, match="Unknown note template"):
        await generate_article_note_patch(
            library,
            revision_id,
            NotePatchGenerateRequest(
                provider_profile_id=provider.id,
                template_id="unknown",
            ),
            generator=fake_note_generator,
        )


@pytest.mark.asyncio
async def test_edit_before_accept_rewrites_lecture_note_section(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_note_fixture(tmp_path)
    await create_chat_message(
        library,
        revision_id,
        role="assistant",
        content="The method depends on a parameter-shift estimator.",
        source_refs=["p-0001"],
    )
    result = await generate_article_note_patch(
        library,
        revision_id,
        NotePatchGenerateRequest(provider_profile_id=provider.id, template_id="deep_reading"),
        generator=fake_note_generator,
    )
    edited = await update_article_note_patch(
        library,
        result.patch.id,
        NotePatchUpdate(
            title="Edited reading note",
            patch_markdown="## Edited\n\nEdited note body [p-0001].",
            status="accepted",
        ),
    )

    assert edited is not None
    assert edited.status == "accepted"
    notes_path = Path(str(edited.metadata["notes_path"]))
    notes_markdown = notes_path.read_text(encoding="utf-8")
    assert "## Edited reading note" in notes_markdown
    assert "Edited note body [p-0001]." in notes_markdown
    assert f"<!-- bilin-note-patch:{edited.id} -->" in notes_markdown


@pytest.mark.asyncio
async def test_custom_note_template_can_generate_patch(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_note_fixture(tmp_path)
    template = await create_user_note_template(
        NoteTemplateCreate(
            name="My seminar template",
            description="Focus on seminar discussion and open questions.",
        )
    )
    assert template.custom is True

    result = await generate_article_note_patch(
        library,
        revision_id,
        NotePatchGenerateRequest(provider_profile_id=provider.id, template_id=template.id),
        generator=fake_custom_note_generator,
    )
    assert result.template.id == template.id
    assert result.patch.title == "My seminar template"
    assert result.patch.metadata["template_id"] == template.id


async def prepare_note_fixture(tmp_path: Path) -> tuple[Library, ProviderProfile, str]:
    library = await create_library(
        LibraryCreate(name="Notes", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00004", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00004",
        version="v1",
        title="Notes fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    blocks = [
        make_block(
            revision.id,
            block_uid="s-0001",
            structural_path="00001",
            block_type="section",
            source_markdown="# Background",
        ),
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00002",
            block_type="paragraph",
            source_markdown="The paper studies gradient estimation for variational circuits.",
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
            name="Mock Note Provider",
            protocol=ProviderProtocol.openai_compatible,
            api_key="test-key",
            default_model="mock-model",
        )
    )
    return library, provider, revision.id


async def fake_note_generator(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    template_name: str,
    template_prompt: str,
    evidence_markdown: str,
    chat_markdown: str,
) -> LLMResponse:
    assert provider.name == "Mock Note Provider"
    assert api_key == "test-key"
    assert model == "mock-model"
    assert template_name == "精读模板"
    assert "background" in template_prompt.casefold()
    assert "[p-0001]" in evidence_markdown
    assert "parameter-shift estimator" in chat_markdown
    return LLMResponse(
        text="## Background\n\nThis paper studies gradient estimation [p-0001].",
        usage={"total_tokens": 30},
    )


async def fake_custom_note_generator(
    provider: ProviderProfile,
    api_key: str,
    model: str,
    template_name: str,
    template_prompt: str,
    evidence_markdown: str,
    chat_markdown: str,
) -> LLMResponse:
    _ = (provider, api_key, model, evidence_markdown, chat_markdown)
    assert template_name == "My seminar template"
    assert "seminar discussion" in template_prompt
    return LLMResponse(
        text="## Seminar\n\nDiscuss gradient estimation [p-0001].",
        usage={"total_tokens": 20},
    )
