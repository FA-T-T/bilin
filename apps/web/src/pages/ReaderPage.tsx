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
  House,
  Languages,
  ListTree,
  MessageSquare,
  Minus,
  Plus,
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

import { apiClient, apiUrl } from "../api/client";
import {
  articleTaskFailedCount,
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
  useArticleTaskSummary,
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
import {
  type ReaderOverlayKind,
  type ReaderPreferences,
  type ReaderViewMode,
  useUiStore
} from "../state/ui";

const emptyReaderAssetFiles: ReaderAssetFile[] = [];
const emptyCitationLookup: CitationLookup = {};
const READING_PROGRESS_RECORD_INTERVAL_MS = 30_000;
const READING_PROGRESS_MAX_IDLE_MS = 60_000;
const READER_OVERLAY_SCROLL_CLOSE_DISTANCE_PX = 64;
const READER_OVERLAY_SCROLL_CLOSE_DELAY_MS = 350;
const READER_OVERLAY_SCROLL_CLOSE_COOLDOWN_MS = 500;
const DESKTOP_READER_RAIL_QUERY = "(min-width: 1181px)";
const CHAPTER_RENDER_SOURCE_MIN_BLOCKS = 220;
const READER_PROGRESS_MILESTONES = [25, 50, 75, 100] as const;

type ReaderOverlayTone = "teal" | "amber" | "blue" | "neutral";
type ReaderWorkspaceGroupId = "read" | "assist" | "output";
type ReaderWorkspacePanel = Exclude<ReaderOverlayKind, "articles">;

interface ReaderWorkspaceItem {
  panel: ReaderWorkspacePanel;
  label: string;
  icon: ReactNode;
  tone: ReaderOverlayTone;
  badge?: number;
}

interface ReaderWorkspaceGroup {
  id: ReaderWorkspaceGroupId;
  label: string;
  items: ReaderWorkspaceItem[];
}

function defaultDesktopReaderRailOpen() {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") return false;
  return window.matchMedia(DESKTOP_READER_RAIL_QUERY).matches;
}

function useMediaQueryMatch(query: string) {
  const [matches, setMatches] = useState(() => mediaQueryMatches(query));

  useEffect(() => {
    if (typeof globalThis.window === "undefined" || !globalThis.window.matchMedia) return;
    const media = globalThis.window.matchMedia(query);
    const update = () => setMatches(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [query]);

  return matches;
}

function mediaQueryMatches(query: string) {
  if (typeof globalThis.window === "undefined" || !globalThis.window.matchMedia) return false;
  return globalThis.window.matchMedia(query).matches;
}

interface ReaderCardDraft {
  cardId?: string;
  blockUid: string;
  cardType: ReaderCard["card_type"];
  anchorText: string;
  title: string;
  bodyMarkdown: string;
  sourceType: ReaderCard["source_type"];
  position: ReaderCard["position"];
  metadata?: ReaderCard["metadata"];
}

interface ReaderRenderSource {
  uid: string;
  title: string;
  startIndex: number;
  endIndex: number;
  blockCount: number;
}

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
  const activeReaderOverlay = useUiStore((state) => state.activeReaderOverlay);
  const setActiveReaderOverlay = useUiStore((state) => state.setActiveReaderOverlay);
  const setReaderStudyContext = useUiStore((state) => state.setReaderStudyContext);
  const readerOverlayAutoCloseEnabled = useUiStore((state) => state.readerOverlayAutoCloseEnabled);
  const readerNoteStickiesOverride = useUiStore((state) => state.readerNoteStickiesOverride);
  const setReaderNoteStickiesOverride = useUiStore((state) => state.setReaderNoteStickiesOverride);
  const taskNotificationOpenDelayMs = useUiStore((state) => state.taskNotificationOpenDelayMs);
  const readerPreferences = useUiStore((state) => state.readerPreferences);
  const setReaderPreference = useUiStore((state) => state.setReaderPreference);
  const readerFeaturePreferences = useUiStore((state) => state.readerFeaturePreferences);
  const setReaderFeaturePreference = useUiStore((state) => state.setReaderFeaturePreference);
  const targetLanguage = useUiStore((state) => state.translationTargetLanguage);
  const setTargetLanguage = useUiStore((state) => state.setTranslationTargetLanguage);
  const autoTranslateOnLanguageSwitch = useUiStore((state) => state.autoTranslateOnLanguageSwitch);
  const setAutoTranslateOnLanguageSwitch = useUiStore(
    (state) => state.setAutoTranslateOnLanguageSwitch
  );
  const providers = useProviders();
  const articleTaskSummary = useArticleTaskSummary();
  const failedArticleTaskCount = articleTaskFailedCount(articleTaskSummary.data);
  const libraryArticles = useArticles(libraryId, targetLanguage);
  const [selectedProviderId, setSelectedProviderId] = useState<string | null>(null);
  const [chatBlockUid, setChatBlockUid] = useState<string | null>(null);
  const [question, setQuestion] = useState("");
  const [readerArticleSearchQuery, setReaderArticleSearchQuery] = useState("");
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
  const [activeRenderSourceUid, setActiveRenderSourceUid] = useState<string | null>(null);
  const [forcedBlockUid, setForcedBlockUid] = useState<string | null>(null);
  const [pendingNavigationBlockUid, setPendingNavigationBlockUid] = useState<string | null>(null);
  const [readerSearchQuery, setReaderSearchQuery] = useState("");
  const [readerSearchCursor, setReaderSearchCursor] = useState(0);
  const [blockColors, setBlockColors] = useState<Record<string, ReaderBlockColor>>({});
  const [chaptersOpen, setChaptersOpen] = useState(defaultDesktopReaderRailOpen);
  const [studyRailOpen, setStudyRailOpen] = useState(defaultDesktopReaderRailOpen);
  const [activeReaderWorkspaceGroup, setActiveReaderWorkspaceGroup] =
    useState<ReaderWorkspaceGroupId>("read");
  const [termWikiEnabled, setTermWikiEnabled] = useState(false);
  const [readerModeMenuOpen, setReaderModeMenuOpen] = useState(false);
  const [kindleChromeHidden, setKindleChromeHidden] = useState(false);
  const [expandedReaderCardByBlock, setExpandedReaderCardByBlock] = useState<
    Record<string, string | null>
  >({});
  const [readerCardDraft, setReaderCardDraft] = useState<ReaderCardDraft | null>(null);
  const [paragraphAskResultByBlockUid, setParagraphAskResultByBlockUid] = useState<
    Record<string, { question: string; answer: string }>
  >({});
  const [quickAskPendingBlockUid, setQuickAskPendingBlockUid] = useState<string | null>(null);
  const [quickAskSavingBlockUid, setQuickAskSavingBlockUid] = useState<string | null>(null);
  const lastExportDownloadKey = useRef<string | null>(null);
  const lastInitialHashNavigation = useRef<string | null>(null);
  const lastSavedProgressNavigation = useRef<string | null>(null);
  const readerOverlayRef = useRef<HTMLElement | null>(null);
  const readerOverlayPointerInside = useRef(false);
  const readerOverlayScrollDirection = useRef<1 | -1 | 0>(0);
  const readerOverlayScrollDistance = useRef(0);
  const readerOverlayScrollStartedAt = useRef(0);
  const lastReaderOverlayScrollY = useRef(0);
  const lastReaderOverlayAutoCloseAt = useRef(0);
  const activeBlockUidRef = useRef<string | null>(null);
  const lastReaderActivityAt = useRef(Date.now());
  const lastReadingProgressSampleAt = useRef(Date.now());
  const pendingReadingProgressDeltas = useRef<Record<string, number>>({});
  const previousTargetLanguage = useRef(targetLanguage);
  const desktopReaderRailPreferred = useMediaQueryMatch(DESKTOP_READER_RAIL_QUERY);
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
  const recoveredLatexmlDocument = isRecoveredLatexmlDocument(document.data);
  const renderSources = useMemo(() => readerRenderSourcesForBlocks(blocks, title), [blocks, title]);
  const segmentedReaderEnabled =
    blocks.length >= CHAPTER_RENDER_SOURCE_MIN_BLOCKS && renderSources.length > 1;
  const renderSourceByUid = useMemo(
    () => new Map(renderSources.map((source) => [source.uid, source] as const)),
    [renderSources]
  );
  const renderSourceByBlockUid = useMemo(
    () => renderSourceMapForBlocks(blocks, renderSources),
    [blocks, renderSources]
  );
  const activeRenderSource = useMemo(() => {
    if (!segmentedReaderEnabled) return null;
    const activeSource = activeBlockUid
      ? (renderSourceByBlockUid.get(activeBlockUid) ?? null)
      : null;
    if (activeSource) return activeSource;
    if (activeRenderSourceUid) {
      const explicitSource = renderSourceByUid.get(activeRenderSourceUid);
      if (explicitSource) return explicitSource;
    }
    return renderSources[0] ?? null;
  }, [
    activeBlockUid,
    activeRenderSourceUid,
    renderSourceByBlockUid,
    renderSourceByUid,
    renderSources,
    segmentedReaderEnabled
  ]);
  const renderBlocks = useMemo(() => {
    if (!segmentedReaderEnabled || !activeRenderSource) return blocks;
    return blocks.slice(activeRenderSource.startIndex, activeRenderSource.endIndex);
  }, [activeRenderSource, blocks, segmentedReaderEnabled]);
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
  const navigationBlockUids = useMemo(
    () => new Set(blocks.map((block) => block.block_uid)),
    [blocks]
  );
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
  const readerProgressMilestone = readerProgressMilestoneForProgress(readerProgress, t);
  const activeChapterLabel = useMemo(() => {
    if (segmentedReaderEnabled && activeRenderSource) return activeRenderSource.title;
    const activeChapter = navBlocks.find((block) => block.block_uid === activeNavBlockUid);
    return activeChapter ? chapterTitle(activeChapter) : t("reader.noChapter");
  }, [activeNavBlockUid, activeRenderSource, navBlocks, segmentedReaderEnabled, t]);
  const chapterNavItems = useMemo(
    () =>
      segmentedReaderEnabled
        ? renderSources.map((source, index) => ({
            uid: source.uid,
            targetBlockUid: source.uid,
            title: source.title,
            number: String(index + 1),
            blockCount: source.blockCount
          }))
        : navBlocks.map((block, index) => ({
            uid: block.block_uid,
            targetBlockUid: block.block_uid,
            title: chapterTitle(block),
            number: chapterNumber(index, block)
          })),
    [navBlocks, renderSources, segmentedReaderEnabled]
  );
  const activeChapterNavUid =
    segmentedReaderEnabled && activeRenderSource ? activeRenderSource.uid : activeNavBlockUid;
  const chapterRailEnabled = chapterNavItems.length > 0;
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
  const readerRightRailOpen = !kindleMode && studyRailOpen;
  const activeWorkspaceOverlay: ReaderOverlayKind =
    activeReaderOverlay && activeReaderOverlay !== "articles" ? activeReaderOverlay : "ask";
  const readerOverlayInline =
    readerRightRailOpen && Boolean(activeReaderOverlay) && activeReaderOverlay !== "articles";

  useEffect(() => {
    const workspaceGroup = readerWorkspaceGroupForOverlay(activeReaderOverlay);
    if (workspaceGroup) setActiveReaderWorkspaceGroup(workspaceGroup);
  }, [activeReaderOverlay]);

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
    if (translations.data?.target_language !== targetLanguage) return map;
    for (const variant of translations.data?.variants ?? []) {
      if (variant.target_language !== targetLanguage) continue;
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
  }, [targetLanguage, translations.data?.target_language, translations.data?.variants]);
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
      map.set(blockUid, translationVariantOptions(variants, t));
    }
    return map;
  }, [t, variantsByBlockUid]);
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
  const knowledgeCardsByBlockUid = useMemo(() => {
    const map = new Map<string, ReaderCard[]>();
    for (const card of readerCards.data?.cards ?? []) {
      if (card.status === "archived") continue;
      if (card.card_type === "note") continue;
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
  const pinnedNoteCardsByBlockUid = useMemo(() => {
    const map = new Map<string, ReaderCard[]>();
    for (const card of readerCards.data?.cards ?? []) {
      if (card.card_type !== "note" || card.status !== "pinned") continue;
      const cards = map.get(card.anchor_block_uid) ?? [];
      cards.push(card);
      map.set(card.anchor_block_uid, cards);
    }
    for (const cards of map.values()) {
      cards.sort((left, right) => String(left.updated_at).localeCompare(String(right.updated_at)));
    }
    return map;
  }, [readerCards.data?.cards]);
  const pinnedNoteCount = useMemo(
    () => [...pinnedNoteCardsByBlockUid.values()].reduce((total, cards) => total + cards.length, 0),
    [pinnedNoteCardsByBlockUid]
  );
  const readerNoteStickiesEnabled =
    !kindleMode && (readerNoteStickiesOverride ?? pinnedNoteCount > 0);
  const termCardsVisible =
    readerFeaturePreferences.termCardsEnabled &&
    hasArticleContext &&
    (termWikiEnabled || knowledgeCardsByBlockUid.size > 0);
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
  const kindleFontScalePercent = Math.round(readerPreferences.fontScale * 100);
  const decreaseKindleFontSize = useCallback(() => {
    setReaderPreference("fontScale", readerPreferences.fontScale - 0.03);
  }, [readerPreferences.fontScale, setReaderPreference]);
  const increaseKindleFontSize = useCallback(() => {
    setReaderPreference("fontScale", readerPreferences.fontScale + 0.03);
  }, [readerPreferences.fontScale, setReaderPreference]);

  const markReaderActivity = useCallback(() => {
    lastReaderActivityAt.current = Date.now();
  }, []);

  useEffect(() => {
    setStudyRailOpen(desktopReaderRailPreferred);
  }, [desktopReaderRailPreferred]);

  const toggleReaderOverlay = useCallback(
    (overlay: ReaderOverlayKind) => {
      setReaderModeMenuOpen(false);
      setActiveReaderOverlay(activeReaderOverlay === overlay ? null : overlay);
    },
    [activeReaderOverlay, setActiveReaderOverlay]
  );

  const toggleReaderWorkspace = useCallback(() => {
    setReaderModeMenuOpen(false);
    if (readerRightRailOpen) {
      setStudyRailOpen(false);
      setActiveReaderOverlay(null);
      return;
    }
    setStudyRailOpen(true);
    setActiveReaderWorkspaceGroup("read");
    setActiveReaderOverlay("ask");
  }, [readerRightRailOpen, setActiveReaderOverlay]);

  const closeReaderOverlay = useCallback(() => {
    setActiveReaderOverlay(null);
  }, [setActiveReaderOverlay]);

  const toggleReaderModeMenu = useCallback(() => {
    setActiveReaderOverlay(null);
    setReaderModeMenuOpen((open) => !open);
  }, [setActiveReaderOverlay]);

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
    if (!kindleMode) setKindleChromeHidden(false);
  }, [kindleMode]);

  useEffect(() => {
    if (typeof window === "undefined") return undefined;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      if (activeReaderOverlay) {
        event.preventDefault();
        closeReaderOverlay();
        return;
      }
      if (readerModeMenuOpen) {
        event.preventDefault();
        setReaderModeMenuOpen(false);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [activeReaderOverlay, closeReaderOverlay, readerModeMenuOpen]);

  useEffect(() => {
    if (
      !activeReaderOverlay ||
      !readerOverlayAutoCloseEnabled ||
      kindleMode ||
      typeof window === "undefined"
    ) {
      return undefined;
    }
    readerOverlayScrollDirection.current = 0;
    readerOverlayScrollDistance.current = 0;
    readerOverlayScrollStartedAt.current = 0;
    lastReaderOverlayScrollY.current = Math.max(0, window.scrollY);
    const handleOverlayScroll = () => {
      const scrollY = Math.max(0, window.scrollY);
      const delta = scrollY - lastReaderOverlayScrollY.current;
      lastReaderOverlayScrollY.current = scrollY;
      if (Math.abs(delta) < 4) return;
      if (readerOverlayPointerInside.current) {
        readerOverlayScrollDirection.current = 0;
        readerOverlayScrollDistance.current = 0;
        readerOverlayScrollStartedAt.current = 0;
        return;
      }
      const direction: 1 | -1 = delta > 0 ? 1 : -1;
      const now = Date.now();
      if (readerOverlayScrollDirection.current !== direction) {
        readerOverlayScrollDirection.current = direction;
        readerOverlayScrollDistance.current = Math.abs(delta);
        readerOverlayScrollStartedAt.current = now;
        return;
      }
      readerOverlayScrollDistance.current += Math.abs(delta);
      if (
        readerOverlayScrollDistance.current >= READER_OVERLAY_SCROLL_CLOSE_DISTANCE_PX &&
        now - readerOverlayScrollStartedAt.current >= READER_OVERLAY_SCROLL_CLOSE_DELAY_MS &&
        now - lastReaderOverlayAutoCloseAt.current >= READER_OVERLAY_SCROLL_CLOSE_COOLDOWN_MS
      ) {
        lastReaderOverlayAutoCloseAt.current = now;
        closeReaderOverlay();
      }
    };
    window.addEventListener("scroll", handleOverlayScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleOverlayScroll);
  }, [activeReaderOverlay, closeReaderOverlay, kindleMode, readerOverlayAutoCloseEnabled]);

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
    setActiveReaderOverlay(null);
  }, [kindleMode, setActiveReaderOverlay]);

  useEffect(() => {
    if (!termWikiEnabled || !readerFeaturePreferences.termCardsEnabled) return;
    setActiveReaderOverlay(null);
  }, [readerFeaturePreferences.termCardsEnabled, setActiveReaderOverlay, termWikiEnabled]);

  useEffect(() => {
    if (navBlocks.length === 0) {
      setChaptersOpen(false);
      return;
    }
    setChaptersOpen(defaultDesktopReaderRailOpen());
  }, [articleId, navBlocks.length]);

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
    setChatBlockUid(null);
    setQuestion("");
    setReaderStudyContext({ scope: "article", blockUid: null });
    setReaderNoteStickiesOverride(null);
    setActiveRenderSourceUid(null);
    setParagraphAskResultByBlockUid({});
    setQuickAskPendingBlockUid(null);
    setQuickAskSavingBlockUid(null);
    setExpandedReaderCardByBlock({});
    lastInitialHashNavigation.current = null;
    lastSavedProgressNavigation.current = null;
    lastReadingProgressSampleAt.current = Date.now();
    pendingReadingProgressDeltas.current = {};
  }, [articleId, setReaderNoteStickiesOverride, setReaderStudyContext, targetLanguage]);

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
      setActiveRenderSourceUid(null);
      return;
    }
    if (!activeBlockUid || !blockIndexByUid.has(activeBlockUid)) {
      setActiveBlockUid(blocks[0].block_uid);
    }
  }, [activeBlockUid, blockIndexByUid, blocks]);

  useEffect(() => {
    if (!segmentedReaderEnabled) {
      if (activeRenderSourceUid !== null) setActiveRenderSourceUid(null);
      return;
    }
    const source = activeBlockUid ? renderSourceByBlockUid.get(activeBlockUid) : renderSources[0];
    const nextUid = source?.uid ?? null;
    if (nextUid !== activeRenderSourceUid) setActiveRenderSourceUid(nextUid);
  }, [
    activeBlockUid,
    activeRenderSourceUid,
    renderSourceByBlockUid,
    renderSources,
    segmentedReaderEnabled
  ]);

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
      const targetSource = renderSourceByBlockUid.get(blockUid);
      if (targetSource) setActiveRenderSourceUid(targetSource.uid);
      setForcedBlockUid(blockUid);
      setActiveBlockUid(blockUid);
      setPendingNavigationBlockUid(kindleMode ? null : blockUid);
      if (typeof window !== "undefined") {
        const nextUrl = `${window.location.pathname}${window.location.search}#${encodeURIComponent(blockUid)}`;
        window.history.replaceState(null, "", nextUrl);
      }
    },
    [kindleMode, markReaderActivity, renderSourceByBlockUid]
  );

  const changeKindlePageBlock = useCallback(
    (blockUid: string) => {
      markReaderActivity();
      const targetSource = renderSourceByBlockUid.get(blockUid);
      if (targetSource) setActiveRenderSourceUid(targetSource.uid);
      setForcedBlockUid(blockUid);
      setActiveBlockUid(blockUid);
      setPendingNavigationBlockUid(null);
      if (typeof window !== "undefined") {
        const nextUrl = `${window.location.pathname}${window.location.search}#${encodeURIComponent(blockUid)}`;
        window.history.replaceState(null, "", nextUrl);
      }
    },
    [markReaderActivity, renderSourceByBlockUid]
  );

  const hideKindleChrome = useCallback(() => {
    if (!kindleMode) return;
    setKindleChromeHidden(true);
    setReaderModeMenuOpen(false);
    setActiveReaderOverlay(null);
  }, [kindleMode, setActiveReaderOverlay]);

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
      if (typeof window === "undefined" || taskNotificationOpenDelayMs <= 0) {
        openTaskDrawer();
        return;
      }
      window.setTimeout(openTaskDrawer, taskNotificationOpenDelayMs);
    }
  }, [
    openTaskDrawer,
    readerFeaturePreferences.taskNotificationsEnabled,
    taskNotificationOpenDelayMs
  ]);

  const handleActiveBlockChange = useCallback(
    (blockUid: string) => {
      markReaderActivity();
      setActiveBlockUid((current) => (current === blockUid ? current : blockUid));
      setChatBlockUid(blockUid);
      setReaderStudyContext({ scope: "block", blockUid });
    },
    [markReaderActivity, setReaderStudyContext]
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

  const openReaderCardDraft = useCallback(
    (block: DocumentBlock, card?: ReaderCard, cardType: ReaderCard["card_type"] = "note") => {
      const selection = selectedTextInsideBlock(block.block_uid);
      setReaderCardDraft({
        cardId: card?.id,
        blockUid: block.block_uid,
        cardType: card?.card_type ?? cardType,
        anchorText: card?.anchor_text || selection || conciseAnchorText(block.source_markdown),
        title: card?.title || selection || conciseAnchorText(block.source_markdown),
        bodyMarkdown: card?.body_markdown || "",
        sourceType: card?.source_type ?? "user_note",
        position: card?.position ?? "right",
        metadata: card?.metadata
      });
    },
    []
  );

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
            status: "pinned",
            metadata: { ...(readerCardDraft.metadata ?? {}), user_edited: true }
          }
        },
        {
          onSuccess: () => {
            setReaderCardDraft(null);
            if (readerCardDraft.cardType === "note") {
              setReaderNoteStickiesOverride(true);
            } else {
              setReaderFeaturePreference("termCardsEnabled", true);
              setTermWikiEnabled(true);
            }
            setReaderActionMessage(t("reader.cardCreated"));
          },
          onError: (error) => setCardActionError(error, setReaderActionMessage, t)
        }
      );
      return;
    }
    createReaderCard.mutate(
      {
        card_type: readerCardDraft.cardType,
        anchor_block_uid: readerCardDraft.blockUid,
        anchor_text: readerCardDraft.anchorText,
        title: readerCardDraft.title,
        body_markdown: readerCardDraft.bodyMarkdown,
        target_language: targetLanguage,
        source_type: readerCardDraft.sourceType,
        status: "pinned",
        position: readerCardDraft.position,
        metadata: { source: "reader_selection", user_edited: true }
      },
      {
        onSuccess: () => {
          setReaderCardDraft(null);
          if (readerCardDraft.cardType === "note") {
            setReaderNoteStickiesOverride(true);
          } else {
            setReaderFeaturePreference("termCardsEnabled", true);
            setTermWikiEnabled(true);
          }
          setReaderActionMessage(t("reader.cardCreated"));
        },
        onError: (error) => setCardActionError(error, setReaderActionMessage, t)
      }
    );
  }, [
    createReaderCard,
    readerCardDraft,
    setReaderNoteStickiesOverride,
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

  const optimizeNoteCard = useCallback(
    async (card: ReaderCard) => {
      try {
        const protectedMetadata = { ...card.metadata, user_edited: true };
        await updateReaderCard.mutateAsync({
          cardId: card.id,
          payload: { metadata: protectedMetadata }
        });
        const result = await generateReaderCard.mutateAsync({
          anchor_block_uid: card.anchor_block_uid,
          anchor_text: card.anchor_text,
          target_language: card.target_language,
          provider_profile_id: selectedProviderId,
          model: selectedProvider?.default_model ?? null,
          native_search: true,
          card_type: "note",
          title: card.title,
          abbreviation: card.abbreviation,
          full_form: card.full_form
        });
        const suggestedBody =
          metadataString(result.card.metadata, "suggested_body_markdown") ||
          result.card.body_markdown ||
          card.body_markdown;
        setReaderCardDraft({
          cardId: card.id,
          blockUid: card.anchor_block_uid,
          cardType: "note",
          anchorText: card.anchor_text,
          title: result.card.title || card.title,
          bodyMarkdown: suggestedBody,
          sourceType: card.source_type,
          position: card.position,
          metadata: protectedMetadata
        });
        setReaderNoteStickiesOverride(true);
        setReaderActionMessage(t("reader.cardGenerated"));
      } catch (error) {
        setCardActionError(error, setReaderActionMessage, t);
      }
    },
    [
      generateReaderCard,
      selectedProvider?.default_model,
      selectedProviderId,
      setReaderNoteStickiesOverride,
      t,
      updateReaderCard
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

  const submitQuestion = (blockUid: string | null = chatBlockUid) => {
    if (!selectedProviderId || !question.trim()) return;
    setStreamingAnswer("");
    setStreamingCitedBlocks([]);
    askQuestion.mutate({
      payload: {
        question: question.trim(),
        provider_profile_id: selectedProviderId,
        model: selectedProvider?.default_model ?? null,
        current_block_uid: blockUid,
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

  const askParagraphQuestion = useCallback(
    (block: DocumentBlock, nextQuestion: string) => {
      if (!selectedProviderId || !nextQuestion.trim()) return;
      setQuickAskPendingBlockUid(block.block_uid);
      askBlockQuestion.mutate(
        {
          question: nextQuestion.trim(),
          provider_profile_id: selectedProviderId,
          model: selectedProvider?.default_model ?? null,
          current_block_uid: block.block_uid,
          max_blocks: 3,
          native_search: false,
          retrieval_mode: "fts"
        },
        {
          onSuccess: (result) => {
            setParagraphAskResultByBlockUid((current) => ({
              ...current,
              [block.block_uid]: {
                question: nextQuestion.trim(),
                answer: result.assistant_message.content
              }
            }));
          },
          onError: (error) => setCardActionError(error, setReaderActionMessage, t),
          onSettled: () => setQuickAskPendingBlockUid(null)
        }
      );
    },
    [askBlockQuestion, selectedProvider?.default_model, selectedProviderId, t]
  );

  const saveParagraphAnswerAsNote = useCallback(
    (block: DocumentBlock) => {
      const result = paragraphAskResultByBlockUid[block.block_uid];
      if (!result) return;
      setQuickAskSavingBlockUid(block.block_uid);
      createReaderCard.mutate(
        {
          card_type: "note",
          anchor_block_uid: block.block_uid,
          anchor_text: conciseAnchorText(block.source_markdown),
          title: result.question.slice(0, 160),
          body_markdown: result.answer,
          target_language: targetLanguage,
          source_type: "user_note",
          status: "pinned",
          position: "right",
          metadata: {
            source: "paragraph_qa",
            question: result.question,
            user_edited: true
          }
        },
        {
          onSuccess: () => {
            setReaderNoteStickiesOverride(true);
            setReaderActionMessage(t("reader.quickAskCardCreated"));
          },
          onError: (error) => setCardActionError(error, setReaderActionMessage, t),
          onSettled: () => setQuickAskSavingBlockUid(null)
        }
      );
    },
    [
      createReaderCard,
      paragraphAskResultByBlockUid,
      setReaderNoteStickiesOverride,
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

  const copyText = useCallback(
    async (text: string, label: string) => {
      if (!text.trim()) {
        setReaderActionMessage(t("reader.copyEmpty", { label }));
        return;
      }
      try {
        await writeClipboardText(text);
        setReaderActionMessage(t("reader.copySuccess", { label }));
      } catch {
        setReaderActionMessage(t("reader.clipboardUnavailable"));
      }
    },
    [t]
  );

  const handleToolbarAction = useCallback(
    (actionId: ReaderToolbarActionId, block: DocumentBlock, content: string) => {
      if (actionId === "copy-source" || actionId === "copy-block") {
        void copyText(block.source_markdown, t("reader.sourceBlockLabel"));
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
            onSuccess: (result) =>
              setReaderActionMessage(t("reader.obsidianSaved", { path: result.note_path })),
            onError: () =>
              void copyText(
                obsidianCalloutForBlock(block, translationByBlockUid.get(block.block_uid), color),
                t("reader.obsidianCalloutLabel")
              )
          }
        );
        return;
      }
      if (actionId === "copy-translation") {
        void copyText(content, t("reader.translationBlockLabel"));
        return;
      }
      if (actionId === "ask-source" || actionId === "explain-block") {
        setChatBlockUid(block.block_uid);
        setReaderStudyContext({ scope: "block", blockUid: block.block_uid });
        setReaderNoteStickiesOverride(true);
        closeReaderOverlay();
        setReaderActionMessage(t("reader.currentBlockSelected", { blockUid: block.block_uid }));
        return;
      }
      if (actionId === "create-card") {
        setReaderFeaturePreference("termCardsEnabled", true);
        setTermWikiEnabled(true);
        openReaderCardDraft(block, undefined, "term");
        return;
      }
      if (actionId === "show-latex" || actionId === "show-source") {
        setInspectedBlock(block);
        return;
      }
      if (actionId === "retranslate") {
        if (!selectedProviderId) {
          setReaderActionMessage(t("reader.selectProviderForBlockRetranslation"));
          return;
        }
        setRetranslationBlock(block);
        setCustomRetranslationPrompt("");
        return;
      }
      if (actionId === "add-note-patch") {
        setChatBlockUid(block.block_uid);
        setReaderStudyContext({ scope: "block", blockUid: block.block_uid });
        setActiveReaderOverlay("noteGenerator");
        setReaderActionMessage(t("reader.blockSelectedForNotes", { blockUid: block.block_uid }));
      }
    },
    [
      blockColors,
      closeReaderOverlay,
      copyText,
      readerFeaturePreferences.colorMarkersEnabled,
      saveObsidianClip,
      selectedProviderId,
      setActiveReaderOverlay,
      setReaderNoteStickiesOverride,
      setReaderFeaturePreference,
      setReaderStudyContext,
      t,
      targetLanguage,
      translationByBlockUid,
      openReaderCardDraft
    ]
  );

  const renderReaderBlock = useCallback(
    (block: DocumentBlock) => {
      const asset = assetForBlock(block, assetById);
      const assetId = asset?.asset_id;
      const blockNotes = pinnedNoteCardsByBlockUid.get(block.block_uid) ?? [];
      const knowledgeCards = knowledgeCardsByBlockUid.get(block.block_uid) ?? [];
      return (
        <ReaderBlockFrame
          block={block}
          notes={blockNotes}
          noteStickiesEnabled={readerNoteStickiesEnabled}
          onAddNote={() => openReaderCardDraft(block)}
          onEditNote={(card) => openReaderCardDraft(block, card)}
          onDeleteNote={deleteCard}
          onOptimizeNote={optimizeNoteCard}
          isOptimizingNote={generateReaderCard.isPending || updateReaderCard.isPending}
          canOptimizeNote={Boolean(selectedProviderId)}
          key={block.block_uid}
        >
          <ReaderBlock
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
            translationVariantOptions={
              translationVariantOptionsByBlockUid.get(block.block_uid) ?? []
            }
            selectedTranslationVariantId={selectedVariantByBlockUid.get(block.block_uid)?.id}
            glossaryAffected={
              readerFeaturePreferences.glossaryReplacementEnabled &&
              affectedBlockUids.has(block.block_uid)
            }
            viewMode={viewMode}
            active={activeBlockUid === block.block_uid}
            controlsVisible={
              readerFeaturePreferences.blockToolsEnabled &&
              currentSearchBlockUid === block.block_uid
            }
            blockToolsEnabled={readerFeaturePreferences.blockToolsEnabled}
            colorMarkersEnabled={readerFeaturePreferences.colorMarkersEnabled}
            sentenceHoverAccentEnabled={readerFeaturePreferences.sentenceHoverAccentEnabled}
            imageLightboxEnabled={readerFeaturePreferences.imageLightboxEnabled}
            searchActive={currentSearchBlockUid === block.block_uid}
            blockColor={blockColors[block.block_uid] ?? "none"}
            termAnnotations={
              readerFeaturePreferences.termCardsEnabled
                ? termAnnotationsForBlock(block, glossaryTerms, knowledgeCards)
                : []
            }
            termWikiEnabled={termCardsVisible}
            readerCards={knowledgeCards}
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
            canQuickAsk={Boolean(selectedProviderId && readerNoteStickiesEnabled)}
            quickAskPending={quickAskPendingBlockUid === block.block_uid}
            quickAskResult={paragraphAskResultByBlockUid[block.block_uid]}
            quickAskSaving={quickAskSavingBlockUid === block.block_uid}
            onQuickAsk={readerNoteStickiesEnabled ? askParagraphQuestion : undefined}
            onQuickAskSaveNote={readerNoteStickiesEnabled ? saveParagraphAnswerAsNote : undefined}
            onToolbarAction={
              readerFeaturePreferences.blockToolsEnabled ? handleToolbarAction : undefined
            }
          />
        </ReaderBlockFrame>
      );
    },
    [
      activeBlockUid,
      affectedBlockUids,
      articleId,
      askParagraphQuestion,
      assetById,
      assetFileUrlsByAssetId,
      assetUrlByAssetId,
      blockColors,
      currentSearchBlockUid,
      deleteCard,
      effectiveCitationLookup,
      expandedReaderCardByBlock,
      exportCard,
      generateCard,
      generateReaderCard.isPending,
      glossaryTerms,
      handleActiveBlockChange,
      handleBlockColorChange,
      handleReaderCardToggle,
      handleToolbarAction,
      handleTranslationVariantChange,
      importCitationArxiv.isPending,
      importCitationToLibrary,
      knowledgeCardsByBlockUid,
      libraryId,
      openReaderCardDraft,
      optimizeNoteCard,
      paragraphAskResultByBlockUid,
      pinCard,
      pinnedNoteCardsByBlockUid,
      quickAskPendingBlockUid,
      quickAskSavingBlockUid,
      readerFeaturePreferences.blockToolsEnabled,
      readerFeaturePreferences.citationPreviewEnabled,
      readerFeaturePreferences.colorMarkersEnabled,
      readerFeaturePreferences.glossaryReplacementEnabled,
      readerFeaturePreferences.imageLightboxEnabled,
      readerFeaturePreferences.sentenceHoverAccentEnabled,
      readerFeaturePreferences.termCardsEnabled,
      readerNoteStickiesEnabled,
      referenceTargets,
      saveParagraphAnswerAsNote,
      selectedProviderId,
      selectedVariantByBlockUid,
      termCardsVisible,
      translationByBlockUid,
      translationVariantOptionsByBlockUid,
      updateReaderCard.isPending,
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

  const readerWorkspaceItems: ReaderWorkspaceItem[] = [
    {
      panel: "ask",
      label: t("reader.fullArticleAsk"),
      icon: <MessageSquare size={15} aria-hidden="true" />,
      tone: readerOverlayTone("ask")
    },
    {
      panel: "search",
      label: t("reader.searchPaper"),
      icon: <Search size={15} aria-hidden="true" />,
      tone: readerOverlayTone("search"),
      badge: readerSearchMatches.length
    },
    {
      panel: "tasks",
      label: t("nav.tasks"),
      icon: <TerminalSquare size={15} aria-hidden="true" />,
      tone: readerOverlayTone("tasks"),
      badge: articleTaskSummary.data?.active ?? 0
    },
    {
      panel: "providers",
      label: t("reader.providerPanel"),
      icon: <Sparkles size={15} aria-hidden="true" />,
      tone: readerOverlayTone("providers"),
      badge: providers.data?.length ?? 0
    },
    {
      panel: "translate",
      label: t("reader.translate"),
      icon: <Languages size={15} aria-hidden="true" />,
      tone: readerOverlayTone("translate")
    },
    {
      panel: "glossary",
      label: t("reader.terms"),
      icon: <BookMarked size={15} aria-hidden="true" />,
      tone: readerOverlayTone("glossary")
    },
    {
      panel: "noteGenerator",
      label: t("reader.noteGenerator"),
      icon: <FileText size={15} aria-hidden="true" />,
      tone: readerOverlayTone("noteGenerator")
    },
    {
      panel: "export",
      label: t("reader.export"),
      icon: <Download size={15} aria-hidden="true" />,
      tone: readerOverlayTone("export")
    },
    {
      panel: "preferences",
      label: t("reader.preferences"),
      icon: <Type size={15} aria-hidden="true" />,
      tone: readerOverlayTone("preferences")
    }
  ];
  const readerWorkspaceGroups: ReaderWorkspaceGroup[] = [
    {
      id: "read",
      label: t("reader.workspaceGroupRead"),
      items: readerWorkspaceItems.filter(
        (item) => readerWorkspaceGroupForOverlay(item.panel) === "read"
      )
    },
    {
      id: "assist",
      label: t("reader.workspaceGroupAssist"),
      items: readerWorkspaceItems.filter(
        (item) => readerWorkspaceGroupForOverlay(item.panel) === "assist"
      )
    },
    {
      id: "output",
      label: t("reader.workspaceGroupOutput"),
      items: readerWorkspaceItems.filter(
        (item) => readerWorkspaceGroupForOverlay(item.panel) === "output"
      )
    }
  ];
  const activeReaderWorkspace =
    readerWorkspaceGroups.find((group) => group.id === activeReaderWorkspaceGroup) ??
    readerWorkspaceGroups[0]!;
  const selectReaderWorkspaceGroup = (group: ReaderWorkspaceGroup) => {
    setStudyRailOpen(true);
    setActiveReaderWorkspaceGroup(group.id);
    if (readerWorkspaceGroupForOverlay(activeReaderOverlay) !== group.id) {
      setActiveReaderOverlay(group.items[0]?.panel ?? null);
    }
  };

  const renderReaderOverlayContent = (overlay: ReaderOverlayKind | null = activeReaderOverlay) => {
    if (overlay === "articles") {
      return (
        <ArticleSwitcherPanel
          currentArticleId={articleId}
          currentArticleItem={currentArticleItem}
          isLoading={libraryArticles.isLoading}
          items={visibleReaderArticleItems}
          query={readerArticleSearchQuery}
          onQueryChange={setReaderArticleSearchQuery}
          onSelect={(item) => {
            switchReaderArticle(item);
            closeReaderOverlay();
          }}
        />
      );
    }
    if (overlay === "search") {
      return (
        <ReaderSearchPanel
          query={readerSearchQuery}
          matches={readerSearchMatches}
          cursor={readerSearchCursor}
          onQueryChange={setReaderSearchQuery}
          onMove={moveReaderSearch}
          onClear={() => {
            setReaderSearchQuery("");
            setReaderSearchCursor(0);
          }}
          onSelect={(blockUid) => {
            navigateToBlock(blockUid);
            closeReaderOverlay();
          }}
        />
      );
    }
    if (overlay === "tasks") {
      return (
        <Stack gap="sm">
          <div className="reader-dock-task-grid">
            <span>{t("task.statusQueued", { count: articleTaskSummary.data?.queued ?? 0 })}</span>
            <span>{t("task.statusRunning", { count: articleTaskSummary.data?.running ?? 0 })}</span>
            <span>{t("task.statusPaused", { count: articleTaskSummary.data?.paused ?? 0 })}</span>
            <span>{t("task.statusFailed", { count: failedArticleTaskCount })}</span>
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
        </Stack>
      );
    }
    if (overlay === "ask") {
      return (
        <ChatPanel
          messages={chat.data?.messages ?? []}
          citedBlocks={
            streamingCitedBlocks.length > 0
              ? streamingCitedBlocks
              : (askQuestion.data?.cited_blocks ?? [])
          }
          streamingAnswer={streamingAnswer}
          referenceTargets={referenceTargets}
          selectedBlockUid={null}
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
          onClearBlock={() => {
            setChatBlockUid(null);
            setReaderStudyContext({ scope: "article", blockUid: null });
          }}
          onAsk={() => {
            setChatBlockUid(null);
            setReaderStudyContext({ scope: "article", blockUid: null });
            submitQuestion(null);
          }}
          onCreateNotePatch={createNotePatchFromMessage}
        />
      );
    }
    if (overlay === "providers") {
      return (
        <Stack gap="sm">
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
          {(providers.data ?? []).slice(0, 5).map((provider) => (
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
            <Text c="dimmed" size="sm">
              {t("library.noProviderConfigured")}
            </Text>
          ) : null}
          <Button size="xs" variant="subtle" onClick={() => navigate("/settings")}>
            {t("nav.settings")}
          </Button>
        </Stack>
      );
    }
    if (overlay === "translate") {
      return (
        <div className="panel reader-translation-panel">
          <Stack gap="sm">
            <Button
              fullWidth
              leftSection={<Languages size={16} />}
              onClick={queueArticleTranslation}
              loading={translateArticle.isPending}
              disabled={!selectedProviderId || !targetLanguage.trim() || blocks.length === 0}
            >
              {t("reader.translatePaper")}
            </Button>
            <Checkbox
              checked={autoTranslateOnLanguageSwitch}
              label={t("reader.autoTranslateOnLanguageSwitch")}
              onChange={(event) => setAutoTranslateOnLanguageSwitch(event.currentTarget.checked)}
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
      );
    }
    if (overlay === "glossary") {
      return (
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
      );
    }
    if (overlay === "noteGenerator") {
      return (
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
        </Stack>
      );
    }
    if (overlay === "export") {
      return (
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
      );
    }
    if (overlay === "preferences") {
      return <ReaderPreferencesPanel showTitle={false} />;
    }
    return null;
  };
  return (
    <div
      className={`reader-page${kindleMode ? " reader-page-kindle" : ""}${
        kindleMode && kindleBlockViewMode === "bilingual" ? " reader-page-kindle-landscape" : ""
      }${kindleMode && kindleChromeHidden ? " reader-kindle-chrome-hidden" : ""}`}
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
      <Modal
        opened={Boolean(activeReaderOverlay) && !kindleMode && !readerOverlayInline}
        onClose={closeReaderOverlay}
        title={activeReaderOverlay ? readerOverlayTitle(activeReaderOverlay, t) : undefined}
        size={readerOverlaySize(activeReaderOverlay)}
        closeOnClickOutside
        closeOnEscape
        closeButtonProps={{ "aria-label": t("reader.closeToolPanel") }}
      >
        <section
          ref={readerOverlayRef}
          onPointerEnter={() => {
            readerOverlayPointerInside.current = true;
          }}
          onPointerLeave={() => {
            readerOverlayPointerInside.current = false;
          }}
        >
          {renderReaderOverlayContent()}
        </section>
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
                className="reader-chrome-button reader-home-button"
                aria-label={t("nav.home")}
                title={t("nav.home")}
                variant="light"
                size="xs"
                leftSection={<House size={15} aria-hidden="true" />}
                onClick={openCurrentLibrary}
              >
                {t("nav.home")}
              </Button>
              <Button
                className="reader-chrome-button"
                aria-pressed={activeReaderOverlay === "articles"}
                title={t("reader.articleSwitcher")}
                variant={activeReaderOverlay === "articles" ? "light" : "subtle"}
                size="xs"
                leftSection={<BookMarked size={15} aria-hidden="true" />}
                onClick={() => toggleReaderOverlay("articles")}
              >
                {t("nav.library")}
              </Button>
            </div>
            <div className="reader-command-middle">
              <div className="reader-surface-switch" aria-label={t("reader.surfaceMode")}>
                <Button
                  aria-pressed={!kindleMode}
                  aria-label={t("reader.htmlMode")}
                  className="reader-chrome-button reader-surface-button"
                  variant={!kindleMode ? "light" : "subtle"}
                  size="xs"
                  leftSection={<FileText size={15} aria-hidden="true" />}
                  onClick={() => setReaderSurfaceMode("workbench")}
                >
                  {t("reader.htmlMode")}
                </Button>
                <Button
                  aria-pressed={kindleMode}
                  aria-label={t("reader.kindleMode")}
                  className="reader-chrome-button reader-surface-button"
                  variant={kindleMode ? "light" : "subtle"}
                  size="xs"
                  leftSection={<BookOpenText size={15} aria-hidden="true" />}
                  onClick={() => setReaderSurfaceMode("kindle")}
                >
                  {t("reader.kindleMode")}
                </Button>
              </div>
            </div>
            <div className="reader-command-zone reader-command-right">
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
              {kindleMode ? (
                <div
                  className="reader-kindle-font-controls"
                  aria-label={t("reader.kindleFontSize")}
                >
                  <ActionIcon
                    aria-label={t("reader.decreaseFontSize")}
                    disabled={readerPreferences.fontScale <= 0.9}
                    variant="subtle"
                    size="sm"
                    onClick={decreaseKindleFontSize}
                  >
                    <Minus size={14} aria-hidden="true" />
                  </ActionIcon>
                  <span className="reader-kindle-font-value" aria-live="polite">
                    <Type size={14} aria-hidden="true" />
                    {kindleFontScalePercent}%
                  </span>
                  <ActionIcon
                    aria-label={t("reader.increaseFontSize")}
                    disabled={readerPreferences.fontScale >= 1.18}
                    variant="subtle"
                    size="sm"
                    onClick={increaseKindleFontSize}
                  >
                    <Plus size={14} aria-hidden="true" />
                  </ActionIcon>
                </div>
              ) : null}
              {!kindleMode ? (
                <Button
                  className="reader-chrome-button"
                  aria-pressed={readerRightRailOpen}
                  aria-label={t("reader.workspaceRail")}
                  title={t("reader.workspaceRail")}
                  variant={readerRightRailOpen ? "light" : "subtle"}
                  size="xs"
                  leftSection={<Columns2 size={15} aria-hidden="true" />}
                  onClick={toggleReaderWorkspace}
                >
                  {t("reader.workspaceShort")}
                </Button>
              ) : null}
              {!kindleMode ? (
                <Button
                  className="reader-chrome-button"
                  aria-pressed={activeReaderOverlay === "preferences"}
                  title={t("reader.preferences")}
                  variant={activeReaderOverlay === "preferences" ? "light" : "subtle"}
                  size="xs"
                  leftSection={<Type size={15} aria-hidden="true" />}
                  onClick={() => toggleReaderOverlay("preferences")}
                >
                  {t("reader.preferences")}
                </Button>
              ) : null}
            </div>
          </div>
        </section>
        {kindleMode ? (
          <KindlePagedReader
            blocks={renderBlocks}
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
              chapterRailEnabled ? " reader-mosaic-has-chapters" : ""
            }${chapterRailOpen ? " reader-mosaic-chapters-open" : " reader-mosaic-left-collapsed reader-mosaic-chapters-collapsed"}${
              readerRightRailOpen
                ? " reader-mosaic-study-open"
                : " reader-mosaic-right-collapsed reader-mosaic-study-collapsed"
            }`}
          >
            {chapterRailEnabled ? (
              <aside
                className={`reader-side-rail reader-article-rail reader-chapter-rail${
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
                      {chapterNavItems.map((item) => (
                        <a
                          key={item.uid}
                          href={`#${item.targetBlockUid}`}
                          className={
                            activeChapterNavUid === item.uid ? "reader-nav-active" : undefined
                          }
                          aria-current={activeChapterNavUid === item.uid ? "location" : undefined}
                          onClick={(event) => {
                            event.preventDefault();
                            navigateToBlock(item.targetBlockUid);
                          }}
                        >
                          <Badge variant="light" size="sm">
                            {item.number}
                          </Badge>
                          <span>{item.title}</span>
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
            <div className="reader-paper-layout reader-paper-layout-no-chapters">
              <section
                className={`reader-paper-shell${
                  readerNoteStickiesEnabled ? " reader-paper-notes-enabled" : ""
                }`}
                aria-label={title}
              >
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
                {recoveredLatexmlDocument ? (
                  <Alert color="yellow" mb="md" title={t("reader.recoveredDocumentTitle")}>
                    {t("reader.recoveredDocumentNotice")}
                  </Alert>
                ) : null}
                <ReaderBlockList
                  blocks={renderBlocks}
                  activeBlockUid={activeBlockUid}
                  fontScale={readerPreferences.fontScale}
                  paragraphSpacingEm={readerPreferences.paragraphSpacingEm}
                  forcedBlockUid={forcedBlockUid}
                  searchTargetBlockUid={currentSearchBlockUid}
                  navigationBlockUids={navigationBlockUids}
                  getBlockText={blockTextForPlaceholder}
                  onActiveBlockChange={handleActiveBlockChange}
                  onNavigateToBlock={navigateToBlock}
                  renderBlock={renderReaderBlock}
                />
              </section>
            </div>
            <aside
              className={`reader-side-rail reader-right-rail reader-study-rail${
                readerRightRailOpen ? "" : " reader-side-rail-collapsed"
              }`}
              aria-label={t("reader.workspaceRail")}
            >
              {readerRightRailOpen ? (
                <>
                  <div className="reader-rail-header reader-workspace-header">
                    <div>
                      <Text fw={720} size="sm">
                        {t("reader.workspaceRail")}
                      </Text>
                      <Text c="dimmed" size="xs" lineClamp={1}>
                        {t("reader.workspaceRailHelp")}
                      </Text>
                    </div>
                    <ActionIcon
                      aria-label={t("reader.collapsePanel", {
                        panel: t("reader.workspaceRail")
                      })}
                      variant="subtle"
                      size="sm"
                      onClick={() => {
                        setStudyRailOpen(false);
                        setActiveReaderOverlay(null);
                      }}
                    >
                      <ChevronRight size={15} aria-hidden="true" />
                    </ActionIcon>
                  </div>
                  <div className="reader-workspace-tools">
                    <div
                      className="reader-workspace-groups"
                      role="group"
                      aria-label={t("reader.workspaceModes")}
                    >
                      {readerWorkspaceGroups.map((group) => (
                        <button
                          key={group.id}
                          type="button"
                          className="reader-workspace-group"
                          aria-pressed={activeReaderWorkspace.id === group.id}
                          onClick={() => selectReaderWorkspaceGroup(group)}
                        >
                          <span>{group.label}</span>
                        </button>
                      ))}
                    </div>
                    <div className="reader-workspace-tabs" aria-label={activeReaderWorkspace.label}>
                      {activeReaderWorkspace.items.map((item) => (
                        <button
                          key={item.panel}
                          type="button"
                          className="reader-workspace-tab"
                          aria-label={item.label}
                          aria-pressed={activeWorkspaceOverlay === item.panel}
                          data-tone={item.tone}
                          title={item.label}
                          onClick={() => {
                            setStudyRailOpen(true);
                            setActiveReaderOverlay(item.panel);
                          }}
                        >
                          {item.icon}
                          <span>{item.label}</span>
                          {typeof item.badge === "number" && item.badge > 0 ? (
                            <span className="reader-toolbar-badge">{item.badge}</span>
                          ) : null}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div
                    className="reader-side-tile reader-workspace-panel reader-tool-tile"
                    data-tone={readerOverlayTone(activeWorkspaceOverlay)}
                  >
                    <div className="reader-workspace-panel-header">
                      <div className="reader-side-tile-title">
                        {readerOverlayIcon(activeWorkspaceOverlay)}
                        <span>{readerOverlayTitle(activeWorkspaceOverlay, t)}</span>
                      </div>
                      {activeWorkspaceOverlay === "ask" ? (
                        <button
                          type="button"
                          className="reader-note-stickies-toggle"
                          aria-pressed={readerNoteStickiesEnabled}
                          onClick={() => setReaderNoteStickiesOverride(!readerNoteStickiesEnabled)}
                        >
                          <StickyNote size={14} aria-hidden="true" />
                          <span>{t("reader.notes")}</span>
                        </button>
                      ) : null}
                    </div>
                    <section
                      ref={readerOverlayRef}
                      className="reader-side-tile-body reader-workspace-body"
                      data-overlay={activeWorkspaceOverlay}
                      onPointerEnter={() => {
                        readerOverlayPointerInside.current = true;
                      }}
                      onPointerLeave={() => {
                        readerOverlayPointerInside.current = false;
                      }}
                    >
                      {renderReaderOverlayContent(activeWorkspaceOverlay)}
                    </section>
                  </div>
                </>
              ) : (
                <button
                  type="button"
                  className="reader-rail-collapsed-button reader-study-rail-spine"
                  aria-expanded={false}
                  onClick={() => {
                    setStudyRailOpen(true);
                    setActiveReaderOverlay(null);
                  }}
                >
                  <MessageSquare size={15} aria-hidden="true" />
                  <span>{t("reader.workspaceShort")}</span>
                </button>
              )}
            </aside>
          </section>
        )}
        {!kindleMode && readerFeaturePreferences.bottomProgressVisible ? (
          <section
            className="reader-bottom-status"
            aria-label={t("reader.readingProgress", { progress: readerProgress })}
          >
            <div className="reader-progress-group">
              <span className="reader-progress-label">
                {readerSearchQuery
                  ? readerSearchMatches.length > 0
                    ? t("reader.searchCount", {
                        current: Math.min(readerSearchCursor + 1, readerSearchMatches.length),
                        total: readerSearchMatches.length
                      })
                    : t("reader.searchNoMatches")
                  : t("reader.readingProgress", { progress: readerProgress })}
              </span>
              <div
                className="reader-progress-track"
                data-complete={readerProgress >= 100 || undefined}
              >
                <progress value={readerProgress} max={100} />
                <span className="reader-progress-milestones" aria-hidden="true">
                  {READER_PROGRESS_MILESTONES.map((milestone) => (
                    <span
                      className="reader-progress-milestone"
                      data-active={readerProgress >= milestone || undefined}
                      key={milestone}
                      style={{ left: `${milestone}%` }}
                    />
                  ))}
                </span>
              </div>
              {!readerSearchQuery && readerProgressMilestone ? (
                <span className="reader-progress-milestone-label" key={readerProgressMilestone.key}>
                  {readerProgressMilestone.label}
                </span>
              ) : null}
            </div>
            <div className="reader-block-counter" aria-live="polite">
              <button
                type="button"
                aria-label={t("reader.searchPrevious")}
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
                aria-label={t("reader.searchNext")}
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

interface ArticleSwitcherPanelProps {
  currentArticleId?: string;
  currentArticleItem: ArticleListItem | null;
  isLoading: boolean;
  items: ArticleListItem[];
  query: string;
  onQueryChange: (value: string) => void;
  onSelect: (item: ArticleListItem) => void;
}

function ArticleSwitcherPanel({
  currentArticleId,
  currentArticleItem,
  isLoading,
  items,
  query,
  onQueryChange,
  onSelect
}: ArticleSwitcherPanelProps) {
  const t = useT();
  return (
    <Stack gap="sm">
      <Text c="dimmed" size="xs" lineClamp={2}>
        {currentArticleItem ? readerArticleTitle(currentArticleItem) : t("reader.noCurrentArticle")}
      </Text>
      <TextInput
        className="reader-article-switch-search"
        aria-label={t("reader.searchLibraryArticles")}
        placeholder={t("reader.searchLibraryArticles")}
        value={query}
        leftSection={<Search size={14} aria-hidden="true" />}
        onChange={(event) => onQueryChange(event.currentTarget.value)}
      />
      <div className="reader-article-switch-list">
        {isLoading ? (
          <Group gap="xs" className="reader-side-loading">
            <Loader size="xs" />
            <Text c="dimmed" size="xs">
              {t("reader.loadingArticles")}
            </Text>
          </Group>
        ) : null}
        {items.map((item) => {
          const isActive = item.article_revision.id === currentArticleId;
          return (
            <button
              key={item.article_revision.id}
              type="button"
              className="reader-article-switch-item"
              aria-current={isActive ? "page" : undefined}
              data-active={isActive || undefined}
              onClick={() => onSelect(item)}
            >
              <span className="reader-article-switch-title">{readerArticleTitle(item)}</span>
              <span className="reader-article-switch-meta">
                {readerArticleSourceLabel(item)} · {readerArticleProgressLabel(item)}
              </span>
              <span className="reader-article-switch-progress" aria-hidden="true">
                <span style={{ width: `${readerArticleProgressPercent(item)}%` }} />
              </span>
            </button>
          );
        })}
        {!isLoading && items.length === 0 ? (
          <Text c="dimmed" size="xs" className="reader-side-empty">
            {t("reader.noLibraryArticles")}
          </Text>
        ) : null}
      </div>
    </Stack>
  );
}

interface ReaderSearchPanelProps {
  query: string;
  matches: ReaderSearchMatch[];
  cursor: number;
  onQueryChange: (value: string) => void;
  onMove: (delta: number) => void;
  onClear: () => void;
  onSelect: (blockUid: string) => void;
}

function ReaderSearchPanel({
  query,
  matches,
  cursor,
  onQueryChange,
  onMove,
  onClear,
  onSelect
}: ReaderSearchPanelProps) {
  const t = useT();
  const activeCursor = matches.length > 0 ? Math.min(cursor, matches.length - 1) : 0;
  return (
    <Stack gap="sm">
      <TextInput
        className="reader-search-input"
        label={t("reader.searchPaper")}
        placeholder={t("reader.searchPlaceholder")}
        value={query}
        leftSection={<Search size={14} aria-hidden="true" />}
        onChange={(event) => onQueryChange(event.currentTarget.value)}
      />
      <Group justify="space-between" gap="xs">
        <Text c="dimmed" size="xs" className="reader-search-status">
          {query
            ? matches.length > 0
              ? t("reader.searchCount", {
                  current: activeCursor + 1,
                  total: matches.length
                })
              : t("reader.searchNoMatches")
            : t("reader.searchHelp")}
        </Text>
        <Group gap={4}>
          <ActionIcon
            aria-label={t("reader.searchPrevious")}
            variant="subtle"
            size="sm"
            disabled={matches.length === 0}
            onClick={() => onMove(-1)}
          >
            <ChevronLeft size={14} aria-hidden="true" />
          </ActionIcon>
          <ActionIcon
            aria-label={t("reader.searchNext")}
            variant="subtle"
            size="sm"
            disabled={matches.length === 0}
            onClick={() => onMove(1)}
          >
            <ChevronRight size={14} aria-hidden="true" />
          </ActionIcon>
          <Button size="xs" variant="subtle" onClick={onClear}>
            {t("reader.searchClear")}
          </Button>
        </Group>
      </Group>
      {matches.length > 0 ? (
        <Stack gap={4}>
          {matches.slice(0, 12).map((match, index) => (
            <button
              key={`${match.blockUid}-${match.index}`}
              type="button"
              className="reader-article-switch-item"
              data-active={index === activeCursor || undefined}
              onClick={() => onSelect(match.blockUid)}
            >
              <span className="reader-article-switch-title">{match.label}</span>
              <span className="reader-article-switch-meta">{match.blockUid}</span>
            </button>
          ))}
        </Stack>
      ) : null}
    </Stack>
  );
}

function ReaderBlockFrame({
  block,
  notes,
  noteStickiesEnabled,
  isOptimizingNote,
  canOptimizeNote,
  onAddNote,
  onEditNote,
  onDeleteNote,
  onOptimizeNote,
  children
}: {
  block: DocumentBlock;
  notes: ReaderCard[];
  noteStickiesEnabled: boolean;
  isOptimizingNote: boolean;
  canOptimizeNote: boolean;
  onAddNote: () => void;
  onEditNote: (card: ReaderCard) => void;
  onDeleteNote: (card: ReaderCard) => void;
  onOptimizeNote: (card: ReaderCard) => void;
  children: ReactNode;
}) {
  const t = useT();
  const canAddNote = block.block_type === "paragraph";
  return (
    <div
      className={`reader-block-frame${noteStickiesEnabled ? " reader-block-frame-notes" : ""}`}
      data-note-count={notes.length}
    >
      <div className="reader-block-frame-main">{children}</div>
      {noteStickiesEnabled ? (
        <aside className="reader-note-sticky-slot" aria-label={t("reader.noteStickies")}>
          {notes.map((card) => (
            <article className="reader-note-sticky" key={card.id}>
              <Group justify="space-between" gap={6} wrap="nowrap">
                <Text fw={700} size="xs" lineClamp={2}>
                  {card.title}
                </Text>
                <Badge size="xs" variant="light">
                  {t("reader.notes")}
                </Badge>
              </Group>
              {card.body_markdown.trim() ? (
                <MarkdownContent content={card.body_markdown} referenceTargets={{}} />
              ) : (
                <Text c="dimmed" size="xs">
                  {card.anchor_text}
                </Text>
              )}
              <Group gap={4} wrap="nowrap" className="reader-note-sticky-actions">
                <Button size="compact-xs" variant="subtle" onClick={() => onEditNote(card)}>
                  {t("reader.editCard")}
                </Button>
                <Button
                  size="compact-xs"
                  variant="subtle"
                  loading={isOptimizingNote}
                  disabled={!canOptimizeNote}
                  onClick={() => onOptimizeNote(card)}
                >
                  {t("reader.noteOptimize")}
                </Button>
                <Button
                  size="compact-xs"
                  variant="subtle"
                  color="red"
                  onClick={() => onDeleteNote(card)}
                >
                  {t("reader.cardDelete")}
                </Button>
              </Group>
            </article>
          ))}
          {notes.length === 0 && canAddNote ? (
            <Button
              className="reader-note-sticky-add"
              size="compact-xs"
              variant="subtle"
              leftSection={<StickyNote size={13} aria-hidden="true" />}
              onClick={onAddNote}
            >
              {t("reader.addNoteSticky")}
            </Button>
          ) : null}
        </aside>
      ) : null}
    </div>
  );
}

function metadataString(metadata: ReaderCard["metadata"] | undefined, key: string): string | null {
  const value = metadata?.[key];
  return typeof value === "string" && value.trim() ? value : null;
}

function readerOverlayTitle(
  overlay: ReaderOverlayKind,
  t: (key: MessageKey, values?: Record<string, string | number>) => string
): string {
  switch (overlay) {
    case "ask":
      return t("reader.fullArticleAsk");
    case "articles":
      return t("reader.articleSwitcher");
    case "search":
      return t("reader.searchPaper");
    case "tasks":
      return t("nav.tasks");
    case "providers":
      return t("reader.providerPanel");
    case "translate":
      return t("reader.translate");
    case "glossary":
      return t("reader.terms");
    case "noteGenerator":
      return t("reader.noteGenerator");
    case "export":
      return t("reader.export");
    case "preferences":
      return t("reader.preferences");
  }
}

function readerOverlayIcon(overlay: ReaderOverlayKind): ReactNode {
  switch (overlay) {
    case "ask":
      return <MessageSquare size={15} aria-hidden="true" />;
    case "articles":
      return <BookMarked size={15} aria-hidden="true" />;
    case "search":
      return <Search size={15} aria-hidden="true" />;
    case "tasks":
      return <TerminalSquare size={15} aria-hidden="true" />;
    case "providers":
      return <Sparkles size={15} aria-hidden="true" />;
    case "translate":
      return <Languages size={15} aria-hidden="true" />;
    case "glossary":
      return <BookMarked size={15} aria-hidden="true" />;
    case "noteGenerator":
      return <FileText size={15} aria-hidden="true" />;
    case "export":
      return <Download size={15} aria-hidden="true" />;
    case "preferences":
      return <Type size={15} aria-hidden="true" />;
  }
}

function readerOverlayTone(overlay: ReaderOverlayKind): ReaderOverlayTone {
  switch (overlay) {
    case "tasks":
    case "glossary":
    case "noteGenerator":
      return "amber";
    case "ask":
    case "articles":
    case "search":
    case "export":
      return "blue";
    case "providers":
    case "translate":
      return "teal";
    case "preferences":
      return "neutral";
  }
}

function readerWorkspaceGroupForOverlay(
  overlay: ReaderOverlayKind | null
): ReaderWorkspaceGroupId | null {
  switch (overlay) {
    case "ask":
    case "search":
    case "preferences":
      return "read";
    case "tasks":
    case "providers":
    case "translate":
    case "glossary":
      return "assist";
    case "noteGenerator":
    case "export":
      return "output";
    case "articles":
    case null:
      return null;
  }
}

function readerOverlaySize(overlay: ReaderOverlayKind | null): string {
  if (overlay === "ask") return "xl";
  if (overlay === "glossary" || overlay === "noteGenerator") return "xl";
  if (overlay === "preferences" || overlay === "export") return "lg";
  return "md";
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

type ReaderPreferenceStyle = CSSProperties & Record<`--${string}`, string>;

function readerRem(pxAtDefaultScale: number, scale: number) {
  return `${Number(((pxAtDefaultScale * scale) / 16).toFixed(4))}rem`;
}

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
    "--reader-body-font-size": readerRem(16.32, fontScale),
    "--reader-source-font-size": readerRem(16.72, fontScale),
    "--reader-translation-font-size": readerRem(16.24, fontScale),
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
            <Title order={2} className="reader-tool-panel-title">
              {t("reader.paperChat")}
            </Title>
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
        aria-label={t("reader.chatQuestion")}
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
  const t = useT();
  return (
    <div className="external-evidence">
      <Text fw={600} size="xs">
        {t("reader.externalEvidence")}
      </Text>
      <Stack gap={4} mt={4}>
        {refs.map((ref, index) => {
          const label =
            ref.title || ref.url || ref.doi || ref.arxiv_id || t("reader.externalCitation");
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
      <Group className="reader-tool-panel-header" justify="space-between" align="flex-start">
        <div className="reader-tool-panel-copy">
          <Group gap="xs">
            <Download size={18} />
            <Title order={2} className="reader-tool-panel-title">
              {t("reader.export")}
            </Title>
          </Group>
          <Text c="dimmed" size="sm">
            {t("reader.exportHelp")}
          </Text>
        </div>
        <Group className="reader-tool-panel-actions reader-export-actions" align="end">
          <Select
            label={t("reader.exportKind")}
            value={exportKind}
            data={[
              {
                value: "bilingual_markdown",
                label: t("reader.exportKindBilingual", { language: targetLanguage })
              },
              {
                value: "translated_markdown",
                label: t("reader.exportKindTranslated", { language: targetLanguage })
              },
              { value: "source_markdown", label: t("reader.exportKindSource") },
              { value: "lecture_notes", label: t("reader.exportKindLectureNotes") },
              { value: "bundle_zip", label: t("reader.exportKindBundle") }
            ]}
            onChange={(value) => {
              if (value) onExportKindChange(value as ArticleExportKind);
            }}
          />
          <Button leftSection={<Download size={16} />} onClick={onExport} loading={isExporting}>
            {t("reader.exportDownload")}
          </Button>
        </Group>
      </Group>
      <Text className="obsidian-export-help" c="dimmed" size="sm" mt="sm">
        {t("reader.obsidianHelp")}
      </Text>
      {result ? (
        <div className="export-result">
          <Text size="sm">
            {t("reader.exportReady", {
              fileName: result.file_name,
              bytes: result.bytes_written
            })}
          </Text>
          {missingTranslationBlockUids.length > 0 ? (
            <Text c="yellow" size="sm">
              {t("reader.exportMissingTranslations", {
                blockUids: missingTranslationBlockUids.join(", ")
              })}
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
              {t("reader.downloadFile")}
            </Button>
          ) : null}
        </div>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          {t("reader.exportError")}
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
  const t = useT();
  const [templateName, setTemplateName] = useState("");
  const [templateDescription, setTemplateDescription] = useState("");
  const [patchDrafts, setPatchDrafts] = useState<Record<string, NotePatchDraft>>({});
  const templateOptions =
    templates.length > 0
      ? templates.map((template) => ({
          value: template.id,
          label: template.custom
            ? t("reader.customTemplateOption", { name: template.name })
            : template.name
        }))
      : [{ value: "deep_reading", label: t("reader.defaultNoteTemplate") }];

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
      <Group className="reader-tool-panel-header" justify="space-between" align="flex-start">
        <div className="reader-tool-panel-copy">
          <Group gap="xs">
            <FileText size={18} />
            <Title order={2} className="reader-tool-panel-title">
              {t("reader.lectureNotes")}
            </Title>
          </Group>
          <Text c="dimmed" size="sm">
            {t("reader.lectureNotesHelp")}
          </Text>
        </div>
        <Group className="reader-tool-panel-actions reader-note-actions" align="end">
          <Select
            label={t("reader.noteTemplate")}
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
            {t("reader.generatePatch")}
          </Button>
        </Group>
      </Group>
      <Stack className="reader-tool-form-section" gap="xs" mt="md">
        <Group className="reader-note-template-form" align="end">
          <TextInput
            label={t("reader.customTemplateName")}
            placeholder={t("reader.customTemplateNamePlaceholder")}
            value={templateName}
            onChange={(event) => setTemplateName(event.currentTarget.value)}
          />
          <Textarea
            label={t("reader.customTemplatePrompt")}
            placeholder={t("reader.customTemplatePromptPlaceholder")}
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
            {t("reader.saveTemplate")}
          </Button>
        </Group>
      </Stack>
      {isLoading ? (
        <Group mt="sm">
          <Loader size="sm" />
          <Text c="dimmed" size="sm">
            {t("reader.loadingNotePatches")}
          </Text>
        </Group>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          {t("reader.notePatchError")}
        </Text>
      ) : null}
      <Stack gap="sm" mt="md">
        {patches.length === 0 ? (
          <Text c="dimmed" size="sm">
            {t("reader.notePatchEmpty")}
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
              <Group className="note-patch-header" justify="space-between" align="flex-start">
                <div className="note-patch-copy">
                  <Group className="note-patch-title-row" gap="xs">
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
                  <Group className="note-patch-actions" gap="xs">
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
                      {t("reader.saveDraft")}
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
                      {t("reader.acceptEdited")}
                    </Button>
                    <Button
                      size="xs"
                      variant="subtle"
                      color="red"
                      leftSection={<X size={14} />}
                      loading={isRejecting}
                      onClick={() => onReject(patch.id)}
                    >
                      {t("reader.rejectPatch")}
                    </Button>
                  </Group>
                ) : null}
              </Group>
              {patch.status === "proposed" ? (
                <Stack gap="xs" mt="sm">
                  <TextInput
                    label={t("reader.noteTitleForPatch", { patchId: patch.id })}
                    value={draft.title}
                    onChange={(event) =>
                      updatePatchDraft(patch.id, { title: event.currentTarget.value })
                    }
                  />
                  <Textarea
                    label={t("reader.patchMarkdownForPatch", { patchId: patch.id })}
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
  const t = useT();
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
      <Group className="reader-tool-panel-header" justify="space-between" align="flex-start">
        <div className="reader-tool-panel-copy">
          <Group gap="xs">
            <BookMarked size={18} />
            <Title order={2} className="reader-tool-panel-title">
              {t("reader.glossary")}
            </Title>
          </Group>
          <Text c="dimmed" size="sm">
            {t("reader.glossaryHelp", { language: targetLanguage, version: activeVersion })}
          </Text>
        </div>
        <Group className="reader-tool-panel-actions reader-glossary-actions">
          <Button
            variant="light"
            leftSection={<Sparkles size={16} />}
            onClick={onExtract}
            loading={isExtracting}
          >
            {t("reader.extractTerms")}
          </Button>
          <Button
            variant="light"
            color="yellow"
            leftSection={<RefreshCw size={16} />}
            disabled={!canRetranslate || affectedBlockUids.length === 0}
            onClick={onRetranslateAffected}
          >
            {t("reader.retranslateAffected")}
          </Button>
        </Group>
      </Group>
      {isLoading ? (
        <Group mt="sm">
          <Loader size="sm" />
          <Text c="dimmed" size="sm">
            {t("reader.loadingGlossary")}
          </Text>
        </Group>
      ) : null}
      {affectedBlockUids.length > 0 ? (
        <Alert color="yellow" mt="sm">
          {t("reader.glossaryOutdatedBlocks", { count: affectedBlockUids.length })}
        </Alert>
      ) : null}
      <Group className="reader-glossary-entry-form" align="end" mt="md">
        <TextInput
          label={t("reader.sourceTerm")}
          value={sourceTerm}
          onChange={(event) => setSourceTerm(event.target.value)}
        />
        <TextInput
          label={t("reader.targetTerm")}
          value={targetTerm}
          onChange={(event) => setTargetTerm(event.target.value)}
        />
        <Button
          leftSection={<Check size={16} />}
          onClick={submitNewTerm}
          loading={isSaving}
          disabled={!sourceTerm.trim() || !targetTerm.trim()}
        >
          {t("reader.addTerm")}
        </Button>
      </Group>
      <Divider my="md" />
      <Stack gap="sm">
        {activeTerms.length === 0 && candidates.length === 0 ? (
          <Text c="dimmed" size="sm">
            {t("reader.glossaryEmpty")}
          </Text>
        ) : null}
        {activeTerms.map((term) => (
          <div className="glossary-row" key={term.id}>
            <Badge className="glossary-status" variant="light" color="green">
              {t("reader.glossaryStatusActive")}
            </Badge>
            <Text className="glossary-source" fw={600}>
              {term.source_term}
            </Text>
            <Text className="glossary-target" c="dimmed">
              {"=>"} {term.target_term}
            </Text>
          </div>
        ))}
        {candidates.map((term) => (
          <div className="glossary-candidate" key={term.id}>
            <div>
              <Group gap="xs">
                <Badge variant="light" color="gray">
                  {t("reader.glossaryStatusCandidate")}
                </Badge>
                <Text fw={600}>{term.source_term}</Text>
              </Group>
              <Text c="dimmed" size="xs">
                {candidateSummary(term, t)}
              </Text>
            </div>
            <TextInput
              aria-label={t("reader.targetTermForSource", { sourceTerm: term.source_term })}
              placeholder={t("reader.confirmedTargetTerm")}
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
              {t("reader.confirmTerm")}
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

function candidateSummary(
  term: GlossaryTerm,
  t: (key: MessageKey, values?: Record<string, string | number>) => string
): string {
  const count = term.metadata?.occurrence_count;
  const blockUids = term.metadata?.block_uids;
  const occurrenceText =
    typeof count === "number"
      ? t("reader.termOccurrenceCount", { count })
      : t("reader.termRuleCandidate");
  const blockText = Array.isArray(blockUids)
    ? ` · ${t("reader.termBlockCount", { count: blockUids.length })}`
    : "";
  return `${occurrenceText}${blockText}`;
}

function readerProgressMilestoneForProgress(
  progress: number,
  t: (key: MessageKey, values?: Record<string, string | number>) => string
) {
  if (progress >= 100) {
    return { key: "complete", label: t("reader.progressMilestoneComplete") };
  }
  if (progress >= 75) {
    return { key: "final", label: t("reader.progressMilestoneFinal") };
  }
  if (progress >= 50) {
    return { key: "half", label: t("reader.progressMilestoneHalf") };
  }
  if (progress >= 25) {
    return { key: "quarter", label: t("reader.progressMilestoneQuarter") };
  }
  return null;
}

function translationVariantOptions(
  variants: TranslationVariant[],
  t: (key: MessageKey, values?: Record<string, string | number>) => string
) {
  return variants.map((variant, index) => {
    const source =
      variant.metadata?.cache_source === "translation_memory"
        ? t("reader.translationSourceMemory")
        : (variant.model ?? t("reader.translationSourceLocal"));
    const status =
      variant.validation_status === "ok"
        ? t("reader.translationStatusOk")
        : variant.validation_status;
    const prefix = variant.is_default
      ? t("reader.translationVariantDefault")
      : t("reader.translationVariantNumber", { number: index + 1 });
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

function isRecoveredLatexmlDocument(document: ArticleDocument | undefined) {
  const metadata = document?.manifest.metadata;
  return (
    metadata?.latexmlpost_mode === "xml_fallback_after_split_timeout" ||
    metadata?.parse_fidelity === "structure_only"
  );
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

function addTermAnnotation(annotations: Map<string, TermAnnotation>, annotation: TermAnnotation) {
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

function readerRenderSourcesForBlocks(blocks: DocumentBlock[], documentTitle: string) {
  if (blocks.length === 0) return [];
  const sections = blocks.flatMap((block, index) =>
    block.block_type === "section" ? [{ block, index, level: readerStructuralLevel(block) }] : []
  );
  if (sections.length === 0) return [wholeDocumentRenderSource(blocks, documentTitle)];

  const titleKey = normalizedRenderSourceTitle(documentTitle);
  const candidateSections = sections.filter(
    ({ block, index }) =>
      !(index <= 1 && titleKey && normalizedRenderSourceTitle(chapterTitle(block)) === titleKey)
  );
  const boundaryLevel = renderSourceBoundaryLevel(candidateSections);
  if (boundaryLevel === null) return [wholeDocumentRenderSource(blocks, documentTitle)];
  const boundaries = candidateSections.filter((entry) => entry.level === boundaryLevel);
  if (boundaries.length === 0) return [wholeDocumentRenderSource(blocks, documentTitle)];

  const sources: ReaderRenderSource[] = [];
  const firstBoundaryIndex = boundaries[0]?.index ?? 0;
  if (firstBoundaryIndex > 0) {
    sources.push({
      uid: blocks[0].block_uid,
      title: documentTitle || "Front matter",
      startIndex: 0,
      endIndex: firstBoundaryIndex,
      blockCount: firstBoundaryIndex
    });
  }

  boundaries.forEach((entry, index) => {
    const endIndex = boundaries[index + 1]?.index ?? blocks.length;
    sources.push({
      uid: entry.block.block_uid,
      title: chapterTitle(entry.block),
      startIndex: entry.index,
      endIndex,
      blockCount: endIndex - entry.index
    });
  });
  return sources.length > 0 ? sources : [wholeDocumentRenderSource(blocks, documentTitle)];
}

function wholeDocumentRenderSource(blocks: DocumentBlock[], title: string): ReaderRenderSource {
  return {
    uid: blocks[0]?.block_uid ?? "document",
    title: title || "Document",
    startIndex: 0,
    endIndex: blocks.length,
    blockCount: blocks.length
  };
}

function renderSourceBoundaryLevel(
  sections: { block: DocumentBlock; index: number; level: number }[]
) {
  if (sections.length === 0) return null;
  const counts = new Map<number, number>();
  for (const section of sections) {
    counts.set(section.level, (counts.get(section.level) ?? 0) + 1);
  }
  const levels = [...counts.keys()].sort((left, right) => left - right);
  return levels.find((level) => (counts.get(level) ?? 0) >= 2) ?? levels[0] ?? null;
}

function renderSourceMapForBlocks(blocks: DocumentBlock[], sources: ReaderRenderSource[]) {
  const map = new Map<string, ReaderRenderSource>();
  for (const source of sources) {
    for (
      let index = source.startIndex;
      index < Math.min(source.endIndex, blocks.length);
      index += 1
    ) {
      map.set(blocks[index].block_uid, source);
    }
  }
  return map;
}

function normalizedRenderSourceTitle(value: string) {
  return value
    .replace(/^#+\s*/, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLocaleLowerCase();
}

function readerStructuralLevel(block: DocumentBlock): number {
  const level = block.metadata?.level;
  return typeof level === "number" && Number.isFinite(level) ? level : 2;
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
  return apiUrl(
    `/libraries/${encodedLibrary}/articles/${encodedArticle}/assets/${encodedAsset}`,
    true
  );
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
        url: apiUrl(
          `/libraries/${encodedLibrary}/articles/${encodedArticle}/assets/${encodedAsset}/files/${index}`,
          true
        ),
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
  return apiUrl(
    `/libraries/${encodedLibrary}/articles/${encodedArticle}/exports/${encodedFile}`,
    true
  );
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
