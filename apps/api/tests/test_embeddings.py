from __future__ import annotations

from pathlib import Path

import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    make_block,
    replace_document,
    upsert_arxiv_revision,
)
from bilin_api.embedding_service import (
    build_article_embeddings,
    get_article_embedding_status,
    hybrid_search_blocks,
    queue_article_embedding,
)
from bilin_api.qa_service import prepare_question_context
from bilin_api.repositories import create_library, create_provider_profile, get_job
from bilin_api.schemas import (
    ArticleManifest,
    ChatAskRequest,
    JobStatus,
    JobType,
    Library,
    LibraryCreate,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProtocol,
    RetrievalMode,
)
from bilin_api.worker import run_worker


@pytest.mark.asyncio
async def test_build_article_embeddings_and_hybrid_retrieval(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, _, revision_id = await prepare_embedding_fixture(tmp_path)

    result = await build_article_embeddings(library, revision_id)
    status = await get_article_embedding_status(library, revision_id)
    matches = await hybrid_search_blocks(library, revision_id, "gradient shifted circuits", limit=2)

    assert result.eligible_blocks == 3
    assert result.embedded_blocks == 3
    assert status.embedded_blocks == 3
    assert status.stale_blocks == 0
    assert matches[0].block.block_uid == "p-0002"
    assert matches[0].retrieval_method == "hybrid"
    assert matches[0].vector_score is not None


@pytest.mark.asyncio
async def test_qa_auto_retrieval_uses_hybrid_when_embeddings_are_current(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, provider, revision_id = await prepare_embedding_fixture(tmp_path)
    await build_article_embeddings(library, revision_id)

    context = await prepare_question_context(
        library,
        revision_id,
        ChatAskRequest(
            question="How are gradients estimated from shifted circuits?",
            provider_profile_id=provider.id,
            retrieval_mode=RetrievalMode.auto,
        ),
    )

    assert context.retrieved_blocks[0].block_uid == "p-0002"
    assert context.retrieved_blocks[0].retrieval_method == "hybrid"
    assert context.retrieved_blocks[0].vector_score is not None


@pytest.mark.asyncio
async def test_embed_article_job_runs_through_worker(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, _, revision_id = await prepare_embedding_fixture(tmp_path)
    job = await queue_article_embedding(library, revision_id)

    assert job.type == JobType.embed_article
    await run_worker(once=True)
    completed = await get_job(job.id)
    status = await get_article_embedding_status(library, revision_id)

    assert completed is not None
    assert completed.status == JobStatus.succeeded
    assert completed.result is not None
    assert completed.result["embedded_blocks"] == 3
    assert status.embedded_blocks == 3


async def prepare_embedding_fixture(tmp_path: Path) -> tuple[Library, ProviderProfile, str]:
    library = await create_library(
        LibraryCreate(name="Embeddings", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00007", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00007",
        version="v1",
        title="Embedding fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    blocks = [
        make_block(
            revision.id,
            block_uid="sec-0001",
            structural_path="00001",
            block_type="section",
            source_markdown="Variational circuits",
            metadata={"level": 1},
        ),
        make_block(
            revision.id,
            block_uid="p-0001",
            structural_path="00002",
            block_type="paragraph",
            source_markdown="Hamiltonian simulation uses observables in variational circuits.",
        ),
        make_block(
            revision.id,
            block_uid="p-0002",
            structural_path="00003",
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
        )
    )
    return library, provider, revision.id
