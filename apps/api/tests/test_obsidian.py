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
from bilin_api.obsidian_service import save_obsidian_clip
from bilin_api.repositories import create_library
from bilin_api.schemas import (
    ArticleManifest,
    LibraryCreate,
    ObsidianClipColor,
    ObsidianClipRequest,
)


@pytest.mark.asyncio
async def test_save_obsidian_clip_groups_blocks_by_library_and_article(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    home = tmp_path / "home"
    onedrive = home / "Library" / "CloudStorage" / "OneDrive-Personal"
    onedrive.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))

    library = await create_library(
        LibraryCreate(name="Transformer Reading", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "1706.03762", "v7")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="1706.03762",
        version="v7",
        title="Attention Is All You Need",
        bundle_path=bundle_path,
        metadata={},
    )
    block = make_block(
        revision.id,
        block_uid="p-0001",
        structural_path="00002",
        block_type="paragraph",
        source_markdown="Self-attention connects all positions in a sequence.",
    )
    second_block = make_block(
        revision.id,
        block_uid="p-0002",
        structural_path="00003",
        block_type="paragraph",
        source_markdown="The Transformer uses attention instead of recurrence.",
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(
            article_revision_id=revision.id,
            source="arxiv",
            arxiv_id="1706.03762v7",
            arxiv_metadata={"title": "Attention Is All You Need"},
        ),
        [block, second_block],
        [],
        block.source_markdown,
    )
    await create_translation_variant(
        library=library,
        block=block,
        target_language="zh-CN",
        raw_markdown="自注意力连接序列中的所有位置。",
        provider_profile_id=None,
        model=None,
        glossary_version=None,
    )

    result = await save_obsidian_clip(
        library,
        revision.id,
        ObsidianClipRequest(
            block_uid="p-0001",
            target_language="zh-CN",
            color=ObsidianClipColor.yellow,
        ),
    )

    note_path = Path(result.note_path)
    content = note_path.read_text(encoding="utf-8")
    assert result.vault_path == str(onedrive / "Obsidian" / "Ilios")
    assert note_path.name == "Transformer Reading.md"
    assert "# Transformer Reading" in content
    assert "## Attention Is All You Need" in content
    assert "> [!important] Key idea · p-0001" in content
    assert "> Self-attention connects all positions in a sequence." in content
    assert "> 自注意力连接序列中的所有位置。" in content
    assert "#ilios/key-idea" in content
    assert "<!-- ilios-" not in content
    assert f"^ilios-{revision.id}-p-0001" in content

    await save_obsidian_clip(
        library,
        revision.id,
        ObsidianClipRequest(
            block_uid="p-0002",
            target_language="zh-CN",
            color=ObsidianClipColor.none,
        ),
    )

    second = await save_obsidian_clip(
        library,
        revision.id,
        ObsidianClipRequest(
            block_uid="p-0001",
            target_language="zh-CN",
            color=ObsidianClipColor.green,
        ),
    )
    updated = note_path.read_text(encoding="utf-8")
    assert second.updated_existing is True
    assert updated.count(f"^ilios-{revision.id}-p-0001") == 1
    assert updated.count(f"^ilios-{revision.id}-p-0002") == 1
    assert f"^ilios-{revision.id}-p-0001\n\n### p-0002" in updated
    assert "<!-- ilios-" not in updated
    assert "> [!success] Evidence · p-0001" in updated


@pytest.mark.asyncio
async def test_save_obsidian_clip_migrates_legacy_html_markers(
    bilin_home: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    home = tmp_path / "home"
    onedrive = home / "Library" / "CloudStorage" / "OneDrive-Personal"
    vault = onedrive / "Obsidian" / "Ilios"
    vault.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))

    library = await create_library(
        LibraryCreate(name="Legacy", path=str(tmp_path / "library")),
    )
    bundle_path = bundle_path_for_arxiv(library, "1706.03762", "v7")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="1706.03762",
        version="v7",
        title="Attention Is All You Need",
        bundle_path=bundle_path,
        metadata={},
    )
    block = make_block(
        revision.id,
        block_uid="p-0008",
        structural_path="00002",
        block_type="paragraph",
        source_markdown="Self-attention relates positions in one sequence.",
    )
    await replace_document(
        library,
        revision,
        ArticleManifest(
            article_revision_id=revision.id,
            source="arxiv",
            arxiv_id="1706.03762v7",
            arxiv_metadata={"title": "Attention Is All You Need"},
        ),
        [block],
        [],
        block.source_markdown,
    )
    note_path = vault / "Legacy.md"
    note_path.write_text(
        "\n".join(
            [
                "# Legacy",
                "",
                "## Attention Is All You Need",
                "",
                f"<!-- ilios-article:{revision.id} -->",
                "",
                f"- Ilios revision: `{revision.id}`",
                "- arXiv: `1706.03762v7`",
                "",
                f"<!-- ilios-block:{revision.id}:p-0008 -->",
                "### p-0008",
                "",
                "> [!important] Key idea · p-0008",
                "> old text",
                f"^ilios-{revision.id}-p-0008",
                f"<!-- /ilios-block:{revision.id}:p-0008 -->",
                "",
                f"<!-- /ilios-article:{revision.id} -->",
                "",
            ]
        ),
        encoding="utf-8",
    )

    result = await save_obsidian_clip(
        library,
        revision.id,
        ObsidianClipRequest(
            block_uid="p-0008",
            target_language="zh-CN",
            color=ObsidianClipColor.blue,
        ),
    )

    updated = Path(result.note_path).read_text(encoding="utf-8")
    assert result.updated_existing is True
    assert "<!-- ilios-" not in updated
    assert updated.count(f"^ilios-{revision.id}-p-0008") == 1
    assert "> [!info] Method · p-0008" in updated
    assert "old text" not in updated
