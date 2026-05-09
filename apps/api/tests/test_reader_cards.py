from __future__ import annotations

from pathlib import Path

import httpx
import pytest

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    create_reader_card,
    make_block,
    replace_document,
    upsert_arxiv_revision,
)
from bilin_api.reader_card_service import (
    canonical_key_for_term,
    collect_reader_card_candidates,
    create_manual_reader_card,
    export_reader_cards_to_obsidian,
    extract_article_reader_cards,
    generate_article_reader_card,
    get_article_reader_cards,
    normalize_full_form,
)
from bilin_api.repositories import create_library
from bilin_api.schemas import (
    ArticleManifest,
    Library,
    LibraryCreate,
    ReaderCardCreate,
    ReaderCardExtractionRequest,
    ReaderCardGenerationRequest,
    ReaderCardObsidianExportRequest,
    ReaderCardSourceType,
    ReaderCardStatus,
    ReaderCardType,
)


@pytest.mark.asyncio
async def test_reader_card_extraction_creates_wikipedia_card(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, revision_id = await prepare_reader_card_fixture(tmp_path)

    async with httpx.AsyncClient(transport=wiki_transport()) as client:
        result = await extract_article_reader_cards(
            library,
            revision_id,
            ReaderCardExtractionRequest(target_language="zh-CN", limit=10),
            client=client,
        )

    assert result.wiki_cards_created == 1
    card = next(card for card in result.cards if card.abbreviation == "CNN")
    assert card.full_form == "Convolutional Neural Networks"
    assert card.source_type == ReaderCardSourceType.wikipedia
    assert card.source_url == "https://zh.wikipedia.org/wiki/卷积神经网络"
    assert "卷积神经网络" in card.body_markdown
    assert card.metadata["evidence_block_uids"] == ["p-0001"]


@pytest.mark.asyncio
async def test_reader_card_generation_does_not_overwrite_user_edited_card(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, revision_id = await prepare_reader_card_fixture(tmp_path)
    card = await create_manual_reader_card(
        library,
        revision_id,
        ReaderCardCreate(
            card_type=ReaderCardType.term,
            anchor_block_uid="p-0001",
            anchor_text="CNN",
            abbreviation="CNN",
            full_form="Convolutional Neural Networks",
            title="Convolutional Neural Networks (CNN)",
            body_markdown="用户自己写的解释。",
            source_type=ReaderCardSourceType.user_note,
            status=ReaderCardStatus.pinned,
        ),
    )

    result = await generate_article_reader_card(
        library,
        revision_id,
        ReaderCardGenerationRequest(
            anchor_block_uid="p-0001",
            anchor_text="CNN",
            abbreviation="CNN",
            full_form="Convolutional Neural Networks",
            target_language="zh-CN",
        ),
    )

    assert result.card.id == card.id
    assert result.card.body_markdown == "用户自己写的解释。"
    assert "suggested_body_markdown" in result.card.metadata
    assert result.source_type == ReaderCardSourceType.paper_local


@pytest.mark.asyncio
async def test_term_card_obsidian_export_excludes_paper_context(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    home = tmp_path / "home"
    onedrive = home / "Library" / "CloudStorage" / "OneDrive-Personal"
    onedrive.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    library, revision_id = await prepare_reader_card_fixture(tmp_path)
    card = await create_reader_card(
        library,
        revision_id=revision_id,
        card_type=ReaderCardType.term,
        anchor_block_uid="p-0001",
        anchor_text="CNN",
        canonical_key=canonical_key_for_term("CNN", "Convolutional Neural Networks"),
        abbreviation="CNN",
        full_form="Convolutional Neural Networks",
        title="Convolutional Neural Networks (CNN)",
        body_markdown="卷积神经网络是一类用于网格结构数据的神经网络。",
        target_language="zh-CN",
        source_type=ReaderCardSourceType.wikipedia,
        source_url="https://zh.wikipedia.org/wiki/卷积神经网络",
        status=ReaderCardStatus.pinned,
    )

    result = await export_reader_cards_to_obsidian(
        library,
        revision_id,
        ReaderCardObsidianExportRequest(target_language="zh-CN", card_ids=[card.id]),
    )

    content = Path(result.note_path).read_text(encoding="utf-8")
    assert "## 术语 Wiki" in content
    assert "### Convolutional Neural Networks (CNN)" in content
    assert "卷积神经网络是一类用于网格结构数据的神经网络。" in content
    assert "https://zh.wikipedia.org/wiki/卷积神经网络" in content
    assert "Convolutional Neural Networks (CNN) improve image classification." not in content
    assert "arXiv" not in content
    assert revision_id not in content


def test_reader_card_normalization_handles_plural_and_hyphen_variants() -> None:
    assert normalize_full_form("Convolutional-Neural-Networks") == "convolutional neural network"
    assert (
        canonical_key_for_term("CNN", "Convolutional Neural Networks")
        == "CNN::convolutional neural network"
    )


def test_reader_card_candidate_extraction_filters_context_phrases() -> None:
    block = make_block(
        "revision-1",
        block_uid="p-terms",
        structural_path="00001",
        block_type="paragraph",
        source_markdown=(
            "On the ImageNet dataset, ResNet improves accuracy. "
            "Architectures for ImageNet are compared with VGG Simonyan2015 and SGD baselines. "
            "Faster R-CNN Ren2015 is a detection method. "
            "The CIFAR-10 test set is also used."
        ),
    )

    candidates = collect_reader_card_candidates([block])
    titles = {candidate.title for candidate in candidates}

    assert "On the ImageNet" not in titles
    assert "Architectures for ImageNet" not in titles
    assert "Simonyan2015" not in titles
    assert "Ren2015" not in titles
    assert "VGG Simonyan2015" not in titles
    assert "Faster R-CNN Ren2015" not in titles
    assert "ImageNet" in titles
    assert "ResNet" in titles
    assert "VGG" in titles
    assert "SGD" in titles
    assert "Faster R-CNN" in titles
    assert "CIFAR-10" in titles
    assert sum(1 for candidate in candidates if candidate.title == "ImageNet") == 1


@pytest.mark.asyncio
async def test_auto_extracted_cards_hide_stale_context_phrase_candidates(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library, revision_id = await prepare_reader_card_fixture(tmp_path)
    await create_reader_card(
        library,
        revision_id=revision_id,
        card_type=ReaderCardType.term,
        anchor_block_uid="p-0001",
        anchor_text="On the ImageNet",
        canonical_key=canonical_key_for_term(None, "On the ImageNet"),
        abbreviation=None,
        full_form="On the ImageNet",
        title="On the ImageNet",
        body_markdown="bad candidate",
        target_language="zh-CN",
        source_type=ReaderCardSourceType.paper_local,
        status=ReaderCardStatus.candidate,
        metadata={"extraction_source": "auto_extract"},
    )
    await create_reader_card(
        library,
        revision_id=revision_id,
        card_type=ReaderCardType.term,
        anchor_block_uid="p-0001",
        anchor_text="ImageNet",
        canonical_key=canonical_key_for_term(None, "ImageNet"),
        abbreviation=None,
        full_form="ImageNet",
        title="ImageNet",
        body_markdown="valid candidate",
        target_language="zh-CN",
        source_type=ReaderCardSourceType.paper_local,
        status=ReaderCardStatus.candidate,
        metadata={"extraction_source": "auto_extract"},
    )

    result = await get_article_reader_cards(library, revision_id, "zh-CN")
    titles = {card.title for card in result.cards}

    assert "On the ImageNet" not in titles
    assert "ImageNet" in titles


async def prepare_reader_card_fixture(tmp_path: Path) -> tuple[Library, str]:
    library = await create_library(
        LibraryCreate(name="Card Library", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "2401.00003", "v1")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00003",
        version="v1",
        title="Reader card fixture",
        bundle_path=bundle_path,
        metadata={},
    )
    block = make_block(
        revision.id,
        block_uid="p-0001",
        structural_path="00001",
        block_type="paragraph",
        source_markdown=(
            "Convolutional Neural Networks (CNN) improve image classification. "
            "Convolutional Neural Networks (CNN) can share weights."
        ),
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(article_revision_id=revision.id, source="arxiv"),
        [block],
        [],
        block.source_markdown,
    )
    return library, revision.id


def wiki_transport() -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "www.wikidata.org":
            action = request.url.params.get("action")
            if action == "wbsearchentities":
                return httpx.Response(200, json={"search": [{"id": "Q17084460"}]})
            if action == "wbgetentities":
                return httpx.Response(
                    200,
                    json={
                        "entities": {
                            "Q17084460": {
                                "labels": {
                                    "en": {"value": "Convolutional Neural Networks"},
                                    "zh": {"value": "卷积神经网络"},
                                },
                                "aliases": {"en": [{"value": "Convolutional Neural Network"}]},
                                "sitelinks": {
                                    "zhwiki": {"title": "卷积神经网络"},
                                    "enwiki": {"title": "Convolutional neural network"},
                                },
                            }
                        }
                    },
                )
        if request.url.host == "zh.wikipedia.org":
            return httpx.Response(
                200,
                json={
                    "title": "卷积神经网络",
                    "extract": "卷积神经网络是一类用于处理网格结构数据的神经网络。",
                    "content_urls": {
                        "desktop": {"page": "https://zh.wikipedia.org/wiki/卷积神经网络"}
                    },
                    "wikibase_item": "Q17084460",
                },
            )
        return httpx.Response(404)

    return httpx.MockTransport(handler)
