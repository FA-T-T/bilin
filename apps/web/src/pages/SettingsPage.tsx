import {
  Alert,
  Badge,
  Button,
  Group,
  Select,
  SegmentedControl,
  Stack,
  Table,
  Tabs,
  Text,
  TextInput,
  Title
} from "@mantine/core";
import { useEffect, useState } from "react";

import {
  useCreateProvider,
  useDiscoverProviderModels,
  useDoctor,
  useProviders,
  useTranslationMemoryEntries,
  useUpdateTranslationMemoryEntry
} from "../api/hooks";
import type {
  ProviderModelInfo,
  ProviderProtocol,
  TranslationMemoryReviewStatus
} from "../api/types";
import { useProductName, useT } from "../i18n";
import { SUPPORTED_LOCALES, type AppLocale } from "../product";
import { useUiStore } from "../state/ui";

type SettingsMode = "user" | "developer";

export function SettingsPage() {
  const t = useT();
  const productName = useProductName();
  const locale = useUiStore((state) => state.locale);
  const setLocale = useUiStore((state) => state.setLocale);
  const doctor = useDoctor();
  const providers = useProviders();
  const createProvider = useCreateProvider();
  const discoverModels = useDiscoverProviderModels();
  const [memoryTargetLanguage, setMemoryTargetLanguage] = useState("zh-CN");
  const [memoryReviewStatus, setMemoryReviewStatus] =
    useState<TranslationMemoryReviewStatus>("pending");
  const memory = useTranslationMemoryEntries(memoryTargetLanguage, memoryReviewStatus, null);
  const updateMemory = useUpdateTranslationMemoryEntry(memoryTargetLanguage);
  const [mode, setMode] = useState<SettingsMode>("user");
  const [providerName, setProviderName] = useState("");
  const [protocol, setProtocol] = useState<ProviderProtocol>("openai-compatible");
  const [apiKey, setApiKey] = useState("");
  const [baseUrl, setBaseUrl] = useState("");
  const [selectedModelId, setSelectedModelId] = useState("");
  const [maxConcurrentRequests, setMaxConcurrentRequests] = useState("1");
  const [requestsPerMinute, setRequestsPerMinute] = useState("");
  const discoveredModels = discoverModels.data?.models ?? [];
  const selectedModel = discoveredModels.find((model) => model.id === selectedModelId) ?? null;
  const selectedModelCanRun = selectedModel ? isRunnableModel(selectedModel) : false;
  const runnableModelCount = discoveredModels.filter(isRunnableModel).length;

  useEffect(() => {
    if (discoverModels.data?.default_model) {
      setSelectedModelId(discoverModels.data.default_model);
    }
  }, [discoverModels.data?.default_model]);

  const detectModels = () => {
    setSelectedModelId("");
    discoverModels.mutate({
      protocol,
      api_key: apiKey,
      base_url: mode === "developer" && baseUrl ? baseUrl : null
    });
  };

  const submitProvider = () => {
    if (!selectedModel || !selectedModelCanRun) return;
    const capabilities = selectedModel.capabilities ?? {};
    createProvider.mutate({
      name: providerName.trim() || automaticProviderName(protocol, selectedModel),
      protocol,
      api_key: apiKey || null,
      base_url: discoverModels.data?.base_url ?? (mode === "developer" && baseUrl ? baseUrl : null),
      default_model: selectedModel.id,
      max_concurrent_requests: parseBoundedInteger(maxConcurrentRequests, 1, 32, 1),
      requests_per_minute:
        mode === "developer" ? parseOptionalBoundedInteger(requestsPerMinute, 1, 6000) : null,
      capabilities: {
        mode,
        model_discovery: true,
        selected_model_id: selectedModel.id,
        selected_model_display_name: selectedModel.display_name,
        selected_model_capabilities: capabilities,
        native_search: capabilities.native_search === true,
        streaming: capabilities.streaming !== false,
        vision: capabilities.vision === true,
        pdf: capabilities.pdf === true
      }
    });
  };

  return (
    <Stack gap="lg">
      <div>
        <Title order={1}>{t("settings.title")}</Title>
        <Text c="dimmed">{t("settings.subtitle")}</Text>
      </div>

      <Tabs defaultValue="models" keepMounted={false} className="settings-tabs">
        <Tabs.List>
          <Tabs.Tab value="models">{t("settings.models")}</Tabs.Tab>
          <Tabs.Tab value="interface">{t("settings.interface")}</Tabs.Tab>
          <Tabs.Tab value="memory">{t("settings.memory")}</Tabs.Tab>
          <Tabs.Tab value="tools">{t("settings.tools")}</Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="models">
          <div className="panel settings-panel">
            <Group justify="space-between" align="flex-start">
              <div>
                <Title order={3}>{t("settings.connectModel")}</Title>
                <Text c="dimmed" size="sm">
                  {t("settings.connectModelHelp", { product: productName })}
                </Text>
              </div>
              <SegmentedControl
                value={mode}
                onChange={(value) => setMode(value as SettingsMode)}
                data={[
                  { label: t("settings.simple"), value: "user" },
                  { label: t("settings.advanced"), value: "developer" }
                ]}
              />
            </Group>

            <div className="provider-form-grid">
              {mode === "developer" ? (
                <TextInput
                  label={t("settings.profileLabel")}
                  placeholder={t("settings.optional")}
                  value={providerName}
                  onChange={(event) => setProviderName(event.target.value)}
                />
              ) : null}
              <Select
                label={t("settings.providerType")}
                value={protocol}
                onChange={(value) => {
                  if (value === "openai-compatible" || value === "anthropic-compatible") {
                    setProtocol(value);
                    setSelectedModelId("");
                    discoverModels.reset();
                  }
                }}
                data={[
                  { label: "OpenAI-compatible", value: "openai-compatible" },
                  { label: "Anthropic-compatible", value: "anthropic-compatible" }
                ]}
              />
              <TextInput
                className="provider-key-input"
                label={t("settings.apiKey")}
                placeholder={t("settings.pasteKey")}
                type="password"
                value={apiKey}
                onChange={(event) => {
                  setApiKey(event.target.value);
                  setSelectedModelId("");
                  discoverModels.reset();
                }}
              />
              {mode === "developer" ? (
                <>
                  <TextInput
                    label={t("settings.baseUrl")}
                    placeholder="https://api.example.com/v1"
                    value={baseUrl}
                    onChange={(event) => {
                      setBaseUrl(event.target.value);
                      setSelectedModelId("");
                      discoverModels.reset();
                    }}
                  />
                  <TextInput
                    label={t("settings.concurrency")}
                    placeholder="1"
                    value={maxConcurrentRequests}
                    onChange={(event) => setMaxConcurrentRequests(event.target.value)}
                  />
                  <TextInput
                    label={t("settings.requestsPerMinute")}
                    placeholder={t("settings.optional")}
                    value={requestsPerMinute}
                    onChange={(event) => setRequestsPerMinute(event.target.value)}
                  />
                </>
              ) : null}
            </div>

            <Group mt="md">
              <Button
                onClick={detectModels}
                loading={discoverModels.isPending}
                disabled={!apiKey.trim()}
                variant="light"
              >
                {t("settings.findModels")}
              </Button>
              <Button
                onClick={submitProvider}
                loading={createProvider.isPending}
                disabled={!apiKey.trim() || !selectedModelCanRun}
              >
                {t("settings.useSelectedModel")}
              </Button>
            </Group>

            {discoverModels.isError ? (
              <Alert color="red" mt="md">
                {t("settings.modelDetectError")}
              </Alert>
            ) : null}
            {discoveredModels.length > 0 && runnableModelCount === 0 ? (
              <Alert color="yellow" mt="md">
                {t("settings.noRunnableModels")}
              </Alert>
            ) : null}
            {discoveredModels.length > 0 ? (
              <div className="model-list" aria-label="Detected models">
                {discoveredModels.map((model) => {
                  const runnable = isRunnableModel(model);
                  const selected = selectedModelId === model.id;
                  const displayName = model.display_name || model.id;
                  return (
                    <button
                      key={model.id}
                      type="button"
                      className={`model-choice ${selected ? "model-choice-selected" : ""}`}
                      disabled={!runnable}
                      aria-label={runnable ? `Select ${displayName}` : `${displayName} unavailable`}
                      onClick={() => setSelectedModelId(model.id)}
                    >
                      <span>
                        <Text fw={650}>{displayName}</Text>
                        <Text size="xs" c="dimmed">
                          {model.id}
                        </Text>
                      </span>
                      <Group gap="xs" justify="flex-end">
                        <Badge color={runnable ? "blue" : "gray"} variant="light">
                          {runnable ? t("settings.ready") : t("settings.unavailable")}
                        </Badge>
                        {model.capabilities?.streaming !== false ? (
                          <Badge variant="light">streaming</Badge>
                        ) : null}
                        {model.capabilities?.native_search === true ? (
                          <Badge variant="light">search</Badge>
                        ) : null}
                        {model.capabilities?.vision === true ? (
                          <Badge variant="light">vision</Badge>
                        ) : null}
                        {model.capabilities?.pdf === true ? (
                          <Badge variant="light">pdf</Badge>
                        ) : null}
                        {selected ? <Badge variant="filled">{t("settings.selected")}</Badge> : null}
                      </Group>
                    </button>
                  );
                })}
              </div>
            ) : null}

            <Text c="dimmed" size="sm" mt="md">
              {t("settings.providerStorageNotice")}
            </Text>
            {createProvider.isError ? (
              <Text c="red" size="sm" mt="sm">
                {t("settings.providerSaveError")}
              </Text>
            ) : null}

            <div className="saved-provider-section">
              <Title order={4}>{t("settings.savedProviders")}</Title>
              {(providers.data ?? []).length === 0 ? (
                <Text c="dimmed" size="sm" mt="xs">
                  {t("settings.noProviders")}
                </Text>
              ) : (
                <div className="saved-provider-list">
                  {(providers.data ?? []).map((provider) => (
                    <div key={provider.id} className="saved-provider-row">
                      <span>
                        <Text fw={650}>{provider.name}</Text>
                        <Text size="xs" c="dimmed">
                          {provider.default_model ?? "-"} · {provider.protocol}
                        </Text>
                      </span>
                      <Group gap="xs" justify="flex-end">
                        <Badge variant="light">
                          {provider.requests_per_minute
                            ? `${provider.requests_per_minute}/min`
                            : `${provider.max_concurrent_requests ?? 1} parallel`}
                        </Badge>
                        <Badge color={provider.key_ref ? "green" : "gray"}>
                          {provider.key_ref ? t("settings.configured") : t("settings.missing")}
                        </Badge>
                      </Group>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </Tabs.Panel>

        <Tabs.Panel value="interface">
          <div className="panel settings-panel">
            <Group justify="space-between" align="flex-start">
              <div>
                <Title order={3}>{t("settings.languageTitle")}</Title>
                <Text c="dimmed" size="sm">
                  {t("settings.languageHelp")}
                </Text>
              </div>
              <Select
                label={t("settings.language")}
                value={locale}
                onChange={(value) => {
                  if (value) setLocale(value as AppLocale);
                }}
                data={SUPPORTED_LOCALES.map((item) => ({
                  value: item.value,
                  label: item.nativeLabel
                }))}
              />
            </Group>
          </div>
        </Tabs.Panel>

        <Tabs.Panel value="memory">
          <div className="panel settings-panel">
            <Group justify="space-between" align="flex-start">
              <div>
                <Title order={3}>{t("settings.memoryReview")}</Title>
                <Text c="dimmed" size="sm">
                  {t("settings.memoryReviewHelp")}
                </Text>
              </div>
              <Group align="end">
                <TextInput
                  label={t("settings.language")}
                  value={memoryTargetLanguage}
                  onChange={(event) => setMemoryTargetLanguage(event.target.value)}
                />
                <Select
                  label={t("settings.reviewStatus")}
                  value={memoryReviewStatus}
                  onChange={(value) => {
                    if (value === "pending" || value === "approved" || value === "rejected") {
                      setMemoryReviewStatus(value);
                    }
                  }}
                  data={[
                    { value: "pending", label: t("settings.pending") },
                    { value: "approved", label: t("settings.approved") },
                    { value: "rejected", label: t("settings.rejected") }
                  ]}
                />
              </Group>
            </Group>

            {memory.isError ? (
              <Alert color="yellow" mt="md">
                {t("settings.memoryLoadError")}
              </Alert>
            ) : null}

            {(memory.data?.entries ?? []).length === 0 ? (
              <Text c="dimmed" size="sm" mt="md">
                {t("settings.noMemory")}
              </Text>
            ) : (
              <Table mt="md" verticalSpacing="sm" className="memory-review-table">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>{t("settings.source")}</Table.Th>
                    <Table.Th>{t("settings.translation")}</Table.Th>
                    <Table.Th>{t("library.status")}</Table.Th>
                    <Table.Th>{t("library.updated")}</Table.Th>
                    <Table.Th>{t("settings.actions")}</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {(memory.data?.entries ?? []).map((entry) => (
                    <Table.Tr key={entry.id}>
                      <Table.Td>
                        <Text size="sm" lineClamp={3}>
                          {entry.source_markdown}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm" lineClamp={3}>
                          {entry.raw_markdown}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Stack gap={4}>
                          <Badge color={memoryStatusColor(entry.review_status)} variant="light">
                            {entry.review_status}
                          </Badge>
                          <Badge color={entry.reuse_enabled ? "green" : "gray"} variant="light">
                            {entry.reuse_enabled ? "reuse on" : "reuse off"}
                          </Badge>
                        </Stack>
                      </Table.Td>
                      <Table.Td>
                        <Text size="xs" c="dimmed">
                          {new Date(entry.updated_at).toLocaleString()}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Group gap="xs">
                          <Button
                            size="xs"
                            variant="light"
                            onClick={() =>
                              updateMemory.mutate({
                                entryId: entry.id,
                                payload: { review_status: "approved", reuse_enabled: true }
                              })
                            }
                          >
                            {t("settings.approve")}
                          </Button>
                          <Button
                            size="xs"
                            variant="subtle"
                            onClick={() =>
                              updateMemory.mutate({
                                entryId: entry.id,
                                payload: { reuse_enabled: false }
                              })
                            }
                          >
                            {t("settings.disable")}
                          </Button>
                          <Button
                            size="xs"
                            color="red"
                            variant="subtle"
                            onClick={() =>
                              updateMemory.mutate({
                                entryId: entry.id,
                                payload: { review_status: "rejected", reuse_enabled: false }
                              })
                            }
                          >
                            {t("settings.reject")}
                          </Button>
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            )}
          </div>
        </Tabs.Panel>

        <Tabs.Panel value="tools">
          <div className="panel">
            <Title order={3}>{t("settings.tools")}</Title>
            <Text c="dimmed" size="sm">
              {t("settings.localToolsHelp", { product: productName })}
            </Text>
            {doctor.isError ? (
              <Alert color="yellow" mt="md">
                {t("settings.toolsApiError")}
              </Alert>
            ) : null}
            <Table mt="md">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>{t("settings.tool")}</Table.Th>
                  <Table.Th>{t("library.status")}</Table.Th>
                  <Table.Th>{t("settings.level")}</Table.Th>
                  <Table.Th>{t("library.path")}</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {(doctor.data?.capabilities ?? []).map((capability) => (
                  <Table.Tr key={capability.tool_name}>
                    <Table.Td>{capability.tool_name}</Table.Td>
                    <Table.Td>
                      <Badge color={capability.status === "available" ? "green" : "gray"}>
                        {capability.status}
                      </Badge>
                    </Table.Td>
                    <Table.Td>{capability.level}</Table.Td>
                    <Table.Td>{capability.path ?? "-"}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </div>
        </Tabs.Panel>
      </Tabs>
    </Stack>
  );
}

function automaticProviderName(protocol: ProviderProtocol, model: ProviderModelInfo): string {
  const provider =
    protocol === "anthropic-compatible" ? "Anthropic-compatible" : "OpenAI-compatible";
  return `${provider} · ${model.display_name || model.id}`;
}

function isRunnableModel(model: ProviderModelInfo): boolean {
  return model.capabilities?.chat !== false && model.capabilities?.translation !== false;
}

function memoryStatusColor(status: TranslationMemoryReviewStatus): string {
  if (status === "approved") return "green";
  if (status === "rejected") return "red";
  return "yellow";
}

function parseBoundedInteger(value: string, min: number, max: number, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseOptionalBoundedInteger(value: string, min: number, max: number): number | null {
  if (!value.trim()) return null;
  return parseBoundedInteger(value, min, max, min);
}
