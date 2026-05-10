from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import FileResponse, PlainTextResponse, StreamingResponse

from bilin_api.article_store import (
    archive_article_revision,
    delete_article_revision,
    get_article_item,
    get_article_reading_progress,
    get_article_revision,
    list_article_items,
    read_article_document,
    resolve_library,
    update_article_reading_progress,
)
from bilin_api.citation_service import (
    get_article_citations,
    lookup_citation_scholar,
    queue_citation_library_import,
)
from bilin_api.embedding_service import (
    build_article_embeddings,
    get_article_embedding_status,
    queue_article_embedding,
)
from bilin_api.export_service import export_article, queue_article_export
from bilin_api.glossary_service import (
    create_article_glossary_term,
    extract_article_glossary_candidates,
    get_article_glossary,
    update_article_glossary_term,
)
from bilin_api.note_service import (
    accept_article_note_patch,
    create_note_patch_from_chat_message,
    create_user_note_template,
    generate_article_note_patch,
    get_article_note_patches,
    list_note_templates,
    reject_article_note_patch,
    update_article_note_patch,
    update_user_note_template,
)
from bilin_api.obsidian_service import save_obsidian_clip
from bilin_api.qa_service import (
    ask_article_question,
    get_article_chat_history,
    prepare_question_context,
    stream_question_answer_events,
)
from bilin_api.reader_card_service import (
    archive_article_reader_card,
    create_manual_reader_card,
    export_reader_cards_to_obsidian,
    extract_article_reader_cards,
    generate_article_reader_card,
    get_article_reader_cards,
    queue_reader_card_extraction,
    queue_reader_card_generation,
    update_article_reader_card,
)
from bilin_api.schemas import (
    ArticleChatHistory,
    ArticleCitations,
    ArticleDeleteResult,
    ArticleDocument,
    ArticleEmbeddingStatus,
    ArticleExportRequest,
    ArticleExportResult,
    ArticleGlossary,
    ArticleListItem,
    ArticleNotePatches,
    ArticleReadingProgress,
    ArticleTranslations,
    ChatAskRequest,
    ChatAskResult,
    ChatToNotePatchRequest,
    CitationLibraryImportRequest,
    CitationLibraryImportResult,
    CitationScholarResult,
    EmbedArticleRequest,
    EmbedArticleResult,
    GlossaryExtractionRequest,
    GlossaryExtractionResult,
    GlossaryTerm,
    GlossaryTermCreate,
    GlossaryTermUpdate,
    Job,
    NotePatch,
    NotePatchGenerateRequest,
    NotePatchGenerateResult,
    NotePatchUpdate,
    NoteTemplate,
    NoteTemplateCreate,
    NoteTemplateUpdate,
    ObsidianClipRequest,
    ObsidianClipResult,
    ReaderCard,
    ReaderCardCreate,
    ReaderCardExtractionRequest,
    ReaderCardExtractionResult,
    ReaderCardGenerationRequest,
    ReaderCardGenerationResult,
    ReaderCardObsidianExportRequest,
    ReaderCardObsidianExportResult,
    ReaderCards,
    ReaderCardUpdate,
    ReadingProgressUpdate,
    TranslationBatchRequest,
    TranslationBatchResult,
    TranslationMemoryLookupResult,
    TranslationVariant,
)
from bilin_api.translation_service import (
    get_article_translations,
    lookup_article_translation_memory,
    queue_article_translation,
    select_article_translation_variant,
)

router = APIRouter(prefix="/libraries/{library_id}/articles", tags=["articles"])

_EXPORT_MEDIA_TYPES = {
    ".md": "text/markdown; charset=utf-8",
    ".zip": "application/zip",
}


@router.get("", response_model=list[ArticleListItem])
async def list_articles(
    library_id: str,
    target_language: str = Query(default="zh-CN", min_length=2, max_length=40),
) -> list[ArticleListItem]:
    library = await _library_or_404(library_id)
    return await list_article_items(library, target_language)


@router.get("/{revision_id}", response_model=ArticleListItem)
async def get_article(
    library_id: str,
    revision_id: str,
    target_language: str = Query(default="zh-CN", min_length=2, max_length=40),
) -> ArticleListItem:
    library = await _library_or_404(library_id)
    item = await get_article_item(library, revision_id, target_language)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    return item


@router.post("/{revision_id}/archive", response_model=ArticleListItem)
async def archive_article(library_id: str, revision_id: str) -> ArticleListItem:
    library = await _library_or_404(library_id)
    item = await archive_article_revision(library, revision_id)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    return item


@router.delete("/{revision_id}", response_model=ArticleDeleteResult)
async def delete_article(library_id: str, revision_id: str) -> ArticleDeleteResult:
    library = await _library_or_404(library_id)
    result = await delete_article_revision(library, revision_id)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    return result


@router.get("/{revision_id}/document", response_model=ArticleDocument)
async def get_article_document(library_id: str, revision_id: str) -> ArticleDocument:
    library = await _library_or_404(library_id)
    document = await read_article_document(library, revision_id)
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    return document


@router.get("/{revision_id}/reading-progress", response_model=ArticleReadingProgress)
async def get_reading_progress(library_id: str, revision_id: str) -> ArticleReadingProgress:
    library = await _library_or_404(library_id)
    progress = await get_article_reading_progress(library, revision_id)
    if progress is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    return progress


@router.put("/{revision_id}/reading-progress", response_model=ArticleReadingProgress)
async def put_reading_progress(
    library_id: str,
    revision_id: str,
    payload: ReadingProgressUpdate,
) -> ArticleReadingProgress:
    library = await _library_or_404(library_id)
    try:
        progress = await update_article_reading_progress(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    if progress is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    return progress


@router.get("/{revision_id}/citations", response_model=ArticleCitations)
async def get_citations(library_id: str, revision_id: str) -> ArticleCitations:
    library = await _library_or_404(library_id)
    try:
        return await get_article_citations(library, revision_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.get("/{revision_id}/citations/{citation_id}/scholar", response_model=CitationScholarResult)
async def get_citation_scholar(
    library_id: str,
    revision_id: str,
    citation_id: str,
) -> CitationScholarResult:
    library = await _library_or_404(library_id)
    try:
        return await lookup_citation_scholar(library, revision_id, citation_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post(
    "/{revision_id}/citations/{citation_id}/import-arxiv",
    response_model=CitationLibraryImportResult,
    status_code=status.HTTP_201_CREATED,
)
async def post_citation_arxiv_import(
    library_id: str,
    revision_id: str,
    citation_id: str,
    payload: CitationLibraryImportRequest,
) -> CitationLibraryImportResult:
    library = await _library_or_404(library_id)
    try:
        return await queue_citation_library_import(library, revision_id, citation_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{revision_id}/translations", response_model=ArticleTranslations)
async def get_translations(
    library_id: str,
    revision_id: str,
    target_language: str = "zh-CN",
) -> ArticleTranslations:
    library = await _library_or_404(library_id)
    return await get_article_translations(library, revision_id, target_language)


@router.post("/{revision_id}/translations", response_model=TranslationBatchResult)
async def post_translation_batch(
    library_id: str,
    revision_id: str,
    payload: TranslationBatchRequest,
) -> TranslationBatchResult:
    library = await _library_or_404(library_id)
    try:
        return await queue_article_translation(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{revision_id}/translations/{variant_id}/select", response_model=TranslationVariant)
async def post_translation_variant_select(
    library_id: str,
    revision_id: str,
    variant_id: str,
) -> TranslationVariant:
    library = await _library_or_404(library_id)
    variant = await select_article_translation_variant(library, revision_id, variant_id)
    if variant is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Translation variant not found",
        )
    return variant


@router.post("/{revision_id}/blocks/{block_uid}/translate", response_model=TranslationBatchResult)
async def post_block_translation(
    library_id: str,
    revision_id: str,
    block_uid: str,
    payload: TranslationBatchRequest,
) -> TranslationBatchResult:
    library = await _library_or_404(library_id)
    scoped_payload = payload.model_copy(update={"block_uids": [block_uid], "force": True})
    try:
        return await queue_article_translation(library, revision_id, scoped_payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get(
    "/{revision_id}/blocks/{block_uid}/translation-memory",
    response_model=TranslationMemoryLookupResult,
)
async def get_block_translation_memory(
    library_id: str,
    revision_id: str,
    block_uid: str,
    target_language: str = "zh-CN",
    glossary_version: str | None = None,
) -> TranslationMemoryLookupResult:
    library = await _library_or_404(library_id)
    try:
        return await lookup_article_translation_memory(
            library,
            revision_id,
            block_uid,
            target_language,
            glossary_version,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.get("/{revision_id}/glossary", response_model=ArticleGlossary)
async def get_glossary(
    library_id: str,
    revision_id: str,
    target_language: str = "zh-CN",
) -> ArticleGlossary:
    library = await _library_or_404(library_id)
    return await get_article_glossary(library, revision_id, target_language)


@router.post("/{revision_id}/glossary/extract", response_model=GlossaryExtractionResult)
async def post_glossary_extraction(
    library_id: str,
    revision_id: str,
    payload: GlossaryExtractionRequest,
) -> GlossaryExtractionResult:
    library = await _library_or_404(library_id)
    return await extract_article_glossary_candidates(library, revision_id, payload)


@router.post("/{revision_id}/glossary", response_model=GlossaryTerm)
async def post_glossary_term(
    library_id: str,
    revision_id: str,
    payload: GlossaryTermCreate,
) -> GlossaryTerm:
    library = await _library_or_404(library_id)
    return await create_article_glossary_term(library, revision_id, payload)


@router.put("/{revision_id}/glossary/{term_id}", response_model=GlossaryTerm)
async def put_glossary_term(
    library_id: str,
    revision_id: str,
    term_id: str,
    payload: GlossaryTermUpdate,
) -> GlossaryTerm:
    library = await _library_or_404(library_id)
    term = await update_article_glossary_term(library, revision_id, term_id, payload)
    if term is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Glossary term not found")
    return term


@router.get("/{revision_id}/cards", response_model=ReaderCards)
async def get_reader_cards(
    library_id: str,
    revision_id: str,
    target_language: str = "zh-CN",
) -> ReaderCards:
    library = await _library_or_404(library_id)
    return await get_article_reader_cards(library, revision_id, target_language)


@router.post("/{revision_id}/cards", response_model=ReaderCard, status_code=status.HTTP_201_CREATED)
async def post_reader_card(
    library_id: str,
    revision_id: str,
    payload: ReaderCardCreate,
) -> ReaderCard:
    library = await _library_or_404(library_id)
    try:
        return await create_manual_reader_card(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.put("/{revision_id}/cards/{card_id}", response_model=ReaderCard)
async def put_reader_card(
    library_id: str,
    revision_id: str,
    card_id: str,
    payload: ReaderCardUpdate,
) -> ReaderCard:
    library = await _library_or_404(library_id)
    card = await update_article_reader_card(library, revision_id, card_id, payload)
    if card is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reader card not found")
    return card


@router.delete("/{revision_id}/cards/{card_id}", response_model=ReaderCard)
async def delete_reader_card(
    library_id: str,
    revision_id: str,
    card_id: str,
) -> ReaderCard:
    library = await _library_or_404(library_id)
    card = await archive_article_reader_card(library, revision_id, card_id)
    if card is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reader card not found")
    return card


@router.post("/{revision_id}/cards/extract", response_model=ReaderCardExtractionResult)
async def post_reader_card_extraction(
    library_id: str,
    revision_id: str,
    payload: ReaderCardExtractionRequest,
) -> ReaderCardExtractionResult:
    library = await _library_or_404(library_id)
    try:
        return await extract_article_reader_cards(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post(
    "/{revision_id}/cards/extract/jobs",
    response_model=Job,
    status_code=status.HTTP_201_CREATED,
)
async def post_reader_card_extraction_job(
    library_id: str,
    revision_id: str,
    payload: ReaderCardExtractionRequest,
) -> Job:
    library = await _library_or_404(library_id)
    return await queue_reader_card_extraction(library, revision_id, payload)


@router.post("/{revision_id}/cards/generate", response_model=ReaderCardGenerationResult)
async def post_reader_card_generation(
    library_id: str,
    revision_id: str,
    payload: ReaderCardGenerationRequest,
) -> ReaderCardGenerationResult:
    library = await _library_or_404(library_id)
    try:
        return await generate_article_reader_card(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post(
    "/{revision_id}/cards/generate/jobs",
    response_model=Job,
    status_code=status.HTTP_201_CREATED,
)
async def post_reader_card_generation_job(
    library_id: str,
    revision_id: str,
    payload: ReaderCardGenerationRequest,
) -> Job:
    library = await _library_or_404(library_id)
    return await queue_reader_card_generation(library, revision_id, payload)


@router.post(
    "/{revision_id}/cards/export/obsidian",
    response_model=ReaderCardObsidianExportResult,
)
async def post_reader_card_obsidian_export(
    library_id: str,
    revision_id: str,
    payload: ReaderCardObsidianExportRequest,
) -> ReaderCardObsidianExportResult:
    library = await _library_or_404(library_id)
    try:
        return await export_reader_cards_to_obsidian(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{revision_id}/chat", response_model=ArticleChatHistory)
async def get_chat_history(library_id: str, revision_id: str) -> ArticleChatHistory:
    library = await _library_or_404(library_id)
    return await get_article_chat_history(library, revision_id)


@router.post("/{revision_id}/chat/ask", response_model=ChatAskResult)
async def post_chat_question(
    library_id: str,
    revision_id: str,
    payload: ChatAskRequest,
) -> ChatAskResult:
    library = await _library_or_404(library_id)
    try:
        return await ask_article_question(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{revision_id}/chat/ask-stream")
async def post_chat_question_stream(
    library_id: str,
    revision_id: str,
    payload: ChatAskRequest,
) -> StreamingResponse:
    library = await _library_or_404(library_id)
    try:
        context = await prepare_question_context(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return StreamingResponse(
        stream_question_answer_events(library, revision_id, payload, context),
        media_type="text/event-stream",
    )


@router.post("/{revision_id}/chat/{message_id}/note-patch", response_model=NotePatch)
async def post_chat_note_patch(
    library_id: str,
    revision_id: str,
    message_id: str,
    payload: ChatToNotePatchRequest,
) -> NotePatch:
    library = await _library_or_404(library_id)
    patch = await create_note_patch_from_chat_message(library, revision_id, message_id, payload)
    if patch is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Assistant chat message not found",
        )
    return patch


@router.get("/{revision_id}/embeddings/status", response_model=ArticleEmbeddingStatus)
async def get_embedding_status(
    library_id: str,
    revision_id: str,
    provider: str = "local-hash",
    model: str = "hashing-64-v1",
) -> ArticleEmbeddingStatus:
    library = await _library_or_404(library_id)
    return await get_article_embedding_status(
        library,
        revision_id,
        EmbedArticleRequest(provider=provider, model=model),
    )


@router.post("/{revision_id}/embeddings", response_model=EmbedArticleResult)
async def post_article_embeddings(
    library_id: str,
    revision_id: str,
    payload: EmbedArticleRequest,
) -> EmbedArticleResult:
    library = await _library_or_404(library_id)
    return await build_article_embeddings(library, revision_id, payload)


@router.post(
    "/{revision_id}/embeddings/jobs",
    response_model=Job,
    status_code=status.HTTP_201_CREATED,
)
async def post_article_embedding_job(
    library_id: str,
    revision_id: str,
    payload: EmbedArticleRequest,
) -> Job:
    library = await _library_or_404(library_id)
    return await queue_article_embedding(library, revision_id, payload)


@router.get("/{revision_id}/notes/templates", response_model=list[NoteTemplate])
async def get_note_templates(library_id: str, revision_id: str) -> list[NoteTemplate]:
    await _library_or_404(library_id)
    _ = revision_id
    return await list_note_templates()


@router.post("/{revision_id}/notes/templates", response_model=NoteTemplate)
async def post_note_template(
    library_id: str,
    revision_id: str,
    payload: NoteTemplateCreate,
) -> NoteTemplate:
    await _library_or_404(library_id)
    _ = revision_id
    return await create_user_note_template(payload)


@router.put("/{revision_id}/notes/templates/{template_id}", response_model=NoteTemplate)
async def put_note_template(
    library_id: str,
    revision_id: str,
    template_id: str,
    payload: NoteTemplateUpdate,
) -> NoteTemplate:
    await _library_or_404(library_id)
    _ = revision_id
    template = await update_user_note_template(template_id, payload)
    if template is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note template not found")
    return template


@router.get("/{revision_id}/notes/patches", response_model=ArticleNotePatches)
async def get_note_patches(library_id: str, revision_id: str) -> ArticleNotePatches:
    library = await _library_or_404(library_id)
    return await get_article_note_patches(library, revision_id)


@router.post("/{revision_id}/notes/generate", response_model=NotePatchGenerateResult)
async def post_note_generation(
    library_id: str,
    revision_id: str,
    payload: NotePatchGenerateRequest,
) -> NotePatchGenerateResult:
    library = await _library_or_404(library_id)
    try:
        return await generate_article_note_patch(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.put("/{revision_id}/notes/patches/{patch_id}", response_model=NotePatch)
async def put_note_patch(
    library_id: str,
    revision_id: str,
    patch_id: str,
    payload: NotePatchUpdate,
) -> NotePatch:
    library = await _library_or_404(library_id)
    patch = await update_article_note_patch(library, patch_id, payload)
    if patch is None or patch.article_revision_id != revision_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note patch not found")
    return patch


@router.post("/{revision_id}/notes/patches/{patch_id}/accept", response_model=NotePatch)
async def post_note_patch_accept(
    library_id: str,
    revision_id: str,
    patch_id: str,
) -> NotePatch:
    library = await _library_or_404(library_id)
    patch = await accept_article_note_patch(library, patch_id)
    if patch is None or patch.article_revision_id != revision_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note patch not found")
    return patch


@router.post("/{revision_id}/notes/patches/{patch_id}/reject", response_model=NotePatch)
async def post_note_patch_reject(
    library_id: str,
    revision_id: str,
    patch_id: str,
) -> NotePatch:
    library = await _library_or_404(library_id)
    patch = await reject_article_note_patch(library, patch_id)
    if patch is None or patch.article_revision_id != revision_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note patch not found")
    return patch


@router.post("/{revision_id}/exports", response_model=ArticleExportResult)
async def post_article_export(
    library_id: str,
    revision_id: str,
    payload: ArticleExportRequest,
) -> ArticleExportResult:
    library = await _library_or_404(library_id)
    try:
        return await export_article(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{revision_id}/exports/jobs", response_model=Job, status_code=status.HTTP_201_CREATED)
async def post_article_export_job(
    library_id: str,
    revision_id: str,
    payload: ArticleExportRequest,
) -> Job:
    library = await _library_or_404(library_id)
    try:
        return await queue_article_export(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{revision_id}/obsidian/clips", response_model=ObsidianClipResult)
async def post_obsidian_clip(
    library_id: str,
    revision_id: str,
    payload: ObsidianClipRequest,
) -> ObsidianClipResult:
    library = await _library_or_404(library_id)
    try:
        return await save_obsidian_clip(library, revision_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{revision_id}/exports/{file_name}")
async def get_article_export(
    library_id: str,
    revision_id: str,
    file_name: str,
) -> FileResponse:
    library = await _library_or_404(library_id)
    revision = await get_article_revision(library, revision_id)
    if revision is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    if Path(file_name).name != file_name:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid export name")
    path = Path(revision.bundle_path) / "export" / file_name
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Export not found")
    return FileResponse(
        path,
        media_type=_EXPORT_MEDIA_TYPES.get(path.suffix.lower(), "application/octet-stream"),
        filename=file_name,
    )


@router.get("/{revision_id}/source-md", response_class=PlainTextResponse)
async def get_source_markdown(library_id: str, revision_id: str) -> str:
    library = await _library_or_404(library_id)
    item = await get_article_item(library, revision_id)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    path = Path(item.article_revision.bundle_path) / "document" / "source.md"
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="source.md not found")
    return path.read_text(encoding="utf-8")


@router.get("/{revision_id}/assets/{asset_id}")
async def get_asset(library_id: str, revision_id: str, asset_id: str) -> FileResponse:
    library = await _library_or_404(library_id)
    document = await read_article_document(library, revision_id)
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    asset = next((item for item in document.assets if item.asset_id == asset_id), None)
    if asset is None or not asset.web_path:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")
    path = Path(asset.web_path)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset file not found")
    _ensure_asset_path(path, Path(document.article_revision.bundle_path))
    return FileResponse(path)


@router.get("/{revision_id}/assets/{asset_id}/files/{file_index}")
async def get_asset_file(
    library_id: str,
    revision_id: str,
    asset_id: str,
    file_index: int,
) -> FileResponse:
    library = await _library_or_404(library_id)
    document = await read_article_document(library, revision_id)
    if document is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    asset = next((item for item in document.assets if item.asset_id == asset_id), None)
    if asset is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")
    asset_files = asset.metadata.get("asset_files")
    if not isinstance(asset_files, list):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset file not found")
    file_record = next(
        (
            item
            for item in asset_files
            if isinstance(item, dict) and item.get("index") == file_index
        ),
        None,
    )
    if not file_record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset file not found")
    web_path = file_record.get("web_path")
    if not isinstance(web_path, str):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset file not found")
    path = Path(web_path)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset file not found")
    _ensure_asset_path(path, Path(document.article_revision.bundle_path))
    return FileResponse(path)


async def _library_or_404(library_id: str):
    try:
        return await resolve_library(library_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


def _ensure_asset_path(path: Path, bundle_path: Path) -> None:
    resolved_path = path.resolve()
    resolved_assets_dir = (bundle_path / "assets").resolve()
    if not resolved_path.is_relative_to(resolved_assets_dir):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset file not found")
