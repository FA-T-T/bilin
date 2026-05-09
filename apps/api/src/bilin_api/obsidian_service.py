from __future__ import annotations

import re
from pathlib import Path

from bilin_api.article_store import get_article_item, get_block_by_uid, list_translation_variants
from bilin_api.glossary_service import active_article_glossary_terms, apply_glossary_to_markdown
from bilin_api.schemas import (
    DocumentBlock,
    Library,
    ObsidianClipColor,
    ObsidianClipRequest,
    ObsidianClipResult,
    ReaderCard,
    ReaderCardObsidianExportResult,
    ReaderCardSourceType,
    TranslationVariant,
)

OBSIDIAN_VAULT_NAME = "Ilios"

COLOR_META: dict[ObsidianClipColor, tuple[str, str, str]] = {
    ObsidianClipColor.none: ("note", "Paper note", "#ilios/note"),
    ObsidianClipColor.yellow: ("important", "Key idea", "#ilios/key-idea"),
    ObsidianClipColor.blue: ("info", "Method", "#ilios/method"),
    ObsidianClipColor.green: ("success", "Evidence", "#ilios/evidence"),
    ObsidianClipColor.pink: ("question", "Question", "#ilios/question"),
    ObsidianClipColor.purple: ("abstract", "Review later", "#ilios/review"),
}


async def save_obsidian_clip(
    library: Library,
    revision_id: str,
    request: ObsidianClipRequest,
) -> ObsidianClipResult:
    item = await get_article_item(library, revision_id)
    if item is None:
        msg = f"Article revision not found: {revision_id}"
        raise ValueError(msg)

    block = await get_block_by_uid(library, revision_id, request.block_uid)
    if block is None:
        msg = f"Block not found: {request.block_uid}"
        raise ValueError(msg)

    vault_path = default_obsidian_vault_path()
    vault_path.mkdir(parents=True, exist_ok=True)
    (vault_path / ".obsidian").mkdir(exist_ok=True)
    note_path = vault_path / f"{safe_filename(library.name)}.md"
    arxiv_metadata = item.manifest.arxiv_metadata if item.manifest else {}
    arxiv_id = item.manifest.arxiv_id if item.manifest else None
    article_title = article_heading(item.family.title, arxiv_metadata)
    translation = await default_translation_for_block(
        library,
        revision_id,
        request.block_uid,
        request.target_language,
    )
    entry = render_block_clip(
        block=block,
        revision_id=revision_id,
        article_title=article_title,
        target_language=request.target_language,
        translation=translation,
        color=request.color,
    )
    created_file = not note_path.exists()
    current = initial_library_note(library.name) if created_file else note_path.read_text("utf-8")
    updated, updated_existing = upsert_article_block(
        current,
        revision_id=revision_id,
        article_title=article_title,
        article_meta=render_article_meta(arxiv_id, revision_id),
        block_uid=request.block_uid,
        entry=entry,
    )
    note_path.write_text(updated, encoding="utf-8")
    return ObsidianClipResult(
        vault_path=str(vault_path),
        note_path=str(note_path),
        article_heading=article_title,
        block_uid=request.block_uid,
        created_file=created_file,
        updated_existing=updated_existing,
    )


async def save_obsidian_term_cards(
    library: Library,
    cards: list[ReaderCard],
) -> ReaderCardObsidianExportResult:
    vault_path = default_obsidian_vault_path()
    vault_path.mkdir(parents=True, exist_ok=True)
    (vault_path / ".obsidian").mkdir(exist_ok=True)
    note_path = vault_path / f"{safe_filename(library.name)}.md"
    created_file = not note_path.exists()
    current = initial_library_note(library.name) if created_file else note_path.read_text("utf-8")
    updated, updated_existing = upsert_term_wiki_cards(current, cards)
    note_path.write_text(updated, encoding="utf-8")
    return ReaderCardObsidianExportResult(
        vault_path=str(vault_path),
        note_path=str(note_path),
        cards_exported=len(cards),
        updated_existing=updated_existing,
    )


def default_obsidian_vault_path() -> Path:
    home = Path.home()
    cloud_storage = home / "Library" / "CloudStorage"
    candidates = sorted(cloud_storage.glob("OneDrive*")) if cloud_storage.exists() else []
    candidates.extend(sorted(home.glob("OneDrive*")))
    root = candidates[0] if candidates else home / "Documents"
    return root / "Obsidian" / OBSIDIAN_VAULT_NAME


async def default_translation_for_block(
    library: Library,
    revision_id: str,
    block_uid: str,
    target_language: str,
) -> str | None:
    active_terms = await active_article_glossary_terms(library, revision_id, target_language)
    selected: TranslationVariant | None = None
    for variant in await list_translation_variants(library, revision_id, target_language):
        if variant.metadata.get("block_uid") != block_uid:
            continue
        if selected is None or variant.is_default:
            selected = variant
        if variant.is_default:
            break
    if selected is None:
        return None
    return apply_glossary_to_markdown(selected.raw_markdown, active_terms)


def upsert_article_block(
    content: str,
    *,
    revision_id: str,
    article_title: str,
    article_meta: str,
    block_uid: str,
    entry: str,
) -> tuple[str, bool]:
    content = strip_legacy_markers(content)
    article_range = find_article_section(content, revision_id)
    if article_range is None:
        article = f"\n\n## {article_title}\n\n{article_meta}\n\n{entry}\n"
        return content.rstrip() + article, False

    article_start, article_end = article_range
    article = content[article_start:article_end]
    anchor = obsidian_block_anchor(revision_id, block_uid)
    if anchor in article:
        block_start, block_end = find_block_entry_range(article, anchor)
        prefix = article[:block_start].rstrip()
        suffix = article[block_end:].lstrip("\n")
        if suffix.strip():
            updated_article = f"{prefix}\n\n{entry.strip()}\n\n{suffix.rstrip()}\n"
        else:
            updated_article = f"{prefix}\n\n{entry.strip()}\n"
        return content[:article_start] + updated_article + content[article_end:], True

    updated_article = article.rstrip() + f"\n\n{entry}\n"
    return content[:article_start] + updated_article + content[article_end:], False


def strip_legacy_markers(content: str) -> str:
    cleaned = re.sub(r"(?m)^<!--\s*/?ilios-(?:article|block):.*?-->\s*\n?", "", content)
    return re.sub(r"\n{3,}", "\n\n", cleaned).strip() + "\n"


def find_article_section(content: str, revision_id: str) -> tuple[int, int] | None:
    metadata = f"- Ilios revision: `{revision_id}`"
    metadata_index = content.find(metadata)
    if metadata_index == -1:
        return None
    heading_start = content.rfind("\n## ", 0, metadata_index)
    if heading_start == -1:
        heading_start = 0 if content.startswith("## ") else -1
    else:
        heading_start += 1
    if heading_start == -1:
        return None
    next_heading = content.find("\n## ", metadata_index + len(metadata))
    return heading_start, len(content) if next_heading == -1 else next_heading + 1


def find_block_entry_range(article: str, anchor: str) -> tuple[int, int]:
    anchor_index = article.find(anchor)
    if anchor_index == -1:
        return len(article), len(article)
    block_start = article.rfind("\n### ", 0, anchor_index)
    if block_start == -1:
        block_start = article.rfind("\n> [!", 0, anchor_index)
    block_start = 0 if block_start == -1 else block_start + 1
    search_from = anchor_index + len(anchor)
    candidates: list[int] = []
    for marker in ("\n### ", "\n## "):
        index = article.find(marker, search_from)
        if index != -1:
            candidates.append(index + 1)
    for marker in ("### ", "## "):
        if article.startswith(marker, search_from):
            candidates.append(search_from)
    block_end = min(candidates) if candidates else len(article)
    return block_start, block_end


def render_block_clip(
    *,
    block: DocumentBlock,
    revision_id: str,
    article_title: str,
    target_language: str,
    translation: str | None,
    color: ObsidianClipColor,
) -> str:
    callout, title, tag = COLOR_META[color]
    lines = [
        f"### {block.block_uid}",
        "",
        f"> [!{callout}] {title} · {block.block_uid}",
        "> **Source**",
        quote_for_obsidian(block.source_markdown),
        ">",
        f"> **Translation ({target_language})**",
        quote_for_obsidian(translation or "_Translation pending._"),
        ">",
        f"> Article: [[#{article_title}]]",
        f"> {tag}",
        obsidian_block_anchor(revision_id, block.block_uid),
    ]
    return "\n".join(lines)


def initial_library_note(library_name: str) -> str:
    return (
        f"# {library_name}\n\n"
        "This note collects paper excerpts saved from Ilios. Each article is kept in its own "
        "section so the same library can grow into one research reading log.\n"
    )


def render_article_meta(arxiv_id: str | None, revision_id: str) -> str:
    parts = [f"- Ilios revision: `{revision_id}`"]
    if arxiv_id:
        parts.append(f"- arXiv: `{arxiv_id}`")
    return "\n".join(parts)


def article_heading(family_title: str | None, arxiv_metadata: dict[str, object]) -> str:
    title = arxiv_metadata.get("title")
    if isinstance(title, str) and title.strip():
        return clean_heading(title)
    if family_title and family_title.strip():
        return clean_heading(family_title)
    return "Untitled paper"


def quote_for_obsidian(markdown: str) -> str:
    return "\n".join(f"> {line}" if line else ">" for line in markdown.strip().splitlines())


def safe_filename(value: str) -> str:
    token = re.sub(r"[\\/:*?\"<>|]+", "-", value.strip())
    token = re.sub(r"\s+", " ", token).strip(" .")
    return token or "Library"


def clean_heading(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def obsidian_block_anchor(revision_id: str, block_uid: str) -> str:
    token = re.sub(r"[^A-Za-z0-9-]+", "-", f"ilios-{revision_id}-{block_uid}")
    return f"^{token.strip('-')}"


def upsert_term_wiki_cards(content: str, cards: list[ReaderCard]) -> tuple[str, bool]:
    content = strip_legacy_markers(content)
    section_start, section_end = find_term_wiki_section(content)
    section = "## 术语 Wiki\n" if section_start is None else content[section_start:section_end]
    updated_existing = False
    for card in sorted(cards, key=lambda item: item.title.casefold()):
        entry = render_term_card_for_obsidian(card)
        anchor = obsidian_card_anchor(card.id)
        if anchor in section:
            entry_start, entry_end = find_term_card_range(section, anchor)
            section = (
                section[:entry_start].rstrip() + f"\n\n{entry}\n" + section[entry_end:].lstrip()
            )
            updated_existing = True
        else:
            section = section.rstrip() + f"\n\n{entry}\n"
    if section_start is None:
        return content.rstrip() + f"\n\n{section.strip()}\n", updated_existing
    return (
        content[:section_start] + section.rstrip() + "\n" + content[section_end:],
        updated_existing,
    )


def find_term_wiki_section(content: str) -> tuple[int, int] | tuple[None, None]:
    marker = "\n## 术语 Wiki"
    start = content.find(marker)
    if start == -1:
        if content.startswith("## 术语 Wiki"):
            start = 0
        else:
            return None, None
    elif start > 0:
        start += 1
    next_heading = content.find("\n## ", start + len("## 术语 Wiki"))
    return start, len(content) if next_heading == -1 else next_heading + 1


def find_term_card_range(section: str, anchor: str) -> tuple[int, int]:
    anchor_index = section.find(anchor)
    if anchor_index == -1:
        return len(section), len(section)
    start = section.rfind("\n### ", 0, anchor_index)
    start = 0 if start == -1 else start + 1
    end = section.find("\n### ", anchor_index + len(anchor))
    return start, len(section) if end == -1 else end + 1


def render_term_card_for_obsidian(card: ReaderCard) -> str:
    lines = [
        f"### {card.title}",
        "",
        card.body_markdown.strip(),
        "",
    ]
    if card.source_type == ReaderCardSourceType.wikipedia and card.source_url:
        lines.append(f"来源：[Wikipedia]({card.source_url})")
    elif card.source_type == ReaderCardSourceType.ai_search:
        lines.append("_AI generated from this paper/search context._")
    else:
        lines.append("_AI generated from this paper context._")
    lines.extend(["", "#ilios/term-wiki", obsidian_card_anchor(card.id)])
    return "\n".join(lines)


def obsidian_card_anchor(card_id: str) -> str:
    token = re.sub(r"[^A-Za-z0-9-]+", "-", f"ilios-card-{card_id}")
    return f"^{token.strip('-')}"
