import { create } from "zustand";
import type { AppLocale } from "../product";
import { normalizeLocale } from "../product";

export type ReaderViewMode = "study" | "bilingual" | "translation" | "source";

export interface ReaderPreferences {
  lineWidthPercent: number;
  fontScale: number;
  paragraphSpacingEm: number;
  bilingualSourceRatio: number;
}

export type ReaderPreferenceKey = keyof ReaderPreferences;

interface UiState {
  locale: AppLocale;
  taskDrawerOpen: boolean;
  readerViewMode: ReaderViewMode;
  readerPreferences: ReaderPreferences;
  setLocale: (locale: AppLocale) => void;
  openTaskDrawer: () => void;
  closeTaskDrawer: () => void;
  setReaderViewMode: (mode: ReaderViewMode) => void;
  setReaderPreference: <Key extends ReaderPreferenceKey>(
    key: Key,
    value: ReaderPreferences[Key]
  ) => void;
  resetReaderPreferences: () => void;
}

const localeStorageKey = "iiios-ui-locale";
const readerPreferencesStorageKey = "iiios-reader-preferences";

export const defaultReaderPreferences: ReaderPreferences = {
  lineWidthPercent: 66,
  fontScale: 1,
  paragraphSpacingEm: 0.34,
  bilingualSourceRatio: 0.6
};

function initialLocale(): AppLocale {
  try {
    const stored = globalThis.localStorage?.getItem(localeStorageKey);
    if (stored) return normalizeLocale(stored);
  } catch {
    // Ignore storage errors and fall back to browser language.
  }
  const language =
    typeof globalThis.navigator === "undefined" ? undefined : globalThis.navigator.language;
  return normalizeLocale(language);
}

function initialReaderPreferences(): ReaderPreferences {
  try {
    const raw = globalThis.localStorage?.getItem(readerPreferencesStorageKey);
    if (!raw) return defaultReaderPreferences;
    const parsed = JSON.parse(raw) as Partial<ReaderPreferences>;
    return normalizeReaderPreferences(parsed);
  } catch {
    return defaultReaderPreferences;
  }
}

function normalizeReaderPreferences(
  value: Partial<ReaderPreferences> | undefined
): ReaderPreferences {
  const legacyValue = value as Partial<ReaderPreferences> & { lineWidthPx?: number };
  const lineWidthPercent =
    typeof value?.lineWidthPercent === "number"
      ? value.lineWidthPercent
      : legacyLineWidthPercent(legacyValue.lineWidthPx);
  return {
    lineWidthPercent: clampNumber(
      lineWidthPercent,
      52,
      86,
      defaultReaderPreferences.lineWidthPercent
    ),
    fontScale: clampNumber(value?.fontScale, 0.9, 1.18, defaultReaderPreferences.fontScale),
    paragraphSpacingEm: clampNumber(
      value?.paragraphSpacingEm,
      0.16,
      0.8,
      defaultReaderPreferences.paragraphSpacingEm
    ),
    bilingualSourceRatio: clampNumber(
      value?.bilingualSourceRatio,
      0.5,
      0.72,
      defaultReaderPreferences.bilingualSourceRatio
    )
  };
}

function legacyLineWidthPercent(lineWidthPx: number | undefined): number | undefined {
  if (typeof lineWidthPx !== "number" || !Number.isFinite(lineWidthPx)) return undefined;
  return Math.round((lineWidthPx / 1240) * 100);
}

function clampNumber(
  value: number | undefined,
  min: number,
  max: number,
  fallback: number
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, value));
}

function saveReaderPreferences(preferences: ReaderPreferences) {
  try {
    globalThis.localStorage?.setItem(readerPreferencesStorageKey, JSON.stringify(preferences));
  } catch {
    // Reading preferences remain usable in memory if localStorage is unavailable.
  }
}

export const useUiStore = create<UiState>((set) => ({
  locale: initialLocale(),
  taskDrawerOpen: false,
  readerViewMode: "study",
  readerPreferences: initialReaderPreferences(),
  setLocale: (locale) => {
    try {
      globalThis.localStorage?.setItem(localeStorageKey, locale);
    } catch {
      // Language switching should still work if localStorage is unavailable.
    }
    set({ locale });
  },
  openTaskDrawer: () => set({ taskDrawerOpen: true }),
  closeTaskDrawer: () => set({ taskDrawerOpen: false }),
  setReaderViewMode: (mode) => set({ readerViewMode: mode }),
  setReaderPreference: (key, value) =>
    set((state) => {
      const next = normalizeReaderPreferences({
        ...state.readerPreferences,
        [key]: value
      });
      saveReaderPreferences(next);
      return { readerPreferences: next };
    }),
  resetReaderPreferences: () => {
    saveReaderPreferences(defaultReaderPreferences);
    set({ readerPreferences: defaultReaderPreferences });
  }
}));
