import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { API_BASE_URL, apiClient, type SseMessage } from "./client";
import type {
  ArticleExportRequest,
  ChatAskRequest,
  ChatToNotePatchRequest,
  CitationLibraryImportRequest,
  EmbedArticleRequest,
  GlossaryExtractionRequest,
  GlossaryTermCreate,
  GlossaryTermUpdate,
  ImportArxivRequest,
  ImportLocalKind,
  LibraryCreate,
  LibraryUpdate,
  NotePatchGenerateRequest,
  NotePatchUpdate,
  NoteTemplateCreate,
  NoteTemplateUpdate,
  ObsidianClipRequest,
  ProviderModelDiscoveryRequest,
  ProviderProfileCreate,
  ProviderProfileUpdate,
  ReaderCardCreate,
  ReaderCardExtractionRequest,
  ReaderCardGenerationRequest,
  ReaderCardObsidianExportRequest,
  ReaderCardUpdate,
  ReadingProgressUpdate,
  TranslationBatchRequest,
  TranslationMemoryEntryUpdate,
  TranslationMemoryReviewStatus
} from "./types";

export const queryKeys = {
  doctor: ["doctor"] as const,
  providerPresets: ["provider-presets"] as const,
  providers: ["providers"] as const,
  libraries: ["libraries"] as const,
  library: (libraryId: string) => ["library", libraryId] as const,
  articles: (libraryId: string, targetLanguage?: string) =>
    targetLanguage
      ? (["articles", libraryId, targetLanguage] as const)
      : (["articles", libraryId] as const),
  articleDocument: (libraryId: string, revisionId: string) =>
    ["article-document", libraryId, revisionId] as const,
  articleReadingProgress: (libraryId: string, revisionId: string) =>
    ["article-reading-progress", libraryId, revisionId] as const,
  articleCitations: (libraryId: string, revisionId: string) =>
    ["article-citations", libraryId, revisionId] as const,
  citationScholar: (libraryId: string, revisionId: string, citationId: string) =>
    ["citation-scholar", libraryId, revisionId, citationId] as const,
  articleEmbeddingStatus: (libraryId: string, revisionId: string) =>
    ["article-embedding-status", libraryId, revisionId] as const,
  articleTranslations: (libraryId: string, revisionId: string, targetLanguage: string) =>
    ["article-translations", libraryId, revisionId, targetLanguage] as const,
  translationMemory: (
    libraryId: string,
    revisionId: string,
    blockUid: string,
    targetLanguage: string,
    glossaryVersion?: string | null
  ) =>
    [
      "translation-memory",
      libraryId,
      revisionId,
      blockUid,
      targetLanguage,
      glossaryVersion ?? null
    ] as const,
  translationMemoryReview: (
    targetLanguage: string,
    reviewStatus?: TranslationMemoryReviewStatus | null,
    reuseEnabled?: boolean | null
  ) =>
    [
      "translation-memory-review",
      targetLanguage,
      reviewStatus ?? null,
      reuseEnabled ?? null
    ] as const,
  articleGlossary: (libraryId: string, revisionId: string, targetLanguage: string) =>
    ["article-glossary", libraryId, revisionId, targetLanguage] as const,
  articleReaderCards: (libraryId: string, revisionId: string, targetLanguage: string) =>
    ["article-reader-cards", libraryId, revisionId, targetLanguage] as const,
  articleChat: (libraryId: string, revisionId: string) =>
    ["article-chat", libraryId, revisionId] as const,
  noteTemplates: (libraryId: string, revisionId: string) =>
    ["note-templates", libraryId, revisionId] as const,
  notePatches: (libraryId: string, revisionId: string) =>
    ["note-patches", libraryId, revisionId] as const,
  jobs: ["jobs"] as const,
  jobSummary: ["jobs", "summary"] as const,
  jobList: (limit: number) => ["jobs", "list", limit] as const
};

export function useDoctor() {
  return useQuery({
    queryKey: queryKeys.doctor,
    queryFn: apiClient.getDoctor,
    retry: false
  });
}

export function useLibraries() {
  return useQuery({
    queryKey: queryKeys.libraries,
    queryFn: apiClient.listLibraries,
    retry: false
  });
}

export function useProviders() {
  return useQuery({
    queryKey: queryKeys.providers,
    queryFn: apiClient.listProviders,
    retry: false
  });
}

export function useProviderPresets() {
  return useQuery({
    queryKey: queryKeys.providerPresets,
    queryFn: apiClient.listProviderPresets,
    retry: false
  });
}

export function useCreateProvider() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ProviderProfileCreate) => apiClient.createProvider(payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.providers })
  });
}

export function useDiscoverProviderModels() {
  return useMutation({
    mutationFn: (payload: ProviderModelDiscoveryRequest) =>
      apiClient.discoverProviderModels(payload)
  });
}

export function useUpdateProvider() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ providerId, payload }: { providerId: string; payload: ProviderProfileUpdate }) =>
      apiClient.updateProvider(providerId, payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.providers })
  });
}

export function useLibrary(libraryId?: string) {
  return useQuery({
    queryKey: queryKeys.library(libraryId ?? ""),
    queryFn: () => apiClient.getLibrary(libraryId ?? ""),
    enabled: Boolean(libraryId),
    retry: false
  });
}

export function useCreateLibrary() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: LibraryCreate) => apiClient.createLibrary(payload),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.libraries })
  });
}

export function useUpdateLibrary() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ libraryId, payload }: { libraryId: string; payload: LibraryUpdate }) =>
      apiClient.updateLibrary(libraryId, payload),
    onSuccess: (library) => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.libraries });
      void queryClient.invalidateQueries({ queryKey: queryKeys.library(library.id) });
    }
  });
}

export function useArchiveLibrary() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (libraryId: string) => apiClient.archiveLibrary(libraryId),
    onSuccess: (library) => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.libraries });
      void queryClient.invalidateQueries({ queryKey: queryKeys.library(library.id) });
    }
  });
}

export function useDeleteLibrary() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (libraryId: string) => apiClient.deleteLibrary(libraryId),
    onSuccess: (result) => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.libraries });
      void queryClient.removeQueries({ queryKey: queryKeys.library(result.library_id) });
      void queryClient.removeQueries({ queryKey: queryKeys.articles(result.library_id) });
    }
  });
}

export function useArticles(libraryId?: string, targetLanguage = "zh-CN") {
  return useQuery({
    queryKey: queryKeys.articles(libraryId ?? "", targetLanguage),
    queryFn: () => apiClient.listArticles(libraryId ?? "", targetLanguage),
    enabled: Boolean(libraryId),
    refetchInterval: 5000,
    retry: false
  });
}

export function useArchiveArticle(libraryId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (revisionId: string) => apiClient.archiveArticle(libraryId ?? "", revisionId),
    onSuccess: () => {
      if (libraryId) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
      }
    }
  });
}

export function useDeleteArticle(libraryId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (revisionId: string) => apiClient.deleteArticle(libraryId ?? "", revisionId),
    onSuccess: (_result, revisionId) => {
      if (libraryId) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
        void queryClient.removeQueries({
          queryKey: queryKeys.articleDocument(libraryId, revisionId)
        });
      }
    }
  });
}

export function useArticleDocument(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.articleDocument(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getArticleDocument(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useArticleReadingProgress(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.articleReadingProgress(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getReadingProgress(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useUpdateReadingProgress(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ReadingProgressUpdate) =>
      apiClient.updateReadingProgress(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (progress) => {
      if (libraryId && revisionId) {
        queryClient.setQueryData(queryKeys.articleReadingProgress(libraryId, revisionId), progress);
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
      }
    }
  });
}

export function useArticleCitations(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.articleCitations(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getArticleCitations(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    staleTime: 60 * 60 * 1000,
    retry: false
  });
}

export function useCitationScholar(
  libraryId?: string,
  revisionId?: string,
  citationId?: string,
  enabled = false
) {
  return useQuery({
    queryKey: queryKeys.citationScholar(libraryId ?? "", revisionId ?? "", citationId ?? ""),
    queryFn: () =>
      apiClient.getCitationScholar(libraryId ?? "", revisionId ?? "", citationId ?? ""),
    enabled: Boolean(enabled && libraryId && revisionId && citationId),
    staleTime: 24 * 60 * 60 * 1000,
    retry: false
  });
}

export function useExportArticle(libraryId?: string, revisionId?: string) {
  return useMutation({
    mutationFn: (payload: ArticleExportRequest) =>
      apiClient.exportArticle(libraryId ?? "", revisionId ?? "", payload)
  });
}

export function useSaveObsidianClip(libraryId?: string, revisionId?: string) {
  return useMutation({
    mutationFn: (payload: ObsidianClipRequest) =>
      apiClient.saveObsidianClip(libraryId ?? "", revisionId ?? "", payload)
  });
}

export function useImportCitationArxiv(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      citationId,
      payload
    }: {
      citationId: string;
      payload: CitationLibraryImportRequest;
    }) => apiClient.importCitationArxiv(libraryId ?? "", revisionId ?? "", citationId, payload),
    onSuccess: () => {
      if (libraryId) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useArticleEmbeddingStatus(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.articleEmbeddingStatus(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getArticleEmbeddingStatus(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    refetchInterval: 5000,
    retry: false
  });
}

export function useBuildArticleEmbeddings(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: EmbedArticleRequest) =>
      apiClient.buildArticleEmbeddings(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleEmbeddingStatus(libraryId, revisionId)
        });
      }
    }
  });
}

export function useQueueArticleEmbeddings(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: EmbedArticleRequest) =>
      apiClient.queueArticleEmbeddings(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleEmbeddingStatus(libraryId, revisionId)
        });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useArticleTranslations(
  libraryId?: string,
  revisionId?: string,
  targetLanguage = "zh-CN"
) {
  return useQuery({
    queryKey: queryKeys.articleTranslations(libraryId ?? "", revisionId ?? "", targetLanguage),
    queryFn: () =>
      apiClient.getArticleTranslations(libraryId ?? "", revisionId ?? "", targetLanguage),
    enabled: Boolean(libraryId && revisionId),
    refetchInterval: 5000,
    retry: false
  });
}

export function useTranslateArticle(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: TranslationBatchRequest) =>
      apiClient.translateArticle(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (_data, payload) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleTranslations(libraryId, revisionId, payload.target_language)
        });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useTranslateLibraryMissing(libraryId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: TranslationBatchRequest) =>
      apiClient.translateLibraryMissing(libraryId ?? "", payload),
    onSuccess: () => {
      if (libraryId) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useTranslateBlock(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ blockUid, payload }: { blockUid: string; payload: TranslationBatchRequest }) =>
      apiClient.translateBlock(libraryId ?? "", revisionId ?? "", blockUid, payload),
    onSuccess: (_data, variables) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleTranslations(
            libraryId,
            revisionId,
            variables.payload.target_language
          )
        });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useSelectTranslationVariant(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ variantId }: { variantId: string; targetLanguage: string }) =>
      apiClient.selectTranslationVariant(libraryId ?? "", revisionId ?? "", variantId),
    onSuccess: (_data, variables) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleTranslations(libraryId, revisionId, variables.targetLanguage)
        });
      }
    }
  });
}

export function useTranslationMemory(
  libraryId?: string,
  revisionId?: string,
  blockUid?: string | null,
  targetLanguage = "zh-CN",
  glossaryVersion?: string | null
) {
  return useQuery({
    queryKey: queryKeys.translationMemory(
      libraryId ?? "",
      revisionId ?? "",
      blockUid ?? "",
      targetLanguage,
      glossaryVersion
    ),
    queryFn: () =>
      apiClient.getTranslationMemory(
        libraryId ?? "",
        revisionId ?? "",
        blockUid ?? "",
        targetLanguage,
        glossaryVersion
      ),
    enabled: Boolean(libraryId && revisionId && blockUid),
    retry: false
  });
}

export function useTranslationMemoryEntries(
  targetLanguage = "zh-CN",
  reviewStatus?: TranslationMemoryReviewStatus | null,
  reuseEnabled?: boolean | null
) {
  return useQuery({
    queryKey: queryKeys.translationMemoryReview(targetLanguage, reviewStatus, reuseEnabled),
    queryFn: () =>
      apiClient.listTranslationMemory({
        targetLanguage,
        reviewStatus,
        reuseEnabled,
        limit: 100
      }),
    retry: false
  });
}

export function useUpdateTranslationMemoryEntry(targetLanguage = "zh-CN") {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      entryId,
      payload
    }: {
      entryId: string;
      payload: TranslationMemoryEntryUpdate;
    }) => apiClient.updateTranslationMemoryEntry(entryId, payload),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["translation-memory-review"] });
      void queryClient.invalidateQueries({
        queryKey: queryKeys.translationMemoryReview(targetLanguage)
      });
    }
  });
}

export function useArticleGlossary(
  libraryId?: string,
  revisionId?: string,
  targetLanguage = "zh-CN"
) {
  return useQuery({
    queryKey: queryKeys.articleGlossary(libraryId ?? "", revisionId ?? "", targetLanguage),
    queryFn: () => apiClient.getArticleGlossary(libraryId ?? "", revisionId ?? "", targetLanguage),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useExtractGlossary(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: GlossaryExtractionRequest) =>
      apiClient.extractGlossary(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (_data, payload) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleGlossary(libraryId, revisionId, payload.target_language)
        });
      }
    }
  });
}

export function useCreateGlossaryTerm(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: GlossaryTermCreate) =>
      apiClient.createGlossaryTerm(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (term) => {
      const targetLanguage = term.metadata?.target_language;
      if (libraryId && revisionId && typeof targetLanguage === "string") {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleGlossary(libraryId, revisionId, targetLanguage)
        });
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleTranslations(libraryId, revisionId, targetLanguage)
        });
      }
    }
  });
}

export function useUpdateGlossaryTerm(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ termId, payload }: { termId: string; payload: GlossaryTermUpdate }) =>
      apiClient.updateGlossaryTerm(libraryId ?? "", revisionId ?? "", termId, payload),
    onSuccess: (term) => {
      const targetLanguage = term.metadata?.target_language;
      if (libraryId && revisionId && typeof targetLanguage === "string") {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleGlossary(libraryId, revisionId, targetLanguage)
        });
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleTranslations(libraryId, revisionId, targetLanguage)
        });
      }
    }
  });
}

export function useArticleReaderCards(
  libraryId?: string,
  revisionId?: string,
  targetLanguage = "zh-CN"
) {
  return useQuery({
    queryKey: queryKeys.articleReaderCards(libraryId ?? "", revisionId ?? "", targetLanguage),
    queryFn: () => apiClient.getReaderCards(libraryId ?? "", revisionId ?? "", targetLanguage),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useCreateReaderCard(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ReaderCardCreate) =>
      apiClient.createReaderCard(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (card) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleReaderCards(libraryId, revisionId, card.target_language)
        });
      }
    }
  });
}

export function useUpdateReaderCard(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ cardId, payload }: { cardId: string; payload: ReaderCardUpdate }) =>
      apiClient.updateReaderCard(libraryId ?? "", revisionId ?? "", cardId, payload),
    onSuccess: (card) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleReaderCards(libraryId, revisionId, card.target_language)
        });
      }
    }
  });
}

export function useDeleteReaderCard(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (cardId: string) =>
      apiClient.deleteReaderCard(libraryId ?? "", revisionId ?? "", cardId),
    onSuccess: (card) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleReaderCards(libraryId, revisionId, card.target_language)
        });
      }
    }
  });
}

export function useExtractReaderCards(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ReaderCardExtractionRequest) =>
      apiClient.extractReaderCards(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (result) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleReaderCards(libraryId, revisionId, result.target_language)
        });
      }
    }
  });
}

export function useGenerateReaderCard(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ReaderCardGenerationRequest) =>
      apiClient.generateReaderCard(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (result) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleReaderCards(libraryId, revisionId, result.card.target_language)
        });
      }
    }
  });
}

export function useExportReaderCardsToObsidian(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ReaderCardObsidianExportRequest) =>
      apiClient.exportReaderCardsToObsidian(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: (_result, payload) => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleReaderCards(libraryId, revisionId, payload.target_language)
        });
      }
    }
  });
}

export function useArticleChat(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.articleChat(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getArticleChat(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useAskArticleQuestion(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ChatAskRequest) =>
      apiClient.askArticleQuestion(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleChat(libraryId, revisionId)
        });
      }
    }
  });
}

export function useAskArticleQuestionStream(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      payload,
      onMessage
    }: {
      payload: ChatAskRequest;
      onMessage: (message: SseMessage) => void;
    }) => apiClient.askArticleQuestionStream(libraryId ?? "", revisionId ?? "", payload, onMessage),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.articleChat(libraryId, revisionId)
        });
      }
    }
  });
}

export function useNoteTemplates(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.noteTemplates(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getNoteTemplates(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useCreateNoteTemplate(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: NoteTemplateCreate) =>
      apiClient.createNoteTemplate(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.noteTemplates(libraryId, revisionId)
        });
      }
    }
  });
}

export function useUpdateNoteTemplate(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ templateId, payload }: { templateId: string; payload: NoteTemplateUpdate }) =>
      apiClient.updateNoteTemplate(libraryId ?? "", revisionId ?? "", templateId, payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.noteTemplates(libraryId, revisionId)
        });
      }
    }
  });
}

export function useNotePatches(libraryId?: string, revisionId?: string) {
  return useQuery({
    queryKey: queryKeys.notePatches(libraryId ?? "", revisionId ?? ""),
    queryFn: () => apiClient.getNotePatches(libraryId ?? "", revisionId ?? ""),
    enabled: Boolean(libraryId && revisionId),
    retry: false
  });
}

export function useGenerateNotePatch(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: NotePatchGenerateRequest) =>
      apiClient.generateNotePatch(libraryId ?? "", revisionId ?? "", payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.notePatches(libraryId, revisionId)
        });
      }
    }
  });
}

export function useCreateNotePatchFromChat(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ messageId, payload }: { messageId: string; payload: ChatToNotePatchRequest }) =>
      apiClient.createNotePatchFromChat(libraryId ?? "", revisionId ?? "", messageId, payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.notePatches(libraryId, revisionId)
        });
      }
    }
  });
}

export function useUpdateNotePatch(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ patchId, payload }: { patchId: string; payload: NotePatchUpdate }) =>
      apiClient.updateNotePatch(libraryId ?? "", revisionId ?? "", patchId, payload),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.notePatches(libraryId, revisionId)
        });
      }
    }
  });
}

export function useAcceptNotePatch(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (patchId: string) =>
      apiClient.acceptNotePatch(libraryId ?? "", revisionId ?? "", patchId),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.notePatches(libraryId, revisionId)
        });
      }
    }
  });
}

export function useRejectNotePatch(libraryId?: string, revisionId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (patchId: string) =>
      apiClient.rejectNotePatch(libraryId ?? "", revisionId ?? "", patchId),
    onSuccess: () => {
      if (libraryId && revisionId) {
        void queryClient.invalidateQueries({
          queryKey: queryKeys.notePatches(libraryId, revisionId)
        });
      }
    }
  });
}

export function useImportArxiv(libraryId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: ImportArxivRequest) => apiClient.importArxiv(libraryId ?? "", payload),
    onSuccess: () => {
      if (libraryId) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useImportLocalFile(libraryId?: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (payload: { file: File; kind: ImportLocalKind; parseAfterImport: boolean }) =>
      apiClient.importLocalFile(libraryId ?? "", payload),
    onSuccess: () => {
      if (libraryId) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.articles(libraryId) });
      }
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    }
  });
}

export function useJobSummary() {
  return useQuery({
    queryKey: queryKeys.jobSummary,
    queryFn: apiClient.getJobSummary,
    refetchInterval: 3000,
    retry: false
  });
}

export function useJobs(options: { limit?: number; enabled?: boolean } = {}) {
  const limit = options.limit ?? 120;
  return useQuery({
    queryKey: queryKeys.jobList(limit),
    queryFn: () => apiClient.listJobs(limit),
    enabled: options.enabled ?? true,
    refetchInterval: options.enabled === false ? false : 5000,
    retry: false
  });
}

export function useJobAction(action: "pause" | "resume" | "cancel") {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (jobId: string) => {
      if (action === "pause") return apiClient.pauseJob(jobId);
      if (action === "resume") return apiClient.resumeJob(jobId);
      return apiClient.cancelJob(jobId);
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.jobs })
  });
}

export function useClearJobs() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: apiClient.clearJobs,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: queryKeys.jobs })
  });
}

export function useJobEvents(enabled = true) {
  const queryClient = useQueryClient();
  useEffect(() => {
    if (!enabled) return undefined;
    if (typeof EventSource === "undefined") return undefined;
    const source = new EventSource(`${API_BASE_URL}/events`);
    source.addEventListener("jobs", () => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    });
    return () => source.close();
  }, [enabled, queryClient]);
}
