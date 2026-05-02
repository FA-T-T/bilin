import { ActionIcon, Badge, Drawer, Group, Progress, Stack, Text, Tooltip } from "@mantine/core";
import { Pause, Play, Square } from "lucide-react";

import { useJobAction, useJobEvents, useJobs } from "../api/hooks";
import type { Job } from "../api/types";
import { useUiStore } from "../state/ui";

export function TaskDrawer() {
  useJobEvents();
  const opened = useUiStore((state) => state.taskDrawerOpen);
  const close = useUiStore((state) => state.closeTaskDrawer);
  const jobs = useJobs();

  return (
    <Drawer opened={opened} onClose={close} position="right" title="Background tasks" size="lg">
      <Stack gap="md">
        <Group justify="space-between">
          <Text size="sm" c="dimmed">
            Imports, parsing, translation, note generation, embedding, and exports run here.
          </Text>
        </Group>
        {jobs.isError ? (
          <Text c="red" size="sm">
            API is unavailable. Start the FastAPI service on port 8000.
          </Text>
        ) : null}
        <Stack gap="sm">
          {(jobs.data ?? []).length === 0 ? (
            <Text c="dimmed" size="sm">
              No queued work yet.
            </Text>
          ) : (
            (jobs.data ?? []).map((job) => <TaskRow key={job.id} job={job} />)
          )}
        </Stack>
      </Stack>
    </Drawer>
  );
}

function TaskRow({ job }: { job: Job }) {
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
          <Tooltip label="Pause">
            <ActionIcon
              size="sm"
              variant="subtle"
              onClick={() => pause.mutate(job.id)}
              disabled={job.status !== "running" && job.status !== "queued"}
              aria-label="Pause job"
            >
              <Pause size={14} />
            </ActionIcon>
          </Tooltip>
          <Tooltip label="Resume">
            <ActionIcon
              size="sm"
              variant="subtle"
              onClick={() => resume.mutate(job.id)}
              disabled={job.status !== "paused"}
              aria-label="Resume job"
            >
              <Play size={14} />
            </ActionIcon>
          </Tooltip>
          <Tooltip label="Cancel">
            <ActionIcon
              size="sm"
              variant="subtle"
              color="red"
              onClick={() => cancel.mutate(job.id)}
              disabled={["succeeded", "failed", "cancelled"].includes(job.status)}
              aria-label="Cancel job"
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
}

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
