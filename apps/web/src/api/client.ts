import type {
  ArticleDeleteResult,
  ArticleDocument,
  ArticleEmbeddingStatus,
  ArticleExportRequest,
  ArticleExportResult,
  ArticleGlossary,
  ArticleChatHistory,
  ArticleCitations,
  ArticleListItem,
  ArticleNotePatches,
  ArticleTranslations,
  ChatAskRequest,
  ChatAskResult,
  ChatToNotePatchRequest,
  CitationLibraryImportRequest,
  CitationLibraryImportResult,
  CitationScholarResult,
  DoctorReport,
  EmbedArticleRequest,
  EmbedArticleResult,
  GlossaryExtractionRequest,
  GlossaryExtractionResult,
  GlossaryTerm,
  GlossaryTermCreate,
  GlossaryTermUpdate,
  ImportArxivRequest,
  ImportLocalKind,
  ImportLocalResult,
  Job,
  JobClearResult,
  JobSummary,
  Library,
  LibraryCreate,
  LibraryDeleteResult,
  LibraryTranslationBatchResult,
  NotePatch,
  NotePatchGenerateRequest,
  NotePatchGenerateResult,
  NotePatchUpdate,
  NoteTemplate,
  NoteTemplateCreate,
  NoteTemplateUpdate,
  ObsidianClipRequest,
  ObsidianClipResult,
  ProviderModelDiscoveryRequest,
  ProviderModelDiscoveryResult,
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
  TranslationBatchRequest,
  TranslationBatchResult,
  TranslationMemoryEntry,
  TranslationMemoryEntryUpdate,
  TranslationMemoryListResult,
  TranslationMemoryLookupResult,
  TranslationMemoryReviewStatus,
  TranslationVariant
} from "./types";

export const API_BASE_URL = import.meta.env.VITE_BILIN_API_URL ?? "http://127.0.0.1:8000";

export interface SseMessage {
  event: string;
  data: unknown;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...init?.headers
    }
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(detail || `Request failed with status ${response.status}`);
  }
  return (await response.json()) as T;
}

async function uploadRequest<T>(
  path: string,
  file: File,
  contentType = "application/octet-stream"
): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: "POST",
    body: file,
    headers: {
      "Content-Type": file.type || contentType
    }
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(detail || `Request failed with status ${response.status}`);
  }
  return (await response.json()) as T;
}

async function streamRequest<T>(
  path: string,
  payload: unknown,
  onMessage: (message: SseMessage) => void
): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(detail || `Request failed with status ${response.status}`);
  }

  let finalResult: T | undefined;
  const handleMessage = (message: SseMessage) => {
    onMessage(message);
    if (message.event === "done") {
      finalResult = message.data as T;
    }
  };

  if (!response.body) {
    parseSseText(await response.text(), handleMessage);
  } else {
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      buffer = emitCompleteSseMessages(buffer, handleMessage);
    }
    buffer += decoder.decode();
    parseSseText(buffer, handleMessage);
  }

  if (!finalResult) {
    throw new Error("Streaming response ended without a done event.");
  }
  return finalResult;
}

function emitCompleteSseMessages(buffer: string, onMessage: (message: SseMessage) => void): string {
  const parts = buffer.split("\n\n");
  const remainder = parts.pop() ?? "";
  parseSseText(parts.join("\n\n"), onMessage);
  return remainder;
}

function parseSseText(text: string, onMessage: (message: SseMessage) => void) {
  for (const rawEvent of text.split("\n\n")) {
    const trimmed = rawEvent.trim();
    if (!trimmed) continue;
    let event = "message";
    const dataLines: string[] = [];
    for (const line of trimmed.split("\n")) {
      if (line.startsWith("event:")) {
        event = line.slice("event:".length).trim();
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice("data:".length).trimStart());
      }
    }
    const dataText = dataLines.join("\n");
    onMessage({ event, data: dataText ? JSON.parse(dataText) : null });
  }
}

export const apiClient = {
  getDoctor: () => request<DoctorReport>("/doctor"),
  listProviders: () => request<ProviderProfile[]>("/providers"),
  createProvider: (payload: ProviderProfileCreate) =>
    request<ProviderProfile>("/providers", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  discoverProviderModels: (payload: ProviderModelDiscoveryRequest) =>
    request<ProviderModelDiscoveryResult>("/providers/discover-models", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  updateProvider: (providerId: string, payload: ProviderProfileUpdate) =>
    request<ProviderProfile>(`/providers/${encodeURIComponent(providerId)}`, {
      method: "PUT",
      body: JSON.stringify(payload)
    }),
  listLibraries: () => request<Library[]>("/libraries"),
  createLibrary: (payload: LibraryCreate) =>
    request<Library>("/libraries", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  getLibrary: (libraryId: string) => request<Library>(`/libraries/${libraryId}`),
  archiveLibrary: (libraryId: string) =>
    request<Library>(`/libraries/${encodeURIComponent(libraryId)}/archive`, { method: "POST" }),
  deleteLibrary: (libraryId: string) =>
    request<LibraryDeleteResult>(`/libraries/${encodeURIComponent(libraryId)}`, {
      method: "DELETE"
    }),
  listArticles: (libraryId: string, targetLanguage = "zh-CN") =>
    request<ArticleListItem[]>(
      `/libraries/${encodeURIComponent(libraryId)}/articles?target_language=${encodeURIComponent(targetLanguage)}`
    ),
  getArticle: (libraryId: string, revisionId: string, targetLanguage = "zh-CN") =>
    request<ArticleListItem>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}?target_language=${encodeURIComponent(targetLanguage)}`
    ),
  archiveArticle: (libraryId: string, revisionId: string) =>
    request<ArticleListItem>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/archive`,
      { method: "POST" }
    ),
  deleteArticle: (libraryId: string, revisionId: string) =>
    request<ArticleDeleteResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}`,
      { method: "DELETE" }
    ),
  getArticleDocument: (libraryId: string, revisionId: string) =>
    request<ArticleDocument>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/document`
    ),
  getArticleCitations: (libraryId: string, revisionId: string) =>
    request<ArticleCitations>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/citations`
    ),
  getCitationScholar: (libraryId: string, revisionId: string, citationId: string) =>
    request<CitationScholarResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/citations/${encodeURIComponent(citationId)}/scholar`
    ),
  importCitationArxiv: (
    libraryId: string,
    revisionId: string,
    citationId: string,
    payload: CitationLibraryImportRequest
  ) =>
    request<CitationLibraryImportResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/citations/${encodeURIComponent(citationId)}/import-arxiv`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  getArticleEmbeddingStatus: (libraryId: string, revisionId: string) =>
    request<ArticleEmbeddingStatus>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/embeddings/status`
    ),
  buildArticleEmbeddings: (libraryId: string, revisionId: string, payload: EmbedArticleRequest) =>
    request<EmbedArticleResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/embeddings`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  queueArticleEmbeddings: (libraryId: string, revisionId: string, payload: EmbedArticleRequest) =>
    request<Job>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/embeddings/jobs`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  exportArticle: (libraryId: string, revisionId: string, payload: ArticleExportRequest) =>
    request<ArticleExportResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/exports`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  saveObsidianClip: (libraryId: string, revisionId: string, payload: ObsidianClipRequest) =>
    request<ObsidianClipResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/obsidian/clips`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  getArticleTranslations: (libraryId: string, revisionId: string, targetLanguage: string) =>
    request<ArticleTranslations>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/translations?target_language=${encodeURIComponent(targetLanguage)}`
    ),
  selectTranslationVariant: (libraryId: string, revisionId: string, variantId: string) =>
    request<TranslationVariant>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/translations/${encodeURIComponent(variantId)}/select`,
      { method: "POST" }
    ),
  getTranslationMemory: (
    libraryId: string,
    revisionId: string,
    blockUid: string,
    targetLanguage: string,
    glossaryVersion?: string | null
  ) =>
    request<TranslationMemoryLookupResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/blocks/${encodeURIComponent(blockUid)}/translation-memory?target_language=${encodeURIComponent(targetLanguage)}${glossaryVersion ? `&glossary_version=${encodeURIComponent(glossaryVersion)}` : ""}`
    ),
  listTranslationMemory: (filters?: {
    targetLanguage?: string;
    reviewStatus?: TranslationMemoryReviewStatus | null;
    reuseEnabled?: boolean | null;
    limit?: number;
  }) => {
    const params = new URLSearchParams();
    if (filters?.targetLanguage) params.set("target_language", filters.targetLanguage);
    if (filters?.reviewStatus) params.set("review_status", filters.reviewStatus);
    if (filters?.reuseEnabled !== undefined && filters.reuseEnabled !== null) {
      params.set("reuse_enabled", String(filters.reuseEnabled));
    }
    if (filters?.limit) params.set("limit", String(filters.limit));
    const suffix = params.toString() ? `?${params.toString()}` : "";
    return request<TranslationMemoryListResult>(`/translation-memory${suffix}`);
  },
  updateTranslationMemoryEntry: (entryId: string, payload: TranslationMemoryEntryUpdate) =>
    request<TranslationMemoryEntry>(`/translation-memory/${encodeURIComponent(entryId)}`, {
      method: "PATCH",
      body: JSON.stringify(payload)
    }),
  getArticleGlossary: (libraryId: string, revisionId: string, targetLanguage: string) =>
    request<ArticleGlossary>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/glossary?target_language=${encodeURIComponent(targetLanguage)}`
    ),
  extractGlossary: (libraryId: string, revisionId: string, payload: GlossaryExtractionRequest) =>
    request<GlossaryExtractionResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/glossary/extract`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  createGlossaryTerm: (libraryId: string, revisionId: string, payload: GlossaryTermCreate) =>
    request<GlossaryTerm>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/glossary`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  updateGlossaryTerm: (
    libraryId: string,
    revisionId: string,
    termId: string,
    payload: GlossaryTermUpdate
  ) =>
    request<GlossaryTerm>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/glossary/${encodeURIComponent(termId)}`,
      {
        method: "PUT",
        body: JSON.stringify(payload)
      }
    ),
  getReaderCards: (libraryId: string, revisionId: string, targetLanguage: string) =>
    request<ReaderCards>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards?target_language=${encodeURIComponent(targetLanguage)}`
    ),
  createReaderCard: (libraryId: string, revisionId: string, payload: ReaderCardCreate) =>
    request<ReaderCard>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  updateReaderCard: (
    libraryId: string,
    revisionId: string,
    cardId: string,
    payload: ReaderCardUpdate
  ) =>
    request<ReaderCard>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards/${encodeURIComponent(cardId)}`,
      {
        method: "PUT",
        body: JSON.stringify(payload)
      }
    ),
  deleteReaderCard: (libraryId: string, revisionId: string, cardId: string) =>
    request<ReaderCard>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards/${encodeURIComponent(cardId)}`,
      { method: "DELETE" }
    ),
  extractReaderCards: (
    libraryId: string,
    revisionId: string,
    payload: ReaderCardExtractionRequest
  ) =>
    request<ReaderCardExtractionResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards/extract`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  generateReaderCard: (
    libraryId: string,
    revisionId: string,
    payload: ReaderCardGenerationRequest
  ) =>
    request<ReaderCardGenerationResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards/generate`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  exportReaderCardsToObsidian: (
    libraryId: string,
    revisionId: string,
    payload: ReaderCardObsidianExportRequest
  ) =>
    request<ReaderCardObsidianExportResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/cards/export/obsidian`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  getArticleChat: (libraryId: string, revisionId: string) =>
    request<ArticleChatHistory>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/chat`
    ),
  askArticleQuestion: (libraryId: string, revisionId: string, payload: ChatAskRequest) =>
    request<ChatAskResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/chat/ask`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  askArticleQuestionStream: (
    libraryId: string,
    revisionId: string,
    payload: ChatAskRequest,
    onMessage: (message: SseMessage) => void
  ) =>
    streamRequest<ChatAskResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/chat/ask-stream`,
      payload,
      onMessage
    ),
  createNotePatchFromChat: (
    libraryId: string,
    revisionId: string,
    messageId: string,
    payload: ChatToNotePatchRequest
  ) =>
    request<NotePatch>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/chat/${encodeURIComponent(messageId)}/note-patch`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  getNoteTemplates: (libraryId: string, revisionId: string) =>
    request<NoteTemplate[]>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/templates`
    ),
  createNoteTemplate: (libraryId: string, revisionId: string, payload: NoteTemplateCreate) =>
    request<NoteTemplate>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/templates`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  updateNoteTemplate: (
    libraryId: string,
    revisionId: string,
    templateId: string,
    payload: NoteTemplateUpdate
  ) =>
    request<NoteTemplate>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/templates/${encodeURIComponent(templateId)}`,
      {
        method: "PUT",
        body: JSON.stringify(payload)
      }
    ),
  getNotePatches: (libraryId: string, revisionId: string) =>
    request<ArticleNotePatches>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/patches`
    ),
  generateNotePatch: (libraryId: string, revisionId: string, payload: NotePatchGenerateRequest) =>
    request<NotePatchGenerateResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/generate`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  updateNotePatch: (
    libraryId: string,
    revisionId: string,
    patchId: string,
    payload: NotePatchUpdate
  ) =>
    request<NotePatch>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/patches/${encodeURIComponent(patchId)}`,
      {
        method: "PUT",
        body: JSON.stringify(payload)
      }
    ),
  acceptNotePatch: (libraryId: string, revisionId: string, patchId: string) =>
    request<NotePatch>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/patches/${encodeURIComponent(patchId)}/accept`,
      { method: "POST" }
    ),
  rejectNotePatch: (libraryId: string, revisionId: string, patchId: string) =>
    request<NotePatch>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/notes/patches/${encodeURIComponent(patchId)}/reject`,
      { method: "POST" }
    ),
  translateArticle: (libraryId: string, revisionId: string, payload: TranslationBatchRequest) =>
    request<TranslationBatchResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/translations`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  translateLibraryMissing: (libraryId: string, payload: TranslationBatchRequest) =>
    request<LibraryTranslationBatchResult>(
      `/libraries/${encodeURIComponent(libraryId)}/translations/missing`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  translateBlock: (
    libraryId: string,
    revisionId: string,
    blockUid: string,
    payload: TranslationBatchRequest
  ) =>
    request<TranslationBatchResult>(
      `/libraries/${encodeURIComponent(libraryId)}/articles/${encodeURIComponent(revisionId)}/blocks/${encodeURIComponent(blockUid)}/translate`,
      {
        method: "POST",
        body: JSON.stringify(payload)
      }
    ),
  importArxiv: (libraryId: string, payload: ImportArxivRequest) =>
    request<Job>(`/libraries/${encodeURIComponent(libraryId)}/imports/arxiv`, {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  importLocalFile: (
    libraryId: string,
    payload: { file: File; kind: ImportLocalKind; parseAfterImport: boolean }
  ) =>
    uploadRequest<ImportLocalResult>(
      `/libraries/${encodeURIComponent(libraryId)}/imports/file?kind=${encodeURIComponent(payload.kind)}&file_name=${encodeURIComponent(payload.file.name)}&parse_after_import=${String(payload.parseAfterImport)}`,
      payload.file,
      localImportContentType(payload.kind)
    ),
  listJobs: (limit = 120) => request<Job[]>(`/jobs?limit=${encodeURIComponent(String(limit))}`),
  getJobSummary: () => request<JobSummary>("/jobs/summary"),
  clearJobs: () => request<JobClearResult>("/jobs", { method: "DELETE" }),
  pauseJob: (jobId: string) => request<Job>(`/jobs/${jobId}/pause`, { method: "POST" }),
  resumeJob: (jobId: string) => request<Job>(`/jobs/${jobId}/resume`, { method: "POST" }),
  cancelJob: (jobId: string) => request<Job>(`/jobs/${jobId}/cancel`, { method: "POST" })
};

function localImportContentType(kind: ImportLocalKind) {
  if (kind === "markdown") return "text/markdown";
  if (kind === "pdf") return "application/pdf";
  return "application/octet-stream";
}
