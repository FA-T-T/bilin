import {
  ActionIcon,
  AppShell,
  Button,
  Group,
  Text,
  Title,
  Tooltip,
  useComputedColorScheme,
  useMantineColorScheme
} from "@mantine/core";
import { BookOpen, Library, Moon, Settings, Sun, TerminalSquare } from "lucide-react";
import { Link, Outlet } from "react-router-dom";

import { useUiStore } from "../state/ui";
import { TaskDrawer } from "./TaskDrawer";

export function AppLayout() {
  const { setColorScheme } = useMantineColorScheme();
  const colorScheme = useComputedColorScheme("light", { getInitialValueInEffect: true });
  const openTaskDrawer = useUiStore((state) => state.openTaskDrawer);

  return (
    <AppShell header={{ height: 62 }} padding="md">
      <AppShell.Header className="app-header">
        <Group justify="space-between" h="100%" px="xl">
          <Group gap="sm" className="brand-lockup">
            <span className="brand-mark" aria-hidden="true">
              <BookOpen size={18} />
            </span>
            <div>
              <Title order={3} className="brand-title">
                Bilin
              </Title>
              <Text c="dimmed" size="xs" className="brand-subtitle">
                Local paper reader
              </Text>
            </div>
          </Group>
          <Group gap="xs" className="app-nav">
            <Button
              component={Link}
              to="/"
              variant="subtle"
              leftSection={<Library size={16} />}
              aria-label="Library"
            >
              Library
            </Button>
            <Button
              component={Link}
              to="/settings"
              variant="subtle"
              leftSection={<Settings size={16} />}
              aria-label="Settings"
            >
              Settings
            </Button>
            <Tooltip label="Tasks">
              <ActionIcon variant="default" onClick={openTaskDrawer} aria-label="Open task drawer">
                <TerminalSquare size={18} />
              </ActionIcon>
            </Tooltip>
            <Tooltip label="Toggle theme">
              <ActionIcon
                variant="default"
                onClick={() => setColorScheme(colorScheme === "dark" ? "light" : "dark")}
                aria-label="Toggle theme"
              >
                {colorScheme === "dark" ? <Sun size={18} /> : <Moon size={18} />}
              </ActionIcon>
            </Tooltip>
          </Group>
        </Group>
      </AppShell.Header>
      <AppShell.Main>
        <Outlet />
        <TaskDrawer />
      </AppShell.Main>
    </AppShell>
  );
}
