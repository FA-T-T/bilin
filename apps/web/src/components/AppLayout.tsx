import {
  ActionIcon,
  AppShell,
  Badge,
  Button,
  Group,
  Text,
  Title,
  Tooltip,
  useComputedColorScheme,
  useMantineColorScheme
} from "@mantine/core";
import { BookOpen, Library, Moon, Settings, Sun, TerminalSquare } from "lucide-react";
import { Link, Outlet, useLocation } from "react-router-dom";

import { useJobSummary } from "../api/hooks";
import { useProductName, useT } from "../i18n";
import { useUiStore } from "../state/ui";
import { TaskDrawer } from "./TaskDrawer";

export function AppLayout() {
  const t = useT();
  const productName = useProductName();
  const location = useLocation();
  const { setColorScheme } = useMantineColorScheme();
  const colorScheme = useComputedColorScheme("light", { getInitialValueInEffect: true });
  const openTaskDrawer = useUiStore((state) => state.openTaskDrawer);
  const jobs = useJobSummary();
  const activeJobCount = jobs.data?.active ?? 0;
  const isReaderRoute = location.pathname.startsWith("/articles/");

  return (
    <AppShell header={{ height: isReaderRoute ? 0 : 62 }} padding={isReaderRoute ? 0 : "md"}>
      {isReaderRoute ? null : (
        <AppShell.Header className="app-header">
          <Group justify="space-between" h="100%" px="xl">
            <Group gap="sm" className="brand-lockup">
              <span className="brand-mark" aria-hidden="true">
                <BookOpen size={18} />
              </span>
              <div>
                <Title order={3} className="brand-title">
                  {productName}
                </Title>
                <Text c="dimmed" size="xs" className="brand-subtitle">
                  {t("app.subtitle")}
                </Text>
              </div>
            </Group>
            <Group gap="xs" className="app-nav">
              <Button
                component={Link}
                to="/"
                variant="subtle"
                leftSection={<Library size={16} />}
                aria-label={t("nav.library")}
              >
                {t("nav.library")}
              </Button>
              <Button
                component={Link}
                to="/settings"
                variant="subtle"
                leftSection={<Settings size={16} />}
                aria-label={t("nav.settings")}
              >
                {t("nav.settings")}
              </Button>
              <Tooltip label={t("nav.tasks")}>
                <span className="task-trigger">
                  <ActionIcon
                    variant="default"
                    onClick={openTaskDrawer}
                    aria-label={t("nav.openTasks")}
                  >
                    <TerminalSquare size={18} />
                  </ActionIcon>
                  {activeJobCount > 0 ? (
                    <Badge className="task-trigger-badge" size="xs" variant="filled">
                      {activeJobCount}
                    </Badge>
                  ) : null}
                </span>
              </Tooltip>
              <Tooltip label={t("nav.toggleTheme")}>
                <ActionIcon
                  variant="default"
                  onClick={() => setColorScheme(colorScheme === "dark" ? "light" : "dark")}
                  aria-label={t("nav.toggleTheme")}
                >
                  {colorScheme === "dark" ? <Sun size={18} /> : <Moon size={18} />}
                </ActionIcon>
              </Tooltip>
            </Group>
          </Group>
        </AppShell.Header>
      )}
      <AppShell.Main>
        <Outlet />
        <TaskDrawer />
      </AppShell.Main>
    </AppShell>
  );
}
