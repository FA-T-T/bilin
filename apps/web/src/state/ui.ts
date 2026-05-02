import { create } from "zustand";

export type ReaderViewMode = "study" | "focus" | "bilingual" | "translation" | "source";

interface UiState {
  taskDrawerOpen: boolean;
  readerViewMode: ReaderViewMode;
  openTaskDrawer: () => void;
  closeTaskDrawer: () => void;
  setReaderViewMode: (mode: ReaderViewMode) => void;
}

export const useUiStore = create<UiState>((set) => ({
  taskDrawerOpen: false,
  readerViewMode: "study",
  openTaskDrawer: () => set({ taskDrawerOpen: true }),
  closeTaskDrawer: () => set({ taskDrawerOpen: false }),
  setReaderViewMode: (mode) => set({ readerViewMode: mode })
}));
