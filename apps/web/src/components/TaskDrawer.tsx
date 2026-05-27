import {
  Badge,
  Button,
  Drawer,
  Group,
  Loader,
  Progress,
  Stack,
  Text
} from "@mantine/core";
import { RotateCcw, Trash2 } from "lucide-react";
import { memo } from "react";

import {
  articleTaskFailedCount,
  useArticleTaskSummary,
  useClearJobs,
  useRetryJobs
} from "../api/hooks";
import type { ArticleTaskProgress, JobStatus } from "../api/types";
import { useT } from "../i18n";
import { useUiStore } from "../state/ui";

const TASK_DRAWER_LIMIT = 120;

export function TaskDrawer() {
  const t = useT();
  const opened = useUiStore((state) => state.taskDrawerOpen);
  const close = useUiStore((state) => state.closeTaskDrawer);
  const summary = useArticleTaskSummary({ limit: TASK_DRAWER_LIMIT, enabled: opened });
  const clearJobs = useClearJobs();
  const taskCount = summary.data?.total ?? 0;
  const shownTaskCount = summary.data?.items?.length ?? 0;
  const isInitialLoading = summary.isPending || (summary.isFetching && !summary.data);

  return (
    <Drawer opened={opened} onClose={close} position="right" title={t("task.title")} size="lg">
      <Stack gap="md">
        <Group justify="space-between" align="flex-start" wrap="nowrap">
          <Text size="sm" c="dimmed">
            {t("task.description")}
          </Text>
          <Button
            size="compact-sm"
            variant="light"
            color="red"
            leftSection={<Trash2 size={14} aria-hidden="true" />}
            loading={clearJobs.isPending}
            disabled={isInitialLoading || taskCount === 0}
            onClick={() => clearJobs.mutate()}
          >
            {t("task.clearAll")}
          </Button>
        </Group>
        <JobSummaryStrip
          queued={summary.data?.queued ?? 0}
          running={summary.data?.running ?? 0}
          paused={summary.data?.paused ?? 0}
          failed={articleTaskFailedCount(summary.data)}
        />
        {taskCount > shownTaskCount ? (
          <Text size="xs" c="dimmed">
            {t("task.showingRecent", { shown: shownTaskCount, total: taskCount })}
          </Text>
        ) : null}
        {summary.isError ? (
          <Text c="red" size="sm">
            {t("task.apiUnavailable")}
          </Text>
        ) : null}
        <Stack gap="sm">
          {isInitialLoading ? (
            <Group className="task-loading-state" gap="xs">
              <Loader size="xs" />
              <Text c="dimmed" size="sm">
                {t("task.loading")}
              </Text>
            </Group>
          ) : taskCount === 0 ? (
            <Text c="dimmed" size="sm">
              {t("task.empty")}
            </Text>
          ) : (
            (summary.data?.items ?? []).map((task) => <TaskRow key={task.id} task={task} />)
          )}
        </Stack>
      </Stack>
    </Drawer>
  );
}

function JobSummaryStrip({
  queued,
  running,
  paused,
  failed
}: {
  queued: number;
  running: number;
  paused: number;
  failed: number;
}) {
  const t = useT();
  return (
    <Group gap={6} className="task-summary-strip">
      <Badge variant="light">{t("task.statusQueued", { count: queued })}</Badge>
      <Badge variant="light" color="blue">
        {t("task.statusRunning", { count: running })}
      </Badge>
      <Badge variant="light" color="yellow">
        {t("task.statusPaused", { count: paused })}
      </Badge>
      <Badge variant="light" color="red">
        {t("task.statusFailed", { count: failed })}
      </Badge>
    </Group>
  );
}

const TaskRow = memo(function TaskRow({ task }: { task: ArticleTaskProgress }) {
  const t = useT();
  const retryJobs = useRetryJobs();
  const failedJobIds = task.failed_job_ids ?? [];
  const canRetry = failedJobIds.length > 0;
  return (
    <div className="task-row">
      <Group justify="space-between" align="flex-start" wrap="nowrap">
        <div className="task-row-main">
          <Group gap="xs" className="task-row-heading" wrap="nowrap">
            <Text className="task-row-title" fw={600} size="sm">
              {taskTitle(task)}
            </Text>
            <Badge
              className="task-row-status"
              size="sm"
              variant="light"
              color={statusColor(task.status)}
            >
              {task.status}
            </Badge>
          </Group>
          <Text className="task-row-message" c="dimmed" size="xs">
            {task.message}
          </Text>
        </div>
        {canRetry ? (
          <Button
            className="task-row-action"
            size="compact-xs"
            variant="light"
            color="blue"
            leftSection={<RotateCcw size={13} aria-hidden="true" />}
            loading={retryJobs.isPending}
            onClick={() => retryJobs.mutate(failedJobIds)}
            aria-label={t("task.continueJob")}
          >
            {t("task.continue")}
          </Button>
        ) : null}
      </Group>
      <Progress value={task.progress * 100} mt="xs" size="sm" />
      <Text className="task-row-detail" c="dimmed" size="xs" mt={6}>
        {taskDetail(task)}
      </Text>
      {task.status === "failed" && task.error ? (
        <Text className="task-row-error" c="red" size="xs" mt="xs">
          {jobErrorText(task)}
        </Text>
      ) : null}
    </div>
  );
});

function taskTitle(task: ArticleTaskProgress): string {
  return (
    task.article_title?.trim() ||
    task.source_id?.trim() ||
    task.article_revision_id?.trim() ||
    task.id
  );
}

function taskDetail(task: ArticleTaskProgress): string {
  const parts: string[] = [];
  if (task.source_id) parts.push(task.source_id);
  if (task.total > 1) parts.push(`${task.current}/${task.total}`);
  parts.push(`${Math.round(task.progress * 100)}%`);
  return parts.join(" / ");
}

function statusColor(status: JobStatus) {
  if (status === "running") return "blue";
  if (status === "paused") return "yellow";
  if (status === "failed") return "red";
  if (status === "succeeded") return "green";
  return "gray";
}

function jobErrorText(task: ArticleTaskProgress): string {
  const error = task.error ?? {};
  const code = typeof error.code === "string" ? error.code : undefined;
  const type = typeof error.type === "string" ? error.type : undefined;
  const rawMessage = typeof error.message === "string" ? error.message.trim() : "";
  const message = rawMessage || (type ? `${type}.` : "Task failed.");
  const details = error.details;
  const installHint =
    details && typeof details === "object" && "install_hint" in details
      ? details.install_hint
      : undefined;
  const hint = typeof installHint === "string" ? ` ${installHint}` : "";
  return code ? `${code}: ${message}${hint}` : `${message}${hint}`;
}
