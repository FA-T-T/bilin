import {
  ActionIcon,
  AppShell,
  Badge,
  Button,
  Group,
  Select,
  Title,
  Tooltip,
  useComputedColorScheme,
  useMantineColorScheme
} from "@mantine/core";
import { Moon, Settings, Sun, TerminalSquare } from "lucide-react";
import { Link, Outlet, useLocation } from "react-router-dom";

import { useJobSummary } from "../api/hooks";
import { useT } from "../i18n";
import { SUPPORTED_LOCALES, type AppLocale } from "../product";
import { useUiStore } from "../state/ui";
import { XianduLogo } from "./brand/XianduLogo";
import { TaskDrawer } from "./TaskDrawer";

export function AppLayout() {
  const t = useT();
  const location = useLocation();
  const { setColorScheme } = useMantineColorScheme();
  const colorScheme = useComputedColorScheme("light", { getInitialValueInEffect: true });
  const locale = useUiStore((state) => state.locale);
  const setLocale = useUiStore((state) => state.setLocale);
  const openTaskDrawer = useUiStore((state) => state.openTaskDrawer);
  const isReaderRoute = location.pathname.startsWith("/articles/");
  const jobs = useJobSummary({ enabled: !isReaderRoute });
  const activeJobCount = jobs.data?.active ?? 0;
  const isHomeRoute = location.pathname === "/";

  const libraryActive = location.pathname === "/" || location.pathname.startsWith("/libraries");
  const settingsActive = location.pathname.startsWith("/settings");

  return (
    <AppShell className="app-shell" header={{ height: isReaderRoute ? 0 : 58 }} padding={0}>
      {!isReaderRoute ? (
        <AppShell.Header className="app-header">
          <div className="app-header-inner">
            <Select
              aria-label={t("settings.language")}
              allowDeselect={false}
              className="app-language-switcher"
              data={SUPPORTED_LOCALES.map((item) => ({
                value: item.value,
                label: item.nativeLabel
              }))}
              onChange={(value) => {
                if (value) setLocale(value as AppLocale);
              }}
              size="xs"
              value={locale}
            />
            <Link
              className="brand-lockup brand-home-link"
              to="/"
              aria-current={libraryActive ? "page" : undefined}
              aria-label="衔牍"
              data-active={libraryActive || undefined}
              data-variant={isHomeRoute ? "main" : "page"}
            >
              {isHomeRoute ? (
                <>
                  <span className="brand-mark" aria-hidden="true">
                    <XianduLogo className="brand-mark-image" decorative />
                  </span>
                  <div>
                    <Title order={3} className="brand-title">
                      衔牍
                    </Title>
                  </div>
                </>
              ) : (
                <XianduLogo className="brand-page-logo" title="衔牍" variant="page" />
              )}
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
          </div>
        </AppShell.Header>
      ) : null}
      <AppShell.Main>
        <Outlet />
        <TaskDrawer />
      </AppShell.Main>
    </AppShell>
  );
}
