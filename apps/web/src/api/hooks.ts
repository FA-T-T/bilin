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
  NotePatchGenerateRequest,
  NotePatchUpdate,
  NoteTemplateCreate,
  NoteTemplateUpdate,
  ObsidianClipRequest,
  ProviderModelDiscoveryRequest,
  ProviderProfileCreate,
  ProviderProfileUpdate,
  TranslationBatchRequest,
  TranslationMemoryEntryUpdate,
  TranslationMemoryReviewStatus
} from "./types";

export const queryKeys = {
  doctor: ["doctor"] as const,
  providers: ["providers"] as const,
  libraries: ["libraries"] as const,
  library: (libraryId: string) => ["library", libraryId] as const,
  articles: (libraryId: string) => ["articles", libraryId] as const,
  articleDocument: (libraryId: string, revisionId: string) =>
    ["article-document", libraryId, revisionId] as const,
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
  articleChat: (libraryId: string, revisionId: string) =>
    ["article-chat", libraryId, revisionId] as const,
  noteTemplates: (libraryId: string, revisionId: string) =>
    ["note-templates", libraryId, revisionId] as const,
  notePatches: (libraryId: string, revisionId: string) =>
    ["note-patches", libraryId, revisionId] as const,
  jobs: ["jobs"] as const
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

export function useArticles(libraryId?: string) {
  return useQuery({
    queryKey: queryKeys.articles(libraryId ?? ""),
    queryFn: () => apiClient.listArticles(libraryId ?? ""),
    enabled: Boolean(libraryId),
    refetchInterval: 5000,
    retry: false
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

export function useJobs() {
  return useQuery({
    queryKey: queryKeys.jobs,
    queryFn: apiClient.listJobs,
    refetchInterval: 5000,
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

export function useJobEvents() {
  const queryClient = useQueryClient();
  useEffect(() => {
    if (typeof EventSource === "undefined") return undefined;
    const source = new EventSource(`${API_BASE_URL}/events`);
    source.addEventListener("jobs", () => {
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    });
    return () => source.close();
  }, [queryClient]);
}
