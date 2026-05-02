from __future__ import annotations

from collections.abc import Awaitable, Callable

from bilin_api.article_store import (
    create_note_patch,
    get_chat_message,
    list_blocks,
    list_chat_messages,
    list_note_patches,
    update_note_patch,
    write_lecture_notes,
)
from bilin_api.llm import LLMResponse, generate_note_patch_markdown
from bilin_api.repositories import (
    create_custom_note_template,
    get_custom_note_template,
    get_provider_api_key,
    get_provider_profile,
    list_custom_note_templates,
    update_custom_note_template,
)
from bilin_api.schemas import (
    ArticleNotePatches,
    ChatMessage,
    ChatToNotePatchRequest,
    DocumentBlock,
    Library,
    NotePatch,
    NotePatchGenerateRequest,
    NotePatchGenerateResult,
    NotePatchUpdate,
    NoteTemplate,
    NoteTemplateCreate,
    NoteTemplateUpdate,
    ProviderProfile,
)

NoteGenerator = Callable[
    [ProviderProfile, str, str, str, str, str, str],
    Awaitable[LLMResponse],
]

NOTE_TEMPLATES: dict[str, NoteTemplate] = {
    "deep_reading": NoteTemplate(
        id="deep_reading",
        name="精读模板",
        description=(
            "Cover background, motivation, assumptions, method, key equations, evidence, "
            "limitations, and follow-up questions."
        ),
    ),
    "group_meeting": NoteTemplate(
        id="group_meeting",
        name="组会模板",
        description=(
            "Prepare a discussion-oriented note with problem framing, main contribution, "
            "slides-worthy figures or equations, critique, and questions for the group."
        ),
    ),
    "quick_skim": NoteTemplate(
        id="quick_skim",
        name="快速扫读模板",
        description=(
            "Extract the minimum useful reading note: problem, approach, result shape, "
            "why it may matter, and whether to read deeply."
        ),
    ),
    "reproduction": NoteTemplate(
        id="reproduction",
        name="复现导向模板",
        description=(
            "Focus on implementation assumptions, data or benchmark setup, algorithm steps, "
            "hyperparameters, missing details, and reproduction risks."
        ),
    ),
}


async def list_note_templates() -> list[NoteTemplate]:
    return [*NOTE_TEMPLATES.values(), *(await list_custom_note_templates())]


async def get_note_template(template_id: str) -> NoteTemplate | None:
    template = NOTE_TEMPLATES.get(template_id)
    if template is not None:
        return template
    return await get_custom_note_template(template_id)


async def create_user_note_template(payload: NoteTemplateCreate) -> NoteTemplate:
    return await create_custom_note_template(payload)


async def update_user_note_template(
    template_id: str,
    payload: NoteTemplateUpdate,
) -> NoteTemplate | None:
    if template_id in NOTE_TEMPLATES:
        return None
    return await update_custom_note_template(template_id, payload)


async def get_article_note_patches(library: Library, revision_id: str) -> ArticleNotePatches:
    return ArticleNotePatches(
        article_revision_id=revision_id,
        patches=await list_note_patches(library, revision_id),
    )


async def generate_article_note_patch(
    library: Library,
    revision_id: str,
    request: NotePatchGenerateRequest,
    generator: NoteGenerator | None = None,
) -> NotePatchGenerateResult:
    template = await get_note_template(request.template_id)
    if template is None:
        msg = f"Unknown note template: {request.template_id}"
        raise ValueError(msg)
    provider = await get_provider_profile(request.provider_profile_id)
    if provider is None:
        msg = f"Provider profile not found: {request.provider_profile_id}"
        raise ValueError(msg)
    model = request.model or provider.default_model
    if not model:
        msg = "Note generation requires a model or provider default_model."
        raise ValueError(msg)
    api_key = await get_provider_api_key(provider)
    if not api_key:
        msg = f"Provider profile has no API key: {provider.id}"
        raise ValueError(msg)

    blocks = await list_blocks(library, revision_id)
    evidence_blocks = select_note_evidence_blocks(blocks, request.max_blocks)
    if not evidence_blocks:
        msg = "No article blocks were available for note generation."
        raise ValueError(msg)
    chat_messages = (
        await list_chat_messages(library, revision_id) if request.include_chat_history else []
    )
    active_generator = generator or generate_note_patch_markdown
    response = await active_generator(
        provider,
        api_key,
        model,
        template.name,
        template.description,
        evidence_to_markdown(evidence_blocks),
        chat_to_markdown(chat_messages),
    )
    source_refs = sorted(
        {
            block.block_uid
            for block in evidence_blocks
            if block.block_type in {"section", "paragraph", "equation", "figure", "table"}
        }
        | {ref for message in chat_messages for ref in message.source_refs}
    )
    patch = await create_note_patch(
        library=library,
        revision_id=revision_id,
        title=template.name,
        patch_markdown=response.text,
        source_refs=source_refs,
        metadata={
            "template_id": template.id,
            "template_name": template.name,
            "provider_profile_id": provider.id,
            "model": model,
            "usage": response.usage,
            "include_chat_history": request.include_chat_history,
        },
    )
    return NotePatchGenerateResult(
        article_revision_id=revision_id,
        patch=patch,
        template=template,
    )


async def update_article_note_patch(
    library: Library,
    patch_id: str,
    payload: NotePatchUpdate,
) -> NotePatch | None:
    patch = await update_note_patch(
        library,
        patch_id,
        title=payload.title,
        patch_markdown=payload.patch_markdown,
        status=payload.status,
        metadata=payload.metadata,
    )
    if patch is not None and patch.status == "accepted":
        notes_path = await write_lecture_notes(library, patch.article_revision_id)
        patch = await update_note_patch(library, patch.id, metadata={"notes_path": str(notes_path)})
    return patch


async def create_note_patch_from_chat_message(
    library: Library,
    revision_id: str,
    message_id: str,
    request: ChatToNotePatchRequest,
) -> NotePatch | None:
    message = await get_chat_message(library, revision_id, message_id)
    if message is None or message.role != "assistant":
        return None
    title = request.title or note_patch_title_from_message(message)
    patch_markdown = chat_message_to_note_markdown(message, title)
    return await create_note_patch(
        library=library,
        revision_id=revision_id,
        title=title,
        patch_markdown=patch_markdown,
        source_refs=message.source_refs,
        metadata={
            "source": "chat_message",
            "chat_message_id": message.id,
            "current_block_uid": message.metadata.get("current_block_uid"),
            "external_refs": [ref.model_dump(mode="json") for ref in message.external_refs],
        },
    )


async def accept_article_note_patch(library: Library, patch_id: str) -> NotePatch | None:
    patch = await update_note_patch(library, patch_id, status="accepted")
    if patch is None:
        return None
    notes_path = await write_lecture_notes(library, patch.article_revision_id)
    return await update_note_patch(library, patch.id, metadata={"notes_path": str(notes_path)})


async def reject_article_note_patch(library: Library, patch_id: str) -> NotePatch | None:
    return await update_note_patch(library, patch_id, status="rejected")


def select_note_evidence_blocks(
    blocks: list[DocumentBlock],
    max_blocks: int,
) -> list[DocumentBlock]:
    preferred = [
        block
        for block in blocks
        if block.block_type in {"section", "paragraph", "equation", "figure", "table"}
        and block.source_markdown.strip()
    ]
    return preferred[:max_blocks]


def evidence_to_markdown(blocks: list[DocumentBlock]) -> str:
    return "\n\n".join(
        (f"[{block.block_uid}] {block.block_type} {block.structural_path}\n{block.source_markdown}")
        for block in blocks
    )


def chat_to_markdown(messages: list[ChatMessage]) -> str:
    lines: list[str] = []
    for message in messages[-12:]:
        refs = ", ".join(f"[{ref}]" for ref in message.source_refs)
        suffix = f" refs: {refs}" if refs else ""
        lines.append(f"{message.role}: {message.content}{suffix}")
    return "\n".join(lines)


def note_patch_title_from_message(message: ChatMessage) -> str:
    first_line = message.content.strip().splitlines()[0] if message.content.strip() else "Chat note"
    return first_line[:80]


def chat_message_to_note_markdown(message: ChatMessage, title: str) -> str:
    lines = [f"## {title}", "", message.content.strip()]
    if message.source_refs:
        refs = ", ".join(f"[{ref}]" for ref in message.source_refs)
        lines.extend(["", f"Current-paper evidence: {refs}"])
    if message.external_refs:
        lines.extend(["", "External evidence:"])
        for ref in message.external_refs:
            label = ref.title or ref.url or ref.doi or ref.arxiv_id or "external citation"
            suffix = f" ({ref.url})" if ref.url else ""
            lines.append(f"- {label}{suffix}")
    return "\n".join(lines).strip() + "\n"
