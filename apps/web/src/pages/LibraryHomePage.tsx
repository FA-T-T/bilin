import {
  ActionIcon,
  Alert,
  Badge,
  Button,
  Group,
  Modal,
  Stack,
  Table,
  Text,
  TextInput,
  Tooltip,
  Title
} from "@mantine/core";
import { Check, Info, Pencil, X } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import {
  useArchiveLibrary,
  useCreateLibrary,
  useDeleteLibrary,
  useLibraries,
  useUpdateLibrary
} from "../api/hooks";
import type { Library } from "../api/types";
import {
  WorkbenchButton,
  WorkbenchCard,
  WorkbenchDivider,
  WorkbenchTitle
} from "../components/workbench/WorkbenchChrome";
import { useT } from "../i18n";

export function LibraryHomePage() {
  const t = useT();
  const libraries = useLibraries();
  const createLibrary = useCreateLibrary();
  const updateLibrary = useUpdateLibrary();
  const archiveLibrary = useArchiveLibrary();
  const deleteLibrary = useDeleteLibrary();
  const [name, setName] = useState("Papers");
  const [path, setPath] = useState("");
  const [editingLibrary, setEditingLibrary] = useState<{ id: string; name: string } | null>(null);
  const [pendingDeleteLibrary, setPendingDeleteLibrary] = useState<Library | null>(null);
  const [libraryActionMessage, setLibraryActionMessage] = useState<{
    kind: "success" | "error";
    text: string;
  } | null>(null);
  const libraryItems = libraries.data ?? [];
  const activeLibraryCount = libraryItems.filter((library) => library.status !== "archived").length;
  const archivedLibraryCount = libraryItems.length - activeLibraryCount;

  const archiveSelectedLibrary = (libraryId: string) => {
    setLibraryActionMessage(null);
    archiveLibrary.mutate(libraryId, {
      onSuccess: () =>
        setLibraryActionMessage({ kind: "success", text: t("library.libraryArchived") }),
      onError: (error) =>
        setLibraryActionMessage({
          kind: "error",
          text: t("library.libraryActionErrorWithMessage", { message: errorMessage(error) })
        })
    });
  };

  const startEditingLibraryName = (library: Library) => {
    setLibraryActionMessage(null);
    setEditingLibrary({ id: library.id, name: library.name });
  };

  const saveLibraryName = (library: Library) => {
    if (editingLibrary?.id !== library.id) return;
    const nextName = editingLibrary.name.trim();
    if (!nextName || nextName === library.name) return;
    setLibraryActionMessage(null);
    updateLibrary.mutate(
      { libraryId: library.id, payload: { name: nextName } },
      {
        onSuccess: () => {
          setEditingLibrary(null);
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

  const confirmDeleteLibrary = () => {
    if (!pendingDeleteLibrary) return;
    setLibraryActionMessage(null);
    deleteLibrary.mutate(pendingDeleteLibrary.id, {
      onSuccess: () => {
        setPendingDeleteLibrary(null);
        setLibraryActionMessage({ kind: "success", text: t("library.libraryDeleted") });
      },
      onError: (error) =>
        setLibraryActionMessage({
          kind: "error",
          text: t("library.libraryActionErrorWithMessage", { message: errorMessage(error) })
        })
    });
  };

  return (
    <Stack gap="lg" className="app-page library-home-page">
      <Group justify="space-between" align="flex-end" className="page-hero">
        <div>
          <Text className="page-eyebrow">{t("library.localWorkspace")}</Text>
          <WorkbenchTitle headingLevel={1} name={t("library.title")} />
          <Text c="dimmed" className="page-subtitle">
            {t("library.subtitle")}
          </Text>
        </div>
        <div className="page-metrics" aria-label={t("library.registered")}>
          <div className="metric-tile">
            <Text size="xs" c="dimmed">
              {t("library.registered")}
            </Text>
            <Text fw={750}>{libraryItems.length}</Text>
          </div>
          <div className="metric-tile">
            <Text size="xs" c="dimmed">
              {t("library.active")}
            </Text>
            <Text fw={750}>{activeLibraryCount}</Text>
          </div>
          <div className="metric-tile">
            <Text size="xs" c="dimmed">
              {t("library.archived")}
            </Text>
            <Text fw={750}>{archivedLibraryCount}</Text>
          </div>
        </div>
      </Group>

      <WorkbenchCard className="panel library-create-panel">
        <Title order={2} className="panel-title">
          {t("library.createTitle")}
        </Title>
        <WorkbenchDivider />
        <div className="library-create-form">
          <TextInput
            label={t("library.name")}
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
          <TextInput
            className="path-input grow-input"
            label={t("library.directoryPath")}
            placeholder="/Users/you/Papers"
            value={path}
            onChange={(event) => setPath(event.target.value)}
          />
          <WorkbenchButton
            onClick={() => createLibrary.mutate({ name, path })}
            loading={createLibrary.isPending}
            disabled={!name.trim() || !path.trim()}
          >
            {t("library.create")}
          </WorkbenchButton>
        </div>
      </WorkbenchCard>

      {libraries.isError ? (
        <Alert color="yellow" icon={<Info size={18} />}>
          {t("library.apiUnavailable")}
        </Alert>
      ) : null}

      <WorkbenchCard className="panel library-table-panel" variant="default">
        <Group justify="space-between" align="center">
          <Title order={2} className="panel-title">
            {t("library.registered")}
          </Title>
          {libraryActionMessage ? (
            <Text c={libraryActionMessage.kind === "success" ? "dimmed" : "red"} size="sm">
              {libraryActionMessage.text}
            </Text>
          ) : null}
        </Group>
        {libraryItems.length === 0 ? (
          <Text c="dimmed" mt="md" className="empty-state">
            {t("library.empty")}
          </Text>
        ) : (
          <div className="table-scroll">
            <Table mt="md" verticalSpacing="sm" className="data-table">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>{t("library.name")}</Table.Th>
                  <Table.Th>{t("library.status")}</Table.Th>
                  <Table.Th>{t("library.path")}</Table.Th>
                  <Table.Th>{t("library.updated")}</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {libraryItems.map((library) => {
                  const isEditingName = editingLibrary?.id === library.id;
                  return (
                    <Table.Tr key={library.id}>
                      <Table.Td data-label={t("library.name")}>
                        {isEditingName ? (
                          <Group gap="xs" wrap="nowrap">
                            <TextInput
                              aria-label={t("library.renameInputLabel")}
                              disabled={updateLibrary.isPending}
                              onChange={(event) =>
                                setEditingLibrary({ id: library.id, name: event.target.value })
                              }
                              onKeyDown={(event) => {
                                if (event.key === "Enter") saveLibraryName(library);
                                if (event.key === "Escape") setEditingLibrary(null);
                              }}
                              size="xs"
                              style={{ minWidth: "12rem" }}
                              value={editingLibrary.name}
                            />
                            <Tooltip label={t("library.saveName")}>
                              <ActionIcon
                                aria-label={t("library.saveName")}
                                disabled={
                                  updateLibrary.isPending ||
                                  !editingLibrary.name.trim() ||
                                  editingLibrary.name.trim() === library.name
                                }
                                loading={updateLibrary.isPending}
                                onClick={() => saveLibraryName(library)}
                                size="sm"
                                variant="light"
                              >
                                <Check size={14} />
                              </ActionIcon>
                            </Tooltip>
                            <Tooltip label={t("library.cancel")}>
                              <ActionIcon
                                aria-label={t("library.cancel")}
                                disabled={updateLibrary.isPending}
                                onClick={() => setEditingLibrary(null)}
                                size="sm"
                                variant="subtle"
                              >
                                <X size={14} />
                              </ActionIcon>
                            </Tooltip>
                          </Group>
                        ) : (
                          <Group gap="xs" wrap="nowrap">
                            <Link to={`/libraries/${library.id}`}>{library.name}</Link>
                            <Tooltip label={t("library.editName")}>
                              <ActionIcon
                                aria-label={t("library.editName")}
                                disabled={updateLibrary.isPending}
                                onClick={() => startEditingLibraryName(library)}
                                size="sm"
                                variant="subtle"
                              >
                                <Pencil size={14} />
                              </ActionIcon>
                            </Tooltip>
                          </Group>
                        )}
                      </Table.Td>
                      <Table.Td data-label={t("library.status")}>
                        <Badge
                          color={library.status === "archived" ? "gray" : undefined}
                          variant="light"
                        >
                          {library.status}
                        </Badge>
                      </Table.Td>
                      <Table.Td data-label={t("library.path")}>{library.path}</Table.Td>
                      <Table.Td data-label={t("library.updated")}>
                        {new Date(library.updated_at).toLocaleString()}
                      </Table.Td>
                      <Table.Td data-label={t("library.actions")}>
                        <Group gap="xs" justify="flex-end" wrap="nowrap">
                          <Button
                            disabled={library.status === "archived" || archiveLibrary.isPending}
                            onClick={() => archiveSelectedLibrary(library.id)}
                            size="xs"
                            variant="subtle"
                          >
                            {t("library.archive")}
                          </Button>
                          <Button
                            color="red"
                            disabled={deleteLibrary.isPending}
                            onClick={() => setPendingDeleteLibrary(library)}
                            size="xs"
                            variant="subtle"
                          >
                            {t("library.delete")}
                          </Button>
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </div>
        )}
      </WorkbenchCard>

      <Modal
        centered
        onClose={() => {
          if (!deleteLibrary.isPending) setPendingDeleteLibrary(null);
        }}
        opened={Boolean(pendingDeleteLibrary)}
        title={t("library.libraryDeleteConfirmTitle")}
      >
        <Stack gap="md">
          <Text fw={600}>{pendingDeleteLibrary?.name}</Text>
          <Text size="sm">{t("library.libraryDeleteConfirmBody")}</Text>
          <Text c="dimmed" size="xs">
            {pendingDeleteLibrary?.path}
          </Text>
          <Group justify="flex-end">
            <Button
              disabled={deleteLibrary.isPending}
              onClick={() => setPendingDeleteLibrary(null)}
              variant="subtle"
            >
              {t("library.cancel")}
            </Button>
            <Button color="red" loading={deleteLibrary.isPending} onClick={confirmDeleteLibrary}>
              {t("library.confirmDelete")}
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
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
