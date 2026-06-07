from __future__ import annotations

import hmac
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi
from fastapi.responses import JSONResponse

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
    research,
    translation_memory,
)
from bilin_api.branding import PRODUCT_NAME_EN
from bilin_api.database import init_global_db
from bilin_api.schemas import (
    AgentActionPlan,
    AgentActionPlanCreate,
    AgentActionPlanStep,
    AgentActionPlanStepCreate,
    AgentActionPlanTransitionRequest,
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
    ReadingOutline,
    ResearchPaperMasteryOutline,
    ResearchPlan,
    ResearchPlanCreate,
    ResearchPlanGenerationRequest,
    ResearchSkill,
    ResearchSkillIndexRequest,
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


def cors_origin_regex() -> str:
    return r"^http://(127\.0\.0\.1|localhost):\d+$"


def cors_allowed_origins() -> list[str]:
    origins = [
        "http://127.0.0.1:3000",
        "http://localhost:3000",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:5174",
        "http://localhost:5173",
        "http://localhost:5174",
    ]
    for origin in os.getenv("BILIN_ALLOWED_ORIGINS", "").split(","):
        cleaned = origin.strip().rstrip("/")
        if cleaned and cleaned not in origins:
            origins.append(cleaned)
    return origins


def api_token() -> str | None:
    token = os.getenv("BILIN_API_TOKEN")
    return token if token else None


def request_api_token(request: Request) -> str | None:
    authorization = request.headers.get("authorization", "")
    if authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    header_token = request.headers.get("x-bilin-api-token")
    if header_token:
        return header_token
    return request.query_params.get("access_token") or request.query_params.get("bilin_token")


app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_allowed_origins(),
    allow_origin_regex=cors_origin_regex(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def require_api_token(request: Request, call_next):
    expected_token = api_token()
    if (
        expected_token
        and request.method != "OPTIONS"
        and request.url.path not in {"/health"}
        and not hmac.compare_digest(request_api_token(request) or "", expected_token)
    ):
        return JSONResponse(
            {"detail": "Missing or invalid Bilin API token."},
            status_code=status.HTTP_401_UNAUTHORIZED,
        )
    return await call_next(request)


app.include_router(health.router)
app.include_router(doctor.router)
app.include_router(libraries.router)
app.include_router(providers.router)
app.include_router(translation_memory.router)
app.include_router(imports.router)
app.include_router(articles.router)
app.include_router(research.router)
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
        AgentActionPlan,
        AgentActionPlanCreate,
        AgentActionPlanStep,
        AgentActionPlanStepCreate,
        AgentActionPlanTransitionRequest,
        ResearchSkill,
        ResearchSkillIndexRequest,
        ReadingOutline,
        ResearchPlan,
        ResearchPlanCreate,
        ResearchPlanGenerationRequest,
        ResearchPaperMasteryOutline,
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
