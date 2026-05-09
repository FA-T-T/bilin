import {
  Alert,
  Badge,
  Button,
  Group,
  Modal,
  Stack,
  Table,
  Text,
  TextInput,
  Title
} from "@mantine/core";
import { Info } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import { useArchiveLibrary, useCreateLibrary, useDeleteLibrary, useLibraries } from "../api/hooks";
import type { Library } from "../api/types";
import { useT } from "../i18n";

export function LibraryHomePage() {
  const t = useT();
  const libraries = useLibraries();
  const createLibrary = useCreateLibrary();
  const archiveLibrary = useArchiveLibrary();
  const deleteLibrary = useDeleteLibrary();
  const [name, setName] = useState("Papers");
  const [path, setPath] = useState("");
  const [pendingDeleteLibrary, setPendingDeleteLibrary] = useState<Library | null>(null);
  const [libraryActionMessage, setLibraryActionMessage] = useState<{
    kind: "success" | "error";
    text: string;
  } | null>(null);

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
    <Stack gap="lg">
      <Group justify="space-between" align="flex-end">
        <div>
          <Title order={1}>{t("library.title")}</Title>
          <Text c="dimmed">{t("library.subtitle")}</Text>
        </div>
      </Group>

      <div className="panel">
        <Title order={3}>{t("library.createTitle")}</Title>
        <Group mt="md" align="end">
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
          <Button
            onClick={() => createLibrary.mutate({ name, path })}
            loading={createLibrary.isPending}
            disabled={!name.trim() || !path.trim()}
          >
            {t("library.create")}
          </Button>
        </Group>
      </div>

      {libraries.isError ? (
        <Alert color="yellow" icon={<Info size={18} />}>
          {t("library.apiUnavailable")}
        </Alert>
      ) : null}

      <div className="panel">
        <Group justify="space-between" align="center">
          <Title order={3}>{t("library.registered")}</Title>
          {libraryActionMessage ? (
            <Text c={libraryActionMessage.kind === "success" ? "dimmed" : "red"} size="sm">
              {libraryActionMessage.text}
            </Text>
          ) : null}
        </Group>
        {(libraries.data ?? []).length === 0 ? (
          <Text c="dimmed" mt="md">
            {t("library.empty")}
          </Text>
        ) : (
          <Table mt="md" verticalSpacing="sm">
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
              {(libraries.data ?? []).map((library) => (
                <Table.Tr key={library.id}>
                  <Table.Td>
                    <Link to={`/libraries/${library.id}`}>{library.name}</Link>
                  </Table.Td>
                  <Table.Td>
                    <Badge
                      color={library.status === "archived" ? "gray" : undefined}
                      variant="light"
                    >
                      {library.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{library.path}</Table.Td>
                  <Table.Td>{new Date(library.updated_at).toLocaleString()}</Table.Td>
                  <Table.Td>
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
              ))}
            </Table.Tbody>
          </Table>
        )}
      </div>

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
