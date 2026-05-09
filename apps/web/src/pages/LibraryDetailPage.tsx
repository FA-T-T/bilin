import {
  Alert,
  Badge,
  Button,
  Collapse,
  FileInput,
  Group,
  Modal,
  Select,
  SegmentedControl,
  Stack,
  Switch,
  Table,
  Text,
  TextInput,
  Title
} from "@mantine/core";
import { Info } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";

import {
  useArchiveArticle,
  useArticles,
  useDeleteArticle,
  useImportArxiv,
  useImportLocalFile,
  useLibrary,
  useProviders,
  useTranslateLibraryMissing
} from "../api/hooks";
import type { ArticleListItem, ImportLocalKind } from "../api/types";
import { useT } from "../i18n";
import { TRANSLATION_TARGET_LOCALES } from "../product";
import { useUiStore } from "../state/ui";

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
  const providers = useProviders();
  const translateMissing = useTranslateLibraryMissing(libraryId);
  const openTaskDrawer = useUiStore((state) => state.openTaskDrawer);
  const taskNotificationsEnabled = useUiStore(
    (state) => state.readerFeaturePreferences.taskNotificationsEnabled
  );
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
  const selectedProvider = useMemo(
    () => (providers.data ?? []).find((provider) => provider.id === selectedProviderId),
    [providers.data, selectedProviderId]
  );
  const translationSummary = useMemo(
    () => summarizeMissingTranslations(articles.data ?? []),
    [articles.data]
  );

  useEffect(() => {
    if (selectedProviderId || providerOptions.length === 0) return;
    setSelectedProviderId(providerOptions[0].value);
  }, [providerOptions, selectedProviderId]);

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
    <Stack gap="lg">
      <Group justify="space-between">
        <div>
          <Title order={1}>{library.data?.name ?? t("library.detailFallback")}</Title>
          <Text c="dimmed">{library.data?.path ?? t("library.detailSubtitle")}</Text>
        </div>
      </Group>

      {library.isError ? (
        <Alert color="red" icon={<Info size={18} />}>
          {t("library.metadataError")}
        </Alert>
      ) : null}

      <div className="panel add-article-panel">
        <Group justify="space-between" align="flex-start">
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

      <div className="panel">
        <Group justify="space-between" align="center">
          <Title order={3}>{t("library.articles")}</Title>
          {articleActionMessage ? (
            <Text c={articleActionMessage.kind === "success" ? "dimmed" : "red"} size="sm">
              {articleActionMessage.text}
            </Text>
          ) : null}
        </Group>
        {articles.isError ? (
          <Alert color="yellow" icon={<Info size={18} />} mt="md">
            {t("library.articleLoadError")}
          </Alert>
        ) : null}
        <Group className="library-batch-actions" justify="space-between" mt="md">
          <Stack gap={2}>
            <Text fw={600}>{t("library.batchActions")}</Text>
            <Text c="dimmed" size="sm">
              {t("library.missingTranslationSummary", {
                articles: translationSummary.articles,
                blocks: translationSummary.blocks,
                active: translationSummary.active
              })}
            </Text>
          </Stack>
          <Group gap="xs" wrap="nowrap">
            <Select
              aria-label={t("library.provider")}
              data={providerOptions}
              disabled={providers.isLoading || providerOptions.length === 0}
              placeholder={t("library.noProviderConfigured")}
              searchable
              value={selectedProviderId || null}
              w={260}
              onChange={(value) => setSelectedProviderId(value ?? "")}
            />
            <Select
              aria-label={t("library.targetLanguage")}
              allowDeselect={false}
              data={[
                ...TRANSLATION_TARGET_LOCALES.map((item) => ({
                  value: item.value,
                  label: item.nativeLabel
                }))
              ]}
              searchable
              value={targetLanguage}
              w={140}
              onChange={(value) => setTargetLanguage(value ?? "zh-CN")}
            />
            <Button
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
        </Group>
        {(articles.data ?? []).length === 0 ? (
          <Text c="dimmed" mt="md">
            {t("library.noArticles")}
          </Text>
        ) : (
          <Table mt="md" verticalSpacing="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>{t("library.paper")}</Table.Th>
                <Table.Th>{t("library.status")}</Table.Th>
                <Table.Th>{t("library.translation")}</Table.Th>
                <Table.Th>{t("library.blocks")}</Table.Th>
                <Table.Th>{t("library.assets")}</Table.Th>
                <Table.Th>{t("library.updated")}</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {(articles.data ?? []).map((item) => (
                <Table.Tr key={item.article_revision.id}>
                  <Table.Td>
                    <Text
                      className="article-title-link"
                      component={Link}
                      fw={600}
                      to={articleRoute(item)}
                    >
                      {item.family.title ?? item.family.external_id}
                    </Text>
                    <Text c="dimmed" size="xs">
                      {item.family.external_id}
                      {item.article_revision.version}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge
                      color={item.article_revision.status === "archived" ? "gray" : undefined}
                      variant="light"
                    >
                      {item.article_revision.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Stack gap={2}>
                      <Badge color={translationStatusColor(item)} variant="light">
                        {translationStatusLabel(item, t)}
                      </Badge>
                      {articleTranslationStatus(item).translatable_blocks > 0 ? (
                        <Text c="dimmed" size="xs">
                          {articleTranslationStatus(item).translated_blocks}/
                          {articleTranslationStatus(item).translatable_blocks}
                        </Text>
                      ) : null}
                    </Stack>
                  </Table.Td>
                  <Table.Td>{item.block_count}</Table.Td>
                  <Table.Td>{item.asset_count}</Table.Td>
                  <Table.Td>{new Date(item.article_revision.updated_at).toLocaleString()}</Table.Td>
                  <Table.Td>
                    <Group gap="xs" justify="flex-end" wrap="nowrap">
                      <Button
                        disabled={
                          item.article_revision.status === "archived" || archiveArticle.isPending
                        }
                        onClick={() => archiveRevision(item.article_revision.id)}
                        size="xs"
                        variant="subtle"
                      >
                        {t("library.archive")}
                      </Button>
                      <Button
                        color="red"
                        disabled={deleteArticle.isPending}
                        onClick={() => setPendingDeleteArticle(item)}
                        size="xs"
                        variant="subtle"
                      >
                        {t("library.delete")}
                      </Button>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
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
    </Stack>
  );
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
