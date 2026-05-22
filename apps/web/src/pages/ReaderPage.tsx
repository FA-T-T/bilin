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
  Text,
  Textarea,
  TextInput,
  Title
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
  RefreshCw,
  Search,
  Send,
  Sparkles,
  StickyNote,
  TerminalSquare,
  Type,
  X
} from "lucide-react";
import {
  type CSSProperties,
  type ReactNode,
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { API_BASE_URL, apiClient } from "../api/client";
import {
  useArticleCitations,
  useArticleGlossary,
  useArticleChat,
  useArticleDocument,
  useArticleReadingProgress,
  useArticleTranslations,
  useArticles,
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
  useJobSummary,
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
  ArticleListItem,
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
  MarkdownContent,
  ReaderBlock,
  type CitationImportMode,
  type CitationLookup,
  type ReaderBlockColor,
  type ReaderAssetFile,
  type ReferenceTargets,
  type TermAnnotation
} from "../components/ReaderBlock";
import { KindlePagedReader } from "../components/KindlePagedReader";
import { ReaderBlockList } from "../components/ReaderBlockList";
import { ReaderPreferencesPanel } from "../components/ReaderPreferencesPanel";
import type { ReaderToolbarActionId } from "../components/readerToolbarActions";
import { activeGlossaryTerms, applyGlossaryToMarkdown } from "../glossary";
import { useT, type MessageKey } from "../i18n";
import { TRANSLATION_TARGET_LOCALES } from "../product";
import { type ReaderPreferences, type ReaderViewMode, useUiStore } from "../state/ui";

const emptyReaderAssetFiles: ReaderAssetFile[] = [];
const emptyCitationLookup: CitationLookup = {};
const READING_PROGRESS_RECORD_INTERVAL_MS = 30_000;
const READING_PROGRESS_MAX_IDLE_MS = 60_000;
const READER_CHROME_HIDE_SCROLL_Y = 128;
const READER_CHROME_REVEAL_SCROLL_Y = 48;
const READER_CHROME_SCROLL_INTENT_PX = 32;

interface ReaderCardDraft {
  cardId?: string;
  blockUid: string;
  anchorText: string;
  title: string;
  bodyMarkdown: string;
}

type ReaderToolbarPanel =
  | "tasks"
  | "providers"
  | "ask"
  | "translate"
  | "glossary"
  | "notes"
  | "export"
  | "preferences";

export function ReaderPage() {
  const t = useT();
  const { articleId } = useParams();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const libraryId = searchParams.get("libraryId") ?? undefined;
  const hasArticleContext = Boolean(libraryId && articleId);
  const viewMode = useUiStore((state) => state.readerViewMode);
  const setReaderViewMode = useUiStore((state) => state.setReaderViewMode);
  const readerSurfaceMode = useUiStore((state) => state.readerSurfaceMode);
  const setReaderSurfaceMode = useUiStore((state) => state.setReaderSurfaceMode);
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
  const jobSummary = useJobSummary();
  const libraryArticles = useArticles(libraryId, targetLanguage);
  const [selectedProviderId, setSelectedProviderId] = useState<string | null>(null);
  const [chatBlockUid, setChatBlockUid] = useState<string | null>(null);
  const [question, setQuestion] = useState("");
  const [readerArticleSearchQuery, setReaderArticleSearchQuery] = useState("");
  const [readerArticleRailOpen, setReaderArticleRailOpen] = useState(false);
  const [activeReaderToolbarPanel, setActiveReaderToolbarPanel] =
    useState<ReaderToolbarPanel | null>(null);
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
  const [termWikiEnabled, setTermWikiEnabled] = useState(false);
  const [readerModeMenuOpen, setReaderModeMenuOpen] = useState(false);
  const [readerChromeHidden, setReaderChromeHidden] = useState(false);
  const [kindleChromeHidden, setKindleChromeHidden] = useState(false);
  const [expandedReaderCardByBlock, setExpandedReaderCardByBlock] = useState<
    Record<string, string | null>
  >({});
  const [quickAskBlockUid, setQuickAskBlockUid] = useState<string | null>(null);
  const [readerCardDraft, setReaderCardDraft] = useState<ReaderCardDraft | null>(null);
  const lastExportDownloadKey = useRef<string | null>(null);
  const lastInitialHashNavigation = useRef<string | null>(null);
  const lastSavedProgressNavigation = useRef<string | null>(null);
  const lastReaderScrollY = useRef(0);
  const readerChromeHiddenRef = useRef(false);
  const readerChromeHideIntentPx = useRef(0);
  const readerChromeRevealIntentPx = useRef(0);
  const activeBlockUidRef = useRef<string | null>(null);
  const lastReaderActivityAt = useRef(Date.now());
  const lastReadingProgressSampleAt = useRef(Date.now());
  const pendingReadingProgressDeltas = useRef<Record<string, number>>({});
  const previousTargetLanguage = useRef(targetLanguage);
  const document = useArticleDocument(libraryId, articleId);
  const readingProgress = useArticleReadingProgress(libraryId, articleId);
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
  const readerArticleItems = useMemo(() => libraryArticles.data ?? [], [libraryArticles.data]);
  const visibleReaderArticleItems = useMemo(
    () => filterReaderArticleItems(readerArticleItems, readerArticleSearchQuery),
    [readerArticleItems, readerArticleSearchQuery]
  );
  const currentArticleItem = useMemo(
    () => readerArticleItems.find((item) => item.article_revision.id === articleId) ?? null,
    [articleId, readerArticleItems]
  );
  const blockIndexByUid = useMemo(() => blockIndexMapForBlocks(blocks), [blocks]);
  const navBlocks = useMemo(
    () => blocks.filter((block) => block.block_type === "section"),
    [blocks]
  );
  const navBlockUidByBlockUid = useMemo(() => navBlockUidMapForBlocks(blocks), [blocks]);
  const activeNavBlockUid = activeBlockUid
    ? (navBlockUidByBlockUid.get(activeBlockUid) ?? null)
    : null;
  const activeBlockIndex = useMemo(() => {
    if (!activeBlockUid) return blocks.length > 0 ? 0 : -1;
    const index = blockIndexByUid.get(activeBlockUid) ?? -1;
    return index >= 0 ? index : blocks.length > 0 ? 0 : -1;
  }, [activeBlockUid, blockIndexByUid, blocks.length]);
  const activeBlockOrdinal = activeBlockIndex >= 0 ? activeBlockIndex + 1 : 0;
  const readerProgress =
    blocks.length > 0 ? Math.round((activeBlockOrdinal / blocks.length) * 100) : 0;
  const activeChapterLabel = useMemo(() => {
    const activeChapter = navBlocks.find((block) => block.block_uid === activeNavBlockUid);
    return activeChapter ? chapterTitle(activeChapter) : t("reader.noChapter");
  }, [activeNavBlockUid, navBlocks, t]);
  const chapterRailEnabled = readerFeaturePreferences.chapterIndexVisible && navBlocks.length > 0;
  const chapterRailOpen = chapterRailEnabled && chaptersOpen;
  const referenceTargets = useMemo(() => referenceTargetsForBlocks(blocks), [blocks]);
  const citationLookup = useMemo(
    () => citationLookupForEntries(citations.data?.citations ?? []),
    [citations.data?.citations]
  );
  const effectiveCitationLookup = readerFeaturePreferences.citationPreviewEnabled
    ? citationLookup
    : emptyCitationLookup;
  const kindleMode = readerSurfaceMode === "kindle";
  const readerRightRailOpen = activeReaderToolbarPanel !== null;

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
  const glossaryTerms = useMemo(() => glossary.data?.terms ?? [], [glossary.data?.terms]);
  const blockTextForPlaceholder = useCallback(
    (block: DocumentBlock) =>
      viewMode === "translation"
        ? (translationByBlockUid.get(block.block_uid) ?? block.source_markdown)
        : block.source_markdown,
    [translationByBlockUid, viewMode]
  );
  const deferredReaderSearchQuery = useDeferredValue(readerSearchQuery);
  const readerSearchMatches = useMemo(
    () => searchReaderBlocks(blocks, translationByBlockUid, deferredReaderSearchQuery),
    [blocks, deferredReaderSearchQuery, translationByBlockUid]
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
  const activeReaderModeOptions = useMemo(
    () =>
      kindleMode
        ? readerModeOptions.filter((option) => ["bilingual", "translation"].includes(option.value))
        : readerModeOptions,
    [kindleMode, readerModeOptions]
  );
  const currentReaderModeLabel =
    activeReaderModeOptions.find((option) => option.value === viewMode)?.label ??
    activeReaderModeOptions[0]?.label ??
    t("reader.modeMenu");
  const kindleBlockViewMode: ReaderViewMode =
    viewMode === "translation" ? "translation" : "bilingual";
  const kindleBlockTextForPagination = useCallback(
    (block: DocumentBlock) => {
      const translation = translationByBlockUid.get(block.block_uid);
      if (kindleBlockViewMode === "translation") return translation ?? block.source_markdown;
      if (!translation) return block.source_markdown;
      return `${block.source_markdown}\n\n${translation}`;
    },
    [kindleBlockViewMode, translationByBlockUid]
  );

  const markReaderActivity = useCallback(() => {
    lastReaderActivityAt.current = Date.now();
  }, []);

  const toggleReaderToolbarPanel = useCallback((panel: ReaderToolbarPanel) => {
    setReaderModeMenuOpen(false);
    setActiveReaderToolbarPanel((current) => (current === panel ? null : panel));
  }, []);

  const closeReaderToolbarPanel = useCallback(() => {
    setActiveReaderToolbarPanel(null);
  }, []);

  const toggleReaderModeMenu = useCallback(() => {
    setActiveReaderToolbarPanel(null);
    setReaderModeMenuOpen((open) => !open);
  }, []);

  const mergePendingReadingDeltas = useCallback((deltas: Record<string, number>) => {
    for (const [blockUid, seconds] of Object.entries(deltas)) {
      pendingReadingProgressDeltas.current[blockUid] =
        (pendingReadingProgressDeltas.current[blockUid] ?? 0) + seconds;
    }
  }, []);

  const collectReadingProgressSample = useCallback(
    (force = false) => {
      const now = Date.now();
      const elapsedMs = now - lastReadingProgressSampleAt.current;
      if (!force && elapsedMs < READING_PROGRESS_RECORD_INTERVAL_MS) return false;
      lastReadingProgressSampleAt.current = now;
      if (typeof globalThis.document !== "undefined" && globalThis.document.hidden && !force) {
        return false;
      }
      if (now - lastReaderActivityAt.current > READING_PROGRESS_MAX_IDLE_MS) return false;
      const blockUid = activeBlockUidRef.current;
      if (!blockUid) return false;
      const seconds = Math.max(
        1,
        Math.min(READING_PROGRESS_RECORD_INTERVAL_MS / 1000, Math.round(elapsedMs / 1000))
      );
      mergePendingReadingDeltas({ [blockUid]: seconds });
      return true;
    },
    [mergePendingReadingDeltas]
  );

  const flushReadingProgress = useCallback(
    (keepalive = false, collectPartialSample = false) => {
      if (!libraryId || !articleId) return;
      if (collectPartialSample) collectReadingProgressSample(true);
      const blockSeconds = pendingReadingProgressDeltas.current;
      const hasDeltas = Object.keys(blockSeconds).length > 0;
      const activeBlockUid = activeBlockUidRef.current;
      if (!hasDeltas && !activeBlockUid) return;
      pendingReadingProgressDeltas.current = {};
      void apiClient
        .updateReadingProgress(
          libraryId,
          articleId,
          {
            active_block_uid: activeBlockUid,
            block_seconds: blockSeconds
          },
          keepalive
        )
        .catch(() => {
          if (!keepalive) mergePendingReadingDeltas(blockSeconds);
        });
    },
    [articleId, collectReadingProgressSample, libraryId, mergePendingReadingDeltas]
  );

  useEffect(() => {
    if (!selectedProviderId && providers.data?.[0]) {
      setSelectedProviderId(providers.data[0].id);
    }
  }, [providers.data, selectedProviderId]);

  useEffect(() => {
    readerChromeHiddenRef.current = readerChromeHidden;
  }, [readerChromeHidden]);

  useEffect(() => {
    if (!kindleMode) setKindleChromeHidden(false);
  }, [kindleMode]);

  useEffect(() => {
    if (kindleMode || typeof window === "undefined") {
      readerChromeHiddenRef.current = false;
      readerChromeHideIntentPx.current = 0;
      readerChromeRevealIntentPx.current = 0;
      setReaderChromeHidden(false);
      return undefined;
    }
    lastReaderScrollY.current = window.scrollY;
    const handleReaderChromeScroll = () => {
      const scrollY = Math.max(0, window.scrollY);
      const delta = scrollY - lastReaderScrollY.current;
      lastReaderScrollY.current = scrollY;
      if (Math.abs(delta) < 4) return;
      if (scrollY < READER_CHROME_REVEAL_SCROLL_Y) {
        readerChromeHideIntentPx.current = 0;
        readerChromeRevealIntentPx.current = 0;
        readerChromeHiddenRef.current = false;
        setReaderChromeHidden(false);
        return;
      }
      if (delta > 0) {
        readerChromeHideIntentPx.current += delta;
        readerChromeRevealIntentPx.current = 0;
      } else {
        readerChromeRevealIntentPx.current += Math.abs(delta);
        readerChromeHideIntentPx.current = 0;
      }
      if (
        delta > 0 &&
        !readerChromeHiddenRef.current &&
        scrollY > READER_CHROME_HIDE_SCROLL_Y &&
        readerChromeHideIntentPx.current >= READER_CHROME_SCROLL_INTENT_PX
      ) {
        readerChromeHiddenRef.current = true;
        setReaderChromeHidden(true);
        setReaderModeMenuOpen(false);
        setActiveReaderToolbarPanel(null);
        return;
      }
      if (
        delta < 0 &&
        readerChromeHiddenRef.current &&
        readerChromeRevealIntentPx.current >= READER_CHROME_SCROLL_INTENT_PX
      ) {
        readerChromeHiddenRef.current = false;
        setReaderChromeHidden(false);
      }
    };
    window.addEventListener("scroll", handleReaderChromeScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleReaderChromeScroll);
  }, [kindleMode]);

  useEffect(() => {
    if (searchParams.get("kindle") === "1") {
      setReaderSurfaceMode("kindle");
    }
  }, [searchParams, setReaderSurfaceMode]);

  useEffect(() => {
    if (!kindleMode) return;
    if (viewMode === "bilingual" || viewMode === "translation") return;
    setReaderViewMode("bilingual");
  }, [kindleMode, setReaderViewMode, viewMode]);

  useEffect(() => {
    if (!kindleMode) return;
    setActiveReaderToolbarPanel(null);
  }, [kindleMode]);

  useEffect(() => {
    if (!termWikiEnabled || !readerFeaturePreferences.termCardsEnabled) return;
    setChaptersOpen(false);
    setActiveReaderToolbarPanel(null);
  }, [readerFeaturePreferences.termCardsEnabled, termWikiEnabled]);

  useEffect(() => {
    activeBlockUidRef.current = activeBlockUid;
  }, [activeBlockUid]);

  useEffect(() => {
    if (typeof window === "undefined") return undefined;
    const mark = () => markReaderActivity();
    window.addEventListener("scroll", mark, { passive: true });
    window.addEventListener("pointermove", mark, { passive: true });
    window.addEventListener("keydown", mark);
    window.addEventListener("focus", mark);
    return () => {
      window.removeEventListener("scroll", mark);
      window.removeEventListener("pointermove", mark);
      window.removeEventListener("keydown", mark);
      window.removeEventListener("focus", mark);
    };
  }, [markReaderActivity]);

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
    lastSavedProgressNavigation.current = null;
    lastReadingProgressSampleAt.current = Date.now();
    pendingReadingProgressDeltas.current = {};
  }, [articleId, targetLanguage]);

  useEffect(() => {
    if (blocks.length === 0 || typeof window === "undefined") return;
    const hashBlockUid = decodeURIComponent(window.location.hash.replace(/^#/, ""));
    if (!hashBlockUid) return;
    if (!blockIndexByUid.has(hashBlockUid)) return;
    const navigationKey = `${articleId ?? "mock"}:${hashBlockUid}`;
    if (lastInitialHashNavigation.current === navigationKey) return;
    lastInitialHashNavigation.current = navigationKey;
    setForcedBlockUid(hashBlockUid);
    setActiveBlockUid(hashBlockUid);
    setPendingNavigationBlockUid(hashBlockUid);
  }, [articleId, blockIndexByUid, blocks.length]);

  useEffect(() => {
    if (blocks.length === 0 || typeof window === "undefined") return;
    if (window.location.hash) return;
    const savedBlockUid = readingProgress.data?.active_block_uid;
    if (!savedBlockUid) return;
    if (!blockIndexByUid.has(savedBlockUid)) return;
    const navigationKey = `${articleId ?? "mock"}:${savedBlockUid}:${readingProgress.data?.updated_at ?? ""}`;
    if (lastSavedProgressNavigation.current === navigationKey) return;
    lastSavedProgressNavigation.current = navigationKey;
    setForcedBlockUid(savedBlockUid);
    setActiveBlockUid(savedBlockUid);
    setPendingNavigationBlockUid(savedBlockUid);
  }, [
    articleId,
    blockIndexByUid,
    blocks.length,
    readingProgress.data?.active_block_uid,
    readingProgress.data?.updated_at
  ]);

  useEffect(() => {
    setReaderSearchCursor(0);
  }, [readerSearchQuery]);

  useEffect(() => {
    if (readerSearchCursor < readerSearchMatches.length) return;
    setReaderSearchCursor(Math.max(0, readerSearchMatches.length - 1));
  }, [readerSearchCursor, readerSearchMatches.length]);

  useEffect(() => {
    if (!pendingNavigationBlockUid) return undefined;
    if (kindleMode) {
      setPendingNavigationBlockUid(null);
      return undefined;
    }
    let frame = 0;
    frame = requestAnimationFrame(() => {
      globalThis.document?.getElementById(pendingNavigationBlockUid)?.scrollIntoView({
        block: "start",
        behavior: "smooth"
      });
      setPendingNavigationBlockUid(null);
    });
    return () => cancelAnimationFrame(frame);
  }, [kindleMode, pendingNavigationBlockUid, forcedBlockUid]);

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
    if (!activeBlockUid || !blockIndexByUid.has(activeBlockUid)) {
      setActiveBlockUid(blocks[0].block_uid);
    }
  }, [activeBlockUid, blockIndexByUid, blocks]);

  useEffect(() => {
    if (!libraryId || !articleId || blocks.length === 0 || typeof window === "undefined") {
      return undefined;
    }
    lastReadingProgressSampleAt.current = Date.now();
    const interval = window.setInterval(() => {
      if (collectReadingProgressSample(false)) flushReadingProgress(false);
    }, READING_PROGRESS_RECORD_INTERVAL_MS);
    return () => {
      window.clearInterval(interval);
      flushReadingProgress(true, true);
    };
  }, [articleId, blocks.length, collectReadingProgressSample, flushReadingProgress, libraryId]);

  useEffect(() => {
    if (!libraryId || !articleId || typeof window === "undefined") return undefined;
    const flushOnExit = () => flushReadingProgress(true, true);
    const handleVisibilityChange = () => {
      if (globalThis.document?.hidden) {
        flushReadingProgress(true, true);
      } else {
        markReaderActivity();
        lastReadingProgressSampleAt.current = Date.now();
      }
    };
    window.addEventListener("pagehide", flushOnExit);
    window.addEventListener("beforeunload", flushOnExit);
    globalThis.document?.addEventListener("visibilitychange", handleVisibilityChange);
    return () => {
      window.removeEventListener("pagehide", flushOnExit);
      window.removeEventListener("beforeunload", flushOnExit);
      globalThis.document?.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [articleId, flushReadingProgress, libraryId, markReaderActivity]);

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

  const navigateToBlock = useCallback(
    (blockUid: string) => {
      markReaderActivity();
      setForcedBlockUid(blockUid);
      setActiveBlockUid(blockUid);
      setPendingNavigationBlockUid(kindleMode ? null : blockUid);
      if (typeof window !== "undefined") {
        const nextUrl = `${window.location.pathname}${window.location.search}#${encodeURIComponent(blockUid)}`;
        window.history.replaceState(null, "", nextUrl);
      }
    },
    [kindleMode, markReaderActivity]
  );

  const changeKindlePageBlock = useCallback(
    (blockUid: string) => {
      markReaderActivity();
      setForcedBlockUid(blockUid);
      setActiveBlockUid(blockUid);
      setPendingNavigationBlockUid(null);
      if (typeof window !== "undefined") {
        const nextUrl = `${window.location.pathname}${window.location.search}#${encodeURIComponent(blockUid)}`;
        window.history.replaceState(null, "", nextUrl);
      }
    },
    [markReaderActivity]
  );

  const hideKindleChrome = useCallback(() => {
    if (!kindleMode) return;
    setKindleChromeHidden(true);
    setReaderModeMenuOpen(false);
    setActiveReaderToolbarPanel(null);
  }, [kindleMode]);

  const showKindleChrome = useCallback(() => {
    if (kindleMode) setKindleChromeHidden(false);
  }, [kindleMode]);

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

  const openCurrentLibrary = useCallback(() => {
    navigate(libraryId ? `/libraries/${libraryId}` : "/");
  }, [libraryId, navigate]);

  const switchReaderArticle = useCallback(
    (item: ArticleListItem) => {
      if (!libraryId) return;
      const nextArticleId = item.article_revision.id;
      if (nextArticleId === articleId) return;
      flushReadingProgress(true, true);
      navigate(`/articles/${nextArticleId}?libraryId=${libraryId}`);
    },
    [articleId, flushReadingProgress, libraryId, navigate]
  );

  const openTaskDrawerForBackgroundWork = useCallback(() => {
    if (readerFeaturePreferences.taskNotificationsEnabled) {
      openTaskDrawer();
    }
  }, [openTaskDrawer, readerFeaturePreferences.taskNotificationsEnabled]);

  const handleActiveBlockChange = useCallback(
    (blockUid: string) => {
      markReaderActivity();
      setActiveBlockUid((current) => (current === blockUid ? current : blockUid));
    },
    [markReaderActivity]
  );

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
          termAnnotations={
            readerFeaturePreferences.termCardsEnabled
              ? termAnnotationsForBlock(
                  block,
                  glossaryTerms,
                  readerCardsByBlockUid.get(block.block_uid) ?? []
                )
              : []
          }
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
      glossaryTerms,
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
      readerFeaturePreferences.termCardsEnabled,
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

  const renderKindleBlock = useCallback(
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
          translation={translationByBlockUid.get(block.block_uid)}
          viewMode={kindleBlockViewMode}
          active={activeBlockUid === block.block_uid}
          controlsVisible={false}
          blockToolsEnabled={false}
          colorMarkersEnabled={false}
          sentenceHoverAccentEnabled={false}
          imageLightboxEnabled={false}
          searchActive={currentSearchBlockUid === block.block_uid}
          blockColor="none"
          termWikiEnabled={false}
          readerCards={[]}
          expandedReaderCardId={null}
          onActivate={handleActiveBlockChange}
        />
      );
    },
    [
      activeBlockUid,
      assetById,
      assetFileUrlsByAssetId,
      assetUrlByAssetId,
      currentSearchBlockUid,
      effectiveCitationLookup,
      handleActiveBlockChange,
      kindleBlockViewMode,
      referenceTargets,
      translationByBlockUid
    ]
  );

  const readerToolbarItems: {
    panel: ReaderToolbarPanel;
    label: string;
    icon: ReactNode;
    badge?: number;
  }[] = [
    {
      panel: "tasks",
      label: t("nav.tasks"),
      icon: <TerminalSquare size={15} aria-hidden="true" />,
      badge: jobSummary.data?.active ?? 0
    },
    {
      panel: "providers",
      label: t("reader.providerPanel"),
      icon: <Sparkles size={15} aria-hidden="true" />,
      badge: providers.data?.length ?? 0
    },
    {
      panel: "ask",
      label: t("reader.askPanel"),
      icon: <MessageSquare size={15} aria-hidden="true" />
    },
    {
      panel: "translate",
      label: t("reader.translate"),
      icon: <Languages size={15} aria-hidden="true" />
    },
    {
      panel: "glossary",
      label: t("reader.terms"),
      icon: <BookMarked size={15} aria-hidden="true" />
    },
    {
      panel: "notes",
      label: t("reader.notes"),
      icon: <FileText size={15} aria-hidden="true" />
    },
    {
      panel: "export",
      label: t("reader.export"),
      icon: <Download size={15} aria-hidden="true" />
    },
    {
      panel: "preferences",
      label: t("reader.preferences"),
      icon: <Type size={15} aria-hidden="true" />
    }
  ];

  return (
    <div
      className={`reader-page${kindleMode ? " reader-page-kindle" : ""}${
        kindleMode && kindleBlockViewMode === "bilingual" ? " reader-page-kindle-landscape" : ""
      }${
        kindleMode && kindleChromeHidden ? " reader-kindle-chrome-hidden" : ""
      }${!kindleMode && readerChromeHidden ? " reader-workbench-chrome-hidden" : ""}`}
      style={readerPreferenceStyle}
      onMouseMove={
        kindleMode && kindleChromeHidden
          ? (event) => {
              if (event.clientY <= 42) showKindleChrome();
            }
          : undefined
      }
    >
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
        {kindleMode && kindleChromeHidden ? (
          <button
            type="button"
            className="reader-kindle-chrome-reveal"
            aria-label={t("reader.showKindleMenu")}
            onClick={showKindleChrome}
            onFocus={showKindleChrome}
          />
        ) : null}
        <section className="reader-command-center" aria-label={t("reader.readingControls")}>
          <div className="reader-command-actions">
            <div className="reader-command-zone reader-command-left">
              <Button
                className="reader-chrome-button"
                aria-pressed={readerArticleRailOpen}
                title={t("reader.articleSwitcher")}
                variant={readerArticleRailOpen ? "light" : "subtle"}
                size="xs"
                leftSection={<BookMarked size={15} aria-hidden="true" />}
                onClick={() => setReaderArticleRailOpen((open) => !open)}
              >
                {t("nav.library")}
              </Button>
            </div>
            <button
              type="button"
              className="reader-command-title reader-command-title-button"
              aria-label={t("reader.returnToLibrary")}
              onClick={openCurrentLibrary}
            >
              Ilios
            </button>
            <div className="reader-command-zone reader-command-right">
              <div className="reader-surface-switch" aria-label={t("reader.surfaceMode")}>
                <Button
                  aria-pressed={!kindleMode}
                  aria-label={t("reader.htmlMode")}
                  className="reader-chrome-button reader-surface-button"
                  variant={!kindleMode ? "light" : "subtle"}
                  size="xs"
                  leftSection={<FileText size={15} aria-hidden="true" />}
                  onClick={() => setReaderSurfaceMode("workbench")}
                />
                <Button
                  aria-pressed={kindleMode}
                  aria-label={t("reader.kindleMode")}
                  className="reader-chrome-button reader-surface-button"
                  variant={kindleMode ? "light" : "subtle"}
                  size="xs"
                  leftSection={<BookOpenText size={15} aria-hidden="true" />}
                  onClick={() => setReaderSurfaceMode("kindle")}
                />
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
                  onClick={toggleReaderModeMenu}
                >
                  {t("reader.modeShort")}
                </Button>
                <Collapse className="reader-mode-popover" in={readerModeMenuOpen}>
                  <div className="reader-mode-options">
                    {activeReaderModeOptions.map((option) => (
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
              {!kindleMode ? (
                <div className="reader-tool-menu" aria-label={t("reader.toolbar")}>
                  {readerToolbarItems.map((item) => (
                    <button
                      key={item.panel}
                      type="button"
                      className="reader-toolbar-button"
                      aria-label={item.label}
                      aria-pressed={activeReaderToolbarPanel === item.panel}
                      title={item.label}
                      onClick={() => toggleReaderToolbarPanel(item.panel)}
                    >
                      {item.icon}
                      {typeof item.badge === "number" && item.badge > 0 ? (
                        <span className="reader-toolbar-badge">{item.badge}</span>
                      ) : null}
                    </button>
                  ))}
                </div>
              ) : null}
            </div>
          </div>
        </section>
        {kindleMode ? (
          <KindlePagedReader
            blocks={blocks}
            activeBlockUid={activeBlockUid}
            title={title}
            fontScale={readerPreferences.fontScale}
            pageLayout={kindleBlockViewMode === "bilingual" ? "landscape" : "auto"}
            getBlockText={kindleBlockTextForPagination}
            renderBlock={renderKindleBlock}
            onPageBlockChange={changeKindlePageBlock}
            onNavigateToBlock={navigateToBlock}
            onPageTurn={hideKindleChrome}
            previousLabel={t("reader.previousPage")}
            nextLabel={t("reader.nextPage")}
            pageLabel={(current, total) => t("reader.pageCount", { current, total })}
          />
        ) : (
          <section
            className={`reader-mosaic${
              readerArticleRailOpen ? "" : " reader-mosaic-left-collapsed"
            }${readerRightRailOpen ? "" : " reader-mosaic-right-collapsed"}`}
          >
            <aside
              className={`reader-side-rail reader-article-rail${
                readerArticleRailOpen ? "" : " reader-side-rail-collapsed"
              }`}
              aria-label={t("reader.articleSwitcher")}
            >
              {readerArticleRailOpen ? (
                <>
                  <div className="reader-rail-header">
                    <div>
                      <Text fw={720} size="sm">
                        {t("reader.articleSwitcher")}
                      </Text>
                      <Text c="dimmed" size="xs" lineClamp={1}>
                        {currentArticleItem
                          ? readerArticleTitle(currentArticleItem)
                          : t("reader.noCurrentArticle")}
                      </Text>
                    </div>
                    <ActionIcon
                      aria-label={t("reader.collapseArticles")}
                      variant="subtle"
                      size="sm"
                      onClick={() => setReaderArticleRailOpen(false)}
                    >
                      <ChevronLeft size={15} aria-hidden="true" />
                    </ActionIcon>
                  </div>
                  <TextInput
                    className="reader-article-switch-search"
                    aria-label={t("reader.searchLibraryArticles")}
                    placeholder={t("reader.searchLibraryArticles")}
                    value={readerArticleSearchQuery}
                    leftSection={<Search size={14} aria-hidden="true" />}
                    onChange={(event) => setReaderArticleSearchQuery(event.currentTarget.value)}
                  />
                  <div className="reader-article-switch-list">
                    {libraryArticles.isLoading ? (
                      <Group gap="xs" className="reader-side-loading">
                        <Loader size="xs" />
                        <Text c="dimmed" size="xs">
                          {t("reader.loadingArticles")}
                        </Text>
                      </Group>
                    ) : null}
                    {visibleReaderArticleItems.map((item) => {
                      const isActive = item.article_revision.id === articleId;
                      return (
                        <button
                          key={item.article_revision.id}
                          type="button"
                          className="reader-article-switch-item"
                          aria-current={isActive ? "page" : undefined}
                          data-active={isActive || undefined}
                          onClick={() => switchReaderArticle(item)}
                        >
                          <span className="reader-article-switch-title">
                            {readerArticleTitle(item)}
                          </span>
                          <span className="reader-article-switch-meta">
                            {readerArticleSourceLabel(item)} · {readerArticleProgressLabel(item)}
                          </span>
                          <span className="reader-article-switch-progress" aria-hidden="true">
                            <span
                              style={{
                                width: `${readerArticleProgressPercent(item)}%`
                              }}
                            />
                          </span>
                        </button>
                      );
                    })}
                    {!libraryArticles.isLoading && visibleReaderArticleItems.length === 0 ? (
                      <Text c="dimmed" size="xs" className="reader-side-empty">
                        {t("reader.noLibraryArticles")}
                      </Text>
                    ) : null}
                  </div>
                </>
              ) : null}
            </aside>
            <div
              className={`reader-paper-layout${
                chapterRailEnabled ? "" : " reader-paper-layout-no-chapters"
              }${chapterRailOpen ? "" : " reader-paper-layout-chapters-collapsed"}`}
            >
              {chapterRailEnabled ? (
                <aside
                  className={`reader-chapter-rail${
                    chapterRailOpen ? "" : " reader-chapter-rail-collapsed"
                  }`}
                  aria-label={t("reader.chapters")}
                >
                  {chapterRailOpen ? (
                    <>
                      <div className="reader-chapter-rail-header">
                        <div>
                          <Text fw={720} size="sm">
                            {t("reader.chapters")}
                          </Text>
                          <Text c="dimmed" size="xs" lineClamp={1}>
                            {activeChapterLabel}
                          </Text>
                        </div>
                        <ActionIcon
                          aria-label={t("reader.collapsePanel", { panel: t("reader.chapters") })}
                          variant="subtle"
                          size="sm"
                          onClick={() => setChaptersOpen(false)}
                        >
                          <ChevronLeft size={15} aria-hidden="true" />
                        </ActionIcon>
                      </div>
                      <nav className="reader-chapter-list" aria-label={t("reader.chapters")}>
                        {navBlocks.map((block, index) => (
                          <a
                            key={block.block_uid}
                            href={`#${block.block_uid}`}
                            className={
                              activeNavBlockUid === block.block_uid
                                ? "reader-nav-active"
                                : undefined
                            }
                            aria-current={
                              activeNavBlockUid === block.block_uid ? "location" : undefined
                            }
                            onClick={(event) => {
                              event.preventDefault();
                              navigateToBlock(block.block_uid);
                            }}
                          >
                            <Badge variant="light" size="sm">
                              {chapterNumber(index, block)}
                            </Badge>
                            <span>{chapterTitle(block)}</span>
                          </a>
                        ))}
                      </nav>
                    </>
                  ) : (
                    <button
                      type="button"
                      className="reader-chapter-rail-tab"
                      aria-expanded={false}
                      onClick={() => setChaptersOpen(true)}
                    >
                      <ListTree size={15} aria-hidden="true" />
                      <span>{t("reader.chapters")}</span>
                    </button>
                  )}
                </aside>
              ) : null}
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
            </div>
            <aside
              className={`reader-side-rail reader-right-rail${
                readerRightRailOpen ? "" : " reader-side-rail-collapsed"
              }`}
              aria-label={t("reader.workspaceRail")}
            >
              {readerRightRailOpen ? (
                <>
                  <div className="reader-rail-header">
                    <div>
                      <Text fw={720} size="sm">
                        {t("reader.workspaceRail")}
                      </Text>
                      <Text c="dimmed" size="xs">
                        {t("reader.workspaceRailHelp")}
                      </Text>
                    </div>
                    <ActionIcon
                      aria-label={t("reader.collapseRightRail")}
                      variant="subtle"
                      size="sm"
                      onClick={closeReaderToolbarPanel}
                    >
                      <ChevronRight size={15} aria-hidden="true" />
                    </ActionIcon>
                  </div>
                  <ReaderSideTile
                    title={t("nav.tasks")}
                    icon={<TerminalSquare size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "tasks"}
                    onToggle={() => toggleReaderToolbarPanel("tasks")}
                    badge={
                      <Badge size="sm" variant="light">
                        {jobSummary.data?.active ?? 0}
                      </Badge>
                    }
                  >
                    <div className="reader-dock-task-grid">
                      <span>{t("task.statusQueued", { count: jobSummary.data?.queued ?? 0 })}</span>
                      <span>
                        {t("task.statusRunning", { count: jobSummary.data?.running ?? 0 })}
                      </span>
                      <span>
                        {t("task.statusSucceeded", { count: jobSummary.data?.succeeded ?? 0 })}
                      </span>
                      <span>{t("task.statusFailed", { count: jobSummary.data?.failed ?? 0 })}</span>
                    </div>
                    <Button
                      fullWidth
                      size="xs"
                      variant="light"
                      leftSection={<TerminalSquare size={14} aria-hidden="true" />}
                      onClick={openTaskDrawer}
                    >
                      {t("reader.manageTasks")}
                    </Button>
                  </ReaderSideTile>
                  <ReaderSideTile
                    title={t("reader.providerPanel")}
                    icon={<Sparkles size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "providers"}
                    onToggle={() => toggleReaderToolbarPanel("providers")}
                    badge={
                      <Badge size="sm" variant="light">
                        {providers.data?.length ?? 0}
                      </Badge>
                    }
                  >
                    <Stack gap="xs">
                      <Select
                        label={t("reader.provider")}
                        placeholder={t("reader.configureProvider")}
                        value={selectedProviderId}
                        onChange={setSelectedProviderId}
                        data={(providers.data ?? []).map((provider) => ({
                          label: `${provider.name} · ${
                            provider.default_model ?? t("reader.noModel")
                          }`,
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
                      {(providers.data ?? []).slice(0, 3).map((provider) => (
                        <div
                          className="reader-provider-row"
                          data-active={provider.id === selectedProviderId || undefined}
                          key={provider.id}
                        >
                          <Text size="sm" fw={620} lineClamp={1}>
                            {provider.name}
                          </Text>
                          <Text c="dimmed" size="xs" lineClamp={1}>
                            {provider.default_model ?? t("reader.noModel")}
                          </Text>
                        </div>
                      ))}
                      {(providers.data ?? []).length === 0 ? (
                        <Text c="dimmed" size="xs">
                          {t("library.noProviderConfigured")}
                        </Text>
                      ) : null}
                      <Button size="xs" variant="subtle" onClick={() => navigate("/settings")}>
                        {t("nav.settings")}
                      </Button>
                    </Stack>
                  </ReaderSideTile>
                  <ReaderSideTile
                    className="reader-ask-tile"
                    title={t("reader.askPanel")}
                    icon={<MessageSquare size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "ask"}
                    onToggle={() => toggleReaderToolbarPanel("ask")}
                  >
                    <ChatPanel
                      messages={chat.data?.messages ?? []}
                      citedBlocks={
                        streamingCitedBlocks.length > 0
                          ? streamingCitedBlocks
                          : (askQuestion.data?.cited_blocks ?? [])
                      }
                      streamingAnswer={streamingAnswer}
                      referenceTargets={referenceTargets}
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
                  </ReaderSideTile>
                  <ReaderSideTile
                    className="reader-tool-tile"
                    title={t("reader.translate")}
                    icon={<Languages size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "translate"}
                    onToggle={() => toggleReaderToolbarPanel("translate")}
                  >
                    <div className="panel reader-translation-panel">
                      <Stack gap="sm">
                        <Button
                          fullWidth
                          leftSection={<Languages size={16} />}
                          onClick={queueArticleTranslation}
                          loading={translateArticle.isPending}
                          disabled={
                            !selectedProviderId || !targetLanguage.trim() || blocks.length === 0
                          }
                        >
                          {t("reader.translatePaper")}
                        </Button>
                        <Checkbox
                          checked={autoTranslateOnLanguageSwitch}
                          label={t("reader.autoTranslateOnLanguageSwitch")}
                          onChange={(event) =>
                            setAutoTranslateOnLanguageSwitch(event.currentTarget.checked)
                          }
                        />
                        <Text c="dimmed" size="sm">
                          {t("reader.translationHelp")}
                        </Text>
                        {translateArticle.data ? (
                          <Text c="dimmed" size="sm">
                            {t("reader.translationQueued", {
                              jobs: translateArticle.data.jobs_created,
                              cached: translateArticle.data.cached_blocks
                            })}
                          </Text>
                        ) : null}
                        {translateArticle.isError || translateBlock.isError ? (
                          <Text c="red" size="sm">
                            {t("reader.translationQueueError")}
                          </Text>
                        ) : null}
                      </Stack>
                    </div>
                  </ReaderSideTile>
                  <ReaderSideTile
                    className="reader-tool-tile"
                    title={t("reader.terms")}
                    icon={<BookMarked size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "glossary"}
                    onToggle={() => toggleReaderToolbarPanel("glossary")}
                  >
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
                  </ReaderSideTile>
                  <ReaderSideTile
                    className="reader-tool-tile"
                    title={t("reader.notes")}
                    icon={<FileText size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "notes"}
                    onToggle={() => toggleReaderToolbarPanel("notes")}
                  >
                    <Stack gap="sm">
                      <Group gap="xs" grow>
                        <Button
                          size="xs"
                          variant={readerFeaturePreferences.termCardsEnabled ? "light" : "subtle"}
                          leftSection={<StickyNote size={14} aria-hidden="true" />}
                          onClick={() => {
                            const nextEnabled = !readerFeaturePreferences.termCardsEnabled;
                            setReaderFeaturePreference("termCardsEnabled", nextEnabled);
                            setTermWikiEnabled(nextEnabled);
                          }}
                        >
                          {t("reader.termWiki")}
                        </Button>
                        <Button
                          size="xs"
                          variant="subtle"
                          leftSection={<Sparkles size={14} aria-hidden="true" />}
                          disabled={!hasArticleContext || extractReaderCards.isPending}
                          loading={extractReaderCards.isPending}
                          onClick={runCardExtraction}
                        >
                          {t("reader.extractCards")}
                        </Button>
                      </Group>
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
                        onSavePatch={(patchId, payload) =>
                          updateNotePatch.mutate({ patchId, payload })
                        }
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
                    </Stack>
                  </ReaderSideTile>
                  <ReaderSideTile
                    className="reader-tool-tile"
                    title={t("reader.export")}
                    icon={<Download size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "export"}
                    onToggle={() => toggleReaderToolbarPanel("export")}
                  >
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
                  </ReaderSideTile>
                  <ReaderSideTile
                    className="reader-tool-tile"
                    title={t("reader.preferences")}
                    icon={<Type size={15} aria-hidden="true" />}
                    open={activeReaderToolbarPanel === "preferences"}
                    onToggle={() => toggleReaderToolbarPanel("preferences")}
                  >
                    <ReaderPreferencesPanel compact showTitle={false} />
                  </ReaderSideTile>
                </>
              ) : null}
            </aside>
          </section>
        )}
        {!kindleMode && readerFeaturePreferences.bottomProgressVisible ? (
          <section
            className="reader-bottom-status"
            aria-label={t("reader.readingProgress", { progress: readerProgress })}
          >
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
          </section>
        ) : null}
      </main>
    </div>
  );
}

interface ReaderSideTileProps {
  title: string;
  icon: ReactNode;
  open: boolean;
  onToggle: () => void;
  badge?: ReactNode;
  children: ReactNode;
  className?: string;
}

function ReaderSideTile({
  title,
  icon,
  open,
  onToggle,
  badge,
  children,
  className
}: ReaderSideTileProps) {
  const t = useT();
  if (!open) return null;
  return (
    <section className={`reader-side-tile reader-side-tile-open${className ? ` ${className}` : ""}`}>
      <button
        type="button"
        className="reader-side-tile-toggle"
        aria-expanded={open}
        aria-label={t(open ? "reader.collapsePanel" : "reader.expandPanel", { panel: title })}
        onClick={onToggle}
      >
        <span className="reader-side-tile-title">
          {icon}
          <span>{title}</span>
        </span>
        <span className="reader-side-tile-actions">
          {badge}
          <ChevronDown data-open={open || undefined} size={15} aria-hidden="true" />
        </span>
      </button>
      <Collapse in={open}>
        <div className="reader-side-tile-body">{children}</div>
      </Collapse>
    </section>
  );
}

function filterReaderArticleItems(items: ArticleListItem[], query: string) {
  const normalizedQuery = query.trim().toLowerCase();
  const filtered = normalizedQuery
    ? items.filter((item) =>
        [
          item.family.title,
          item.family.external_id,
          item.family.source,
          item.article_revision.version,
          item.article_revision.status
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(normalizedQuery)
      )
    : items;
  return [...filtered].sort((left, right) =>
    String(right.article_revision.updated_at).localeCompare(
      String(left.article_revision.updated_at)
    )
  );
}

function readerArticleTitle(item: ArticleListItem) {
  return item.family.title || item.family.external_id || item.article_revision.id;
}

function readerArticleSourceLabel(item: ArticleListItem) {
  if (item.family.source === "arxiv") return "arXiv";
  if (item.family.source === "local_file") return "Local";
  return item.family.source;
}

function readerArticleProgressPercent(item: ArticleListItem) {
  const progress = item.reading_progress;
  if (!progress || progress.segment_count <= 0 || progress.total_seconds <= 0) return 0;
  if (typeof progress.active_segment_index === "number") {
    return Math.min(
      100,
      Math.round(((progress.active_segment_index + 1) / progress.segment_count) * 100)
    );
  }
  const visitedSegments = (progress.segments ?? []).filter((seconds) => seconds > 0).length;
  return Math.min(100, Math.round((visitedSegments / progress.segment_count) * 100));
}

function readerArticleProgressLabel(item: ArticleListItem) {
  const seconds = item.reading_progress?.total_seconds ?? 0;
  if (seconds <= 0) return "0m";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${Math.max(1, minutes)}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest > 0 ? `${hours}h ${rest}m` : `${hours}h`;
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
  referenceTargets: ReferenceTargets;
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
  referenceTargets,
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
  const t = useT();
  return (
    <div className="panel reader-chat-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <MessageSquare size={18} />
            <Title order={3}>{t("reader.paperChat")}</Title>
          </Group>
          <Text c="dimmed" size="sm">
            {t("reader.paperChatHelp")}
          </Text>
        </div>
        {selectedBlockUid ? (
          <Button variant="subtle" size="xs" onClick={onClearBlock}>
            {t("reader.currentBlock", { blockUid: selectedBlockUid })}
          </Button>
        ) : null}
      </Group>
      <Stack gap="sm" mt="md">
        {messages.length === 0 ? (
          <Text c="dimmed" size="sm">
            {t("reader.paperChatEmpty")}
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
                    {t("reader.createNotePatch")}
                  </Button>
                ) : null}
              </Group>
              <ChatMessageContent message={message} referenceTargets={referenceTargets} />
              {sourceRefs.length > 0 ? (
                <Group gap="xs" aria-label={t("reader.currentPaperEvidence")}>
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
            <ChatAnswerMarkdown
              content={streamingAnswer}
              referenceTargets={referenceTargets}
              sourceRefs={citedBlocks.map((block) => block.block_uid)}
            />
          </div>
        ) : null}
      </Stack>
      {citedBlocks.length > 0 ? (
        <div className="retrieved-blocks">
          <Text fw={600} size="sm">
            {t("reader.currentPaperEvidence")}
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
        className="reader-chat-question"
        label={t("reader.chatQuestion")}
        placeholder={t("reader.chatQuestionPlaceholder")}
        autosize
        minRows={2}
        mt="md"
        value={question}
        onChange={(event) => onQuestionChange(event.target.value)}
      />
      <Group className="reader-chat-actions" justify="space-between" align="center" mt="sm">
        <Checkbox
          label={t("reader.nativeSearch")}
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
          {t("reader.askPaper")}
        </Button>
      </Group>
      {!nativeSearchAvailable ? (
        <Text c="dimmed" size="xs" mt="xs">
          {t("reader.nativeSearchUnavailable")}
        </Text>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          {t("reader.askError")}
        </Text>
      ) : null}
    </div>
  );
}

function ChatMessageContent({
  message,
  referenceTargets
}: {
  message: ChatMessage;
  referenceTargets: ReferenceTargets;
}) {
  if (message.role !== "assistant") {
    return <Text>{message.content}</Text>;
  }
  return (
    <ChatAnswerMarkdown
      content={message.content}
      referenceTargets={referenceTargets}
      sourceRefs={message.source_refs ?? []}
    />
  );
}

function ChatAnswerMarkdown({
  content,
  referenceTargets,
  sourceRefs
}: {
  content: string;
  referenceTargets: ReferenceTargets;
  sourceRefs: string[];
}) {
  return (
    <div className="chat-message-markdown">
      <MarkdownContent
        content={prepareChatAnswerMarkdown(content, sourceRefs)}
        referenceTargets={referenceTargets}
      />
    </div>
  );
}

function prepareChatAnswerMarkdown(content: string, sourceRefs: string[]) {
  return linkChatSourceRefs(normalizeInlineChatBullets(content), sourceRefs);
}

function normalizeInlineChatBullets(content: string) {
  return content.replace(/([。.!?])\s+-\s+(?=\*\*)/g, "$1\n- ");
}

function linkChatSourceRefs(content: string, sourceRefs: string[]) {
  const refs = new Set(sourceRefs.filter(Boolean));
  return content.replace(/\[([A-Za-z]+-\d{4,})\]/g, (match, ref: string) => {
    if (refs.size > 0 && !refs.has(ref)) return match;
    return `[${ref}](#${ref})`;
  });
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

function searchReaderBlocks(
  blocks: DocumentBlock[],
  translationByBlockUid: Map<string, string>,
  query: string
): ReaderSearchMatch[] {
  const normalizedQuery = query.trim().toLocaleLowerCase();
  if (!normalizedQuery) return [];
  const matches: ReaderSearchMatch[] = [];
  for (const block of blocks) {
    const title = isSearchTitleBlock(block) ? chapterTitle(block) : block.block_uid;
    let matchIndex = title.toLocaleLowerCase().indexOf(normalizedQuery);
    if (matchIndex < 0) {
      matchIndex = plainTextForReaderSearch(block.source_markdown)
        .toLocaleLowerCase()
        .indexOf(normalizedQuery);
    }
    if (matchIndex < 0) {
      const translation = translationByBlockUid.get(block.block_uid);
      matchIndex = translation
        ? plainTextForReaderSearch(translation).toLocaleLowerCase().indexOf(normalizedQuery)
        : -1;
    }
    if (matchIndex >= 0) {
      matches.push({
        blockUid: block.block_uid,
        label: title,
        index: matchIndex
      });
    }
  }
  return matches;
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
    for (const alias of citationAliases(citation)) {
      lookup[alias] = citation;
    }
  }
  return lookup;
}

function citationAliases(citation: CitationEntry) {
  const aliases = new Set<string>([citation.id]);
  if (citation.id.startsWith("bib:")) {
    aliases.add(`bib.${citation.id.slice(4)}`);
  } else if (citation.id.startsWith("bib.")) {
    aliases.add(`bib:${citation.id.slice(4)}`);
  }
  if (citation.citation_key) {
    aliases.add(citation.citation_key);
    aliases.add(`bib:${citation.citation_key}`);
    aliases.add(`bib.${citation.citation_key}`);
  }
  const metadataAliases = citation.metadata?.aliases;
  if (Array.isArray(metadataAliases)) {
    for (const alias of metadataAliases) {
      if (typeof alias === "string" && alias.trim()) aliases.add(alias.trim());
    }
  }
  return aliases;
}

function termAnnotationsForBlock(
  block: DocumentBlock,
  glossaryTerms: GlossaryTerm[],
  readerCards: ReaderCard[]
): TermAnnotation[] {
  const annotations = new Map<string, TermAnnotation>();
  for (const card of readerCards) {
    if (card.card_type !== "term" || card.status === "archived") continue;
    const definition = conciseDefinition(card.body_markdown);
    if (!definition) continue;
    for (const term of [card.full_form, card.abbreviation, card.anchor_text, card.title]) {
      addTermAnnotation(annotations, {
        term: term ?? "",
        definition,
        source: "reader_card",
        sourceType: card.source_type
      });
    }
  }
  const blockText = `${block.source_markdown}\n${block.source_latex ?? ""}`;
  for (const term of glossaryTerms) {
    if (term.status === "archived") continue;
    const sourceTerm = term.source_term.trim();
    if (!sourceTerm || !textContainsTerm(blockText, sourceTerm)) continue;
    const metadataDefinition = stringMetadataValue(
      term.metadata?.llm_definition ??
        term.metadata?.definition ??
        term.metadata?.short_definition ??
        term.metadata?.brief_definition
    );
    const definition =
      metadataDefinition ||
      (term.target_term.trim()
        ? `${term.source_term} -> ${term.target_term}`
        : String(term.metadata?.phrase_type ?? "Detected paper term"));
    addTermAnnotation(annotations, {
      term: sourceTerm,
      definition,
      source: "glossary",
      sourceType: stringMetadataValue(term.metadata?.definition_source)
    });
  }
  return [...annotations.values()];
}

function addTermAnnotation(
  annotations: Map<string, TermAnnotation>,
  annotation: TermAnnotation
) {
  const term = annotation.term.trim();
  const definition = annotation.definition.trim();
  if (!term || !definition) return;
  const key = term.toLocaleLowerCase();
  const current = annotations.get(key);
  if (!current || termAnnotationPriority(annotation) > termAnnotationPriority(current)) {
    annotations.set(key, { ...annotation, term, definition });
  }
}

function termAnnotationPriority(annotation: TermAnnotation) {
  if (annotation.source === "reader_card" && annotation.sourceType === "ai_search") return 4;
  if (annotation.source === "reader_card" && annotation.sourceType === "paper_local") return 3;
  if (annotation.source === "reader_card") return 2;
  return 1;
}

function conciseDefinition(markdown: string) {
  const text = markdown
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[#*_>~-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!text) return "";
  const firstSentence = text.match(/^.{20,160}?[。.!?](?:\s|$)/)?.[0]?.trim();
  return firstSentence ?? text.slice(0, 160).trim();
}

function textContainsTerm(text: string, term: string) {
  return new RegExp(`(^|[^\\p{L}\\p{N}_-])${escapeRegExp(term)}($|[^\\p{L}\\p{N}_-])`, "iu").test(
    text
  );
}

function stringMetadataValue(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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

function blockIndexMapForBlocks(blocks: DocumentBlock[]) {
  const map = new Map<string, number>();
  blocks.forEach((block, index) => map.set(block.block_uid, index));
  return map;
}

function navBlockUidMapForBlocks(blocks: DocumentBlock[]) {
  const map = new Map<string, string>();
  let currentSectionUid: string | null = null;
  for (const block of blocks) {
    if (block.block_type === "section") {
      currentSectionUid = block.block_uid;
    }
    if (currentSectionUid) {
      map.set(block.block_uid, currentSectionUid);
    }
  }
  const firstSection = blocks.find((block) => block.block_type === "section")?.block_uid;
  if (!firstSection) return map;
  for (const block of blocks) {
    if (!map.has(block.block_uid)) map.set(block.block_uid, firstSection);
  }
  return map;
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
