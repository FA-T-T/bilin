import { create } from "zustand";
import type { AppLocale } from "../product";
import { normalizeLocale } from "../product";

export type ReaderViewMode = "study" | "focus" | "bilingual" | "translation" | "source";

interface UiState {
  locale: AppLocale;
  taskDrawerOpen: boolean;
  readerViewMode: ReaderViewMode;
  setLocale: (locale: AppLocale) => void;
  openTaskDrawer: () => void;
  closeTaskDrawer: () => void;
  setReaderViewMode: (mode: ReaderViewMode) => void;
}

const localeStorageKey = "iiios-ui-locale";

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

export const useUiStore = create<UiState>((set) => ({
  locale: initialLocale(),
  taskDrawerOpen: false,
  readerViewMode: "study",
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
  setReaderViewMode: (mode) => set({ readerViewMode: mode })
}));
