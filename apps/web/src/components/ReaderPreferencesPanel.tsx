import { Button, Divider, Group, Slider, Stack, Switch, Text, Title } from "@mantine/core";
import { RotateCcw } from "lucide-react";

import { useT, type MessageKey } from "../i18n";
import {
  type ReaderFeaturePreferenceKey,
  type ReaderFeaturePreferences,
  type ReaderPreferenceKey,
  type ReaderPreferences,
  useUiStore
} from "../state/ui";

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

interface FeatureControl {
  key: ReaderFeaturePreferenceKey;
  labelKey: MessageKey;
  helpKey: MessageKey;
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

const featureControls: FeatureControl[] = [
  {
    key: "chapterIndexVisible",
    labelKey: "reader.featureChapterIndex",
    helpKey: "reader.featureChapterIndexHelp"
  },
  {
    key: "bottomProgressVisible",
    labelKey: "reader.featureBottomProgress",
    helpKey: "reader.featureBottomProgressHelp"
  },
  {
    key: "blockToolsEnabled",
    labelKey: "reader.featureBlockTools",
    helpKey: "reader.featureBlockToolsHelp"
  },
  {
    key: "colorMarkersEnabled",
    labelKey: "reader.featureColorMarkers",
    helpKey: "reader.featureColorMarkersHelp"
  },
  {
    key: "termCardsEnabled",
    labelKey: "reader.featureTermCards",
    helpKey: "reader.featureTermCardsHelp"
  },
  {
    key: "quickAskEnabled",
    labelKey: "reader.featureQuickAsk",
    helpKey: "reader.featureQuickAskHelp"
  },
  {
    key: "sentenceHoverAccentEnabled",
    labelKey: "reader.featureSentenceHover",
    helpKey: "reader.featureSentenceHoverHelp"
  },
  {
    key: "citationPreviewEnabled",
    labelKey: "reader.featureCitationPreview",
    helpKey: "reader.featureCitationPreviewHelp"
  },
  {
    key: "imageLightboxEnabled",
    labelKey: "reader.featureImageLightbox",
    helpKey: "reader.featureImageLightboxHelp"
  },
  {
    key: "watermarkVisible",
    labelKey: "reader.featureWatermark",
    helpKey: "reader.featureWatermarkHelp"
  },
  {
    key: "taskNotificationsEnabled",
    labelKey: "reader.featureTaskNotifications",
    helpKey: "reader.featureTaskNotificationsHelp"
  },
  {
    key: "glossaryReplacementEnabled",
    labelKey: "reader.featureGlossaryReplacement",
    helpKey: "reader.featureGlossaryReplacementHelp"
  },
  {
    key: "includeUntranslatedInExport",
    labelKey: "reader.featureIncludeUntranslatedExport",
    helpKey: "reader.featureIncludeUntranslatedExportHelp"
  }
];

export function ReaderPreferencesPanel({
  compact = false,
  showTitle = true
}: ReaderPreferencesPanelProps) {
  const t = useT();
  const preferences = useUiStore((state) => state.readerPreferences);
  const featurePreferences = useUiStore((state) => state.readerFeaturePreferences);
  const setReaderPreference = useUiStore((state) => state.setReaderPreference);
  const setReaderFeaturePreference = useUiStore((state) => state.setReaderFeaturePreference);
  const resetReaderPreferences = useUiStore((state) => state.resetReaderPreferences);
  const resetReaderFeaturePreferences = useUiStore((state) => state.resetReaderFeaturePreferences);
  const resetAllReaderPreferences = () => {
    resetReaderPreferences();
    resetReaderFeaturePreferences();
  };

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
            onClick={resetAllReaderPreferences}
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
      <Divider className="reader-preferences-divider" />
      <Stack gap="xs" className="reader-feature-switches">
        <div>
          <Text fw={700} size="sm">
            {t("reader.featureToggles")}
          </Text>
          <Text c="dimmed" size="xs">
            {t("reader.featureTogglesHelp")}
          </Text>
        </div>
        {featureControls.map((control) => (
          <FeatureSwitch
            control={control}
            key={control.key}
            preferences={featurePreferences}
            onChange={setReaderFeaturePreference}
          />
        ))}
      </Stack>
      {!showTitle ? (
        <Button
          className="reader-preferences-reset"
          variant="subtle"
          size="xs"
          leftSection={<RotateCcw size={14} aria-hidden="true" />}
          onClick={resetAllReaderPreferences}
        >
          {t("reader.resetPreferences")}
        </Button>
      ) : null}
    </section>
  );
}

function FeatureSwitch({
  control,
  preferences,
  onChange
}: {
  control: FeatureControl;
  preferences: ReaderFeaturePreferences;
  onChange: <Key extends ReaderFeaturePreferenceKey>(
    key: Key,
    value: ReaderFeaturePreferences[Key]
  ) => void;
}) {
  const t = useT();
  return (
    <Switch
      className="reader-feature-switch"
      checked={preferences[control.key]}
      label={t(control.labelKey)}
      description={t(control.helpKey)}
      onChange={(event) => onChange(control.key, event.currentTarget.checked)}
    />
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
