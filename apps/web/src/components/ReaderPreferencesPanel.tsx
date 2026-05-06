import { Button, Group, Slider, Stack, Text, Title } from "@mantine/core";
import { RotateCcw } from "lucide-react";

import { useT, type MessageKey } from "../i18n";
import { type ReaderPreferenceKey, type ReaderPreferences, useUiStore } from "../state/ui";

interface ReaderPreferencesPanelProps {
  compact?: boolean;
  showTitle?: boolean;
}

interface PreferenceControl {
  key: ReaderPreferenceKey;
  labelKey: MessageKey;
  helpKey: MessageKey;
  min: number;
  max: number;
  step: number;
  valueLabel: (value: number) => string;
}

const controls: PreferenceControl[] = [
  {
    key: "lineWidthPercent",
    labelKey: "reader.prefLineWidth",
    helpKey: "reader.prefLineWidthHelp",
    min: 52,
    max: 86,
    step: 1,
    valueLabel: (value) => `${Math.round(value)}%`
  },
  {
    key: "fontScale",
    labelKey: "reader.prefFontScale",
    helpKey: "reader.prefFontScaleHelp",
    min: 0.9,
    max: 1.18,
    step: 0.01,
    valueLabel: (value) => `${Math.round(value * 100)}%`
  },
  {
    key: "paragraphSpacingEm",
    labelKey: "reader.prefParagraphSpacing",
    helpKey: "reader.prefParagraphSpacingHelp",
    min: 0.16,
    max: 0.8,
    step: 0.02,
    valueLabel: (value) => `${value.toFixed(2)} em`
  },
  {
    key: "bilingualSourceRatio",
    labelKey: "reader.prefBilingualRatio",
    helpKey: "reader.prefBilingualRatioHelp",
    min: 0.5,
    max: 0.72,
    step: 0.01,
    valueLabel: (value) => `${Math.round(value * 100)}:${Math.round((1 - value) * 100)}`
  }
];

export function ReaderPreferencesPanel({
  compact = false,
  showTitle = true
}: ReaderPreferencesPanelProps) {
  const t = useT();
  const preferences = useUiStore((state) => state.readerPreferences);
  const setReaderPreference = useUiStore((state) => state.setReaderPreference);
  const resetReaderPreferences = useUiStore((state) => state.resetReaderPreferences);

  return (
    <section
      className={`reader-preferences-panel${compact ? " reader-preferences-panel-compact" : ""}`}
      aria-label={t("reader.preferences")}
    >
      {showTitle ? (
        <Group justify="space-between" align="flex-start" className="reader-preferences-header">
          <div>
            <Title order={compact ? 5 : 3}>{t("reader.preferences")}</Title>
            <Text c="dimmed" size="sm">
              {t("reader.preferencesHelp")}
            </Text>
          </div>
          <Button
            variant="subtle"
            size="xs"
            leftSection={<RotateCcw size={14} aria-hidden="true" />}
            onClick={resetReaderPreferences}
          >
            {t("reader.resetPreferences")}
          </Button>
        </Group>
      ) : null}
      <div className="reader-preference-grid">
        {controls.map((control) => (
          <PreferenceSlider
            control={control}
            key={control.key}
            preferences={preferences}
            onChange={setReaderPreference}
          />
        ))}
      </div>
      {!showTitle ? (
        <Button
          className="reader-preferences-reset"
          variant="subtle"
          size="xs"
          leftSection={<RotateCcw size={14} aria-hidden="true" />}
          onClick={resetReaderPreferences}
        >
          {t("reader.resetPreferences")}
        </Button>
      ) : null}
    </section>
  );
}

function PreferenceSlider({
  control,
  preferences,
  onChange
}: {
  control: PreferenceControl;
  preferences: ReaderPreferences;
  onChange: <Key extends ReaderPreferenceKey>(key: Key, value: ReaderPreferences[Key]) => void;
}) {
  const t = useT();
  const value = preferences[control.key];
  return (
    <Stack gap={6} className="reader-preference-control">
      <Group justify="space-between" gap="sm" wrap="nowrap">
        <Text fw={650} size="sm">
          {t(control.labelKey)}
        </Text>
        <Text className="reader-preference-value" size="xs">
          {control.valueLabel(value)}
        </Text>
      </Group>
      <Slider
        thumbLabel={t(control.labelKey)}
        value={value}
        min={control.min}
        max={control.max}
        step={control.step}
        label={control.valueLabel}
        onChange={(nextValue) => onChange(control.key, nextValue)}
      />
      <Text c="dimmed" size="xs">
        {t(control.helpKey)}
      </Text>
    </Stack>
  );
}
