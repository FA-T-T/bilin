from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from bilin_api.branding import PRODUCT_NAME_EN

JsonDict = dict[str, Any]


class Health(BaseModel):
    status: str = "ok"
    app: str = PRODUCT_NAME_EN
    version: str


class DoctorCapabilityStatus(StrEnum):
    available = "available"
    missing = "missing"


class DoctorCapabilityLevel(StrEnum):
    required = "required"
    recommended = "recommended"
    optional = "optional"


class DoctorCapability(BaseModel):
    tool_name: str
    status: DoctorCapabilityStatus
    detected_version: str | None = None
    path: str | None = None
    level: DoctorCapabilityLevel
    message: str


class DoctorReport(BaseModel):
    bilin_home: str = Field(title="App Home")
    capabilities: list[DoctorCapability]


class LibraryStatus(StrEnum):
    active = "active"
    missing = "missing"
    archived = "archived"


class LibraryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    path: str = Field(min_length=1)


class LibraryUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class Library(BaseModel):
    id: str
    name: str
    path: str
    status: LibraryStatus
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class LibraryDeleteResult(BaseModel):
    library_id: str
    path: str
    deleted_cache: bool


class ProviderProtocol(StrEnum):
    openai_compatible = "openai-compatible"
    anthropic_compatible = "anthropic-compatible"


class ProviderPreset(BaseModel):
    id: str
    name: str
    protocol: ProviderProtocol
    base_url: str
    default_max_concurrent_requests: int = Field(default=1, ge=1, le=32)
    default_requests_per_minute: int | None = Field(default=None, ge=1, le=6000)
    metadata: JsonDict = Field(default_factory=dict)


class ProviderProfile(BaseModel):
    id: str
    name: str
    protocol: ProviderProtocol
    base_url: str | None = None
    key_ref: str | None = None
    default_model: str | None = None
    max_concurrent_requests: int = Field(default=1, ge=1, le=32)
    requests_per_minute: int | None = Field(default=None, ge=1, le=6000)
    capabilities: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class ProviderProfileCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    protocol: ProviderProtocol = ProviderProtocol.openai_compatible
    base_url: str | None = None
    api_key: str | None = None
    default_model: str | None = None
    max_concurrent_requests: int = Field(default=1, ge=1, le=32)
    requests_per_minute: int | None = Field(default=None, ge=1, le=6000)
    capabilities: JsonDict = Field(default_factory=dict)


class ProviderProfileUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    protocol: ProviderProtocol | None = None
    base_url: str | None = None
    api_key: str | None = None
    default_model: str | None = None
    max_concurrent_requests: int | None = Field(default=None, ge=1, le=32)
    requests_per_minute: int | None = Field(default=None, ge=1, le=6000)
    capabilities: JsonDict | None = None


class ProviderModelInfo(BaseModel):
    id: str
    display_name: str | None = None
    owned_by: str | None = None
    created_at: str | None = None
    capabilities: JsonDict = Field(default_factory=dict)
    metadata: JsonDict = Field(default_factory=dict)


class ProviderModelDiscoveryRequest(BaseModel):
    protocol: ProviderProtocol = ProviderProtocol.openai_compatible
    api_key: str = Field(min_length=1)
    base_url: str | None = None


class ProviderModelDiscoveryResult(BaseModel):
    protocol: ProviderProtocol
    base_url: str
    models: list[ProviderModelInfo] = Field(default_factory=list)
    default_model: str | None = None
    capabilities: JsonDict = Field(default_factory=dict)


class JobStatus(StrEnum):
    queued = "queued"
    running = "running"
    paused = "paused"
    succeeded = "succeeded"
    failed = "failed"
    cancelled = "cancelled"


class JobType(StrEnum):
    import_arxiv = "import_arxiv"
    parse_article = "parse_article"
    translate_block = "translate_block"
    embed_article = "embed_article"
    export_article = "export_article"
    extract_reader_cards = "extract_reader_cards"
    generate_reader_card = "generate_reader_card"


class RetrievalMode(StrEnum):
    auto = "auto"
    fts = "fts"
    hybrid = "hybrid"


class ImportLocalKind(StrEnum):
    tex_archive = "tex_archive"
    markdown = "markdown"
    pdf = "pdf"


class Job(BaseModel):
    id: str
    type: JobType
    status: JobStatus
    priority: int = 0
    payload: JsonDict = Field(default_factory=dict)
    result: JsonDict | None = None
    error: JsonDict | None = None
    progress: float = Field(default=0.0, ge=0.0, le=1.0)
    attempts: int = 0
    created_at: datetime
    updated_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    lease_owner: str | None = None


class JobClearResult(BaseModel):
    cleared: int


class JobSummary(BaseModel):
    total: int = 0
    queued: int = 0
    running: int = 0
    paused: int = 0
    succeeded: int = 0
    failed: int = 0
    cancelled: int = 0
    active: int = 0
    updated_at: datetime | None = None


class ArticleFamily(BaseModel):
    id: str
    source: str
    external_id: str
    title: str | None = None
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class ArticleRevision(BaseModel):
    id: str
    family_id: str
    version: str
    bundle_path: str
    status: str
    manifest_version: int = 1
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class AssetRecord(BaseModel):
    id: str
    article_revision_id: str
    asset_id: str
    kind: str
    source_path: str | None = None
    web_path: str | None = None
    caption: str | None = None
    label: str | None = None
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class ArticleTranslationState(StrEnum):
    not_required = "not_required"
    not_started = "not_started"
    translating = "translating"
    partial = "partial"
    translated = "translated"
    failed = "failed"


class ArticleTranslationStatus(BaseModel):
    target_language: str = "zh-CN"
    status: ArticleTranslationState = ArticleTranslationState.not_started
    translatable_blocks: int = 0
    translated_blocks: int = 0
    queued_jobs: int = 0
    running_jobs: int = 0
    paused_jobs: int = 0
    failed_jobs: int = 0


class ArticleReadingProgress(BaseModel):
    article_revision_id: str
    active_block_uid: str | None = None
    active_segment_index: int | None = Field(default=None, ge=0)
    segment_count: int = Field(default=0, ge=0)
    segments: list[int] = Field(default_factory=list)
    total_seconds: int = Field(default=0, ge=0)
    updated_at: datetime | None = None


class ReadingProgressUpdate(BaseModel):
    active_block_uid: str | None = Field(default=None, max_length=120)
    block_seconds: dict[str, int] = Field(default_factory=dict)


class DocumentBlock(BaseModel):
    id: str
    article_revision_id: str
    block_uid: str
    structural_path: str
    block_type: str
    parent_uid: str | None = None
    content_hash: str
    context_hash: str | None = None
    source_markdown: str
    source_latex: str | None = None
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class TranslationVariant(BaseModel):
    id: str
    block_id: str
    target_language: str
    provider_profile_id: str | None = None
    model: str | None = None
    raw_markdown: str
    render_ast: JsonDict | None = None
    validation_status: str = "unchecked"
    glossary_version: str | None = None
    is_default: bool = False
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class TranslationBatchRequest(BaseModel):
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    provider_profile_id: str = Field(min_length=1)
    model: str | None = None
    glossary_version: str | None = None
    force: bool = False
    block_uids: list[str] | None = None
    custom_prompt: str | None = None


class TranslationBatchResult(BaseModel):
    library_id: str
    article_revision_id: str
    target_language: str
    jobs_created: int
    existing_jobs: int = 0
    cached_blocks: int
    skipped_blocks: int
    job_ids: list[str] = Field(default_factory=list)


class LibraryTranslationBatchResult(BaseModel):
    library_id: str
    target_language: str
    articles_considered: int = 0
    articles_queued: int = 0
    jobs_created: int = 0
    existing_jobs: int = 0
    cached_blocks: int = 0
    skipped_blocks: int = 0
    job_ids: list[str] = Field(default_factory=list)
    article_results: list[TranslationBatchResult] = Field(default_factory=list)


class ArticleTranslations(BaseModel):
    article_revision_id: str
    target_language: str
    variants: list[TranslationVariant] = Field(default_factory=list)


class TranslationMemoryReviewStatus(StrEnum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class TranslationMemoryEntry(BaseModel):
    id: str
    source_hash: str
    source_markdown: str
    target_language: str
    raw_markdown: str
    provider_profile_id: str | None = None
    model: str | None = None
    validation_status: str = "ok"
    review_status: TranslationMemoryReviewStatus = TranslationMemoryReviewStatus.pending
    reuse_enabled: bool = False
    glossary_version: str | None = None
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class TranslationMemoryListResult(BaseModel):
    entries: list[TranslationMemoryEntry] = Field(default_factory=list)


class TranslationMemoryEntryUpdate(BaseModel):
    review_status: TranslationMemoryReviewStatus | None = None
    reuse_enabled: bool | None = None
    metadata: JsonDict | None = None


class TranslationMemoryLookupResult(BaseModel):
    article_revision_id: str
    block_uid: str
    target_language: str
    content_hash: str
    glossary_version: str | None = None
    entries: list[TranslationMemoryEntry] = Field(default_factory=list)


class GlossaryTerm(BaseModel):
    id: str
    scope: str
    source_term: str
    target_term: str
    language_direction: str
    status: str = "candidate"
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class GlossaryTermCreate(BaseModel):
    source_term: str = Field(min_length=1, max_length=160)
    target_term: str = Field(default="", max_length=160)
    language_direction: str = Field(default="en->zh-CN", min_length=3, max_length=40)
    status: str = Field(default="active", min_length=1, max_length=40)
    metadata: JsonDict = Field(default_factory=dict)


class GlossaryTermUpdate(BaseModel):
    target_term: str | None = Field(default=None, max_length=160)
    status: str | None = Field(default=None, min_length=1, max_length=40)
    metadata: JsonDict | None = None


class GlossaryExtractionRequest(BaseModel):
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    limit: int = Field(default=40, ge=1, le=200)


class GlossaryExtractionResult(BaseModel):
    article_revision_id: str
    target_language: str
    candidates_created: int
    existing_candidates: int
    terms: list[GlossaryTerm] = Field(default_factory=list)


class ArticleGlossary(BaseModel):
    article_revision_id: str
    target_language: str
    active_version: str
    terms: list[GlossaryTerm] = Field(default_factory=list)
    affected_block_uids: list[str] = Field(default_factory=list)


class ReaderCardType(StrEnum):
    term = "term"
    note = "note"
    formula = "formula"
    figure = "figure"
    question = "question"


class ReaderCardSourceType(StrEnum):
    wikipedia = "wikipedia"
    wikidata = "wikidata"
    ai_search = "ai_search"
    paper_local = "paper_local"
    user_note = "user_note"


class ReaderCardStatus(StrEnum):
    candidate = "candidate"
    pinned = "pinned"
    exported = "exported"
    archived = "archived"


class ReaderCardPosition(StrEnum):
    left = "left"
    right = "right"
    floating = "floating"


class ReaderCard(BaseModel):
    id: str
    article_revision_id: str
    card_type: ReaderCardType
    anchor_block_uid: str
    anchor_text: str
    canonical_key: str
    abbreviation: str | None = None
    full_form: str | None = None
    title: str
    body_markdown: str = ""
    target_language: str
    source_type: ReaderCardSourceType
    source_url: str | None = None
    position: ReaderCardPosition = ReaderCardPosition.right
    status: ReaderCardStatus = ReaderCardStatus.candidate
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class ReaderCardCreate(BaseModel):
    card_type: ReaderCardType = ReaderCardType.note
    anchor_block_uid: str = Field(min_length=1, max_length=120)
    anchor_text: str = Field(min_length=1, max_length=240)
    abbreviation: str | None = Field(default=None, max_length=80)
    full_form: str | None = Field(default=None, max_length=240)
    title: str = Field(min_length=1, max_length=240)
    body_markdown: str = Field(default="", max_length=4000)
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    source_type: ReaderCardSourceType = ReaderCardSourceType.user_note
    source_url: str | None = Field(default=None, max_length=800)
    position: ReaderCardPosition = ReaderCardPosition.right
    status: ReaderCardStatus = ReaderCardStatus.pinned
    metadata: JsonDict = Field(default_factory=dict)


class ReaderCardUpdate(BaseModel):
    anchor_text: str | None = Field(default=None, min_length=1, max_length=240)
    abbreviation: str | None = Field(default=None, max_length=80)
    full_form: str | None = Field(default=None, max_length=240)
    title: str | None = Field(default=None, min_length=1, max_length=240)
    body_markdown: str | None = Field(default=None, max_length=4000)
    source_url: str | None = Field(default=None, max_length=800)
    position: ReaderCardPosition | None = None
    status: ReaderCardStatus | None = None
    metadata: JsonDict | None = None


class ReaderCards(BaseModel):
    article_revision_id: str
    target_language: str
    cards: list[ReaderCard] = Field(default_factory=list)


class ReaderCardExtractionRequest(BaseModel):
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    limit: int = Field(default=30, ge=1, le=120)
    force: bool = False


class ReaderCardExtractionResult(BaseModel):
    article_revision_id: str
    target_language: str
    candidates_created: int
    existing_candidates: int
    wiki_cards_created: int
    cards: list[ReaderCard] = Field(default_factory=list)


class ReaderCardGenerationRequest(BaseModel):
    anchor_block_uid: str = Field(min_length=1, max_length=120)
    anchor_text: str = Field(min_length=1, max_length=240)
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    provider_profile_id: str | None = Field(default=None, min_length=1)
    model: str | None = None
    native_search: bool = True
    card_type: ReaderCardType = ReaderCardType.term
    title: str | None = Field(default=None, max_length=240)
    abbreviation: str | None = Field(default=None, max_length=80)
    full_form: str | None = Field(default=None, max_length=240)


class ReaderCardGenerationResult(BaseModel):
    article_revision_id: str
    card: ReaderCard
    native_search_used: bool = False
    source_type: ReaderCardSourceType


class ReaderCardObsidianExportRequest(BaseModel):
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    card_ids: list[str] | None = None


class ReaderCardObsidianExportResult(BaseModel):
    vault_path: str
    note_path: str
    cards_exported: int
    updated_existing: bool = False


class ChatMessage(BaseModel):
    id: str
    article_revision_id: str
    role: str
    content: str
    source_refs: list[str] = Field(default_factory=list)
    external_refs: list[ExternalCitation] = Field(default_factory=list)
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime


class RetrievedBlock(BaseModel):
    block_uid: str
    block_type: str
    structural_path: str
    source_markdown: str
    score: float
    evidence_type: str = "current_paper"
    retrieval_method: str = "fts"
    fts_score: float | None = None
    vector_score: float | None = None


class ExternalCitation(BaseModel):
    source: str = "external_native_search"
    title: str | None = None
    url: str | None = None
    doi: str | None = None
    arxiv_id: str | None = None
    retrieved_at: str = ""
    model: str = ""
    raw_snippet: str = ""
    metadata: JsonDict = Field(default_factory=dict)


class CitationEntry(BaseModel):
    id: str
    label: str
    title: str
    raw_text: str
    authors: str | None = None
    year: str | None = None
    arxiv_id: str | None = None
    scholar_query: str
    scholar_url: str
    metadata: JsonDict = Field(default_factory=dict)


class ArticleCitations(BaseModel):
    article_revision_id: str
    citations: list[CitationEntry] = Field(default_factory=list)


class ScholarSearchResult(BaseModel):
    title: str
    url: str
    snippet: str | None = None
    source: str = "google_scholar"


class CitationScholarResult(BaseModel):
    citation_id: str
    query: str
    scholar_url: str
    first_result: ScholarSearchResult | None = None
    status: str = "ok"
    message: str | None = None


class CitationArxivCandidate(BaseModel):
    citation_id: str
    arxiv_id: str
    title: str
    abs_url: str
    source: str = "citation"


class CitationLibraryImportRequest(BaseModel):
    download_pdf: bool = True
    translate_after_import: bool = False
    target_language: str = "zh-CN"
    provider_profile_id: str | None = None
    model: str | None = None


class CitationLibraryImportResult(BaseModel):
    citation_id: str
    candidate: CitationArxivCandidate
    job: Job
    translate_after_import: bool = False


class ChatAskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=8000)
    provider_profile_id: str = Field(min_length=1)
    model: str | None = None
    current_block_uid: str | None = None
    max_blocks: int = Field(default=6, ge=1, le=20)
    native_search: bool = False
    retrieval_mode: RetrievalMode = RetrievalMode.auto


class ArticleChatHistory(BaseModel):
    article_revision_id: str
    messages: list[ChatMessage] = Field(default_factory=list)


class ChatAskResult(BaseModel):
    article_revision_id: str
    user_message: ChatMessage
    assistant_message: ChatMessage
    cited_blocks: list[RetrievedBlock] = Field(default_factory=list)
    external_refs: list[ExternalCitation] = Field(default_factory=list)
    native_search_used: bool = False


class ChatToNotePatchRequest(BaseModel):
    title: str | None = Field(default=None, max_length=160)


class NotePatch(BaseModel):
    id: str
    article_revision_id: str
    status: str
    title: str
    patch_markdown: str
    source_refs: list[str] = Field(default_factory=list)
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class NoteTemplate(BaseModel):
    id: str
    name: str
    description: str
    custom: bool = False
    metadata: JsonDict = Field(default_factory=dict)


class NoteTemplateCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(min_length=1, max_length=4000)
    metadata: JsonDict = Field(default_factory=dict)


class NoteTemplateUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, min_length=1, max_length=4000)
    metadata: JsonDict | None = None


class ArticleNotePatches(BaseModel):
    article_revision_id: str
    patches: list[NotePatch] = Field(default_factory=list)


class NotePatchGenerateRequest(BaseModel):
    provider_profile_id: str = Field(min_length=1)
    template_id: str = Field(default="deep_reading", min_length=1, max_length=80)
    model: str | None = None
    max_blocks: int = Field(default=12, ge=1, le=40)
    include_chat_history: bool = True


class NotePatchUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    patch_markdown: str | None = Field(default=None, min_length=1)
    status: str | None = Field(default=None, min_length=1, max_length=40)
    metadata: JsonDict | None = None


class NotePatchGenerateResult(BaseModel):
    article_revision_id: str
    patch: NotePatch
    template: NoteTemplate


class ArticleExportKind(StrEnum):
    source_markdown = "source_markdown"
    translated_markdown = "translated_markdown"
    bilingual_markdown = "bilingual_markdown"
    lecture_notes = "lecture_notes"
    bundle_zip = "bundle_zip"


class ArticleExportRequest(BaseModel):
    kind: ArticleExportKind = ArticleExportKind.bilingual_markdown
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    include_untranslated: bool = True


class ArticleExportResult(BaseModel):
    article_revision_id: str
    kind: ArticleExportKind
    target_language: str | None = None
    file_name: str
    path: str
    bytes_written: int
    missing_translation_block_uids: list[str] = Field(default_factory=list)
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime


class ObsidianClipColor(StrEnum):
    none = "none"
    yellow = "yellow"
    blue = "blue"
    green = "green"
    pink = "pink"
    purple = "purple"


class ObsidianClipRequest(BaseModel):
    block_uid: str = Field(min_length=1, max_length=120)
    target_language: str = Field(default="zh-CN", min_length=2, max_length=40)
    color: ObsidianClipColor = ObsidianClipColor.none


class ObsidianClipResult(BaseModel):
    vault_path: str
    note_path: str
    article_heading: str
    block_uid: str
    created_file: bool = False
    updated_existing: bool = False


class BlockEmbedding(BaseModel):
    id: str
    article_revision_id: str
    block_id: str
    block_uid: str
    provider: str
    model: str
    dimensions: int
    source_hash: str
    vector: list[float] = Field(default_factory=list)
    metadata: JsonDict = Field(default_factory=dict)
    created_at: datetime
    updated_at: datetime


class EmbedArticleRequest(BaseModel):
    provider: str = Field(default="local-hash", min_length=1, max_length=80)
    model: str = Field(default="hashing-64-v1", min_length=1, max_length=120)
    force: bool = False


class ArticleEmbeddingStatus(BaseModel):
    article_revision_id: str
    provider: str
    model: str
    dimensions: int
    eligible_blocks: int
    embedded_blocks: int
    stale_blocks: int = 0
    updated_at: datetime | None = None


class EmbedArticleResult(BaseModel):
    library_id: str
    article_revision_id: str
    provider: str
    model: str
    dimensions: int
    eligible_blocks: int
    embedded_blocks: int
    skipped_blocks: int
    stale_blocks_deleted: int


class ParseErrorInfo(BaseModel):
    code: str
    message: str
    details: JsonDict = Field(default_factory=dict)


class ArticleManifest(BaseModel):
    schema_version: int = 1
    article_revision_id: str
    arxiv_id: str | None = None
    source: str
    source_fingerprint: str | None = None
    pdf_fingerprint: str | None = None
    arxiv_metadata: JsonDict = Field(default_factory=dict)
    main_tex_file: str | None = None
    latexml_command: list[str] = Field(default_factory=list)
    tool_versions: JsonDict = Field(default_factory=dict)
    generated_artifacts: JsonDict = Field(default_factory=dict)
    parse_status: str = "not_started"
    errors: list[ParseErrorInfo] = Field(default_factory=list)
    metadata: JsonDict = Field(default_factory=dict)


class ArticleListItem(BaseModel):
    article_revision: ArticleRevision
    family: ArticleFamily
    manifest: ArticleManifest | None = None
    block_count: int = 0
    asset_count: int = 0
    translation_status: ArticleTranslationStatus = Field(default_factory=ArticleTranslationStatus)
    reading_progress: ArticleReadingProgress | None = None


class ArticleDeleteResult(BaseModel):
    library_id: str
    article_family_id: str
    article_revision_id: str
    bundle_path: str
    deleted_cache: bool
    removed_family: bool = False


class ArticleDocument(BaseModel):
    article_revision: ArticleRevision
    manifest: ArticleManifest
    blocks: list[DocumentBlock]
    assets: list[AssetRecord] = Field(default_factory=list)


class ImportArxivRequest(BaseModel):
    arxiv_id: str = Field(min_length=1)
    version: str | None = None
    download_pdf: bool = True
    parse_after_import: bool = True


class ImportArxivResult(BaseModel):
    library_id: str
    article_family_id: str
    article_revision_id: str
    bundle_path: str
    parse_job_id: str | None = None


class ImportLocalResult(BaseModel):
    library_id: str
    article_family_id: str
    article_revision_id: str
    bundle_path: str
    source_kind: ImportLocalKind
    parse_job_id: str | None = None


class DevInfo(BaseModel):
    bilin_home: Path
    global_db_path: Path
