import {
  ActionIcon,
  Alert,
  Badge,
  Button,
  Collapse,
  FileInput,
  Group,
  Modal,
  MultiSelect,
  Select,
  SegmentedControl,
  Stack,
  Switch,
  Text,
  TextInput,
  Tooltip,
  Title
} from "@mantine/core";
import {
  Archive,
  BookOpenText,
  ChevronDown,
  Check,
  Database,
  ExternalLink,
  FileText,
  Folder,
  Inbox,
  Info,
  Languages,
  Newspaper,
  Pencil,
  PlusCircle,
  RefreshCw,
  Search,
  Star,
  Trash2,
  Upload,
  X
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";

import {
  useArchiveArticle,
  useArticles,
  useArxivDailyRecommendations,
  useArxivRecommendationCategories,
  useArxivRecommendationPreferences,
  useDeleteArticle,
  useImportArxiv,
  useImportLocalFile,
  useJobSummary,
  useLibrary,
  useProviders,
  useTranslateLibraryMissing,
  useUpdateArxivRecommendationPreferences,
  useUpdateLibrary
} from "../api/hooks";
import type {
  ArxivRecommendationEngine,
  ArxivRecommendationItem,
  ArxivRecommendationRequest,
  ArticleListItem,
  ArticleReadingProgress,
  ImportLocalKind
} from "../api/types";
import { useT } from "../i18n";
import { TRANSLATION_TARGET_LOCALES } from "../product";
import { useUiStore } from "../state/ui";

type ArticleFilter = "all" | "reading" | "needs_translation" | "translated";
type ArticleSort = "updated" | "title" | "progress";
type LibrarySurface = "articles" | "arxiv_daily";

export function LibraryDetailPage() {
  const t = useT();
  const { libraryId } = useParams();
  const library = useLibrary(libraryId);
  const targetLanguage = useUiStore((state) => state.translationTargetLanguage);
  const setTargetLanguage = useUiStore((state) => state.setTranslationTargetLanguage);
  const articles = useArticles(libraryId, targetLanguage);
  const archiveArticle = useArchiveArticle(libraryId);
  const deleteArticle = useDeleteArticle(libraryId);
  const importArxiv = useImportArxiv(libraryId);
  const importLocalFile = useImportLocalFile(libraryId);
  const updateLibrary = useUpdateLibrary();
  const providers = useProviders();
  const translateMissing = useTranslateLibraryMissing(libraryId);
  const jobs = useJobSummary();
  const arxivCategories = useArxivRecommendationCategories(libraryId);
  const arxivPreferences = useArxivRecommendationPreferences(libraryId);
  const updateArxivPreferences = useUpdateArxivRecommendationPreferences(libraryId);
  const openTaskDrawer = useUiStore((state) => state.openTaskDrawer);
  const taskNotificationsEnabled = useUiStore(
    (state) => state.readerFeaturePreferences.taskNotificationsEnabled
  );
  const showArxivInlinePanel = useMediaQueryMatch("(max-width: 1180px)");
  const showArticleInlinePanel = useMediaQueryMatch("(max-width: 1180px)");
  const activeJobCount = jobs.data?.active ?? 0;
  const [importSource, setImportSource] = useState<"arxiv" | "file">("arxiv");
  const [showImportOptions, setShowImportOptions] = useState(false);
  const [arxivId, setArxivId] = useState("");
  const [version, setVersion] = useState("");
  const [downloadPdf, setDownloadPdf] = useState(true);
  const [parseAfterImport, setParseAfterImport] = useState(true);
  const [localFile, setLocalFile] = useState<File | null>(null);
  const [localKind, setLocalKind] = useState<ImportLocalKind>("tex_archive");
  const [localParseAfterImport, setLocalParseAfterImport] = useState(true);
  const [selectedProviderId, setSelectedProviderId] = useState("");
  const [isEditingLibraryName, setIsEditingLibraryName] = useState(false);
  const [libraryNameDraft, setLibraryNameDraft] = useState("");
  const [articleSearchQuery, setArticleSearchQuery] = useState("");
  const [articleFilter, setArticleFilter] = useState<ArticleFilter>("all");
  const [articleSort, setArticleSort] = useState<ArticleSort>("updated");
  const [surface, setSurface] = useState<LibrarySurface>("articles");
  const [recommendationCategories, setRecommendationCategories] = useState<string[]>([]);
  const [recommendationKeywords, setRecommendationKeywords] = useState("");
  const [recommendationEngine, setRecommendationEngine] =
    useState<ArxivRecommendationEngine>("heuristic");
  const [recommendationRefreshNonce, setRecommendationRefreshNonce] = useState(0);
  const [expandedRecommendationIds, setExpandedRecommendationIds] = useState<Set<string>>(
    () => new Set()
  );
  const [selectedRevisionId, setSelectedRevisionId] = useState<string | null>(null);
  const [libraryActionMessage, setLibraryActionMessage] = useState<{
    kind: "success" | "error";
    text: string;
  } | null>(null);
  const [pendingDeleteArticle, setPendingDeleteArticle] = useState<ArticleListItem | null>(null);
  const [articleActionMessage, setArticleActionMessage] = useState<{
    kind: "success" | "error";
    text: string;
  } | null>(null);
  const lastImportJobId = useRef<string | null>(null);
  const lastLocalImportRevisionId = useRef<string | null>(null);
  const providerOptions = useMemo(
    () =>
      (providers.data ?? []).map((provider) => ({
        value: provider.id,
        label: provider.default_model
          ? `${provider.name} · ${provider.default_model}`
          : provider.name
      })),
    [providers.data]
  );
  const arxivCategoryOptions = useMemo(
    () =>
      (arxivCategories.data?.categories ?? []).map((category) => ({
        value: category.id,
        label: `${category.id} · ${category.name} · ${category.group}`
      })),
    [arxivCategories.data?.categories]
  );
  const selectedProvider = useMemo(
    () => (providers.data ?? []).find((provider) => provider.id === selectedProviderId),
    [providers.data, selectedProviderId]
  );
  const articleItems = useMemo(() => articles.data ?? [], [articles.data]);
  const translationSummary = useMemo(
    () => summarizeMissingTranslations(articleItems),
    [articleItems]
  );
  const visibleArticleItems = useMemo(
    () => filterAndSortArticles(articleItems, articleSearchQuery, articleFilter, articleSort),
    [articleFilter, articleItems, articleSearchQuery, articleSort]
  );
  const selectedArticle = useMemo(
    () =>
      visibleArticleItems.find((item) => item.article_revision.id === selectedRevisionId) ??
      visibleArticleItems[0] ??
      null,
    [selectedRevisionId, visibleArticleItems]
  );
  const readingArticleCount = useMemo(
    () => articleItems.filter((item) => (item.reading_progress?.total_seconds ?? 0) > 0).length,
    [articleItems]
  );
  const translatedArticleCount = useMemo(
    () =>
      articleItems.filter((item) => articleTranslationStatus(item).status === "translated").length,
    [articleItems]
  );
  const archivedArticleCount = useMemo(
    () => articleItems.filter((item) => item.article_revision.status === "archived").length,
    [articleItems]
  );
  const recommendationKeywordList = useMemo(
    () =>
      recommendationKeywords
        .split(",")
        .map((keyword) => keyword.trim())
        .filter(Boolean),
    [recommendationKeywords]
  );
  const recommendationRequest = useMemo<ArxivRecommendationRequest>(
    () => ({
      target_language: targetLanguage,
      categories: recommendationCategories,
      keywords: recommendationKeywordList,
      max_results: 80,
      engine: recommendationEngine,
      provider_profile_id:
        recommendationEngine === "provider" && selectedProviderId ? selectedProviderId : null,
      model:
        recommendationEngine === "provider" && selectedProvider?.default_model
          ? selectedProvider.default_model
          : null,
      refresh: recommendationRefreshNonce > 0
    }),
    [
      recommendationCategories,
      recommendationEngine,
      recommendationKeywordList,
      recommendationRefreshNonce,
      selectedProvider?.default_model,
      selectedProviderId,
      targetLanguage
    ]
  );
  const arxivDaily = useArxivDailyRecommendations(
    libraryId,
    recommendationRequest,
    surface === "arxiv_daily"
  );

  useEffect(() => {
    if (selectedProviderId || providerOptions.length === 0) return;
    setSelectedProviderId(providerOptions[0].value);
  }, [providerOptions, selectedProviderId]);

  useEffect(() => {
    if (!isEditingLibraryName) setLibraryNameDraft(library.data?.name ?? "");
  }, [isEditingLibraryName, library.data?.name]);

  useEffect(() => {
    if (!arxivPreferences.data) return;
    setRecommendationCategories((current) =>
      current.length > 0 ? current : (arxivPreferences.data.categories ?? [])
    );
    setRecommendationKeywords((current) =>
      current.trim() ? current : (arxivPreferences.data.keywords ?? []).join(", ")
    );
  }, [arxivPreferences.data]);

  useEffect(() => {
    if (visibleArticleItems.length === 0) {
      setSelectedRevisionId(null);
      return;
    }
    if (
      selectedRevisionId &&
      visibleArticleItems.some((item) => item.article_revision.id === selectedRevisionId)
    ) {
      return;
    }
    setSelectedRevisionId(visibleArticleItems[0].article_revision.id);
  }, [selectedRevisionId, visibleArticleItems]);

  const startEditingLibraryName = () => {
    if (!library.data) return;
    setLibraryActionMessage(null);
    setLibraryNameDraft(library.data.name);
    setIsEditingLibraryName(true);
  };

  const saveLibraryName = () => {
    if (!libraryId || !library.data) return;
    const nextName = libraryNameDraft.trim();
    if (!nextName || nextName === library.data.name) return;
    setLibraryActionMessage(null);
    updateLibrary.mutate(
      { libraryId, payload: { name: nextName } },
      {
        onSuccess: (updatedLibrary) => {
          setLibraryNameDraft(updatedLibrary.name);
          setIsEditingLibraryName(false);
          setLibraryActionMessage({ kind: "success", text: t("library.nameUpdated") });
        },
        onError: (error) =>
          setLibraryActionMessage({
            kind: "error",
            text: t("library.libraryActionErrorWithMessage", { message: errorMessage(error) })
          })
      }
    );
  };

  const submitImport = () => {
    if (!arxivId.trim()) return;
    importArxiv.mutate({
      arxiv_id: arxivId.trim(),
      version: version.trim() || null,
      download_pdf: downloadPdf,
      parse_after_import: parseAfterImport
    });
  };

  const submitLocalImport = () => {
    if (!localFile) return;
    importLocalFile.mutate({
      file: localFile,
      kind: localKind,
      parseAfterImport: localKind === "tex_archive" && localParseAfterImport
    });
  };

  const articleRoute = (item: ArticleListItem) =>
    `/articles/${item.article_revision.id}?libraryId=${encodeURIComponent(libraryId ?? "")}`;

  const archiveRevision = (revisionId: string) => {
    setArticleActionMessage(null);
    archiveArticle.mutate(revisionId, {
      onSuccess: () =>
        setArticleActionMessage({ kind: "success", text: t("library.articleArchived") }),
      onError: (error) =>
        setArticleActionMessage({
          kind: "error",
          text: t("library.articleActionErrorWithMessage", {
            message: errorMessage(error)
          })
        })
    });
  };

  const confirmDeleteRevision = () => {
    if (!pendingDeleteArticle) return;
    setArticleActionMessage(null);
    deleteArticle.mutate(pendingDeleteArticle.article_revision.id, {
      onSuccess: () => {
        setPendingDeleteArticle(null);
        setArticleActionMessage({ kind: "success", text: t("library.articleDeleted") });
      },
      onError: (error) =>
        setArticleActionMessage({
          kind: "error",
          text: t("library.articleActionErrorWithMessage", {
            message: errorMessage(error)
          })
        })
    });
  };

  const queueMissingTranslations = () => {
    if (!selectedProviderId) {
      setArticleActionMessage({
        kind: "error",
        text: t("library.translationBatchNoProvider")
      });
      return;
    }
    const language = targetLanguage.trim() || "zh-CN";
    setArticleActionMessage(null);
    translateMissing.mutate(
      {
        target_language: language,
        provider_profile_id: selectedProviderId,
        model: selectedProvider?.default_model ?? null,
        force: false
      },
      {
        onSuccess: (result) => {
          setArticleActionMessage({
            kind: "success",
            text: t("library.translationBatchQueued", {
              articles: result.articles_queued,
              jobs: result.jobs_created,
              existing: result.existing_jobs,
              cached: result.cached_blocks
            })
          });
          if (result.jobs_created > 0 || result.existing_jobs > 0) {
            if (taskNotificationsEnabled) openTaskDrawer();
          }
        },
        onError: (error) =>
          setArticleActionMessage({
            kind: "error",
            text: t("library.translationBatchErrorWithMessage", {
              message: errorMessage(error)
            })
          })
      }
    );
  };

  const saveRecommendationPreferences = () => {
    updateArxivPreferences.mutate({
      categories: recommendationCategories,
      keywords: recommendationKeywordList
    });
  };

  const refreshRecommendations = () => {
    setRecommendationRefreshNonce((value) => value + 1);
    void arxivDaily.refetch();
  };

  const toggleRecommendation = (arxivId: string) => {
    setExpandedRecommendationIds((current) => {
      const next = new Set(current);
      if (next.has(arxivId)) next.delete(arxivId);
      else next.add(arxivId);
      return next;
    });
  };

  const importRecommendation = (item: ArxivRecommendationItem) => {
    importArxiv.mutate({
      arxiv_id: item.arxiv_id,
      version: null,
      download_pdf: true,
      parse_after_import: true
    });
  };

  const arxivDailyPanelProps: ArxivDailyPanelProps = {
    categoryOptions: arxivCategoryOptions,
    categories: recommendationCategories,
    engine: recommendationEngine,
    keywords: recommendationKeywords,
    loading: arxivDaily.isLoading,
    message: arxivDaily.data?.message ?? null,
    providerOptions,
    recommendationCount: arxivDaily.data?.items?.length ?? 0,
    selectedProviderId,
    targetLanguage,
    updatePending: updateArxivPreferences.isPending,
    onCategoriesChange: setRecommendationCategories,
    onEngineChange: setRecommendationEngine,
    onKeywordsChange: setRecommendationKeywords,
    onProviderChange: setSelectedProviderId,
    onRefresh: refreshRecommendations,
    onSavePreferences: saveRecommendationPreferences,
    onTargetLanguageChange: (value) => setTargetLanguage(value)
  };

  const articleManagementPanel = (
    <>
      <div
        className="library-import-strip library-rail-action-card"
        aria-label={t("library.addArticle")}
      >
        <Group justify="space-between" align="flex-start" gap="sm">
          <div>
            <Title order={3}>{t("library.addArticle")}</Title>
            <Text c="dimmed" size="sm">
              {t("library.addArticleHelp")}
            </Text>
          </div>
          <SegmentedControl
            value={importSource}
            onChange={(value) => setImportSource(value as "arxiv" | "file")}
            data={[
              { label: "arXiv", value: "arxiv" },
              { label: t("library.localFile"), value: "file" }
            ]}
          />
        </Group>

        {importSource === "arxiv" ? (
          <>
            <Group mt="md" align="end" className="add-article-form">
              <TextInput
                id="library-arxiv-input"
                className="grow-input"
                label={t("library.arxivId")}
                placeholder={t("library.arxivIdPlaceholder")}
                value={arxivId}
                onChange={(event) => setArxivId(event.target.value)}
              />
              <Button
                onClick={submitImport}
                loading={importArxiv.isPending}
                disabled={!libraryId || !arxivId.trim()}
              >
                {t("library.addArticle")}
              </Button>
              <Button variant="subtle" onClick={() => setShowImportOptions((open) => !open)}>
                {t("library.options")}
              </Button>
            </Group>
            <Collapse in={showImportOptions}>
              <Group mt="md" className="advanced-options">
                <TextInput
                  label={t("library.version")}
                  placeholder={t("library.versionPlaceholder")}
                  value={version}
                  onChange={(event) => setVersion(event.target.value)}
                />
                <Switch
                  label={t("library.downloadPdf")}
                  checked={downloadPdf}
                  onChange={(event) => setDownloadPdf(event.currentTarget.checked)}
                />
                <Switch
                  label={t("library.parseAfterImport")}
                  checked={parseAfterImport}
                  onChange={(event) => setParseAfterImport(event.currentTarget.checked)}
                />
              </Group>
            </Collapse>
          </>
        ) : (
          <>
            <Group mt="md" align="end" className="add-article-form">
              <FileInput
                className="grow-input"
                label={t("library.file")}
                placeholder={t("library.filePlaceholder")}
                value={localFile}
                onChange={setLocalFile}
              />
              <Select
                label={t("library.type")}
                value={localKind}
                onChange={(value) => {
                  if (value === "tex_archive" || value === "markdown" || value === "pdf") {
                    setLocalKind(value);
                  }
                }}
                data={[
                  { value: "tex_archive", label: t("library.texArchive") },
                  { value: "markdown", label: t("library.markdown") },
                  { value: "pdf", label: t("library.pdfSaveOnly") }
                ]}
              />
              <Button
                onClick={submitLocalImport}
                loading={importLocalFile.isPending}
                disabled={!libraryId || !localFile}
              >
                {t("library.importFile")}
              </Button>
            </Group>
            <Group mt="md" className="advanced-options">
              <Switch
                label={t("library.parseTexArchive")}
                checked={localParseAfterImport}
                disabled={localKind !== "tex_archive"}
                onChange={(event) => setLocalParseAfterImport(event.currentTarget.checked)}
              />
            </Group>
          </>
        )}

        {importArxiv.isSuccess ? (
          <Text c="dimmed" size="sm" mt="sm">
            {t("library.importQueued")}
          </Text>
        ) : null}
        {importArxiv.isError ? (
          <Text c="red" size="sm" mt="sm">
            {t("library.importQueueErrorWithMessage", {
              message: errorMessage(importArxiv.error)
            })}
          </Text>
        ) : null}
        {importLocalFile.isSuccess ? (
          <Text c="dimmed" size="sm" mt="sm">
            {t("library.localImported")}
          </Text>
        ) : null}
        {importLocalFile.isError ? (
          <Text c="red" size="sm" mt="sm">
            {t("library.localImportError")}
          </Text>
        ) : null}
      </div>

      <div className="library-batch-strip library-rail-action-card">
        <Stack gap={2}>
          <Text fw={650}>{t("library.batchActions")}</Text>
          <Text c="dimmed" size="sm">
            {t("library.missingTranslationSummary", {
              articles: translationSummary.articles,
              blocks: translationSummary.blocks,
              active: translationSummary.active
            })}
          </Text>
        </Stack>
        <Group gap="xs" wrap="nowrap" className="library-batch-controls">
          <Select
            aria-label={t("library.provider")}
            data={providerOptions}
            disabled={providers.isLoading || providerOptions.length === 0}
            placeholder={t("library.noProviderConfigured")}
            searchable
            value={selectedProviderId || null}
            onChange={(value) => setSelectedProviderId(value ?? "")}
          />
          <Select
            aria-label={t("library.targetLanguage")}
            allowDeselect={false}
            data={TRANSLATION_TARGET_LOCALES.map((item) => ({
              value: item.value,
              label: item.nativeLabel
            }))}
            searchable
            value={targetLanguage}
            onChange={(value) => setTargetLanguage(value ?? "zh-CN")}
          />
        </Group>
      </div>
    </>
  );

  useEffect(() => {
    const job = importArxiv.data;
    if (!job || lastImportJobId.current === job.id) return;
    lastImportJobId.current = job.id;
    setArxivId("");
    setVersion("");
    if (taskNotificationsEnabled) openTaskDrawer();
  }, [importArxiv.data, openTaskDrawer, taskNotificationsEnabled]);

  useEffect(() => {
    const result = importLocalFile.data;
    if (!result || lastLocalImportRevisionId.current === result.article_revision_id) return;
    lastLocalImportRevisionId.current = result.article_revision_id;
    setLocalFile(null);
    if (taskNotificationsEnabled) openTaskDrawer();
  }, [importLocalFile.data, openTaskDrawer, taskNotificationsEnabled]);

  return (
    <div className="library-workbench-page">
      <div className="library-workbench">
        <aside className="library-left-rail" aria-label={t("library.libraryRail")}>
          <div className="library-rail-header">
            <Group gap="xs" wrap="nowrap">
              <Folder size={17} aria-hidden="true" />
              <Text fw={720}>{t("nav.library")}</Text>
            </Group>
            <Tooltip label={t("library.editName")}>
              <ActionIcon
                aria-label={t("library.editName")}
                disabled={!library.data || updateLibrary.isPending}
                onClick={startEditingLibraryName}
                size="sm"
                variant="subtle"
              >
                <Pencil size={14} aria-hidden="true" />
              </ActionIcon>
            </Tooltip>
          </div>

          <div className="library-current-card">
            {isEditingLibraryName ? (
              <Group gap="xs" wrap="nowrap">
                <TextInput
                  aria-label={t("library.renameInputLabel")}
                  disabled={updateLibrary.isPending}
                  onChange={(event) => setLibraryNameDraft(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") saveLibraryName();
                    if (event.key === "Escape") setIsEditingLibraryName(false);
                  }}
                  size="xs"
                  value={libraryNameDraft}
                />
                <ActionIcon
                  aria-label={t("library.saveName")}
                  disabled={
                    updateLibrary.isPending ||
                    !libraryNameDraft.trim() ||
                    libraryNameDraft.trim() === library.data?.name
                  }
                  loading={updateLibrary.isPending}
                  onClick={saveLibraryName}
                  size="sm"
                  variant="light"
                >
                  <Check size={14} aria-hidden="true" />
                </ActionIcon>
                <ActionIcon
                  aria-label={t("library.cancel")}
                  disabled={updateLibrary.isPending}
                  onClick={() => setIsEditingLibraryName(false)}
                  size="sm"
                  variant="subtle"
                >
                  <X size={14} aria-hidden="true" />
                </ActionIcon>
              </Group>
            ) : (
              <>
                <Text fw={720} lineClamp={1}>
                  {library.data?.name ?? t("library.detailFallback")}
                </Text>
                <Text c="dimmed" size="xs" lineClamp={2}>
                  {library.data?.path ?? t("library.detailSubtitle")}
                </Text>
              </>
            )}
            {libraryActionMessage ? (
              <Text c={libraryActionMessage.kind === "success" ? "dimmed" : "red"} size="xs">
                {libraryActionMessage.text}
              </Text>
            ) : null}
          </div>

          {library.isError ? (
            <Alert color="red" icon={<Info size={16} />} className="library-rail-alert">
              {t("library.metadataError")}
            </Alert>
          ) : null}

          <nav className="library-rail-section" aria-label={t("library.collections")}>
            <Text className="library-rail-label">{t("library.collections")}</Text>
            <button
              type="button"
              className="library-rail-item"
              data-active={articleFilter === "all" || undefined}
              onClick={() => setArticleFilter("all")}
            >
              <FileText size={15} aria-hidden="true" />
              <span>{t("library.allPapers")}</span>
              <strong>{articleItems.length}</strong>
            </button>
            <button
              type="button"
              className="library-rail-item"
              data-active={articleFilter === "reading" || undefined}
              onClick={() => setArticleFilter("reading")}
            >
              <Inbox size={15} aria-hidden="true" />
              <span>{t("library.reading")}</span>
              <strong>{readingArticleCount}</strong>
            </button>
            <button
              type="button"
              className="library-rail-item"
              data-active={articleFilter === "needs_translation" || undefined}
              onClick={() => setArticleFilter("needs_translation")}
            >
              <Languages size={15} aria-hidden="true" />
              <span>{t("library.needsTranslation")}</span>
              <strong>{translationSummary.articles}</strong>
            </button>
            <button
              type="button"
              className="library-rail-item"
              data-active={articleFilter === "translated" || undefined}
              onClick={() => setArticleFilter("translated")}
            >
              <Star size={15} aria-hidden="true" />
              <span>{t("library.translatedPapers")}</span>
              <strong>{translatedArticleCount}</strong>
            </button>
          </nav>

          <div className="library-rail-section">
            <Text className="library-rail-label">{t("library.sources")}</Text>
            <button
              type="button"
              className="library-rail-item"
              data-active={surface === "articles" || undefined}
              onClick={() => setSurface("articles")}
            >
              <FileText size={15} aria-hidden="true" />
              <span>arXiv</span>
              <strong>
                {articleItems.filter((item) => item.family.source === "arxiv").length}
              </strong>
            </button>
            <button
              type="button"
              className="library-rail-item"
              data-active={surface === "arxiv_daily" || undefined}
              onClick={() => setSurface("arxiv_daily")}
            >
              <Newspaper size={15} aria-hidden="true" />
              <span>{t("library.arxivDaily")}</span>
              <strong>{arxivDaily.data?.items?.length ?? "—"}</strong>
            </button>
            <button
              type="button"
              className="library-rail-item"
              data-active={surface === "articles" || undefined}
              onClick={() => setSurface("articles")}
            >
              <Folder size={15} aria-hidden="true" />
              <span>{t("library.localFile")}</span>
              <strong>
                {articleItems.filter((item) => item.family.source !== "arxiv").length}
              </strong>
            </button>
          </div>

          <div className="library-storage-meter">
            <Group gap="xs" justify="space-between">
              <Group gap={6}>
                <Database size={14} aria-hidden="true" />
                <Text size="xs">{t("library.localStorage")}</Text>
              </Group>
              <Badge size="xs" variant="light">
                {library.data?.status ?? "active"}
              </Badge>
            </Group>
            <div className="library-storage-track" aria-hidden="true">
              <span style={{ width: `${Math.min(86, 14 + articleItems.length * 3)}%` }} />
            </div>
            <Text c="dimmed" size="xs">
              {articleItems.length} {t("library.articles")} · {archivedArticleCount}{" "}
              {t("library.archived")}
            </Text>
          </div>
        </aside>

        <main
          className={`library-article-surface${
            surface === "arxiv_daily" ? " library-article-surface-recommendations" : ""
          }`}
        >
          {surface === "arxiv_daily" ? (
            <ArxivDailySurface
              expandedIds={expandedRecommendationIds}
              importPending={importArxiv.isPending}
              loading={arxivDaily.isLoading}
              panelProps={arxivDailyPanelProps}
              recommendations={arxivDaily.data?.items ?? []}
              showPanel={showArxivInlinePanel}
              onImport={importRecommendation}
              onToggle={toggleRecommendation}
            />
          ) : (
            <>
              <div className="library-surface-header">
                <div>
                  <Text className="page-eyebrow">{t("library.localWorkspace")}</Text>
                  <Title order={1} className="library-workbench-title">
                    {t("library.articles")}
                  </Title>
                </div>
                <Group gap="xs" className="library-surface-actions">
                  <Button
                    leftSection={<Upload size={16} />}
                    variant="light"
                    onClick={() => {
                      setImportSource("arxiv");
                      globalThis.document?.getElementById("library-arxiv-input")?.focus();
                    }}
                  >
                    {t("library.import")}
                  </Button>
                  <Button
                    leftSection={<Languages size={16} />}
                    disabled={
                      !libraryId ||
                      !selectedProviderId ||
                      translationSummary.blocks === 0 ||
                      translateMissing.isPending
                    }
                    loading={translateMissing.isPending}
                    onClick={queueMissingTranslations}
                  >
                    {t("library.translateMissing")}
                  </Button>
                </Group>
              </div>

              <div className="library-toolbar">
                <TextInput
                  aria-label={t("library.searchPapers")}
                  className="library-search-input"
                  leftSection={<Search size={15} aria-hidden="true" />}
                  placeholder={t("library.searchPapers")}
                  value={articleSearchQuery}
                  onChange={(event) => setArticleSearchQuery(event.currentTarget.value)}
                />
                <Select
                  aria-label={t("library.filter")}
                  allowDeselect={false}
                  data={[
                    { value: "all", label: t("library.allPapers") },
                    { value: "reading", label: t("library.reading") },
                    { value: "needs_translation", label: t("library.needsTranslation") },
                    { value: "translated", label: t("library.translatedPapers") }
                  ]}
                  value={articleFilter}
                  onChange={(value) => setArticleFilter((value ?? "all") as ArticleFilter)}
                />
                <Select
                  aria-label={t("library.sort")}
                  allowDeselect={false}
                  data={[
                    { value: "updated", label: t("library.sortUpdated") },
                    { value: "title", label: t("library.sortTitle") },
                    { value: "progress", label: t("library.sortProgress") }
                  ]}
                  value={articleSort}
                  onChange={(value) => setArticleSort((value ?? "updated") as ArticleSort)}
                />
              </div>

              {showArticleInlinePanel ? articleManagementPanel : null}

              {articleActionMessage ? (
                <div
                  className={`library-inline-message library-inline-${articleActionMessage.kind}`}
                >
                  {articleActionMessage.text}
                </div>
              ) : null}
              {articles.isError ? (
                <Alert color="yellow" icon={<Info size={18} />}>
                  {t("library.articleLoadError")}
                </Alert>
              ) : null}

              <section className="library-paper-list" aria-label={t("library.articles")}>
                {articleItems.length === 0 ? (
                  <Text c="dimmed" className="empty-state">
                    {t("library.noArticles")}
                  </Text>
                ) : visibleArticleItems.length === 0 ? (
                  <Text c="dimmed" className="empty-state">
                    {t("library.noMatchingArticles")}
                  </Text>
                ) : (
                  visibleArticleItems.map((item) => {
                    const status = articleTranslationStatus(item);
                    const selected =
                      selectedArticle?.article_revision.id === item.article_revision.id;
                    return (
                      <div
                        key={item.article_revision.id}
                        className="library-paper-row"
                        role="button"
                        tabIndex={0}
                        data-selected={selected || undefined}
                        title={readingProgressTitle(item.reading_progress)}
                        onClick={() => setSelectedRevisionId(item.article_revision.id)}
                        onKeyDown={(event) => {
                          if (event.key !== "Enter" && event.key !== " ") return;
                          event.preventDefault();
                          setSelectedRevisionId(item.article_revision.id);
                        }}
                      >
                        <span className="library-paper-icon" aria-hidden="true">
                          <FileText size={16} />
                        </span>
                        <span className="library-paper-main">
                          <Link
                            className="library-paper-title library-paper-title-link"
                            to={articleRoute(item)}
                            onClick={(event) => event.stopPropagation()}
                          >
                            <ReadingProgressTitleBackground progress={item.reading_progress} />
                            <span>{item.family.title ?? item.family.external_id}</span>
                          </Link>
                          <span className="library-paper-meta">
                            {articleSourceLabel(item)} · {item.family.external_id}
                            {item.article_revision.version} · {item.block_count}{" "}
                            {t("library.blocks")}
                          </span>
                        </span>
                        <span className="library-paper-status">
                          <Badge color={translationStatusColor(item)} variant="light">
                            {translationStatusLabel(item, t)}
                          </Badge>
                          {status.translatable_blocks > 0 ? (
                            <small>
                              {status.translated_blocks}/{status.translatable_blocks}
                            </small>
                          ) : null}
                        </span>
                        <span className="library-paper-progress">
                          <span>{articleProgressLabel(item)}</span>
                          <span className="library-progress-track" aria-hidden="true">
                            <span style={{ width: `${articleReadProgressPercent(item)}%` }} />
                          </span>
                        </span>
                      </div>
                    );
                  })
                )}
              </section>
            </>
          )}
        </main>

        <aside className="library-right-rail" aria-label={t("library.paperPreview")}>
          {surface === "arxiv_daily" && !showArxivInlinePanel ? (
            <ArxivDailyRail
              activeJobCount={activeJobCount}
              engine={recommendationEngine}
              importPending={importArxiv.isPending}
              panelProps={arxivDailyPanelProps}
              providersConfigured={providerOptions.length}
              selectedProviderLabel={selectedProvider?.name ?? ""}
            />
          ) : surface === "arxiv_daily" ? null : (
            <div className="library-right-rail-stack">
              {!showArticleInlinePanel ? articleManagementPanel : null}
              <div className="library-preview-card">
                {selectedArticle ? (
                  <>
                    <Text className="library-rail-label">{t("library.paperSelected")}</Text>
                    <Title order={3} className="library-preview-title">
                      {selectedArticle.family.title ?? selectedArticle.family.external_id}
                    </Title>
                    <Text c="dimmed" size="sm">
                      {selectedArticleSubtitle(selectedArticle)}
                    </Text>
                    <div className="library-preview-stats">
                      <div>
                        <span>{t("library.status")}</span>
                        <strong>{selectedArticle.article_revision.status}</strong>
                      </div>
                      <div>
                        <span>{t("library.translation")}</span>
                        <strong>{translationStatusLabel(selectedArticle, t)}</strong>
                      </div>
                      <div>
                        <span>{t("library.assets")}</span>
                        <strong>{selectedArticle.asset_count}</strong>
                      </div>
                      <div>
                        <span>{t("library.updated")}</span>
                        <strong>
                          {new Date(
                            selectedArticle.article_revision.updated_at
                          ).toLocaleDateString()}
                        </strong>
                      </div>
                    </div>
                    <Group grow gap="xs" className="library-preview-actions">
                      <Button
                        component={Link}
                        to={articleRoute(selectedArticle)}
                        leftSection={<BookOpenText size={16} />}
                      >
                        {t("library.read")}
                      </Button>
                      <Button
                        variant="light"
                        leftSection={<Languages size={16} />}
                        disabled={!selectedProviderId || translateMissing.isPending}
                        onClick={queueMissingTranslations}
                      >
                        {t("library.translateMissing")}
                      </Button>
                    </Group>
                    <Group grow gap="xs">
                      <Button
                        variant="subtle"
                        leftSection={<Archive size={15} />}
                        disabled={
                          selectedArticle.article_revision.status === "archived" ||
                          archiveArticle.isPending
                        }
                        onClick={() => archiveRevision(selectedArticle.article_revision.id)}
                      >
                        {t("library.archive")}
                      </Button>
                      <Button
                        color="red"
                        variant="subtle"
                        leftSection={<Trash2 size={15} />}
                        disabled={deleteArticle.isPending}
                        onClick={() => setPendingDeleteArticle(selectedArticle)}
                      >
                        {t("library.delete")}
                      </Button>
                    </Group>
                  </>
                ) : (
                  <Text c="dimmed" size="sm">
                    {t("library.noPaperSelected")}
                  </Text>
                )}
              </div>
            </div>
          )}
        </aside>
      </div>

      <Modal
        centered
        onClose={() => {
          if (!deleteArticle.isPending) setPendingDeleteArticle(null);
        }}
        opened={Boolean(pendingDeleteArticle)}
        title={t("library.deleteConfirmTitle")}
      >
        <Stack gap="md">
          <Text fw={600}>
            {pendingDeleteArticle?.family.title ?? pendingDeleteArticle?.family.external_id}
          </Text>
          <Text size="sm">{t("library.deleteConfirmBody")}</Text>
          <Group justify="flex-end">
            <Button
              disabled={deleteArticle.isPending}
              onClick={() => setPendingDeleteArticle(null)}
              variant="subtle"
            >
              {t("library.cancel")}
            </Button>
            <Button color="red" loading={deleteArticle.isPending} onClick={confirmDeleteRevision}>
              {t("library.confirmDelete")}
            </Button>
          </Group>
        </Stack>
      </Modal>
    </div>
  );
}

type ArxivDailyPanelProps = {
  categoryOptions: { value: string; label: string }[];
  categories: string[];
  engine: ArxivRecommendationEngine;
  keywords: string;
  loading: boolean;
  message: string | null;
  providerOptions: { value: string; label: string }[];
  recommendationCount: number;
  selectedProviderId: string;
  targetLanguage: string;
  updatePending: boolean;
  onCategoriesChange: (categories: string[]) => void;
  onEngineChange: (engine: ArxivRecommendationEngine) => void;
  onKeywordsChange: (keywords: string) => void;
  onProviderChange: (providerId: string) => void;
  onRefresh: () => void;
  onSavePreferences: () => void;
  onTargetLanguageChange: (language: string) => void;
};

function ArxivDailySurface({
  expandedIds,
  importPending,
  loading,
  panelProps,
  recommendations,
  showPanel,
  onImport,
  onToggle
}: {
  expandedIds: Set<string>;
  importPending: boolean;
  loading: boolean;
  panelProps: ArxivDailyPanelProps;
  recommendations: ArxivRecommendationItem[];
  showPanel: boolean;
  onImport: (item: ArxivRecommendationItem) => void;
  onToggle: (arxivId: string) => void;
}) {
  const t = useT();
  return (
    <div className="arxiv-daily-surface">
      <div className="library-surface-header">
        <div>
          <Text className="page-eyebrow">{t("library.arxivDailyEyebrow")}</Text>
          <Title order={1} className="library-workbench-title">
            {t("library.arxivDailyTitle")}
          </Title>
        </div>
      </div>

      {showPanel ? (
        <div className="arxiv-daily-mobile-panel">
          <ArxivDailyPanel {...panelProps} />
        </div>
      ) : null}

      <section className="arxiv-recommendation-feed" aria-label={t("library.arxivDaily")}>
        {loading ? (
          <Text c="dimmed" className="empty-state">
            {t("library.loadingRecommendations")}
          </Text>
        ) : recommendations.length === 0 ? (
          <Text c="dimmed" className="empty-state">
            {t("library.noRecommendations")}
          </Text>
        ) : (
          recommendations.map((item) => (
            <ArxivRecommendationRow
              expanded={expandedIds.has(item.arxiv_id)}
              importPending={importPending}
              item={item}
              key={item.arxiv_id}
              onImport={onImport}
              onToggle={onToggle}
            />
          ))
        )}
      </section>
    </div>
  );
}

function ArxivDailyPanel({
  categoryOptions,
  categories,
  engine,
  keywords,
  loading,
  message,
  providerOptions,
  recommendationCount,
  selectedProviderId,
  targetLanguage,
  updatePending,
  onCategoriesChange,
  onEngineChange,
  onKeywordsChange,
  onProviderChange,
  onRefresh,
  onSavePreferences,
  onTargetLanguageChange
}: ArxivDailyPanelProps) {
  const t = useT();
  return (
    <div className="arxiv-daily-panel">
      <div className="arxiv-daily-panel-actions">
        <Button
          leftSection={<RefreshCw size={16} />}
          loading={loading}
          onClick={onRefresh}
          variant="light"
        >
          {t("library.refreshRecommendations")}
        </Button>
        <Button
          leftSection={<Check size={16} />}
          loading={updatePending}
          onClick={onSavePreferences}
          variant="subtle"
        >
          {t("library.saveRecommendationPrefs")}
        </Button>
      </div>

      <div className="arxiv-daily-controls">
        <MultiSelect
          aria-label={t("library.arxivCategories")}
          className="arxiv-category-picker"
          data={categoryOptions}
          disabled={categoryOptions.length === 0}
          label={t("library.arxivCategories")}
          maxDropdownHeight={360}
          onChange={onCategoriesChange}
          placeholder={t("library.arxivCategoriesPlaceholder")}
          searchable
          value={categories}
        />
        <TextInput
          aria-label={t("library.recommendationKeywords")}
          label={t("library.recommendationKeywords")}
          onChange={(event) => onKeywordsChange(event.currentTarget.value)}
          placeholder={t("library.recommendationKeywordsPlaceholder")}
          value={keywords}
        />
        <Select
          aria-label={t("library.targetLanguage")}
          allowDeselect={false}
          data={TRANSLATION_TARGET_LOCALES.map((item) => ({
            value: item.value,
            label: item.nativeLabel
          }))}
          label={t("library.targetLanguage")}
          onChange={(value) => onTargetLanguageChange(value ?? "zh-CN")}
          searchable
          value={targetLanguage}
        />
        <Select
          aria-label={t("library.recommendationEngine")}
          allowDeselect={false}
          data={[
            { value: "heuristic", label: t("library.recommendationEngineHeuristic") },
            { value: "provider", label: t("library.recommendationEngineProvider") },
            { value: "claude_cli", label: "Claude CLI" },
            { value: "codex_cli", label: "Codex CLI" }
          ]}
          label={t("library.recommendationEngine")}
          onChange={(value) => onEngineChange((value ?? "heuristic") as ArxivRecommendationEngine)}
          value={engine}
        />
        {engine === "provider" ? (
          <Select
            aria-label={t("library.provider")}
            data={providerOptions}
            disabled={providerOptions.length === 0}
            label={t("library.provider")}
            onChange={(value) => onProviderChange(value ?? "")}
            placeholder={t("library.noProviderConfigured")}
            searchable
            value={selectedProviderId || null}
          />
        ) : null}
      </div>

      <div className="arxiv-daily-status-stack">
        <div className="arxiv-daily-summary-strip">
          <Text size="sm">{t("library.recommendationCount", { count: recommendationCount })}</Text>
          <Text c="dimmed" size="sm">
            {t("library.arxivDailyInteractionHint")}
          </Text>
        </div>
        {message ? (
          <div className="library-inline-message library-inline-info">{message}</div>
        ) : null}
      </div>
    </div>
  );
}

function ArxivRecommendationRow({
  expanded,
  importPending,
  item,
  onImport,
  onToggle
}: {
  expanded: boolean;
  importPending: boolean;
  item: ArxivRecommendationItem;
  onImport: (item: ArxivRecommendationItem) => void;
  onToggle: (arxivId: string) => void;
}) {
  const t = useT();
  const translatedTitle = item.title_target_language || t("library.titleTranslationPending");
  const translatedSummary = item.summary_target_language || t("library.summaryTranslationPending");
  return (
    <article className="arxiv-recommendation-row" data-expanded={expanded || undefined}>
      <button
        type="button"
        className="arxiv-recommendation-title-button"
        onClick={() => onToggle(item.arxiv_id)}
      >
        <span className="arxiv-recommendation-title-stack">
          <span className="arxiv-recommendation-title">{item.title}</span>
          <span className="arxiv-recommendation-title-target">{translatedTitle}</span>
          <span className="arxiv-recommendation-meta">
            {item.arxiv_id} · {item.primary_category ?? item.categories?.[0] ?? "arXiv"} ·{" "}
            {formatRecommendationDate(item.published ?? item.updated)}
          </span>
        </span>
        <span className="arxiv-recommendation-status">
          <Badge color={item.is_in_library ? "green" : "teal"} variant="light">
            {item.is_in_library ? t("library.inLibrary") : t("library.newPaper")}
          </Badge>
          <ChevronDown size={16} aria-hidden="true" />
        </span>
      </button>
      {expanded ? (
        <div className="arxiv-recommendation-expanded">
          <Text className="arxiv-recommendation-abstract">{translatedSummary}</Text>
          <Text c="dimmed" size="sm">
            {item.recommendation_reason || recommendationReasonFallback(item, t)}
          </Text>
          <Group gap="xs" className="arxiv-recommendation-actions">
            <Button
              disabled={item.is_in_library}
              leftSection={<PlusCircle size={16} />}
              loading={importPending}
              onClick={() => onImport(item)}
            >
              {item.is_in_library ? t("library.inLibrary") : t("library.addToXiandu")}
            </Button>
            <Button
              component="a"
              href={item.abs_url}
              leftSection={<ExternalLink size={15} />}
              target="_blank"
              rel="noreferrer"
              variant="subtle"
            >
              {t("library.openArxiv")}
            </Button>
          </Group>
        </div>
      ) : null}
    </article>
  );
}

function ArxivDailyRail({
  activeJobCount,
  engine,
  importPending,
  panelProps,
  providersConfigured,
  selectedProviderLabel
}: {
  activeJobCount: number;
  engine: ArxivRecommendationEngine;
  importPending: boolean;
  panelProps: ArxivDailyPanelProps;
  providersConfigured: number;
  selectedProviderLabel: string;
}) {
  const t = useT();
  return (
    <div className="library-preview-card arxiv-daily-rail-card">
      <Text className="library-rail-label">{t("nav.tasks")}</Text>
      <Title order={3} className="library-preview-title">
        {t("library.recommendationRailTitle")}
      </Title>
      <ArxivDailyPanel {...panelProps} />
      <div className="library-preview-stats">
        <div>
          <span>{t("library.import")}</span>
          <strong>{importPending ? t("library.queued") : t("library.ready")}</strong>
        </div>
        <div>
          <span>{t("nav.tasks")}</span>
          <strong>{activeJobCount}</strong>
        </div>
        <div>
          <span>{t("library.recommendationEngine")}</span>
          <strong>{engine.replace("_", " ")}</strong>
        </div>
        <div>
          <span>{t("library.provider")}</span>
          <strong>{selectedProviderLabel || providersConfigured}</strong>
        </div>
      </div>
      <Text c="dimmed" size="sm">
        {t("library.recommendationRailHelp")}
      </Text>
    </div>
  );
}

function ReadingProgressTitleBackground({
  progress
}: {
  progress?: ArticleReadingProgress | null;
}) {
  const segments = progress?.segments ?? [];
  if (segments.length === 0 || Math.max(...segments) <= 0) return null;
  const opacityLimit = readingProgressOpacityLimit(segments);
  return (
    <span aria-hidden="true" className="article-title-progress-heatmap">
      {segments.map((seconds, index) => (
        <span
          className="article-title-progress-segment"
          key={`${index}-${seconds}`}
          style={{
            backgroundColor: `rgba(15, 118, 110, ${Math.min(seconds / opacityLimit, 1) * 0.62})`
          }}
        />
      ))}
    </span>
  );
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

function readingProgressOpacityLimit(segments: number[]) {
  const peak = Math.max(...segments, 0);
  const mean = segments.reduce((total, seconds) => total + seconds, 0) / segments.length;
  return Math.max(mean + (peak - mean) * 0.5, 60);
}

function readingProgressTitle(progress?: ArticleReadingProgress | null) {
  if (!progress || progress.total_seconds <= 0) return undefined;
  const location =
    progress.active_block_uid && typeof progress.active_segment_index === "number"
      ? `, resume at block ${progress.active_segment_index + 1}`
      : "";
  return `Reading time ${formatReadingDuration(progress.total_seconds)}${location}`;
}

function formatReadingDuration(totalSeconds: number) {
  if (totalSeconds < 60) return `${totalSeconds}s`;
  if (totalSeconds < 3600) return `${Math.round(totalSeconds / 60)}m`;
  return `${(totalSeconds / 3600).toFixed(1)}h`;
}

function translationStatusLabel(item: ArticleListItem, t: ReturnType<typeof useT>) {
  const status = articleTranslationStatus(item).status;
  if (status === "translated") return t("library.translationTranslated");
  if (status === "translating") return t("library.translationTranslating");
  if (status === "partial") return t("library.translationPartial");
  if (status === "failed") return t("library.translationFailed");
  if (status === "not_required") return t("library.translationNotRequired");
  return t("library.translationNotStarted");
}

function translationStatusColor(item: ArticleListItem) {
  const status = articleTranslationStatus(item).status;
  if (status === "translated") return "green";
  if (status === "translating") return "blue";
  if (status === "partial") return "yellow";
  if (status === "failed") return "red";
  if (status === "not_required") return "gray";
  return "gray";
}

function articleTranslationStatus(item: ArticleListItem) {
  return (
    item.translation_status ?? {
      target_language: "zh-CN",
      status: "not_started",
      translatable_blocks: 0,
      translated_blocks: 0,
      queued_jobs: 0,
      running_jobs: 0,
      paused_jobs: 0,
      failed_jobs: 0
    }
  );
}

function filterAndSortArticles(
  items: ArticleListItem[],
  query: string,
  filter: ArticleFilter,
  sort: ArticleSort
) {
  const normalizedQuery = query.trim().toLowerCase();
  const filtered = items.filter((item) => {
    if (normalizedQuery) {
      const haystack = [
        item.family.title,
        item.family.external_id,
        item.family.source,
        item.article_revision.version,
        item.article_revision.status
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      if (!haystack.includes(normalizedQuery)) return false;
    }
    if (filter === "reading") return (item.reading_progress?.total_seconds ?? 0) > 0;
    if (filter === "needs_translation") return articleNeedsTranslation(item);
    if (filter === "translated") return articleTranslationStatus(item).status === "translated";
    return true;
  });

  return [...filtered].sort((left, right) => {
    if (sort === "title") {
      return (left.family.title ?? left.family.external_id).localeCompare(
        right.family.title ?? right.family.external_id
      );
    }
    if (sort === "progress") {
      return articleReadProgressPercent(right) - articleReadProgressPercent(left);
    }
    return String(right.article_revision.updated_at).localeCompare(
      String(left.article_revision.updated_at)
    );
  });
}

function articleNeedsTranslation(item: ArticleListItem) {
  const status = articleTranslationStatus(item);
  return Math.max(status.translatable_blocks - status.translated_blocks, 0) > 0;
}

function articleReadProgressPercent(item: ArticleListItem) {
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

function articleProgressLabel(item: ArticleListItem) {
  const seconds = item.reading_progress?.total_seconds ?? 0;
  if (seconds <= 0) return "0m";
  return formatReadingDuration(seconds);
}

function articleSourceLabel(item: ArticleListItem) {
  if (item.family.source === "arxiv") return "arXiv";
  if (item.family.source === "local_file") return "Local";
  return item.family.source;
}

function formatRecommendationDate(value?: string | null) {
  if (!value) return "recent";
  return new Date(value).toLocaleDateString();
}

function recommendationReasonFallback(item: ArxivRecommendationItem, t: ReturnType<typeof useT>) {
  if (!item.score_reasons || item.score_reasons.length === 0) {
    return t("library.recommendationReasonFallback");
  }
  return item.score_reasons.join(" · ");
}

function selectedArticleSubtitle(item: ArticleListItem) {
  const manifestStatus = item.manifest?.parse_status ?? item.article_revision.status;
  return `${articleSourceLabel(item)} ${item.family.external_id}${item.article_revision.version} · ${manifestStatus} · ${item.block_count} blocks`;
}

function summarizeMissingTranslations(items: ArticleListItem[]) {
  return items.reduce(
    (summary, item) => {
      if (item.article_revision.status === "archived") return summary;
      const status = articleTranslationStatus(item);
      const missing = Math.max(status.translatable_blocks - status.translated_blocks, 0);
      if (missing > 0) {
        summary.articles += 1;
        summary.blocks += missing;
      }
      summary.active += status.queued_jobs + status.running_jobs + status.paused_jobs;
      return summary;
    },
    { articles: 0, blocks: 0, active: 0 }
  );
}

function errorMessage(error: unknown) {
  if (!(error instanceof Error)) return "Unknown error";
  try {
    const payload = JSON.parse(error.message) as { detail?: unknown };
    if (typeof payload.detail === "string") return payload.detail;
  } catch {
    return error.message;
  }
  return error.message;
}
