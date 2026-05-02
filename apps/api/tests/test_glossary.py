from __future__ import annotations

from pathlib import Path

import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    create_translation_variant,
    make_block,
    replace_document,
    upsert_arxiv_revision,
)
from bilin_api.glossary_service import (
    apply_glossary_to_markdown,
    create_article_glossary_term,
    extract_article_glossary_candidates,
    get_article_glossary,
    glossary_context_markdown,
    update_article_glossary_term,
)
from bilin_api.repositories import create_library
from bilin_api.schemas import (
    ArticleManifest,
    GlossaryExtractionRequest,
    GlossaryTermCreate,
    GlossaryTermUpdate,
    Library,
    LibraryCreate,
)


@pytest.mark.asyncio
async def test_extract_confirm_render_and_mark_affected_blocks(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, revision_id, block_id = await prepare_glossary_fixture(tmp_path)

    result = await extract_article_glossary_candidates(
        library,
        revision_id,
        GlossaryExtractionRequest(target_language="zh-CN"),
    )
    terms_by_source = {term.source_term.casefold(): term for term in result.terms}
    assert result.candidates_created >= 1
    assert "parameter shift rule" in terms_by_source

    candidate = terms_by_source["parameter shift rule"]
    active = await update_article_glossary_term(
        library,
        revision_id,
        candidate.id,
        GlossaryTermUpdate(target_term="参数平移法则", status="active"),
    )
    assert active is not None
    assert active.status == "active"

    rendered = apply_glossary_to_markdown(
        "The parameter shift rule stays, but $parameter shift rule$ is protected.",
        [active],
    )
    assert "参数平移法则 stays" in rendered
    assert "$parameter shift rule$" in rendered

    context = await glossary_context_markdown(library, revision_id, "zh-CN")
    assert "parameter shift rule => 参数平移法则" in context

    await create_translation_variant(
        library=library,
        block=make_block(
            revision_id,
            block_uid="temporary",
            structural_path="999",
            block_type="paragraph",
            source_markdown="temporary",
        ).model_copy(update={"id": block_id, "block_uid": "p-0001"}),
        target_language="zh-CN",
        raw_markdown="The parameter shift rule is useful.",
        provider_profile_id="provider",
        model="model",
        glossary_version="glossary:none",
        metadata={"block_uid": "p-0001", "content_hash": "hash", "context_hash": "context"},
    )
    glossary = await get_article_glossary(library, revision_id, "zh-CN")
    assert glossary.active_version.startswith("glossary:")
    assert "p-0001" in glossary.affected_block_uids


@pytest.mark.asyncio
async def test_create_article_glossary_term_deduplicates_source(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, revision_id, _ = await prepare_glossary_fixture(tmp_path)
    first = await create_article_glossary_term(
        library,
        revision_id,
        GlossaryTermCreate(source_term="Hamiltonian Simulation", target_term="哈密顿量模拟"),
    )
    second = await create_article_glossary_term(
        library,
        revision_id,
        GlossaryTermCreate(source_term="hamiltonian simulation", target_term="哈密顿模拟"),
    )
    assert first.id == second.id
    assert second.target_term == "哈密顿模拟"


async def prepare_glossary_fixture(tmp_path: Path) -> tuple[Library, str, str]:
    library = await create_library(
        LibraryCreate(name="Glossary", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00002", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00002",
        version="v1",
        title="Glossary fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    blocks = [
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00001",
            block_type="paragraph",
            source_markdown=(
                "parameter shift rule. parameter shift rule. "
                "Quantum Approximate Optimization Algorithm (QAOA)."
            ),
        ),
        make_block(
            revision.id,
            block_uid="eq-0001",
            structural_path="00002",
            block_type="equation",
            source_markdown="E=mc^2",
        ),
    ]
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        blocks,
        [],
        blocks[0].source_markdown,
    )
    return library, revision.id, blocks[0].id
