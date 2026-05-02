import { Alert, Button, Group, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { Info } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";

import { useCreateLibrary, useLibraries } from "../api/hooks";

export function LibraryHomePage() {
  const libraries = useLibraries();
  const createLibrary = useCreateLibrary();
  const [name, setName] = useState("Papers");
  const [path, setPath] = useState("");

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="flex-end">
        <div>
          <Title order={1}>Library</Title>
          <Text c="dimmed">
            Keep papers, caches, source bundles, and notes in one local folder.
          </Text>
        </div>
      </Group>

      <div className="panel">
        <Title order={3}>Create library</Title>
        <Group mt="md" align="end">
          <TextInput label="Name" value={name} onChange={(event) => setName(event.target.value)} />
          <TextInput
            className="path-input grow-input"
            label="Directory path"
            placeholder="/Users/you/Papers"
            value={path}
            onChange={(event) => setPath(event.target.value)}
          />
          <Button
            onClick={() => createLibrary.mutate({ name, path })}
            loading={createLibrary.isPending}
            disabled={!name.trim() || !path.trim()}
          >
            Create
          </Button>
        </Group>
      </div>

      {libraries.isError ? (
        <Alert color="yellow" icon={<Info size={18} />}>
          The API is not reachable. Start FastAPI on port 8000 to list and create libraries.
        </Alert>
      ) : null}

      <div className="panel">
        <Title order={3}>Registered libraries</Title>
        {(libraries.data ?? []).length === 0 ? (
          <Text c="dimmed" mt="md">
            No libraries have been registered in this local profile.
          </Text>
        ) : (
          <Table mt="md" verticalSpacing="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Path</Table.Th>
                <Table.Th>Updated</Table.Th>
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
