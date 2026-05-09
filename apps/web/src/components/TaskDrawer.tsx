import {
  ActionIcon,
  Badge,
  Button,
  Drawer,
  Group,
  Progress,
  Stack,
  Text,
  Tooltip
} from "@mantine/core";
import { Pause, Play, Square, Trash2 } from "lucide-react";
import { memo } from "react";

import { useClearJobs, useJobAction, useJobEvents, useJobs, useJobSummary } from "../api/hooks";
import type { Job } from "../api/types";
import { useT } from "../i18n";
import { useUiStore } from "../state/ui";

const TASK_DRAWER_LIMIT = 120;

export function TaskDrawer() {
  const t = useT();
  const opened = useUiStore((state) => state.taskDrawerOpen);
  useJobEvents(opened);
  const close = useUiStore((state) => state.closeTaskDrawer);
  const jobs = useJobs({ limit: TASK_DRAWER_LIMIT, enabled: opened });
  const summary = useJobSummary();
  const clearJobs = useClearJobs();
  const jobCount = summary.data?.total ?? jobs.data?.length ?? 0;
  const shownJobCount = jobs.data?.length ?? 0;

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
            disabled={jobCount === 0}
            onClick={() => clearJobs.mutate()}
          >
            {t("task.clearAll")}
          </Button>
        </Group>
        <JobSummaryStrip
          queued={summary.data?.queued ?? 0}
          running={summary.data?.running ?? 0}
          paused={summary.data?.paused ?? 0}
          succeeded={summary.data?.succeeded ?? 0}
          failed={summary.data?.failed ?? 0}
        />
        {jobCount > shownJobCount ? (
          <Text size="xs" c="dimmed">
            {t("task.showingRecent", { shown: shownJobCount, total: jobCount })}
          </Text>
        ) : null}
        {jobs.isError ? (
          <Text c="red" size="sm">
            {t("task.apiUnavailable")}
          </Text>
        ) : null}
        <Stack gap="sm">
          {jobCount === 0 ? (
            <Text c="dimmed" size="sm">
              {t("task.empty")}
            </Text>
          ) : (
            (jobs.data ?? []).map((job) => <TaskRow key={job.id} job={job} />)
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
  succeeded,
  failed
}: {
  queued: number;
  running: number;
  paused: number;
  succeeded: number;
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
      <Badge variant="light" color="green">
        {t("task.statusSucceeded", { count: succeeded })}
      </Badge>
      <Badge variant="light" color="red">
        {t("task.statusFailed", { count: failed })}
      </Badge>
    </Group>
  );
}

const TaskRow = memo(function TaskRow({ job }: { job: Job }) {
  const t = useT();
  const pause = useJobAction("pause");
  const resume = useJobAction("resume");
  const cancel = useJobAction("cancel");
  return (
    <div className="task-row">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <Text fw={600} size="sm">
              {job.type}
            </Text>
            <Badge size="sm" variant="light">
              {job.status}
            </Badge>
          </Group>
          <Text c="dimmed" size="xs">
            {job.id}
          </Text>
        </div>
        <Group gap={4}>
          <Tooltip label={t("task.pause")}>
            <ActionIcon
              size="sm"
              variant="subtle"
              onClick={() => pause.mutate(job.id)}
              disabled={job.status !== "running" && job.status !== "queued"}
              aria-label={t("task.pauseJob")}
            >
              <Pause size={14} />
            </ActionIcon>
          </Tooltip>
          <Tooltip label={t("task.resume")}>
            <ActionIcon
              size="sm"
              variant="subtle"
              onClick={() => resume.mutate(job.id)}
              disabled={job.status !== "paused"}
              aria-label={t("task.resumeJob")}
            >
              <Play size={14} />
            </ActionIcon>
          </Tooltip>
          <Tooltip label={t("task.cancel")}>
            <ActionIcon
              size="sm"
              variant="subtle"
              color="red"
              onClick={() => cancel.mutate(job.id)}
              disabled={["succeeded", "failed", "cancelled"].includes(job.status)}
              aria-label={t("task.cancelJob")}
            >
              <Square size={14} />
            </ActionIcon>
          </Tooltip>
        </Group>
      </Group>
      <Progress value={job.progress * 100} mt="xs" size="sm" />
      {job.status === "failed" && job.error ? (
        <Text c="red" size="xs" mt="xs">
          {jobErrorText(job)}
        </Text>
      ) : null}
    </div>
  );
});

function jobErrorText(job: Job): string {
  const error = job.error ?? {};
  const code = typeof error.code === "string" ? error.code : undefined;
  const message = typeof error.message === "string" ? error.message : "Task failed.";
  const details = error.details;
  const installHint =
    details && typeof details === "object" && "install_hint" in details
      ? details.install_hint
      : undefined;
  const hint = typeof installHint === "string" ? ` ${installHint}` : "";
  return code ? `${code}: ${message}${hint}` : `${message}${hint}`;
}
