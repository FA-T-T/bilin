import {
  Alert,
  Badge,
  Button,
  Collapse,
  FileInput,
  Group,
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
import { useState } from "react";
import { Link, useParams } from "react-router-dom";

import { useArticles, useImportArxiv, useImportLocalFile, useLibrary } from "../api/hooks";
import type { ImportLocalKind } from "../api/types";
import { useT } from "../i18n";

export function LibraryDetailPage() {
  const t = useT();
  const { libraryId } = useParams();
  const library = useLibrary(libraryId);
  const articles = useArticles(libraryId);
  const importArxiv = useImportArxiv(libraryId);
  const importLocalFile = useImportLocalFile(libraryId);
  const [importSource, setImportSource] = useState<"arxiv" | "file">("arxiv");
  const [showImportOptions, setShowImportOptions] = useState(false);
  const [arxivId, setArxivId] = useState("");
  const [version, setVersion] = useState("");
  const [downloadPdf, setDownloadPdf] = useState(true);
  const [parseAfterImport, setParseAfterImport] = useState(true);
  const [localFile, setLocalFile] = useState<File | null>(null);
  const [localKind, setLocalKind] = useState<ImportLocalKind>("tex_archive");
  const [localParseAfterImport, setLocalParseAfterImport] = useState(true);

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
                placeholder="1706.03762 or 1706.03762v7"
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
            {t("library.importQueueError")}
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
        <Title order={3}>{t("library.articles")}</Title>
        {articles.isError ? (
          <Alert color="yellow" icon={<Info size={18} />} mt="md">
            {t("library.articleLoadError")}
          </Alert>
        ) : null}
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
                    <Text fw={600}>{item.family.title ?? item.family.external_id}</Text>
                    <Text c="dimmed" size="xs">
                      {item.family.external_id}
                      {item.article_revision.version}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge variant="light">{item.article_revision.status}</Badge>
                  </Table.Td>
                  <Table.Td>{item.block_count}</Table.Td>
                  <Table.Td>{item.asset_count}</Table.Td>
                  <Table.Td>{new Date(item.article_revision.updated_at).toLocaleString()}</Table.Td>
                  <Table.Td>
                    <Button
                      component={Link}
                      size="xs"
                      variant="light"
                      to={`/articles/${item.article_revision.id}?libraryId=${libraryId}`}
                    >
                      {t("library.open")}
                    </Button>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </div>
    </Stack>
  );
}
