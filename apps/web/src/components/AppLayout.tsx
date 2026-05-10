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
import { Moon, Settings, Sun, TerminalSquare } from "lucide-react";
import { Link, Outlet, useLocation } from "react-router-dom";

import { useJobSummary } from "../api/hooks";
import { useProductName, useT } from "../i18n";
import { useUiStore } from "../state/ui";
import { XianduLogo } from "./brand/XianduLogo";
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

  const libraryActive = location.pathname === "/" || location.pathname.startsWith("/libraries");
  const settingsActive = location.pathname.startsWith("/settings");

  return (
    <AppShell className="app-shell" header={{ height: isReaderRoute ? 0 : 58 }} padding={0}>
      {!isReaderRoute ? (
        <AppShell.Header className="app-header">
          <Group justify="space-between" h="100%" px="xl" className="app-header-inner">
            <Link
              className="brand-lockup brand-library-link"
              to="/"
              aria-current={libraryActive ? "page" : undefined}
              aria-label={t("nav.library")}
              data-active={libraryActive || undefined}
            >
              <span className="brand-mark" aria-hidden="true">
                <XianduLogo title={productName} />
              </span>
              <div>
                <Title order={3} className="brand-title">
                  {productName}
                </Title>
                <Text c="dimmed" size="xs" className="brand-subtitle">
                  {t("app.subtitle")}
                </Text>
              </div>
            </Link>
            <Group gap="xs" className="app-nav">
              <Button
                component={Link}
                to="/settings"
                variant="subtle"
                leftSection={<Settings size={16} />}
                aria-label={t("nav.settings")}
                aria-current={settingsActive ? "page" : undefined}
                data-active={settingsActive || undefined}
              >
                {t("nav.settings")}
              </Button>
              <Tooltip label={t("nav.tasks")}>
                <span className="task-trigger">
                  <ActionIcon
                    variant="default"
                    onClick={openTaskDrawer}
                    aria-label={t("nav.openGlobalTasks")}
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
      ) : null}
      <AppShell.Main>
        <Outlet />
        <TaskDrawer />
      </AppShell.Main>
    </AppShell>
  );
}
