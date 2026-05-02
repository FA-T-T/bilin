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

export function LibraryDetailPage() {
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
          <Title order={1}>{library.data?.name ?? "Library detail"}</Title>
          <Text c="dimmed">
            {library.data?.path ?? "Registered library metadata and article bundles."}
          </Text>
        </div>
      </Group>

      {library.isError ? (
        <Alert color="red" icon={<Info size={18} />}>
          Library metadata could not be loaded from the API.
        </Alert>
      ) : null}

      <div className="panel add-article-panel">
        <Group justify="space-between" align="flex-start">
          <div>
            <Title order={3}>Add article</Title>
            <Text c="dimmed" size="sm">
              Use an arXiv ID for the normal path, or keep a local file inside this library.
            </Text>
          </div>
          <SegmentedControl
            value={importSource}
            onChange={(value) => setImportSource(value as "arxiv" | "file")}
            data={[
              { label: "arXiv", value: "arxiv" },
              { label: "Local file", value: "file" }
            ]}
          />
        </Group>

        {importSource === "arxiv" ? (
          <>
            <Group mt="md" align="end" className="add-article-form">
              <TextInput
                className="grow-input"
                label="arXiv ID"
                placeholder="1706.03762 or 1706.03762v7"
                value={arxivId}
                onChange={(event) => setArxivId(event.target.value)}
              />
              <Button
                onClick={submitImport}
                loading={importArxiv.isPending}
                disabled={!libraryId || !arxivId.trim()}
              >
                Add article
              </Button>
              <Button variant="subtle" onClick={() => setShowImportOptions((open) => !open)}>
                Options
              </Button>
            </Group>
            <Collapse in={showImportOptions}>
              <Group mt="md" className="advanced-options">
                <TextInput
                  label="Version"
                  placeholder="optional, e.g. v2"
                  value={version}
                  onChange={(event) => setVersion(event.target.value)}
                />
                <Switch
                  label="Download PDF"
                  checked={downloadPdf}
                  onChange={(event) => setDownloadPdf(event.currentTarget.checked)}
                />
                <Switch
                  label="Parse after import"
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
                label="File"
                placeholder="TeX archive, Markdown, or PDF"
                value={localFile}
                onChange={setLocalFile}
              />
              <Select
                label="Type"
                value={localKind}
                onChange={(value) => {
                  if (value === "tex_archive" || value === "markdown" || value === "pdf") {
                    setLocalKind(value);
                  }
                }}
                data={[
                  { value: "tex_archive", label: "TeX archive" },
                  { value: "markdown", label: "Markdown" },
                  { value: "pdf", label: "PDF save-only" }
                ]}
              />
              <Button
                onClick={submitLocalImport}
                loading={importLocalFile.isPending}
                disabled={!libraryId || !localFile}
              >
                Import file
              </Button>
            </Group>
            <Group mt="md" className="advanced-options">
              <Switch
                label="Parse TeX archive after import"
                checked={localParseAfterImport}
                disabled={localKind !== "tex_archive"}
                onChange={(event) => setLocalParseAfterImport(event.currentTarget.checked)}
              />
            </Group>
          </>
        )}

        {importArxiv.isSuccess ? (
          <Text c="dimmed" size="sm" mt="sm">
            Import job queued. The task drawer will show download and parse progress.
          </Text>
        ) : null}
        {importArxiv.isError ? (
          <Text c="red" size="sm" mt="sm">
            Import job could not be queued. Check that the API is running.
          </Text>
        ) : null}
        {importLocalFile.isSuccess ? (
          <Text c="dimmed" size="sm" mt="sm">
            Local file imported. TeX archives can be parsed by the worker; Markdown creates weak
            structured blocks immediately, and PDF is saved only.
          </Text>
        ) : null}
        {importLocalFile.isError ? (
          <Text c="red" size="sm" mt="sm">
            Local file could not be imported. Check file type and API availability.
          </Text>
        ) : null}
      </div>

      <div className="panel">
        <Title order={3}>Articles</Title>
        {articles.isError ? (
          <Alert color="yellow" icon={<Info size={18} />} mt="md">
            Article records could not be loaded.
          </Alert>
        ) : null}
        {(articles.data ?? []).length === 0 ? (
          <Text c="dimmed" mt="md">
            No imported articles yet.
          </Text>
        ) : (
          <Table mt="md" verticalSpacing="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Paper</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Blocks</Table.Th>
                <Table.Th>Assets</Table.Th>
                <Table.Th>Updated</Table.Th>
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
                      Open
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
