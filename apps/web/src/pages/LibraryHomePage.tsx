import { Alert, Button, Group, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { Info } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import { useCreateLibrary, useLibraries } from "../api/hooks";
import { useT } from "../i18n";

export function LibraryHomePage() {
  const t = useT();
  const libraries = useLibraries();
  const createLibrary = useCreateLibrary();
  const [name, setName] = useState("Papers");
  const [path, setPath] = useState("");

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
        <Title order={3}>{t("library.registered")}</Title>
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
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {(libraries.data ?? []).map((library) => (
                <Table.Tr key={library.id}>
                  <Table.Td>
                    <Link to={`/libraries/${library.id}`}>{library.name}</Link>
                  </Table.Td>
                  <Table.Td>{library.status}</Table.Td>
                  <Table.Td>{library.path}</Table.Td>
                  <Table.Td>{new Date(library.updated_at).toLocaleString()}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </div>
    </Stack>
  );
}
