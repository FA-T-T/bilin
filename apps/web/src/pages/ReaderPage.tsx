import {
  Alert,
  ActionIcon,
  Badge,
  Button,
  Checkbox,
  Collapse,
  Divider,
  Group,
  Loader,
  Modal,
  Select,
  Stack,
  Tabs,
  Text,
  Textarea,
  TextInput,
  Title,
  useComputedColorScheme,
  useMantineColorScheme
} from "@mantine/core";
import {
  BookOpenText,
  BookMarked,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Check,
  Columns2,
  Download,
  FileText,
  Languages,
  ListTree,
  MessageSquare,
  Moon,
  RefreshCw,
  Search,
  Send,
  Sparkles,
  StickyNote,
  Sun,
  TerminalSquare,
  Type,
  X
} from "lucide-react";
import { type CSSProperties, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { API_BASE_URL } from "../api/client";
import {
  useArticleCitations,
  useArticleGlossary,
  useArticleChat,
  useArticleDocument,
  useArticleTranslations,
  useAskArticleQuestion,
  useAskArticleQuestionStream,
  useCreateNotePatchFromChat,
  useCreateNoteTemplate,
  useCreateGlossaryTerm,
  useCreateReaderCard,
  useDeleteReaderCard,
  useExportArticle,
  useExportReaderCardsToObsidian,
  useExtractGlossary,
  useExtractReaderCards,
  useGenerateReaderCard,
  useGenerateNotePatch,
  useImportCitationArxiv,
  useNotePatches,
  useNoteTemplates,
  useProviders,
  useArticleReaderCards,
  useRejectNotePatch,
  useSaveObsidianClip,
  useSelectTranslationVariant,
  useTranslateArticle,
  useTranslateBlock,
  useUpdateGlossaryTerm,
  useUpdateReaderCard,
  useUpdateNotePatch
} from "../api/hooks";
import type {
  ArticleDocument,
  ArticleExportKind,
  ArticleExportResult,
  AssetRecord,
  ChatMessage,
  CitationEntry,
  DocumentBlock,
  ExternalCitation,
  GlossaryTerm,
  NotePatch,
  NotePatchUpdate,
  NoteTemplate,
  ReaderCard,
  RetrievedBlock,
  TranslationVariant
} from "../api/types";
import {
  ReaderBlock,
  type CitationImportMode,
  type CitationLookup,
  type ReaderBlockColor,
  type ReaderAssetFile,
  type ReferenceTargets
} from "../components/ReaderBlock";
import { ReaderBlockList } from "../components/ReaderBlockList";
import { ReaderPreferencesPanel } from "../components/ReaderPreferencesPanel";
import type { ReaderToolbarActionId } from "../components/readerToolbarActions";
import { activeGlossaryTerms, applyGlossaryToMarkdown } from "../glossary";
import { useT, type MessageKey } from "../i18n";
import { TRANSLATION_TARGET_LOCALES } from "../product";
import { type ReaderPreferences, type ReaderViewMode, useUiStore } from "../state/ui";

const emptyReaderAssetFiles: ReaderAssetFile[] = [];
const emptyCitationLookup: CitationLookup = {};

interface ReaderCardDraft {
  cardId?: string;
  blockUid: string;
  anchorText: string;
  title: string;
  bodyMarkdown: string;
}

type ReaderToolTab = "translate" | "glossary" | "chat" | "notes" | "export";

export function ReaderPage() {
  const t = useT();
  const { articleId } = useParams();
  const navigate = useNavigate();
  const { setColorScheme } = useMantineColorScheme();
  const colorScheme = useComputedColorScheme("light", { getInitialValueInEffect: true });
  const [searchParams] = useSearchParams();
  const libraryId = searchParams.get("libraryId") ?? undefined;
  const hasArticleContext = Boolean(libraryId && articleId);
  const viewMode = useUiStore((state) => state.readerViewMode);
  const setReaderViewMode = useUiStore((state) => state.setReaderViewMode);
  const openTaskDrawer = useUiStore((state) => state.openTaskDrawer);
  const readerPreferences = useUiStore((state) => state.readerPreferences);
  const readerFeaturePreferences = useUiStore((state) => state.readerFeaturePreferences);
  const setReaderFeaturePreference = useUiStore((state) => state.setReaderFeaturePreference);
  const targetLanguage = useUiStore((state) => state.translationTargetLanguage);
  const setTargetLanguage = useUiStore((state) => state.setTranslationTargetLanguage);
  const autoTranslateOnLanguageSwitch = useUiStore((state) => state.autoTranslateOnLanguageSwitch);
  const setAutoTranslateOnLanguageSwitch = useUiStore(
    (state) => state.setAutoTranslateOnLanguageSwitch
  );
  const providers = useProviders();
  const [selectedProviderId, setSelectedProviderId] = useState<string | null>(null);
  const [chatBlockUid, setChatBlockUid] = useState<string | null>(null);
  const [question, setQuestion] = useState("");
  const [nativeSearch, setNativeSearch] = useState(false);
  const [selectedTemplateId, setSelectedTemplateId] = useState("deep_reading");
  const [exportKind, setExportKind] = useState<ArticleExportKind>("bilingual_markdown");
  const [inspectedBlock, setInspectedBlock] = useState<DocumentBlock | null>(null);
  const [retranslationBlock, setRetranslationBlock] = useState<DocumentBlock | null>(null);
  const [customRetranslationPrompt, setCustomRetranslationPrompt] = useState("");
  const [variantOverrides, setVariantOverrides] = useState<Record<string, string>>({});
  const [streamingAnswer, setStreamingAnswer] = useState("");
  const [streamingCitedBlocks, setStreamingCitedBlocks] = useState<RetrievedBlock[]>([]);
  const [readerActionMessage, setReaderActionMessage] = useState<string | null>(null);
  const [activeBlockUid, setActiveBlockUid] = useState<string | null>(null);
  const [forcedBlockUid, setForcedBlockUid] = useState<string | null>(null);
  const [pendingNavigationBlockUid, setPendingNavigationBlockUid] = useState<string | null>(null);
  const [readerSearchQuery, setReaderSearchQuery] = useState("");
  const [readerSearchCursor, setReaderSearchCursor] = useState(0);
  const [blockColors, setBlockColors] = useState<Record<string, ReaderBlockColor>>({});
  const [chaptersOpen, setChaptersOpen] = useState(false);
  const [readerPreferencesOpen, setReaderPreferencesOpen] = useState(false);
  const [termWikiEnabled, setTermWikiEnabled] = useState(false);
  const [readerToolTab, setReaderToolTab] = useState<ReaderToolTab>("translate");
  const [readerWorkbenchOpen, setReaderWorkbenchOpen] = useState(false);
  const [readerModeMenuOpen, setReaderModeMenuOpen] = useState(false);
  const [readerToolMenuOpen, setReaderToolMenuOpen] = useState(false);
  const [expandedReaderCardByBlock, setExpandedReaderCardByBlock] = useState<
    Record<string, string | null>
  >({});
  const [quickAskBlockUid, setQuickAskBlockUid] = useState<string | null>(null);
  const [readerCardDraft, setReaderCardDraft] = useState<ReaderCardDraft | null>(null);
  const readerSearchInputRef = useRef<HTMLInputElement | null>(null);
  const lastExportDownloadKey = useRef<string | null>(null);
  const lastInitialHashNavigation = useRef<string | null>(null);
  const previousTargetLanguage = useRef(targetLanguage);
  const document = useArticleDocument(libraryId, articleId);
  const citations = useArticleCitations(libraryId, articleId);
  const exportArticle = useExportArticle(libraryId, articleId);
  const saveObsidianClip = useSaveObsidianClip(libraryId, articleId);
  const importCitationArxiv = useImportCitationArxiv(libraryId, articleId);
  const exportResult = exportArticle.data;
  const currentExportDownloadUrl = exportDownloadUrl(libraryId, articleId, exportResult);
  const translations = useArticleTranslations(libraryId, articleId, targetLanguage);
  const glossary = useArticleGlossary(libraryId, articleId, targetLanguage);
  const readerCards = useArticleReaderCards(libraryId, articleId, targetLanguage);
  const chat = useArticleChat(libraryId, articleId);
  const noteTemplates = useNoteTemplates(libraryId, articleId);
  const notePatches = useNotePatches(libraryId, articleId);
  const askBlockQuestion = useAskArticleQuestion(libraryId, articleId);
  const askQuestion = useAskArticleQuestionStream(libraryId, articleId);
  const generateNotePatch = useGenerateNotePatch(libraryId, articleId);
  const createNotePatchFromChat = useCreateNotePatchFromChat(libraryId, articleId);
  const createNoteTemplate = useCreateNoteTemplate(libraryId, articleId);
  const updateNotePatch = useUpdateNotePatch(libraryId, articleId);
  const rejectNotePatch = useRejectNotePatch(libraryId, articleId);
  const extractGlossary = useExtractGlossary(libraryId, articleId);
  const createGlossaryTerm = useCreateGlossaryTerm(libraryId, articleId);
  const updateGlossaryTerm = useUpdateGlossaryTerm(libraryId, articleId);
  const createReaderCard = useCreateReaderCard(libraryId, articleId);
  const updateReaderCard = useUpdateReaderCard(libraryId, articleId);
  const deleteReaderCard = useDeleteReaderCard(libraryId, articleId);
  const extractReaderCards = useExtractReaderCards(libraryId, articleId);
  const generateReaderCard = useGenerateReaderCard(libraryId, articleId);
  const exportReaderCards = useExportReaderCardsToObsidian(libraryId, articleId);
  const translateArticle = useTranslateArticle(libraryId, articleId);
  const translateBlock = useTranslateBlock(libraryId, articleId);
  const selectTranslationVariant = useSelectTranslationVariant(libraryId, articleId);
  const blocks = useMemo(() => document.data?.blocks ?? [], [document.data?.blocks]);
  const assets = useMemo(() => document.data?.assets ?? [], [document.data?.assets]);
  const title = articleTitle(document.data, t);
  const navBlocks = blocks.filter((block) => block.block_type === "section");
  const activeNavBlockUid = useMemo(
    () => navBlockUidForActiveBlock(blocks, navBlocks, activeBlockUid),
    [activeBlockUid, blocks, navBlocks]
  );
  const activeBlockIndex = useMemo(() => {
    if (!activeBlockUid) return blocks.length > 0 ? 0 : -1;
    const index = blocks.findIndex((block) => block.block_uid === activeBlockUid);
    return index >= 0 ? index : blocks.length > 0 ? 0 : -1;
  }, [activeBlockUid, blocks]);
  const activeBlockOrdinal = activeBlockIndex >= 0 ? activeBlockIndex + 1 : 0;
  const readerProgress =
    blocks.length > 0 ? Math.round((activeBlockOrdinal / blocks.length) * 100) : 0;
  const activeChapterLabel = useMemo(() => {
    const activeChapter = navBlocks.find((block) => block.block_uid === activeNavBlockUid);
    return activeChapter ? chapterTitle(activeChapter) : t("reader.noChapter");
  }, [activeNavBlockUid, navBlocks, t]);
  const referenceTargets = useMemo(() => referenceTargetsForBlocks(blocks), [blocks]);
  const citationLookup = useMemo(
    () => citationLookupForEntries(citations.data?.citations ?? []),
    [citations.data?.citations]
  );
  const effectiveCitationLookup = readerFeaturePreferences.citationPreviewEnabled
    ? citationLookup
    : emptyCitationLookup;

  const assetById = useMemo(
    () => new Map(assets.map((asset) => [asset.asset_id, asset] as const)),
    [assets]
  );
  const assetUrlByAssetId = useMemo(() => {
    const map = new Map<string, string | undefined>();
    for (const asset of assets) {
      map.set(asset.asset_id, assetUrl(libraryId, articleId, asset));
    }
    return map;
  }, [articleId, assets, libraryId]);
  const assetFileUrlsByAssetId = useMemo(() => {
    const map = new Map<string, ReaderAssetFile[]>();
    for (const asset of assets) {
      map.set(asset.asset_id, assetFileUrls(libraryId, articleId, asset));
    }
    return map;
  }, [articleId, assets, libraryId]);
  const variantsByBlockUid = useMemo(() => {
    const map = new Map<string, TranslationVariant[]>();
    for (const variant of translations.data?.variants ?? []) {
      if (variant.validation_status !== "ok") continue;
      const blockUid = variant.metadata?.block_uid;
      if (typeof blockUid !== "string") continue;
      const variants = map.get(blockUid) ?? [];
      variants.push(variant);
      map.set(blockUid, variants);
    }
    for (const variants of map.values()) {
      variants.sort((left, right) => {
        if (left.is_default !== right.is_default) return left.is_default ? -1 : 1;
        return String(right.updated_at).localeCompare(String(left.updated_at));
      });
    }
    return map;
  }, [translations.data?.variants]);
  const selectedVariantByBlockUid = useMemo(() => {
    const map = new Map<string, TranslationVariant>();
    for (const [blockUid, variants] of variantsByBlockUid.entries()) {
      const override = variants.find((variant) => variant.id === variantOverrides[blockUid]);
      const selected = override ?? variants.find((variant) => variant.is_default) ?? variants[0];
      if (selected) {
        map.set(blockUid, selected);
      }
    }
    return map;
  }, [variantOverrides, variantsByBlockUid]);
  const translationVariantOptionsByBlockUid = useMemo(() => {
    const map = new Map<string, { value: string; label: string }[]>();
    for (const [blockUid, variants] of variantsByBlockUid.entries()) {
      map.set(blockUid, translationVariantOptions(variants));
    }
    return map;
  }, [variantsByBlockUid]);
  const translationByBlockUid = useMemo(() => {
    const map = new Map<string, string>();
    const terms = readerFeaturePreferences.glossaryReplacementEnabled
      ? activeGlossaryTerms(glossary.data?.terms ?? [])
      : [];
    for (const [blockUid, variant] of selectedVariantByBlockUid.entries()) {
      map.set(blockUid, applyGlossaryToMarkdown(variant.raw_markdown, terms));
    }
    return map;
  }, [
    glossary.data?.terms,
    readerFeaturePreferences.glossaryReplacementEnabled,
    selectedVariantByBlockUid
  ]);
  const readerCardsByBlockUid = useMemo(() => {
    const map = new Map<string, ReaderCard[]>();
    for (const card of readerCards.data?.cards ?? []) {
      if (card.status === "archived") continue;
      const cards = map.get(card.anchor_block_uid) ?? [];
      cards.push(card);
      map.set(card.anchor_block_uid, cards);
    }
    for (const cards of map.values()) {
      cards.sort((left, right) => {
        const statusOrder = cardStatusOrder(left.status) - cardStatusOrder(right.status);
        if (statusOrder !== 0) return statusOrder;
        return left.title.localeCompare(right.title);
      });
    }
    return map;
  }, [readerCards.data?.cards]);
  const termCardsVisible =
    readerFeaturePreferences.termCardsEnabled &&
    hasArticleContext &&
    (termWikiEnabled || readerCardsByBlockUid.size > 0);
  const blockTextForPlaceholder = useCallback(
    (block: DocumentBlock) =>
      viewMode === "translation"
        ? (translationByBlockUid.get(block.block_uid) ?? block.source_markdown)
        : block.source_markdown,
    [translationByBlockUid, viewMode]
  );
  const readerSearchIndex = useMemo(
    () => buildReaderSearchIndex(blocks, translationByBlockUid),
    [blocks, translationByBlockUid]
  );
  const readerSearchMatches = useMemo(
    () => searchReaderIndex(readerSearchIndex, readerSearchQuery),
    [readerSearchIndex, readerSearchQuery]
  );
  const currentSearchMatch =
    readerSearchMatches.length > 0
      ? readerSearchMatches[Math.min(readerSearchCursor, readerSearchMatches.length - 1)]
      : null;
  const currentSearchBlockUid = currentSearchMatch?.blockUid ?? null;
  const affectedBlockUids = useMemo(
    () => new Set(glossary.data?.affected_block_uids ?? []),
    [glossary.data?.affected_block_uids]
  );
  const selectedProvider = (providers.data ?? []).find(
    (provider) => provider.id === selectedProviderId
  );
  const readerPreferenceStyle = useMemo(
    () => readerStyleForPreferences(readerPreferences),
    [readerPreferences]
  );
  const readerModeOptions = useMemo(
    () => [
      {
        label: t("reader.study"),
        value: "study" as ReaderViewMode,
        icon: <BookOpenText size={14} />
      },
      {
        label: t("reader.bilingual"),
        value: "bilingual" as ReaderViewMode,
        icon: <Columns2 size={14} />
      },
      {
        label: t("reader.translationView"),
        value: "translation" as ReaderViewMode,
        icon: <Languages size={14} />
      },
      {
        label: t("reader.sourceView"),
        value: "source" as ReaderViewMode,
        icon: <FileText size={14} />
      }
    ],
    [t]
  );
  const currentReaderModeLabel =
    readerModeOptions.find((option) => option.value === viewMode)?.label ?? t("reader.modeMenu");
  const currentReaderToolLabel = useMemo(() => {
    if (readerToolTab === "translate") return t("reader.translate");
    if (readerToolTab === "glossary") return t("reader.terms");
    if (readerToolTab === "chat") return t("reader.ask");
    if (readerToolTab === "notes") return t("reader.notes");
    return t("reader.export");
  }, [readerToolTab, t]);

  useEffect(() => {
    if (!selectedProviderId && providers.data?.[0]) {
      setSelectedProviderId(providers.data[0].id);
    }
  }, [providers.data, selectedProviderId]);

  useEffect(() => {
    if (!termWikiEnabled || !readerFeaturePreferences.termCardsEnabled) return;
    setChaptersOpen(false);
    setReaderPreferencesOpen(false);
  }, [readerFeaturePreferences.termCardsEnabled, termWikiEnabled]);

  useEffect(() => {
    const templates = noteTemplates.data ?? [];
    if (templates.length > 0 && !templates.some((template) => template.id === selectedTemplateId)) {
      setSelectedTemplateId(templates[0].id);
    }
  }, [noteTemplates.data, selectedTemplateId]);

  useEffect(() => {
    setVariantOverrides({});
    setForcedBlockUid(null);
    setPendingNavigationBlockUid(null);
    setReaderSearchQuery("");
    setReaderSearchCursor(0);
    setExpandedReaderCardByBlock({});
    lastInitialHashNavigation.current = null;
  }, [articleId, targetLanguage]);

  useEffect(() => {
    if (blocks.length === 0 || typeof window === "undefined") return;
    const hashBlockUid = decodeURIComponent(window.location.hash.replace(/^#/, ""));
    if (!hashBlockUid) return;
    if (!blocks.some((block) => block.block_uid === hashBlockUid)) return;
    const navigationKey = `${articleId ?? "mock"}:${hashBlockUid}`;
    if (lastInitialHashNavigation.current === navigationKey) return;
    lastInitialHashNavigation.current = navigationKey;
    setForcedBlockUid(hashBlockUid);
    setActiveBlockUid(hashBlockUid);
    setPendingNavigationBlockUid(hashBlockUid);
  }, [articleId, blocks]);

  useEffect(() => {
    setReaderSearchCursor(0);
  }, [readerSearchQuery]);

  useEffect(() => {
    if (readerSearchCursor < readerSearchMatches.length) return;
    setReaderSearchCursor(Math.max(0, readerSearchMatches.length - 1));
  }, [readerSearchCursor, readerSearchMatches.length]);

  useEffect(() => {
    if (!pendingNavigationBlockUid) return undefined;
    let frame = 0;
    frame = requestAnimationFrame(() => {
      globalThis.document?.getElementById(pendingNavigationBlockUid)?.scrollIntoView({
        block: "start",
        behavior: "smooth"
      });
      setPendingNavigationBlockUid(null);
    });
    return () => cancelAnimationFrame(frame);
  }, [pendingNavigationBlockUid, forcedBlockUid]);

  useEffect(() => {
    if (!exportResult || !currentExportDownloadUrl) return;
    const downloadKey = `${exportResult.file_name}:${exportResult.created_at}:${exportResult.bytes_written}`;
    if (lastExportDownloadKey.current === downloadKey) return;
    lastExportDownloadKey.current = downloadKey;
    triggerBrowserDownload(currentExportDownloadUrl, exportResult.file_name);
  }, [currentExportDownloadUrl, exportResult]);

  useEffect(() => {
    if (!libraryId || !articleId) {
      setBlockColors({});
      return;
    }
    try {
      const raw = globalThis.localStorage?.getItem(blockColorStorageKey(libraryId, articleId));
      setBlockColors(raw ? parseStoredBlockColors(raw) : {});
    } catch {
      setBlockColors({});
    }
  }, [articleId, libraryId]);

  useEffect(() => {
    if (blocks.length === 0) {
      setActiveBlockUid(null);
      return;
    }
    if (!activeBlockUid || !blocks.some((block) => block.block_uid === activeBlockUid)) {
      setActiveBlockUid(blocks[0].block_uid);
    }
  }, [activeBlockUid, blocks]);

  const translationPayload = useMemo(
    () => ({
      target_language: targetLanguage,
      provider_profile_id: selectedProviderId ?? "",
      model: selectedProvider?.default_model ?? null,
      glossary_version: glossary.data?.active_version ?? null,
      force: false,
      block_uids: null,
      custom_prompt: null
    }),
    [
      glossary.data?.active_version,
      selectedProvider?.default_model,
      selectedProviderId,
      targetLanguage
    ]
  );

  const navigateToBlock = useCallback((blockUid: string) => {
    setForcedBlockUid(blockUid);
    setActiveBlockUid(blockUid);
    setPendingNavigationBlockUid(blockUid);
    if (typeof window !== "undefined") {
      const nextUrl = `${window.location.pathname}${window.location.search}#${encodeURIComponent(blockUid)}`;
      window.history.replaceState(null, "", nextUrl);
    }
  }, []);

  const moveReaderSearch = useCallback(
    (delta: number) => {
      if (readerSearchMatches.length === 0) return;
      const nextIndex =
        (readerSearchCursor + delta + readerSearchMatches.length) % readerSearchMatches.length;
      setReaderSearchCursor(nextIndex);
      navigateToBlock(readerSearchMatches[nextIndex].blockUid);
    },
    [navigateToBlock, readerSearchCursor, readerSearchMatches]
  );

  const jumpToCurrentReaderSearchMatch = useCallback(() => {
    if (!currentSearchMatch) return;
    navigateToBlock(currentSearchMatch.blockUid);
  }, [currentSearchMatch, navigateToBlock]);

  const clearReaderSearch = useCallback(() => {
    setReaderSearchQuery("");
    setReaderSearchCursor(0);
    setForcedBlockUid(null);
  }, []);

  const openCurrentLibrary = useCallback(() => {
    navigate(libraryId ? `/libraries/${libraryId}` : "/");
  }, [libraryId, navigate]);

  const openReaderTool = useCallback((tab: ReaderToolTab) => {
    setReaderToolTab(tab);
    setReaderWorkbenchOpen(true);
    setReaderToolMenuOpen(false);
  }, []);

  const openTaskDrawerForBackgroundWork = useCallback(() => {
    if (readerFeaturePreferences.taskNotificationsEnabled) {
      openTaskDrawer();
    }
  }, [openTaskDrawer, readerFeaturePreferences.taskNotificationsEnabled]);

  const handleActiveBlockChange = useCallback((blockUid: string) => {
    setActiveBlockUid((current) => (current === blockUid ? current : blockUid));
  }, []);

  const queueArticleTranslation = useCallback(() => {
    if (!selectedProviderId) return;
    translateArticle.mutate(translationPayload);
  }, [selectedProviderId, translateArticle, translationPayload]);

  useEffect(() => {
    if (previousTargetLanguage.current === targetLanguage) return;
    previousTargetLanguage.current = targetLanguage;
    setVariantOverrides({});
    setReaderActionMessage(t("reader.languageSwitched", { language: targetLanguage }));
    if (!autoTranslateOnLanguageSwitch || !hasArticleContext || blocks.length === 0) return;
    if (!selectedProviderId) {
      setReaderActionMessage(t("reader.autoTranslateNeedsProvider", { language: targetLanguage }));
      return;
    }
    translateArticle.mutate(translationPayload, {
      onSuccess: (result) => {
        setReaderActionMessage(
          t("reader.languageSwitchTranslationQueued", {
            language: targetLanguage,
            jobs: result.jobs_created,
            cached: result.cached_blocks,
            existing: result.existing_jobs
          })
        );
        if (result.jobs_created > 0 || result.existing_jobs > 0) {
          openTaskDrawerForBackgroundWork();
        }
      },
      onError: () => setReaderActionMessage(t("reader.translationQueueError"))
    });
  }, [
    autoTranslateOnLanguageSwitch,
    blocks.length,
    hasArticleContext,
    openTaskDrawerForBackgroundWork,
    selectedProviderId,
    t,
    targetLanguage,
    translateArticle,
    translationPayload
  ]);

  const importCitationToLibrary = useCallback(
    (citation: CitationEntry, mode: CitationImportMode) => {
      const translateAfterImport = mode === "add-and-translate";
      if (translateAfterImport && !selectedProviderId) {
        setReaderActionMessage(t("reader.selectProviderForCitationTranslation"));
        return;
      }
      importCitationArxiv.mutate(
        {
          citationId: citation.id,
          payload: {
            download_pdf: true,
            translate_after_import: translateAfterImport,
            target_language: targetLanguage,
            provider_profile_id: translateAfterImport ? selectedProviderId : null,
            model: translateAfterImport ? (selectedProvider?.default_model ?? null) : null
          }
        },
        {
          onSuccess: (result) => {
            openTaskDrawerForBackgroundWork();
            setReaderActionMessage(
              t(
                translateAfterImport
                  ? "reader.citationImportTranslateQueued"
                  : "reader.citationImportQueued",
                {
                  title: result.candidate.title,
                  arxivId: result.candidate.arxiv_id
                }
              )
            );
          },
          onError: (error) => {
            setReaderActionMessage(
              t("reader.citationImportFailed", {
                message: error instanceof Error ? error.message : String(error)
              })
            );
          }
        }
      );
    },
    [
      importCitationArxiv,
      openTaskDrawerForBackgroundWork,
      selectedProvider?.default_model,
      selectedProviderId,
      t,
      targetLanguage
    ]
  );

  const queueBlockTranslation = useCallback(
    (blockUid: string, customPrompt?: string) => {
      if (!selectedProviderId) return;
      translateBlock.mutate({
        blockUid,
        payload: {
          ...translationPayload,
          force: true,
          block_uids: [blockUid],
          custom_prompt: customPrompt?.trim() || null
        }
      });
    },
    [selectedProviderId, translateBlock, translationPayload]
  );

  const submitCustomRetranslation = useCallback(() => {
    if (!retranslationBlock) return;
    queueBlockTranslation(retranslationBlock.block_uid, customRetranslationPrompt);
    setReaderActionMessage(`Queued retranslation for ${retranslationBlock.block_uid}.`);
    setRetranslationBlock(null);
    setCustomRetranslationPrompt("");
  }, [customRetranslationPrompt, queueBlockTranslation, retranslationBlock]);

  const handleTranslationVariantChange = useCallback(
    (blockUid: string, variantId: string) => {
      setVariantOverrides((current) => ({ ...current, [blockUid]: variantId }));
      selectTranslationVariant.mutate({ variantId, targetLanguage });
      setReaderActionMessage(`Selected translation variant for ${blockUid}.`);
    },
    [selectTranslationVariant, targetLanguage]
  );

  const handleBlockColorChange = useCallback(
    (blockUid: string, color: ReaderBlockColor) => {
      if (!libraryId || !articleId) return;
      setBlockColors((current) => {
        const next = { ...current };
        if (color === "none") {
          delete next[blockUid];
        } else {
          next[blockUid] = color;
        }
        try {
          globalThis.localStorage?.setItem(
            blockColorStorageKey(libraryId, articleId),
            JSON.stringify(next)
          );
        } catch {
          // Color marks remain usable in memory if localStorage is unavailable.
        }
        return next;
      });
    },
    [articleId, libraryId]
  );

  const handleReaderCardToggle = useCallback((blockUid: string, cardId: string) => {
    setExpandedReaderCardByBlock((current) => ({
      ...current,
      [blockUid]: current[blockUid] === cardId ? null : cardId
    }));
  }, []);

  const openReaderCardDraft = useCallback((block: DocumentBlock, card?: ReaderCard) => {
    const selection = selectedTextInsideBlock(block.block_uid);
    setReaderCardDraft({
      cardId: card?.id,
      blockUid: block.block_uid,
      anchorText: card?.anchor_text || selection || conciseAnchorText(block.source_markdown),
      title: card?.title || selection || conciseAnchorText(block.source_markdown),
      bodyMarkdown: card?.body_markdown || ""
    });
  }, []);

  const submitReaderCardDraft = useCallback(() => {
    if (!readerCardDraft) return;
    if (readerCardDraft.cardId) {
      updateReaderCard.mutate(
        {
          cardId: readerCardDraft.cardId,
          payload: {
            anchor_text: readerCardDraft.anchorText,
            title: readerCardDraft.title,
            body_markdown: readerCardDraft.bodyMarkdown,
            status: "pinned"
          }
        },
        {
          onSuccess: () => {
            setReaderCardDraft(null);
            setReaderFeaturePreference("termCardsEnabled", true);
            setTermWikiEnabled(true);
            setReaderActionMessage(t("reader.cardCreated"));
          },
          onError: (error) => setCardActionError(error, setReaderActionMessage, t)
        }
      );
      return;
    }
    createReaderCard.mutate(
      {
        card_type: "note",
        anchor_block_uid: readerCardDraft.blockUid,
        anchor_text: readerCardDraft.anchorText,
        title: readerCardDraft.title,
        body_markdown: readerCardDraft.bodyMarkdown,
        target_language: targetLanguage,
        source_type: "user_note",
        status: "pinned",
        position: "right",
        metadata: { source: "reader_selection" }
      },
      {
        onSuccess: () => {
          setReaderCardDraft(null);
          setReaderFeaturePreference("termCardsEnabled", true);
          setTermWikiEnabled(true);
          setReaderActionMessage(t("reader.cardCreated"));
        },
        onError: (error) => setCardActionError(error, setReaderActionMessage, t)
      }
    );
  }, [
    createReaderCard,
    readerCardDraft,
    setReaderFeaturePreference,
    t,
    targetLanguage,
    updateReaderCard
  ]);

  const generateCard = useCallback(
    (card: ReaderCard) => {
      generateReaderCard.mutate(
        {
          anchor_block_uid: card.anchor_block_uid,
          anchor_text: card.anchor_text,
          target_language: card.target_language,
          provider_profile_id: selectedProviderId,
          model: selectedProvider?.default_model ?? null,
          native_search: true,
          card_type: card.card_type,
          title: card.title,
          abbreviation: card.abbreviation,
          full_form: card.full_form
        },
        {
          onSuccess: (result) => {
            setReaderFeaturePreference("termCardsEnabled", true);
            setTermWikiEnabled(true);
            setExpandedReaderCardByBlock((current) => ({
              ...current,
              [result.card.anchor_block_uid]: result.card.id
            }));
            setReaderActionMessage(t("reader.cardGenerated"));
          },
          onError: (error) => setCardActionError(error, setReaderActionMessage, t)
        }
      );
    },
    [
      generateReaderCard,
      selectedProvider?.default_model,
      selectedProviderId,
      setReaderFeaturePreference,
      t
    ]
  );

  const pinCard = useCallback(
    (card: ReaderCard) => {
      updateReaderCard.mutate(
        {
          cardId: card.id,
          payload: { status: "pinned" }
        },
        { onError: (error) => setCardActionError(error, setReaderActionMessage, t) }
      );
    },
    [t, updateReaderCard]
  );

  const exportCard = useCallback(
    (card: ReaderCard) => {
      exportReaderCards.mutate(
        {
          target_language: card.target_language,
          card_ids: [card.id]
        },
        {
          onSuccess: (result) =>
            setReaderActionMessage(t("reader.cardExported", { count: result.cards_exported })),
          onError: (error) => setCardActionError(error, setReaderActionMessage, t)
        }
      );
    },
    [exportReaderCards, t]
  );

  const deleteCard = useCallback(
    (card: ReaderCard) => {
      deleteReaderCard.mutate(card.id, {
        onSuccess: () => {
          setExpandedReaderCardByBlock((current) => ({
            ...current,
            [card.anchor_block_uid]: null
          }));
        },
        onError: (error) => setCardActionError(error, setReaderActionMessage, t)
      });
    },
    [deleteReaderCard, t]
  );

  const runCardExtraction = useCallback(() => {
    extractReaderCards.mutate(
      { target_language: targetLanguage, limit: 30, force: false },
      {
        onSuccess: (result) => {
          setReaderFeaturePreference("termCardsEnabled", true);
          setTermWikiEnabled(true);
          setReaderActionMessage(t("reader.cardsFound", { count: result.cards?.length ?? 0 }));
        },
        onError: (error) => setCardActionError(error, setReaderActionMessage, t)
      }
    );
  }, [extractReaderCards, setReaderFeaturePreference, t, targetLanguage]);

  const queueAffectedRetranslation = useCallback(() => {
    const affected = glossary.data?.affected_block_uids ?? [];
    if (!selectedProviderId || affected.length === 0) return;
    translateArticle.mutate({
      ...translationPayload,
      force: true,
      block_uids: affected
    });
  }, [
    glossary.data?.affected_block_uids,
    selectedProviderId,
    translateArticle,
    translationPayload
  ]);

  const submitQuestion = () => {
    if (!selectedProviderId || !question.trim()) return;
    setStreamingAnswer("");
    setStreamingCitedBlocks([]);
    askQuestion.mutate({
      payload: {
        question: question.trim(),
        provider_profile_id: selectedProviderId,
        model: selectedProvider?.default_model ?? null,
        current_block_uid: chatBlockUid,
        max_blocks: 6,
        native_search: nativeSearch,
        retrieval_mode: "auto"
      },
      onMessage: (message) => {
        const data = message.data;
        if (message.event === "evidence" && isEvidenceStreamData(data)) {
          setStreamingCitedBlocks(data.cited_blocks);
        }
        if (message.event === "delta" && isDeltaStreamData(data)) {
          setStreamingAnswer((current) => `${current}${data.text}`);
        }
        if (message.event === "done") {
          setStreamingAnswer("");
          setStreamingCitedBlocks([]);
        }
      }
    });
    setQuestion("");
  };

  const submitBlockQuestion = useCallback(
    (block: DocumentBlock, blockQuestion: string) => {
      if (!selectedProviderId) {
        setReaderActionMessage(t("reader.quickAskNeedsProvider"));
        return;
      }
      setQuickAskBlockUid(block.block_uid);
      askBlockQuestion.mutate(
        {
          question: blockQuestion,
          provider_profile_id: selectedProviderId,
          model: selectedProvider?.default_model ?? null,
          current_block_uid: block.block_uid,
          max_blocks: 4,
          native_search: nativeSearch,
          retrieval_mode: "auto"
        },
        {
          onSuccess: (result) => {
            const answer = result.assistant_message.content.trim();
            createReaderCard.mutate(
              {
                card_type: "question",
                anchor_block_uid: block.block_uid,
                anchor_text: block.source_markdown.slice(0, 220),
                abbreviation: "Q",
                title: questionCardTitle(blockQuestion),
                body_markdown: answer,
                target_language: targetLanguage,
                source_type: result.native_search_used ? "ai_search" : "paper_local",
                status: "pinned",
                position: "left",
                metadata: {
                  source: "quick_block_question",
                  chat_message_id: result.assistant_message.id,
                  cited_blocks: (result.cited_blocks ?? []).map((item) => item.block_uid)
                }
              },
              {
                onSuccess: (card) => {
                  setReaderFeaturePreference("termCardsEnabled", true);
                  setTermWikiEnabled(true);
                  setExpandedReaderCardByBlock((current) => ({
                    ...current,
                    [card.anchor_block_uid]: card.id
                  }));
                  setReaderActionMessage(t("reader.quickAskCardCreated"));
                },
                onError: (error) => setCardActionError(error, setReaderActionMessage, t)
              }
            );
          },
          onError: (error) => setCardActionError(error, setReaderActionMessage, t),
          onSettled: () => setQuickAskBlockUid(null)
        }
      );
    },
    [
      askBlockQuestion,
      createReaderCard,
      nativeSearch,
      selectedProvider?.default_model,
      selectedProviderId,
      setReaderFeaturePreference,
      t,
      targetLanguage
    ]
  );

  const createNotePatchFromMessage = (messageId: string) => {
    createNotePatchFromChat.mutate({
      messageId,
      payload: { title: null }
    });
  };

  const queueNoteGeneration = () => {
    if (!selectedProviderId || !selectedTemplateId) return;
    generateNotePatch.mutate({
      provider_profile_id: selectedProviderId,
      template_id: selectedTemplateId,
      model: selectedProvider?.default_model ?? null,
      max_blocks: 12,
      include_chat_history: true
    });
  };

  const queueExport = () => {
    exportArticle.mutate({
      kind: exportKind,
      target_language: targetLanguage,
      include_untranslated: readerFeaturePreferences.includeUntranslatedInExport
    });
  };

  const copyText = useCallback(async (text: string, label: string) => {
    if (!text.trim()) {
      setReaderActionMessage(`${label} has no text to copy.`);
      return;
    }
    try {
      await writeClipboardText(text);
      setReaderActionMessage(`${label} copied.`);
    } catch {
      setReaderActionMessage("Clipboard is unavailable. Select the text and copy it manually.");
    }
  }, []);

  const handleToolbarAction = useCallback(
    (actionId: ReaderToolbarActionId, block: DocumentBlock, content: string) => {
      if (actionId === "copy-source" || actionId === "copy-block") {
        void copyText(block.source_markdown, "Source block");
        return;
      }
      if (actionId === "copy-obsidian") {
        const color = readerFeaturePreferences.colorMarkersEnabled
          ? (blockColors[block.block_uid] ?? "none")
          : "none";
        saveObsidianClip.mutate(
          {
            block_uid: block.block_uid,
            target_language: targetLanguage,
            color
          },
          {
            onSuccess: (result) => setReaderActionMessage(`Saved to Obsidian: ${result.note_path}`),
            onError: () =>
              void copyText(
                obsidianCalloutForBlock(block, translationByBlockUid.get(block.block_uid), color),
                "Obsidian callout"
              )
          }
        );
        return;
      }
      if (actionId === "copy-translation") {
        void copyText(content, "Translation block");
        return;
      }
      if (actionId === "ask-source" || actionId === "explain-block") {
        setChatBlockUid(block.block_uid);
        setReaderActionMessage(`Current block set to ${block.block_uid}.`);
        return;
      }
      if (actionId === "create-card") {
        setReaderFeaturePreference("termCardsEnabled", true);
        setTermWikiEnabled(true);
        openReaderCardDraft(block);
        return;
      }
      if (actionId === "show-latex" || actionId === "show-source") {
        setInspectedBlock(block);
        return;
      }
      if (actionId === "retranslate") {
        if (!selectedProviderId) {
          setReaderActionMessage("Select a provider before retranslating this block.");
          return;
        }
        setRetranslationBlock(block);
        setCustomRetranslationPrompt("");
        return;
      }
      if (actionId === "add-note-patch") {
        setChatBlockUid(block.block_uid);
        setReaderActionMessage(`Block ${block.block_uid} is selected for notes and questions.`);
      }
    },
    [
      blockColors,
      copyText,
      readerFeaturePreferences.colorMarkersEnabled,
      saveObsidianClip,
      selectedProviderId,
      setReaderFeaturePreference,
      targetLanguage,
      translationByBlockUid,
      openReaderCardDraft
    ]
  );

  const renderReaderBlock = useCallback(
    (block: DocumentBlock) => {
      const asset = assetForBlock(block, assetById);
      const assetId = asset?.asset_id;
      return (
        <ReaderBlock
          key={block.block_uid}
          block={block}
          asset={asset}
          assetUrl={assetId ? assetUrlByAssetId.get(assetId) : undefined}
          assetFileUrls={
            assetId
              ? (assetFileUrlsByAssetId.get(assetId) ?? emptyReaderAssetFiles)
              : emptyReaderAssetFiles
          }
          referenceTargets={referenceTargets}
          citations={effectiveCitationLookup}
          citationImportPending={
            readerFeaturePreferences.citationPreviewEnabled && importCitationArxiv.isPending
          }
          canImportCitationWithTranslation={
            readerFeaturePreferences.citationPreviewEnabled && Boolean(selectedProviderId)
          }
          onCitationImport={
            readerFeaturePreferences.citationPreviewEnabled && libraryId && articleId
              ? importCitationToLibrary
              : undefined
          }
          translation={translationByBlockUid.get(block.block_uid)}
          translationVariantOptions={translationVariantOptionsByBlockUid.get(block.block_uid) ?? []}
          selectedTranslationVariantId={selectedVariantByBlockUid.get(block.block_uid)?.id}
          glossaryAffected={
            readerFeaturePreferences.glossaryReplacementEnabled &&
            affectedBlockUids.has(block.block_uid)
          }
          viewMode={viewMode}
          active={activeBlockUid === block.block_uid}
          controlsVisible={
            readerFeaturePreferences.blockToolsEnabled && currentSearchBlockUid === block.block_uid
          }
          blockToolsEnabled={readerFeaturePreferences.blockToolsEnabled}
          colorMarkersEnabled={readerFeaturePreferences.colorMarkersEnabled}
          sentenceHoverAccentEnabled={readerFeaturePreferences.sentenceHoverAccentEnabled}
          imageLightboxEnabled={readerFeaturePreferences.imageLightboxEnabled}
          searchActive={currentSearchBlockUid === block.block_uid}
          blockColor={blockColors[block.block_uid] ?? "none"}
          termWikiEnabled={termCardsVisible}
          readerCards={readerCardsByBlockUid.get(block.block_uid) ?? []}
          expandedReaderCardId={expandedReaderCardByBlock[block.block_uid] ?? null}
          onActivate={handleActiveBlockChange}
          onBlockColorChange={
            readerFeaturePreferences.colorMarkersEnabled ? handleBlockColorChange : undefined
          }
          onTranslationVariantChange={handleTranslationVariantChange}
          onReaderCardToggle={handleReaderCardToggle}
          onReaderCardGenerate={generateCard}
          onReaderCardEdit={(card) => openReaderCardDraft(block, card)}
          onReaderCardPin={pinCard}
          onReaderCardDelete={deleteCard}
          onReaderCardExport={exportCard}
          canQuickAsk={readerFeaturePreferences.quickAskEnabled && Boolean(selectedProviderId)}
          quickAskPending={quickAskBlockUid === block.block_uid && askBlockQuestion.isPending}
          onQuickAsk={readerFeaturePreferences.quickAskEnabled ? submitBlockQuestion : undefined}
          onToolbarAction={
            readerFeaturePreferences.blockToolsEnabled ? handleToolbarAction : undefined
          }
        />
      );
    },
    [
      activeBlockUid,
      affectedBlockUids,
      articleId,
      assetById,
      assetFileUrlsByAssetId,
      assetUrlByAssetId,
      blockColors,
      effectiveCitationLookup,
      currentSearchBlockUid,
      deleteCard,
      expandedReaderCardByBlock,
      exportCard,
      generateCard,
      handleActiveBlockChange,
      handleBlockColorChange,
      handleReaderCardToggle,
      handleToolbarAction,
      handleTranslationVariantChange,
      importCitationArxiv.isPending,
      importCitationToLibrary,
      libraryId,
      openReaderCardDraft,
      pinCard,
      referenceTargets,
      readerCardsByBlockUid,
      readerFeaturePreferences.blockToolsEnabled,
      readerFeaturePreferences.citationPreviewEnabled,
      readerFeaturePreferences.colorMarkersEnabled,
      readerFeaturePreferences.glossaryReplacementEnabled,
      readerFeaturePreferences.imageLightboxEnabled,
      readerFeaturePreferences.quickAskEnabled,
      readerFeaturePreferences.sentenceHoverAccentEnabled,
      selectedProviderId,
      selectedVariantByBlockUid,
      askBlockQuestion.isPending,
      quickAskBlockUid,
      termCardsVisible,
      translationByBlockUid,
      translationVariantOptionsByBlockUid,
      submitBlockQuestion,
      viewMode
    ]
  );

  return (
    <div className="reader-page" style={readerPreferenceStyle}>
      <Modal
        opened={Boolean(inspectedBlock)}
        onClose={() => setInspectedBlock(null)}
        title={t("reader.sourceInspector")}
        size="lg"
        closeButtonProps={{ "aria-label": t("reader.closeSourceInspector") }}
      >
        {inspectedBlock ? (
          <pre className="source-inspector">
            {inspectedBlock.source_latex || inspectedBlock.source_markdown}
          </pre>
        ) : null}
      </Modal>
      <Modal
        opened={Boolean(retranslationBlock)}
        onClose={() => {
          setRetranslationBlock(null);
          setCustomRetranslationPrompt("");
        }}
        title={
          retranslationBlock
            ? `${t("reader.retranslateBlock")} ${retranslationBlock.block_uid}`
            : t("reader.retranslateBlock")
        }
        size="lg"
        closeButtonProps={{ "aria-label": t("reader.closeRetranslation") }}
      >
        <Textarea
          label={t("reader.customPrompt")}
          placeholder={t("reader.customPromptPlaceholder")}
          autosize
          minRows={4}
          value={customRetranslationPrompt}
          onChange={(event) => setCustomRetranslationPrompt(event.target.value)}
        />
        <Group justify="flex-end" mt="md">
          <Button
            leftSection={<RefreshCw size={16} />}
            onClick={submitCustomRetranslation}
            loading={translateBlock.isPending}
            disabled={!selectedProviderId || !retranslationBlock}
          >
            {t("reader.queueRetranslation")}
          </Button>
        </Group>
      </Modal>
      <Modal
        opened={Boolean(readerCardDraft)}
        onClose={() => setReaderCardDraft(null)}
        title={readerCardDraft?.cardId ? t("reader.editCard") : t("reader.createCard")}
        size="md"
      >
        <Stack gap="sm">
          <TextInput
            label={t("reader.cardAnchor")}
            value={readerCardDraft?.anchorText ?? ""}
            onChange={(event) =>
              setReaderCardDraft((current) =>
                current ? { ...current, anchorText: event.currentTarget.value } : current
              )
            }
          />
          <TextInput
            label={t("reader.cardTitle")}
            value={readerCardDraft?.title ?? ""}
            onChange={(event) =>
              setReaderCardDraft((current) =>
                current ? { ...current, title: event.currentTarget.value } : current
              )
            }
          />
          <Textarea
            label={t("reader.cardBody")}
            description={t("reader.cardSelectionHelp")}
            autosize
            minRows={4}
            value={readerCardDraft?.bodyMarkdown ?? ""}
            onChange={(event) =>
              setReaderCardDraft((current) =>
                current ? { ...current, bodyMarkdown: event.currentTarget.value } : current
              )
            }
          />
          <Group justify="flex-end">
            <Button
              leftSection={<StickyNote size={16} />}
              onClick={submitReaderCardDraft}
              loading={createReaderCard.isPending || updateReaderCard.isPending}
              disabled={!readerCardDraft?.anchorText.trim() || !readerCardDraft?.title.trim()}
            >
              {t("reader.cardSave")}
            </Button>
          </Group>
        </Stack>
      </Modal>
      <main className="reader-main">
        <section className="reader-command-center" aria-label={t("reader.readingControls")}>
          <div className="reader-command-title" aria-hidden="true">
            Ilios / 衔牍 · Research Paper Reader
          </div>
          <div className="reader-command-actions">
            <div className="reader-command-zone reader-command-left">
              <Button
                className="reader-chrome-button"
                variant="subtle"
                size="xs"
                leftSection={<BookMarked size={15} aria-hidden="true" />}
                onClick={openCurrentLibrary}
              >
                {t("nav.library")}
              </Button>
              <div className="reader-search-dock" role="search">
                <TextInput
                  ref={readerSearchInputRef}
                  className="reader-search-input"
                  aria-label={t("reader.searchPaper")}
                  placeholder={t("reader.searchPlaceholder")}
                  value={readerSearchQuery}
                  leftSection={<Search size={14} aria-hidden="true" />}
                  rightSection={
                    readerSearchQuery ? (
                      <ActionIcon
                        aria-label={t("reader.searchClear")}
                        size="sm"
                        variant="subtle"
                        onClick={clearReaderSearch}
                      >
                        <X size={13} aria-hidden="true" />
                      </ActionIcon>
                    ) : null
                  }
                  onChange={(event) => setReaderSearchQuery(event.currentTarget.value)}
                  onKeyDown={(event) => {
                    if (event.key !== "Enter") return;
                    event.preventDefault();
                    if (event.shiftKey) {
                      moveReaderSearch(-1);
                    } else {
                      jumpToCurrentReaderSearchMatch();
                    }
                  }}
                />
                {readerSearchQuery ? (
                  <Group gap={4} wrap="nowrap" className="reader-search-actions">
                    <ActionIcon
                      aria-label={t("reader.searchPrevious")}
                      size="sm"
                      variant="subtle"
                      disabled={readerSearchMatches.length === 0}
                      onClick={() => moveReaderSearch(-1)}
                    >
                      <ChevronLeft size={13} aria-hidden="true" />
                    </ActionIcon>
                    <ActionIcon
                      aria-label={t("reader.searchNext")}
                      size="sm"
                      variant="subtle"
                      disabled={readerSearchMatches.length === 0}
                      onClick={() => moveReaderSearch(1)}
                    >
                      <ChevronRight size={13} aria-hidden="true" />
                    </ActionIcon>
                  </Group>
                ) : null}
              </div>
            </div>
            <div
              data-testid="reader-view-mode"
              className="reader-mode-list"
              aria-label={t("reader.readingControls")}
            >
              <Button
                aria-label={t("reader.modeMenu")}
                aria-expanded={readerModeMenuOpen}
                className="reader-mode-trigger"
                leftSection={<BookOpenText size={15} aria-hidden="true" />}
                rightSection={<ChevronDown size={14} aria-hidden="true" />}
                size="xs"
                variant="subtle"
                onClick={() => setReaderModeMenuOpen((open) => !open)}
              >
                {currentReaderModeLabel}
              </Button>
              <Collapse className="reader-mode-popover" in={readerModeMenuOpen}>
                <div className="reader-mode-options">
                  {readerModeOptions.map((option) => (
                    <button
                      key={option.value}
                      type="button"
                      aria-pressed={viewMode === option.value}
                      onClick={() => {
                        setReaderViewMode(option.value);
                        setReaderModeMenuOpen(false);
                      }}
                    >
                      {option.icon}
                      <span>{option.label}</span>
                    </button>
                  ))}
                </div>
              </Collapse>
            </div>
            <div className="reader-command-zone reader-command-right">
              <div className="reader-tool-menu" aria-label={t("reader.readerTools")}>
                <Button
                  aria-expanded={readerToolMenuOpen}
                  className="reader-chrome-button reader-tool-button"
                  variant={readerToolMenuOpen || readerWorkbenchOpen ? "light" : "subtle"}
                  size="xs"
                  leftSection={<Sparkles size={15} aria-hidden="true" />}
                  rightSection={<ChevronDown size={14} aria-hidden="true" />}
                  onClick={() => setReaderToolMenuOpen((open) => !open)}
                >
                  {t("reader.readerTools")}
                </Button>
                <Collapse className="reader-tool-popover" in={readerToolMenuOpen}>
                  <div className="reader-tool-options">
                    <button type="button" onClick={() => openReaderTool("chat")}>
                      <MessageSquare size={15} aria-hidden="true" />
                      <span>{t("reader.ask")}</span>
                    </button>
                    <button type="button" onClick={() => openReaderTool("translate")}>
                      <Languages size={15} aria-hidden="true" />
                      <span>{t("reader.translate")}</span>
                    </button>
                    <button
                      type="button"
                      aria-pressed={readerFeaturePreferences.termCardsEnabled}
                      onClick={() => {
                        const nextEnabled = !readerFeaturePreferences.termCardsEnabled;
                        setReaderFeaturePreference("termCardsEnabled", nextEnabled);
                        setTermWikiEnabled(nextEnabled);
                        setReaderToolMenuOpen(false);
                      }}
                    >
                      <StickyNote size={15} aria-hidden="true" />
                      <span>{t("reader.termWiki")}</span>
                    </button>
                    <button
                      type="button"
                      disabled={!hasArticleContext || extractReaderCards.isPending}
                      onClick={() => {
                        runCardExtraction();
                        setReaderToolMenuOpen(false);
                      }}
                    >
                      <Sparkles size={15} aria-hidden="true" />
                      <span>{t("reader.extractCards")}</span>
                    </button>
                    <button type="button" onClick={() => openReaderTool("glossary")}>
                      <BookMarked size={15} aria-hidden="true" />
                      <span>{t("reader.terms")}</span>
                    </button>
                    <button type="button" onClick={() => openReaderTool("notes")}>
                      <FileText size={15} aria-hidden="true" />
                      <span>{t("reader.notes")}</span>
                    </button>
                    <button type="button" onClick={() => openReaderTool("export")}>
                      <Download size={15} aria-hidden="true" />
                      <span>{t("reader.export")}</span>
                    </button>
                  </div>
                </Collapse>
              </div>
              <Button
                aria-expanded={readerPreferencesOpen}
                aria-label={t("reader.preferences")}
                className="reader-chrome-button reader-preferences-trigger"
                title={t("reader.preferences")}
                variant={readerPreferencesOpen ? "light" : "subtle"}
                size="xs"
                leftSection={<Type size={15} aria-hidden="true" />}
                onClick={() => setReaderPreferencesOpen((open) => !open)}
              >
                {t("reader.preferences")}
              </Button>
              <ActionIcon
                aria-label={t("nav.openTasks")}
                className="reader-more-button"
                variant="subtle"
                size="sm"
                onClick={openTaskDrawer}
              >
                <TerminalSquare size={16} aria-hidden="true" />
              </ActionIcon>
              <ActionIcon
                aria-label={t("nav.toggleTheme")}
                className="reader-more-button"
                variant="subtle"
                size="sm"
                onClick={() => setColorScheme(colorScheme === "dark" ? "light" : "dark")}
              >
                {colorScheme === "dark" ? (
                  <Sun size={16} aria-hidden="true" />
                ) : (
                  <Moon size={16} aria-hidden="true" />
                )}
              </ActionIcon>
            </div>
          </div>
          <Collapse className="reader-preferences-flyout" in={readerPreferencesOpen}>
            <ReaderPreferencesPanel compact showTitle={false} />
          </Collapse>
        </section>
        <section
          className={`reader-workbench${readerWorkbenchOpen ? " reader-workbench-open" : ""}`}
          aria-label={currentReaderToolLabel}
        >
          <Tabs
            value={readerToolTab}
            onChange={(value) => {
              if (!value) return;
              setReaderToolTab(value as ReaderToolTab);
              setReaderWorkbenchOpen(true);
            }}
            keepMounted={false}
          >
            {readerWorkbenchOpen ? (
              <div className="reader-workbench-header">
                <Text size="sm" fw={650}>
                  {currentReaderToolLabel}
                </Text>
                <ActionIcon
                  aria-label={t("reader.closeToolPanel")}
                  variant="subtle"
                  size="sm"
                  onClick={() => setReaderWorkbenchOpen(false)}
                >
                  <X size={15} aria-hidden="true" />
                </ActionIcon>
              </div>
            ) : null}
            <Tabs.Panel value="translate">
              <div className="panel reader-translation-panel">
                <Group align="end">
                  <Select
                    label={t("reader.provider")}
                    placeholder={t("reader.configureProvider")}
                    value={selectedProviderId}
                    onChange={setSelectedProviderId}
                    data={(providers.data ?? []).map((provider) => ({
                      label: `${provider.name} · ${provider.default_model ?? t("reader.noModel")}`,
                      value: provider.id
                    }))}
                  />
                  <Select
                    label={t("reader.targetLanguage")}
                    data={TRANSLATION_TARGET_LOCALES.map((item) => ({
                      value: item.value,
                      label: item.nativeLabel
                    }))}
                    searchable
                    value={targetLanguage}
                    onChange={(value) => {
                      if (value) setTargetLanguage(value);
                    }}
                  />
                  <Button
                    leftSection={<Languages size={16} />}
                    onClick={queueArticleTranslation}
                    loading={translateArticle.isPending}
                    disabled={!selectedProviderId || !targetLanguage.trim() || blocks.length === 0}
                  >
                    {t("reader.translatePaper")}
                  </Button>
                </Group>
                <Checkbox
                  mt="sm"
                  checked={autoTranslateOnLanguageSwitch}
                  label={t("reader.autoTranslateOnLanguageSwitch")}
                  onChange={(event) =>
                    setAutoTranslateOnLanguageSwitch(event.currentTarget.checked)
                  }
                />
                <Text c="dimmed" size="sm" mt="sm">
                  {t("reader.translationHelp")}
                </Text>
                {translateArticle.data ? (
                  <Text c="dimmed" size="sm" mt="xs">
                    {t("reader.translationQueued", {
                      jobs: translateArticle.data.jobs_created,
                      cached: translateArticle.data.cached_blocks
                    })}
                  </Text>
                ) : null}
                {translateArticle.isError || translateBlock.isError ? (
                  <Text c="red" size="sm" mt="xs">
                    {t("reader.translationQueueError")}
                  </Text>
                ) : null}
              </div>
            </Tabs.Panel>

            <Tabs.Panel value="glossary">
              <GlossaryPanel
                terms={glossary.data?.terms ?? []}
                targetLanguage={targetLanguage}
                activeVersion={glossary.data?.active_version ?? "glossary:none"}
                affectedBlockUids={glossary.data?.affected_block_uids ?? []}
                isLoading={glossary.isLoading}
                isExtracting={extractGlossary.isPending}
                isSaving={createGlossaryTerm.isPending || updateGlossaryTerm.isPending}
                canRetranslate={Boolean(selectedProviderId)}
                onExtract={() =>
                  extractGlossary.mutate({
                    target_language: targetLanguage,
                    limit: 40
                  })
                }
                onCreate={(sourceTerm, targetTerm) =>
                  createGlossaryTerm.mutate({
                    source_term: sourceTerm,
                    target_term: targetTerm,
                    language_direction: `en->${targetLanguage}`,
                    status: "active",
                    metadata: { target_language: targetLanguage }
                  })
                }
                onConfirm={(term, targetTerm) =>
                  updateGlossaryTerm.mutate({
                    termId: term.id,
                    payload: {
                      target_term: targetTerm,
                      status: "active",
                      metadata: { target_language: targetLanguage }
                    }
                  })
                }
                onRetranslateAffected={queueAffectedRetranslation}
              />
            </Tabs.Panel>

            <Tabs.Panel value="chat">
              <ChatPanel
                messages={chat.data?.messages ?? []}
                citedBlocks={
                  streamingCitedBlocks.length > 0
                    ? streamingCitedBlocks
                    : (askQuestion.data?.cited_blocks ?? [])
                }
                streamingAnswer={streamingAnswer}
                selectedBlockUid={chatBlockUid}
                question={question}
                nativeSearch={nativeSearch}
                nativeSearchAvailable={Boolean(selectedProvider?.capabilities?.native_search)}
                isAsking={askQuestion.isPending}
                isCreatingNotePatch={createNotePatchFromChat.isPending}
                canAsk={Boolean(selectedProviderId)}
                canCreateNotePatch={Boolean(selectedProviderId)}
                error={askQuestion.isError}
                onQuestionChange={setQuestion}
                onNativeSearchChange={setNativeSearch}
                onClearBlock={() => setChatBlockUid(null)}
                onAsk={submitQuestion}
                onCreateNotePatch={createNotePatchFromMessage}
              />
            </Tabs.Panel>

            <Tabs.Panel value="notes">
              <NotesPanel
                templates={noteTemplates.data ?? []}
                patches={notePatches.data?.patches ?? []}
                selectedTemplateId={selectedTemplateId}
                isLoading={noteTemplates.isLoading || notePatches.isLoading}
                isGenerating={generateNotePatch.isPending}
                isSavingPatch={updateNotePatch.isPending}
                isSavingTemplate={createNoteTemplate.isPending}
                isRejecting={rejectNotePatch.isPending}
                canGenerate={Boolean(selectedProviderId && blocks.length > 0)}
                error={
                  generateNotePatch.isError ||
                  createNoteTemplate.isError ||
                  updateNotePatch.isError ||
                  rejectNotePatch.isError
                }
                onTemplateChange={setSelectedTemplateId}
                onGenerate={queueNoteGeneration}
                onCreateTemplate={(name, description) =>
                  createNoteTemplate.mutate(
                    { name, description, metadata: { source: "reader" } },
                    { onSuccess: (template) => setSelectedTemplateId(template.id) }
                  )
                }
                onSavePatch={(patchId, payload) => updateNotePatch.mutate({ patchId, payload })}
                onAcceptEdited={(patchId, payload) =>
                  updateNotePatch.mutate({
                    patchId,
                    payload: {
                      ...payload,
                      status: "accepted"
                    }
                  })
                }
                onReject={(patchId) => rejectNotePatch.mutate(patchId)}
              />
            </Tabs.Panel>

            <Tabs.Panel value="export">
              <ExportPanel
                exportKind={exportKind}
                targetLanguage={targetLanguage}
                result={exportResult}
                isExporting={exportArticle.isPending}
                error={exportArticle.isError}
                downloadUrl={currentExportDownloadUrl}
                onExportKindChange={setExportKind}
                onExport={queueExport}
              />
            </Tabs.Panel>
          </Tabs>
        </section>
        <section className="reader-paper-shell" aria-label={title}>
          {readerFeaturePreferences.watermarkVisible ? (
            <p className="reader-content-watermark">{t("reader.contentWatermark")}</p>
          ) : null}
          {readerActionMessage ? (
            <div className="reader-action-status" role="status">
              <Check size={15} aria-hidden="true" />
              {readerActionMessage}
            </div>
          ) : null}
          {!hasArticleContext ? (
            <Alert color="yellow" mb="md">
              {t("reader.noArticleContext")}
            </Alert>
          ) : null}
          {hasArticleContext && document.isLoading ? (
            <Group>
              <Loader size="sm" />
              <Text c="dimmed">{t("reader.loadingDocument")}</Text>
            </Group>
          ) : null}
          {hasArticleContext && document.isError ? (
            <Alert color="red" mb="md">
              {t("reader.documentLoadError")}
            </Alert>
          ) : null}
          <ReaderBlockList
            blocks={blocks}
            activeBlockUid={activeBlockUid}
            fontScale={readerPreferences.fontScale}
            paragraphSpacingEm={readerPreferences.paragraphSpacingEm}
            forcedBlockUid={forcedBlockUid}
            searchTargetBlockUid={currentSearchBlockUid}
            getBlockText={blockTextForPlaceholder}
            onActiveBlockChange={handleActiveBlockChange}
            onNavigateToBlock={navigateToBlock}
            renderBlock={renderReaderBlock}
          />
        </section>
        {readerFeaturePreferences.bottomProgressVisible ||
        readerFeaturePreferences.chapterIndexVisible ? (
          <section
            className="reader-bottom-status"
            aria-label={t("reader.readingProgress", { progress: readerProgress })}
          >
            {readerFeaturePreferences.chapterIndexVisible ? (
              <div className="reader-bottom-chapters">
                <button
                  type="button"
                  aria-label={t("reader.chapters")}
                  aria-expanded={chaptersOpen}
                  onClick={() => setChaptersOpen((open) => !open)}
                  disabled={navBlocks.length === 0}
                >
                  <ListTree size={14} aria-hidden="true" />
                  <span>{activeChapterLabel}</span>
                  <ChevronDown size={14} aria-hidden="true" />
                </button>
                {navBlocks.length > 0 ? (
                  <Collapse className="reader-bottom-chapter-popover" in={chaptersOpen}>
                    <nav className="reader-bottom-chapter-list" aria-label={t("reader.chapters")}>
                      {navBlocks.map((block, index) => (
                        <a
                          key={block.block_uid}
                          href={`#${block.block_uid}`}
                          className={
                            activeNavBlockUid === block.block_uid ? "reader-nav-active" : undefined
                          }
                          aria-current={
                            activeNavBlockUid === block.block_uid ? "location" : undefined
                          }
                          onMouseEnter={() => handleActiveBlockChange(block.block_uid)}
                          onClick={(event) => {
                            event.preventDefault();
                            navigateToBlock(block.block_uid);
                            setChaptersOpen(false);
                          }}
                        >
                          <Badge variant="light" size="sm">
                            {chapterNumber(index, block)}
                          </Badge>
                          <span>{chapterTitle(block)}</span>
                        </a>
                      ))}
                    </nav>
                  </Collapse>
                ) : null}
              </div>
            ) : null}
            {readerFeaturePreferences.bottomProgressVisible ? (
              <>
                <div className="reader-progress-group">
                  <span>
                    {readerSearchQuery
                      ? readerSearchMatches.length > 0
                        ? t("reader.searchCount", {
                            current: Math.min(readerSearchCursor + 1, readerSearchMatches.length),
                            total: readerSearchMatches.length
                          })
                        : t("reader.searchNoMatches")
                      : t("reader.readingProgress", { progress: readerProgress })}
                  </span>
                  <progress value={readerProgress} max={100} />
                </div>
                <div className="reader-block-counter" aria-live="polite">
                  <button
                    type="button"
                    onClick={() => moveReaderSearch(-1)}
                    disabled={readerSearchMatches.length === 0}
                  >
                    <ChevronLeft size={14} aria-hidden="true" />
                  </button>
                  <span>
                    {activeBlockOrdinal} / {Math.max(blocks.length, 1)}
                  </span>
                  <button
                    type="button"
                    onClick={() => moveReaderSearch(1)}
                    disabled={readerSearchMatches.length === 0}
                  >
                    <ChevronRight size={14} aria-hidden="true" />
                  </button>
                </div>
                <div className="reader-status-context">
                  <span>{currentReaderModeLabel}</span>
                </div>
              </>
            ) : null}
          </section>
        ) : null}
      </main>
    </div>
  );
}

function blockColorStorageKey(libraryId: string, articleId: string) {
  return `ilios-block-colors:${libraryId}:${articleId}`;
}

function cardStatusOrder(status: ReaderCard["status"]) {
  if (status === "pinned") return 0;
  if (status === "exported") return 1;
  if (status === "candidate") return 2;
  return 3;
}

function selectedTextInsideBlock(blockUid: string) {
  if (typeof window === "undefined") return "";
  const selection = window.getSelection();
  const text = selection?.toString().trim() ?? "";
  if (!text) return "";
  const anchor = selection?.anchorNode;
  const element = anchor instanceof Element ? anchor : anchor?.parentElement;
  const blockElement = element?.closest?.(`#${CSS.escape(blockUid)}`);
  return blockElement ? text.slice(0, 220) : "";
}

function conciseAnchorText(markdown: string) {
  const plain = markdown
    .replace(/!\[[^\]]*]\([^)]*\)/g, " ")
    .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\$([^$]+)\$/g, "$1")
    .replace(/[*_#>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return plain.slice(0, 80) || "Reader card";
}

function setCardActionError(
  error: unknown,
  setReaderActionMessage: (message: string | null) => void,
  t: (key: MessageKey, values?: Record<string, string | number>) => string
) {
  setReaderActionMessage(
    t("reader.cardActionFailed", {
      message: error instanceof Error ? error.message : String(error)
    })
  );
}

function questionCardTitle(question: string): string {
  const normalized = question.replace(/\s+/g, " ").trim();
  if (normalized.length <= 48) return normalized;
  return `${normalized.slice(0, 47)}...`;
}

type ReaderPreferenceStyle = CSSProperties & Record<`--${string}`, string>;

function readerStyleForPreferences(preferences: ReaderPreferences): ReaderPreferenceStyle {
  const lineWidthPercent = Math.round(preferences.lineWidthPercent);
  const wideWidthPercent = Math.min(100, Math.max(lineWidthPercent + 22, lineWidthPercent * 1.34));
  const fontScale = preferences.fontScale;
  const sourceRatio = preferences.bilingualSourceRatio;
  const translationRatio = 1 - sourceRatio;

  return {
    "--reader-line-width": `${lineWidthPercent}%`,
    "--reader-wide-width": `${Math.round(wideWidthPercent)}%`,
    "--reader-table-width": "min(92%, 860px)",
    "--reader-body-font-size": `${16.32 * fontScale}px`,
    "--reader-source-font-size": `${16.72 * fontScale}px`,
    "--reader-translation-font-size": `${16.24 * fontScale}px`,
    "--reader-paragraph-spacing": `${preferences.paragraphSpacingEm}em`,
    "--reader-source-column": `${sourceRatio}fr`,
    "--reader-translation-column": `${translationRatio}fr`
  };
}

async function writeClipboardText(text: string) {
  if (writeClipboardTextWithDomFallback(text)) {
    return;
  }
  if (!navigator.clipboard?.writeText) throw new Error("Clipboard API unavailable");
  await navigator.clipboard.writeText(text);
}

function writeClipboardTextWithDomFallback(text: string) {
  if (typeof document.execCommand !== "function") return false;
  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "true");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  textarea.style.top = "0";
  document.body.appendChild(textarea);
  textarea.focus();
  textarea.select();
  try {
    return document.execCommand("copy");
  } catch {
    return false;
  } finally {
    textarea.remove();
  }
}

function parseStoredBlockColors(raw: string): Record<string, ReaderBlockColor> {
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object") return {};
  const colors = new Set<ReaderBlockColor>(["yellow", "blue", "green", "pink", "purple"]);
  const result: Record<string, ReaderBlockColor> = {};
  for (const [blockUid, color] of Object.entries(parsed)) {
    if (typeof blockUid === "string" && colors.has(color as ReaderBlockColor)) {
      result[blockUid] = color as ReaderBlockColor;
    }
  }
  return result;
}

const obsidianColorMeta: Record<ReaderBlockColor, { callout: string; title: string; tag: string }> =
  {
    none: { callout: "note", title: "Paper note", tag: "#ilios/note" },
    yellow: { callout: "important", title: "Key idea", tag: "#ilios/key-idea" },
    blue: { callout: "info", title: "Method", tag: "#ilios/method" },
    green: { callout: "success", title: "Evidence", tag: "#ilios/evidence" },
    pink: { callout: "question", title: "Question", tag: "#ilios/question" },
    purple: { callout: "abstract", title: "Review later", tag: "#ilios/review" }
  };

function obsidianCalloutForBlock(
  block: DocumentBlock,
  translation: string | undefined,
  color: ReaderBlockColor
) {
  const meta = obsidianColorMeta[color];
  const source = quoteForObsidian(block.source_markdown);
  const translated = translation?.trim()
    ? `>\n> **Translation**\n${quoteForObsidian(translation)}`
    : "";
  return [
    `> [!${meta.callout}] ${meta.title} · ${block.block_uid}`,
    source,
    translated,
    `>\n> ${meta.tag}`,
    `^${obsidianBlockId(block.block_uid)}`
  ]
    .filter(Boolean)
    .join("\n");
}

function quoteForObsidian(markdown: string) {
  return markdown
    .trim()
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");
}

function obsidianBlockId(blockUid: string) {
  return `ilios-${blockUid.replace(/[^A-Za-z0-9-]/g, "-")}`;
}

interface GlossaryPanelProps {
  terms: GlossaryTerm[];
  targetLanguage: string;
  activeVersion: string;
  affectedBlockUids: string[];
  isLoading: boolean;
  isExtracting: boolean;
  isSaving: boolean;
  canRetranslate: boolean;
  onExtract: () => void;
  onCreate: (sourceTerm: string, targetTerm: string) => void;
  onConfirm: (term: GlossaryTerm, targetTerm: string) => void;
  onRetranslateAffected: () => void;
}

interface ChatPanelProps {
  messages: ChatMessage[];
  citedBlocks: RetrievedBlock[];
  streamingAnswer: string;
  selectedBlockUid: string | null;
  question: string;
  nativeSearch: boolean;
  nativeSearchAvailable: boolean;
  isAsking: boolean;
  isCreatingNotePatch: boolean;
  canAsk: boolean;
  canCreateNotePatch: boolean;
  error: boolean;
  onQuestionChange: (value: string) => void;
  onNativeSearchChange: (value: boolean) => void;
  onClearBlock: () => void;
  onAsk: () => void;
  onCreateNotePatch: (messageId: string) => void;
}

interface NotesPanelProps {
  templates: NoteTemplate[];
  patches: NotePatch[];
  selectedTemplateId: string;
  isLoading: boolean;
  isGenerating: boolean;
  isSavingPatch: boolean;
  isSavingTemplate: boolean;
  isRejecting: boolean;
  canGenerate: boolean;
  error: boolean;
  onTemplateChange: (value: string) => void;
  onGenerate: () => void;
  onCreateTemplate: (name: string, description: string) => void;
  onSavePatch: (patchId: string, payload: NotePatchUpdate) => void;
  onAcceptEdited: (patchId: string, payload: NotePatchUpdate) => void;
  onReject: (patchId: string) => void;
}

interface ExportPanelProps {
  exportKind: ArticleExportKind;
  targetLanguage: string;
  result?: ArticleExportResult;
  isExporting: boolean;
  error: boolean;
  downloadUrl?: string;
  onExportKindChange: (value: ArticleExportKind) => void;
  onExport: () => void;
}

function ChatPanel({
  messages,
  citedBlocks,
  streamingAnswer,
  selectedBlockUid,
  question,
  nativeSearch,
  nativeSearchAvailable,
  isAsking,
  isCreatingNotePatch,
  canAsk,
  canCreateNotePatch,
  error,
  onQuestionChange,
  onNativeSearchChange,
  onClearBlock,
  onAsk,
  onCreateNotePatch
}: ChatPanelProps) {
  return (
    <div className="panel reader-chat-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <MessageSquare size={18} />
            <Title order={3}>Paper chat</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Answers are grounded in local article blocks and saved with cited block IDs.
          </Text>
        </div>
        {selectedBlockUid ? (
          <Button variant="subtle" size="xs" onClick={onClearBlock}>
            Current block {selectedBlockUid}
          </Button>
        ) : null}
      </Group>
      <Stack gap="sm" mt="md">
        {messages.length === 0 ? (
          <Text c="dimmed" size="sm">
            No questions yet. Use a block toolbar or ask about the whole paper.
          </Text>
        ) : null}
        {messages.map((message) => {
          const sourceRefs = message.source_refs ?? [];
          const externalRefs = message.external_refs ?? [];
          return (
            <div className={`chat-message chat-message-${message.role}`} key={message.id}>
              <Group justify="space-between" align="center">
                <Badge variant="light">{message.role}</Badge>
                {message.role === "assistant" ? (
                  <Button
                    size="xs"
                    variant="subtle"
                    leftSection={<FileText size={14} />}
                    loading={isCreatingNotePatch}
                    disabled={!canCreateNotePatch}
                    onClick={() => onCreateNotePatch(message.id)}
                  >
                    Create note patch
                  </Button>
                ) : null}
              </Group>
              <Text>{message.content}</Text>
              {sourceRefs.length > 0 ? (
                <Group gap="xs" aria-label="Current-paper evidence">
                  {sourceRefs.map((ref) => (
                    <a className="source-ref" href={`#${ref}`} key={ref}>
                      {ref}
                    </a>
                  ))}
                </Group>
              ) : null}
              {externalRefs.length > 0 ? <ExternalEvidence refs={externalRefs} /> : null}
            </div>
          );
        })}
        {streamingAnswer ? (
          <div className="chat-message chat-message-assistant" aria-live="polite">
            <Badge variant="light">assistant</Badge>
            <Text>{streamingAnswer}</Text>
          </div>
        ) : null}
      </Stack>
      {citedBlocks.length > 0 ? (
        <div className="retrieved-blocks">
          <Text fw={600} size="sm">
            Current-paper evidence
          </Text>
          <Group gap="xs" mt="xs">
            {citedBlocks.map((block) => (
              <a className="source-ref" href={`#${block.block_uid}`} key={block.block_uid}>
                {block.block_uid}
              </a>
            ))}
          </Group>
        </div>
      ) : null}
      <Textarea
        label="Question"
        placeholder="Ask about the current paragraph or the whole paper"
        autosize
        minRows={2}
        mt="md"
        value={question}
        onChange={(event) => onQuestionChange(event.target.value)}
      />
      <Group justify="space-between" align="center" mt="sm">
        <Checkbox
          label="Use model-native search"
          checked={nativeSearch}
          disabled={!nativeSearchAvailable}
          onChange={(event) => onNativeSearchChange(event.currentTarget.checked)}
        />
        <Button
          leftSection={<Send size={16} />}
          onClick={onAsk}
          loading={isAsking}
          disabled={!canAsk || !question.trim()}
        >
          Ask paper
        </Button>
      </Group>
      {!nativeSearchAvailable ? (
        <Text c="dimmed" size="xs" mt="xs">
          Native search is disabled for this provider, so answers are restricted to article context.
        </Text>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          Question could not be answered. Check provider settings or select a parsed article.
        </Text>
      ) : null}
    </div>
  );
}

function ExternalEvidence({ refs }: { refs: ExternalCitation[] }) {
  return (
    <div className="external-evidence">
      <Text fw={600} size="xs">
        External evidence
      </Text>
      <Stack gap={4} mt={4}>
        {refs.map((ref, index) => {
          const label = ref.title || ref.url || ref.doi || ref.arxiv_id || "External citation";
          return (
            <Text size="xs" c="dimmed" key={`${label}-${index}`}>
              {ref.url ? (
                <a href={ref.url} target="_blank" rel="noreferrer">
                  {label}
                </a>
              ) : (
                label
              )}
              {ref.doi ? ` · DOI ${ref.doi}` : ""}
              {ref.arxiv_id ? ` · arXiv ${ref.arxiv_id}` : ""}
            </Text>
          );
        })}
      </Stack>
    </div>
  );
}

function ExportPanel({
  exportKind,
  targetLanguage,
  result,
  isExporting,
  error,
  downloadUrl,
  onExportKindChange,
  onExport
}: ExportPanelProps) {
  const t = useT();
  const missingTranslationBlockUids = result?.missing_translation_block_uids ?? [];
  return (
    <div className="panel reader-export-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <Download size={18} />
            <Title order={3}>Export</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Create a complete Markdown file or portable bundle and download it through the browser.
          </Text>
        </div>
        <Group align="end">
          <Select
            label="Export kind"
            value={exportKind}
            data={[
              { value: "bilingual_markdown", label: `Bilingual Markdown (${targetLanguage})` },
              { value: "translated_markdown", label: `Translated Markdown (${targetLanguage})` },
              { value: "source_markdown", label: "Source Markdown" },
              { value: "lecture_notes", label: "Lecture notes" },
              { value: "bundle_zip", label: "Article bundle zip" }
            ]}
            onChange={(value) => {
              if (value) onExportKindChange(value as ArticleExportKind);
            }}
          />
          <Button leftSection={<Download size={16} />} onClick={onExport} loading={isExporting}>
            Export and download
          </Button>
        </Group>
      </Group>
      <Text className="obsidian-export-help" c="dimmed" size="sm" mt="sm">
        {t("reader.obsidianHelp")}
      </Text>
      {result ? (
        <div className="export-result">
          <Text size="sm">
            Ready: {result.file_name} ({result.bytes_written} bytes). The browser download should
            start automatically.
          </Text>
          {missingTranslationBlockUids.length > 0 ? (
            <Text c="yellow" size="sm">
              Missing translations: {missingTranslationBlockUids.join(", ")}
            </Text>
          ) : null}
          {downloadUrl ? (
            <Button
              component="a"
              href={downloadUrl}
              download={result.file_name}
              rel="noreferrer"
              variant="light"
              size="xs"
              leftSection={<Download size={14} />}
            >
              Download file
            </Button>
          ) : null}
        </div>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          Export failed. Check that the article has parsed document artifacts.
        </Text>
      ) : null}
    </div>
  );
}

function NotesPanel({
  templates,
  patches,
  selectedTemplateId,
  isLoading,
  isGenerating,
  isSavingPatch,
  isSavingTemplate,
  isRejecting,
  canGenerate,
  error,
  onTemplateChange,
  onGenerate,
  onCreateTemplate,
  onSavePatch,
  onAcceptEdited,
  onReject
}: NotesPanelProps) {
  const [templateName, setTemplateName] = useState("");
  const [templateDescription, setTemplateDescription] = useState("");
  const [patchDrafts, setPatchDrafts] = useState<Record<string, NotePatchDraft>>({});
  const templateOptions =
    templates.length > 0
      ? templates.map((template) => ({
          value: template.id,
          label: template.custom ? `${template.name} · custom` : template.name
        }))
      : [{ value: "deep_reading", label: "精读模板" }];

  useEffect(() => {
    setPatchDrafts((current) => {
      const next: Record<string, NotePatchDraft> = {};
      let changed = false;
      for (const patch of patches) {
        const draft = current[patch.id];
        next[patch.id] = draft ?? {
          title: patch.title,
          patchMarkdown: patch.patch_markdown
        };
        if (!draft) changed = true;
      }
      if (Object.keys(current).length !== patches.length) changed = true;
      return changed ? next : current;
    });
  }, [patches]);

  const updatePatchDraft = (patchId: string, values: Partial<NotePatchDraft>) => {
    setPatchDrafts((current) => ({
      ...current,
      [patchId]: {
        title: current[patchId]?.title ?? "",
        patchMarkdown: current[patchId]?.patchMarkdown ?? "",
        ...values
      }
    }));
  };

  const submitTemplate = () => {
    const name = templateName.trim();
    const description = templateDescription.trim();
    if (!name || !description) return;
    onCreateTemplate(name, description);
    setTemplateName("");
    setTemplateDescription("");
  };

  return (
    <div className="panel reader-notes-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <FileText size={18} />
            <Title order={3}>Lecture notes</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Generate editable learning-note patches from article evidence and saved chat.
          </Text>
        </div>
        <Group align="end">
          <Select
            label="Template"
            value={selectedTemplateId}
            data={templateOptions}
            onChange={(value) => {
              if (value) onTemplateChange(value);
            }}
          />
          <Button
            leftSection={<FileText size={16} />}
            onClick={onGenerate}
            loading={isGenerating}
            disabled={!canGenerate || !selectedTemplateId}
          >
            Generate patch
          </Button>
        </Group>
      </Group>
      <Stack gap="xs" mt="md">
        <Group align="end">
          <TextInput
            label="Custom template name"
            placeholder="Seminar critique"
            value={templateName}
            onChange={(event) => setTemplateName(event.currentTarget.value)}
          />
          <Textarea
            label="Custom template prompt"
            placeholder="Focus on assumptions, open questions, and discussion points"
            autosize
            minRows={2}
            value={templateDescription}
            onChange={(event) => setTemplateDescription(event.currentTarget.value)}
          />
          <Button
            variant="light"
            onClick={submitTemplate}
            loading={isSavingTemplate}
            disabled={!templateName.trim() || !templateDescription.trim()}
          >
            Save template
          </Button>
        </Group>
      </Stack>
      {isLoading ? (
        <Group mt="sm">
          <Loader size="sm" />
          <Text c="dimmed" size="sm">
            Loading note patches...
          </Text>
        </Group>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          Note patch action failed. Check provider settings and the article document.
        </Text>
      ) : null}
      <Stack gap="sm" mt="md">
        {patches.length === 0 ? (
          <Text c="dimmed" size="sm">
            No lecture-note patches yet. Generate one from the selected template.
          </Text>
        ) : null}
        {patches.map((patch) => {
          const sourceRefs = patch.source_refs ?? [];
          const draft = patchDrafts[patch.id] ?? {
            title: patch.title,
            patchMarkdown: patch.patch_markdown
          };
          return (
            <div className="note-patch" key={patch.id}>
              <Group justify="space-between" align="flex-start">
                <div>
                  <Group gap="xs">
                    <Badge variant="light" color={noteStatusColor(patch.status)}>
                      {patch.status}
                    </Badge>
                    <Text fw={700}>{patch.title}</Text>
                  </Group>
                  {sourceRefs.length > 0 ? (
                    <Group gap="xs" mt="xs">
                      {sourceRefs.map((ref) => (
                        <a className="source-ref" href={`#${ref}`} key={ref}>
                          {ref}
                        </a>
                      ))}
                    </Group>
                  ) : null}
                </div>
                {patch.status === "proposed" ? (
                  <Group gap="xs">
                    <Button
                      size="xs"
                      variant="light"
                      onClick={() =>
                        onSavePatch(patch.id, {
                          title: draft.title,
                          patch_markdown: draft.patchMarkdown
                        })
                      }
                      loading={isSavingPatch}
                    >
                      Save draft
                    </Button>
                    <Button
                      size="xs"
                      variant="light"
                      color="green"
                      leftSection={<Check size={14} />}
                      loading={isSavingPatch}
                      onClick={() =>
                        onAcceptEdited(patch.id, {
                          title: draft.title,
                          patch_markdown: draft.patchMarkdown
                        })
                      }
                    >
                      Accept edited
                    </Button>
                    <Button
                      size="xs"
                      variant="subtle"
                      color="red"
                      leftSection={<X size={14} />}
                      loading={isRejecting}
                      onClick={() => onReject(patch.id)}
                    >
                      Reject
                    </Button>
                  </Group>
                ) : null}
              </Group>
              {patch.status === "proposed" ? (
                <Stack gap="xs" mt="sm">
                  <TextInput
                    label={`Note title for ${patch.id}`}
                    value={draft.title}
                    onChange={(event) =>
                      updatePatchDraft(patch.id, { title: event.currentTarget.value })
                    }
                  />
                  <Textarea
                    label={`Patch markdown for ${patch.id}`}
                    autosize
                    minRows={5}
                    value={draft.patchMarkdown}
                    onChange={(event) =>
                      updatePatchDraft(patch.id, { patchMarkdown: event.currentTarget.value })
                    }
                  />
                </Stack>
              ) : (
                <pre className="note-markdown">{patch.patch_markdown}</pre>
              )}
            </div>
          );
        })}
      </Stack>
    </div>
  );
}

interface NotePatchDraft {
  title: string;
  patchMarkdown: string;
}

function GlossaryPanel({
  terms,
  targetLanguage,
  activeVersion,
  affectedBlockUids,
  isLoading,
  isExtracting,
  isSaving,
  canRetranslate,
  onExtract,
  onCreate,
  onConfirm,
  onRetranslateAffected
}: GlossaryPanelProps) {
  const [sourceTerm, setSourceTerm] = useState("");
  const [targetTerm, setTargetTerm] = useState("");
  const [candidateTargets, setCandidateTargets] = useState<Record<string, string>>({});
  const activeTerms = terms.filter((term) => term.status === "active");
  const candidates = terms.filter((term) => term.status === "candidate");

  const submitNewTerm = () => {
    const source = sourceTerm.trim();
    const target = targetTerm.trim();
    if (!source || !target) return;
    onCreate(source, target);
    setSourceTerm("");
    setTargetTerm("");
  };

  const confirmCandidate = (term: GlossaryTerm) => {
    const target = (candidateTargets[term.id] ?? term.target_term).trim();
    if (!target) return;
    onConfirm(term, target);
  };

  return (
    <div className="panel reader-glossary-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <BookMarked size={18} />
            <Title order={3}>Glossary</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Article terminology for {targetLanguage}. Active version {activeVersion}.
          </Text>
        </div>
        <Group>
          <Button
            variant="light"
            leftSection={<Sparkles size={16} />}
            onClick={onExtract}
            loading={isExtracting}
          >
            Extract terms
          </Button>
          <Button
            variant="light"
            color="yellow"
            leftSection={<RefreshCw size={16} />}
            disabled={!canRetranslate || affectedBlockUids.length === 0}
            onClick={onRetranslateAffected}
          >
            Retranslate affected
          </Button>
        </Group>
      </Group>
      {isLoading ? (
        <Group mt="sm">
          <Loader size="sm" />
          <Text c="dimmed" size="sm">
            Loading glossary...
          </Text>
        </Group>
      ) : null}
      {affectedBlockUids.length > 0 ? (
        <Alert color="yellow" mt="sm">
          {affectedBlockUids.length} translated blocks were generated with an older glossary
          version.
        </Alert>
      ) : null}
      <Group align="end" mt="md">
        <TextInput
          label="Source term"
          value={sourceTerm}
          onChange={(event) => setSourceTerm(event.target.value)}
        />
        <TextInput
          label="Target term"
          value={targetTerm}
          onChange={(event) => setTargetTerm(event.target.value)}
        />
        <Button
          leftSection={<Check size={16} />}
          onClick={submitNewTerm}
          loading={isSaving}
          disabled={!sourceTerm.trim() || !targetTerm.trim()}
        >
          Add term
        </Button>
      </Group>
      <Divider my="md" />
      <Stack gap="sm">
        {activeTerms.length === 0 && candidates.length === 0 ? (
          <Text c="dimmed" size="sm">
            No glossary terms yet. Extract candidates from the parsed article or add a term
            manually.
          </Text>
        ) : null}
        {activeTerms.map((term) => (
          <div className="glossary-row" key={term.id}>
            <Badge variant="light" color="green">
              Active
            </Badge>
            <Text fw={600}>{term.source_term}</Text>
            <Text c="dimmed">
              {"=>"} {term.target_term}
            </Text>
          </div>
        ))}
        {candidates.map((term) => (
          <div className="glossary-candidate" key={term.id}>
            <div>
              <Group gap="xs">
                <Badge variant="light" color="gray">
                  Candidate
                </Badge>
                <Text fw={600}>{term.source_term}</Text>
              </Group>
              <Text c="dimmed" size="xs">
                {candidateSummary(term)}
              </Text>
            </div>
            <TextInput
              aria-label={`Target term for ${term.source_term}`}
              placeholder="Confirmed target term"
              value={candidateTargets[term.id] ?? term.target_term}
              onChange={(event) =>
                setCandidateTargets((current) => ({
                  ...current,
                  [term.id]: event.target.value
                }))
              }
            />
            <Button
              variant="light"
              leftSection={<Check size={16} />}
              onClick={() => confirmCandidate(term)}
              loading={isSaving}
              disabled={!(candidateTargets[term.id] ?? term.target_term).trim()}
            >
              Confirm
            </Button>
          </div>
        ))}
      </Stack>
    </div>
  );
}

function noteStatusColor(status: string): string {
  if (status === "accepted") return "green";
  if (status === "rejected") return "red";
  return "blue";
}

function candidateSummary(term: GlossaryTerm): string {
  const count = term.metadata?.occurrence_count;
  const blockUids = term.metadata?.block_uids;
  const occurrenceText = typeof count === "number" ? `${count} occurrences` : "rule candidate";
  const blockText = Array.isArray(blockUids) ? ` · ${blockUids.length} blocks` : "";
  return `${occurrenceText}${blockText}`;
}

function translationVariantOptions(variants: TranslationVariant[]) {
  return variants.map((variant, index) => {
    const source =
      variant.metadata?.cache_source === "translation_memory"
        ? "memory"
        : (variant.model ?? "local");
    const status = variant.validation_status === "ok" ? "ok" : variant.validation_status;
    const prefix = variant.is_default ? "Default" : `Variant ${index + 1}`;
    return {
      value: variant.id,
      label: `${prefix} · ${source} · ${status}`
    };
  });
}

function isEvidenceStreamData(data: unknown): data is { cited_blocks: RetrievedBlock[] } {
  return (
    typeof data === "object" &&
    data !== null &&
    Array.isArray((data as { cited_blocks?: unknown }).cited_blocks)
  );
}

function isDeltaStreamData(data: unknown): data is { text: string } {
  return (
    typeof data === "object" &&
    data !== null &&
    typeof (data as { text?: unknown }).text === "string"
  );
}

export interface ReaderSearchIndexEntry {
  blockUid: string;
  title: string;
  sourceText: string;
  translationText: string;
  haystack: string;
}

export interface ReaderSearchState {
  query: string;
  cursor: number;
  matches: ReaderSearchMatch[];
}

interface ReaderSearchMatch {
  blockUid: string;
  label: string;
  index: number;
}

function buildReaderSearchIndex(
  blocks: DocumentBlock[],
  translationByBlockUid: Map<string, string>
): ReaderSearchIndexEntry[] {
  return blocks.map((block) => {
    const sourceText = plainTextForReaderSearch(block.source_markdown);
    const translationText = plainTextForReaderSearch(
      translationByBlockUid.get(block.block_uid) ?? ""
    );
    const title = isSearchTitleBlock(block) ? chapterTitle(block) : block.block_uid;
    return {
      blockUid: block.block_uid,
      title,
      sourceText,
      translationText,
      haystack: `${title}\n${sourceText}\n${translationText}`.toLocaleLowerCase()
    };
  });
}

function searchReaderIndex(index: ReaderSearchIndexEntry[], query: string): ReaderSearchMatch[] {
  const normalizedQuery = query.trim().toLocaleLowerCase();
  if (!normalizedQuery) return [];
  return index.flatMap((entry) => {
    const matchIndex = entry.haystack.indexOf(normalizedQuery);
    if (matchIndex < 0) return [];
    return [
      {
        blockUid: entry.blockUid,
        label: entry.title,
        index: matchIndex
      }
    ];
  });
}

function plainTextForReaderSearch(markdown: string) {
  return markdown
    .replace(/<[^>]+>/g, " ")
    .replace(/!\[[^\]]*]\([^)]*\)/g, " ")
    .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/\\\((.*?)\\\)/g, "$1")
    .replace(/\\\[(.*?)\\\]/gs, "$1")
    .replace(/\$([^$]+)\$/g, "$1")
    .replace(/^#+\s+/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}

function isSearchTitleBlock(block: DocumentBlock) {
  return ["title", "abstract", "section", "subsection", "subsubsection"].includes(block.block_type);
}

function articleTitle(document: ArticleDocument | undefined, t: ReturnType<typeof useT>): string {
  const title = document?.manifest.arxiv_metadata?.title;
  return typeof title === "string" && title.trim() ? title : t("reader.emptyTitle");
}

function chapterNumber(index: number, block: DocumentBlock): string {
  const level = block.metadata?.level;
  if (typeof level === "number" && level > 1) return `§${index + 1}`;
  return `${index + 1}`;
}

function chapterTitle(block: DocumentBlock): string {
  const text = block.source_markdown
    .replace(/^#+\s*/, "")
    .replace(/\*\*/g, "")
    .replace(/`/g, "")
    .trim();
  return text || block.structural_path;
}

function assetForBlock(
  block: DocumentBlock,
  assets: Map<string, AssetRecord>
): AssetRecord | undefined {
  const assetId = block.metadata?.asset_id;
  return typeof assetId === "string" ? assets.get(assetId) : undefined;
}

function stringMetadata(metadata: DocumentBlock["metadata"] | undefined, key: string) {
  const value = metadata?.[key];
  return typeof value === "string" ? value : undefined;
}

function referenceTargetsForBlocks(blocks: DocumentBlock[]): ReferenceTargets {
  const targets: ReferenceTargets = {};
  for (const block of blocks) {
    const target = { blockUid: block.block_uid, blockType: referenceTargetBlockType(block) };
    targets[block.block_uid] = target;
    const label = block.metadata?.label;
    if (typeof label === "string" && label.trim()) {
      targets[label] = target;
    }
  }
  return targets;
}

function citationLookupForEntries(citations: CitationEntry[]): CitationLookup {
  const lookup: CitationLookup = {};
  for (const citation of citations) {
    lookup[citation.id] = citation;
  }
  return lookup;
}

function referenceTargetBlockType(block: DocumentBlock): string {
  const label = block.metadata?.label;
  if (
    block.block_type === "table" &&
    /ltx_(?:equation|equationgroup|eqn_)/i.test(
      stringMetadata(block.metadata, "html_fragment") ?? ""
    )
  ) {
    return "equation";
  }
  if (
    block.block_type === "figure" &&
    ((typeof label === "string" && /(^tab:|\.T\d+$)/i.test(label)) ||
      /^\*\*Table\s+\d+/i.test(block.source_markdown))
  ) {
    return "table";
  }
  return block.block_type;
}

function navBlockUidForActiveBlock(
  blocks: DocumentBlock[],
  navBlocks: DocumentBlock[],
  activeBlockUid: string | null
): string | null {
  if (!activeBlockUid) return null;
  if (navBlocks.some((block) => block.block_uid === activeBlockUid)) return activeBlockUid;
  const activeIndex = blocks.findIndex((block) => block.block_uid === activeBlockUid);
  for (let index = activeIndex; index >= 0; index -= 1) {
    if (blocks[index]?.block_type === "section") return blocks[index].block_uid;
  }
  return navBlocks[0]?.block_uid ?? activeBlockUid;
}

function assetUrl(
  libraryId: string | undefined,
  articleId: string | undefined,
  asset: AssetRecord | undefined
): string | undefined {
  if (!libraryId || !articleId || !asset?.web_path) return undefined;
  const encodedLibrary = encodeURIComponent(libraryId);
  const encodedArticle = encodeURIComponent(articleId);
  const encodedAsset = encodeURIComponent(asset.asset_id);
  return `${API_BASE_URL}/libraries/${encodedLibrary}/articles/${encodedArticle}/assets/${encodedAsset}`;
}

function assetFileUrls(
  libraryId: string | undefined,
  articleId: string | undefined,
  asset: AssetRecord | undefined
): ReaderAssetFile[] {
  if (!libraryId || !articleId || !asset) return [];
  const assetFiles = asset.metadata?.asset_files;
  if (!Array.isArray(assetFiles)) {
    const originalReference = asset.metadata?.original_reference;
    const url = assetUrl(libraryId, articleId, asset);
    return typeof originalReference === "string" && url
      ? [{ index: 1, originalReference, url }]
      : [];
  }
  const encodedLibrary = encodeURIComponent(libraryId);
  const encodedArticle = encodeURIComponent(articleId);
  const encodedAsset = encodeURIComponent(asset.asset_id);
  return assetFiles.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const index = "index" in item ? item.index : undefined;
    const originalReference = "original_reference" in item ? item.original_reference : undefined;
    const webPath = "web_path" in item ? item.web_path : undefined;
    if (
      typeof index !== "number" ||
      typeof originalReference !== "string" ||
      typeof webPath !== "string"
    ) {
      return [];
    }
    return [
      {
        index,
        originalReference,
        url: `${API_BASE_URL}/libraries/${encodedLibrary}/articles/${encodedArticle}/assets/${encodedAsset}/files/${index}`,
        metadata: item as Record<string, unknown>
      }
    ];
  });
}

function exportDownloadUrl(
  libraryId: string | undefined,
  articleId: string | undefined,
  result: ArticleExportResult | undefined
): string | undefined {
  if (!libraryId || !articleId || !result) return undefined;
  const encodedLibrary = encodeURIComponent(libraryId);
  const encodedArticle = encodeURIComponent(articleId);
  const encodedFile = encodeURIComponent(result.file_name);
  return `${API_BASE_URL}/libraries/${encodedLibrary}/articles/${encodedArticle}/exports/${encodedFile}`;
}

function triggerBrowserDownload(url: string, fileName: string): void {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  anchor.rel = "noreferrer";
  anchor.style.display = "none";
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
}
