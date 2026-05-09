import {
  Copy,
  FileInput,
  MessageSquare,
  RefreshCw,
  ScrollText,
  StickyNote,
  Terminal
} from "lucide-react";
import type { ReactNode } from "react";
import type { MessageKey } from "../i18n";

export type ToolbarKind = "source" | "translation" | "environment";
export type ReaderToolbarActionId =
  | "copy-source"
  | "copy-obsidian"
  | "ask-source"
  | "create-card"
  | "show-latex"
  | "copy-translation"
  | "retranslate"
  | "add-note-patch"
  | "copy-block"
  | "explain-block"
  | "show-source";

export interface ToolbarActionDefinition {
  id: ReaderToolbarActionId;
  labelKey: MessageKey;
  icon: ReactNode;
}

const iconSize = 15;

export const READER_TOOLBAR_ACTIONS: Record<ToolbarKind, ToolbarActionDefinition[]> = {
  source: [
    { id: "copy-source", labelKey: "toolbar.copySource", icon: <Copy size={iconSize} /> },
    { id: "copy-obsidian", labelKey: "toolbar.copyObsidian", icon: <FileInput size={iconSize} /> },
    { id: "ask-source", labelKey: "toolbar.askSource", icon: <MessageSquare size={iconSize} /> },
    { id: "create-card", labelKey: "toolbar.createCard", icon: <StickyNote size={iconSize} /> },
    { id: "show-latex", labelKey: "toolbar.showLatex", icon: <Terminal size={iconSize} /> }
  ],
  translation: [
    { id: "copy-translation", labelKey: "toolbar.copyTranslation", icon: <Copy size={iconSize} /> },
    { id: "retranslate", labelKey: "toolbar.retranslate", icon: <RefreshCw size={iconSize} /> },
    { id: "add-note-patch", labelKey: "toolbar.addNotePatch", icon: <ScrollText size={iconSize} /> }
  ],
  environment: [
    { id: "copy-block", labelKey: "toolbar.copyBlock", icon: <Copy size={iconSize} /> },
    {
      id: "explain-block",
      labelKey: "toolbar.explainBlock",
      icon: <MessageSquare size={iconSize} />
    },
    { id: "show-source", labelKey: "toolbar.showSource", icon: <Terminal size={iconSize} /> }
  ]
};
