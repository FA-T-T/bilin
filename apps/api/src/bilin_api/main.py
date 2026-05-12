from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi

from bilin_api import __version__
from bilin_api.api import (
    articles,
    doctor,
    events,
    health,
    imports,
    jobs,
    libraries,
    providers,
    recommendations,
    translation_memory,
)
from bilin_api.branding import PRODUCT_NAME_EN
from bilin_api.database import init_global_db
from bilin_api.schemas import (
    ArticleChatHistory,
    ArticleCitations,
    ArticleDeleteResult,
    ArticleDocument,
    ArticleEmbeddingStatus,
    ArticleExportRequest,
    ArticleExportResult,
    ArticleFamily,
    ArticleGlossary,
    ArticleListItem,
    ArticleManifest,
    ArticleNotePatches,
    ArticleRevision,
    ArticleTranslations,
    ArticleTranslationStatus,
    ArxivCategory,
    ArxivCategoryListResult,
    ArxivRecommendationItem,
    ArxivRecommendationPreferences,
    ArxivRecommendationPreferencesUpdate,
    ArxivRecommendationRequest,
    ArxivRecommendationResult,
    AssetRecord,
    BlockEmbedding,
    ChatAskRequest,
    ChatAskResult,
    ChatMessage,
    ChatToNotePatchRequest,
    CitationArxivCandidate,
    CitationEntry,
    CitationLibraryImportRequest,
    CitationLibraryImportResult,
    CitationScholarResult,
    DocumentBlock,
    EmbedArticleRequest,
    EmbedArticleResult,
    ExternalCitation,
    GlossaryExtractionRequest,
    GlossaryExtractionResult,
    GlossaryTerm,
    GlossaryTermCreate,
    GlossaryTermUpdate,
    ImportArxivRequest,
    ImportArxivResult,
    ImportLocalResult,
    Library,
    LibraryDeleteResult,
    NotePatch,
    NotePatchGenerateRequest,
    NotePatchGenerateResult,
    NotePatchUpdate,
    NoteTemplate,
    NoteTemplateCreate,
    NoteTemplateUpdate,
    ObsidianClipRequest,
    ObsidianClipResult,
    ParseErrorInfo,
    ProviderModelDiscoveryRequest,
    ProviderModelDiscoveryResult,
    ProviderModelInfo,
    ProviderProfile,
    ProviderProfileCreate,
    ProviderProfileUpdate,
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
    RetrievedBlock,
    ScholarSearchResult,
    TranslationBatchRequest,
    TranslationBatchResult,
    TranslationMemoryEntry,
    TranslationMemoryEntryUpdate,
    TranslationMemoryListResult,
    TranslationMemoryLookupResult,
    TranslationVariant,
)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    await init_global_db()
    yield


app = FastAPI(
    title=f"{PRODUCT_NAME_EN} API",
    version=__version__,
    description=f"Local-first API for {PRODUCT_NAME_EN}.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://127.0.0.1:5173",
        "http://127.0.0.1:5174",
        "http://localhost:5173",
        "http://localhost:5174",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(doctor.router)
app.include_router(libraries.router)
app.include_router(providers.router)
app.include_router(translation_memory.router)
app.include_router(imports.router)
app.include_router(articles.router)
app.include_router(recommendations.router)
app.include_router(jobs.router)
app.include_router(events.router)


def custom_openapi() -> dict:
    if app.openapi_schema:
        return app.openapi_schema
    schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )
    components = schema.setdefault("components", {}).setdefault("schemas", {})
    for model in (
        ProviderProfile,
        ProviderProfileCreate,
        ProviderProfileUpdate,
        ProviderModelInfo,
        ProviderModelDiscoveryRequest,
        ProviderModelDiscoveryResult,
        ArxivCategory,
        ArxivCategoryListResult,
        ArxivRecommendationPreferences,
        ArxivRecommendationPreferencesUpdate,
        ArxivRecommendationRequest,
        ArxivRecommendationItem,
        ArxivRecommendationResult,
        Library,
        LibraryDeleteResult,
        ArticleFamily,
        ArticleRevision,
        ArticleManifest,
        AssetRecord,
        ArticleListItem,
        ArticleDeleteResult,
        ArticleTranslationStatus,
        ArticleDocument,
        ArticleCitations,
        CitationEntry,
        CitationScholarResult,
        ScholarSearchResult,
        ArticleEmbeddingStatus,
        ArticleExportRequest,
        ArticleExportResult,
        BlockEmbedding,
        DocumentBlock,
        EmbedArticleRequest,
        EmbedArticleResult,
        ArticleTranslations,
        TranslationBatchRequest,
        TranslationBatchResult,
        TranslationVariant,
        TranslationMemoryEntry,
        TranslationMemoryEntryUpdate,
        TranslationMemoryListResult,
        TranslationMemoryLookupResult,
        ArticleGlossary,
        GlossaryTerm,
        GlossaryTermCreate,
        GlossaryTermUpdate,
        GlossaryExtractionRequest,
        GlossaryExtractionResult,
        ArticleChatHistory,
        ChatAskRequest,
        ChatAskResult,
        ChatToNotePatchRequest,
        RetrievedBlock,
        ChatMessage,
        ExternalCitation,
        CitationArxivCandidate,
        NotePatch,
        NoteTemplate,
        NoteTemplateCreate,
        NoteTemplateUpdate,
        ArticleNotePatches,
        NotePatchGenerateRequest,
        NotePatchGenerateResult,
        NotePatchUpdate,
        ObsidianClipRequest,
        ObsidianClipResult,
        ReaderCard,
        ReaderCards,
        ReaderCardCreate,
        ReaderCardUpdate,
        ReaderCardExtractionRequest,
        ReaderCardExtractionResult,
        ReaderCardGenerationRequest,
        ReaderCardGenerationResult,
        ReaderCardObsidianExportRequest,
        ReaderCardObsidianExportResult,
        ParseErrorInfo,
        CitationLibraryImportRequest,
        CitationLibraryImportResult,
        ImportArxivRequest,
        ImportArxivResult,
        ImportLocalResult,
    ):
        model_schema = model.model_json_schema(ref_template="#/components/schemas/{model}")
        for name, definition in model_schema.pop("$defs", {}).items():
            components.setdefault(name, definition)
        components.setdefault(
            model.__name__,
            model_schema,
        )
    app.openapi_schema = schema
    return app.openapi_schema


app.openapi = custom_openapi
