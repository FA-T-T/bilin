import { Copy, MessageSquare, RefreshCw, ScrollText, Terminal } from "lucide-react";
import type { ReactNode } from "react";

export type ToolbarKind = "source" | "translation" | "environment";
export type ReaderToolbarActionId =
  | "copy-source"
  | "ask-source"
  | "show-latex"
  | "copy-translation"
  | "retranslate"
  | "add-note-patch"
  | "copy-block"
  | "explain-block"
  | "show-source";

export interface ToolbarActionDefinition {
  id: ReaderToolbarActionId;
  label: string;
  icon: ReactNode;
}

const iconSize = 15;

export const READER_TOOLBAR_ACTIONS: Record<ToolbarKind, ToolbarActionDefinition[]> = {
  source: [
    { id: "copy-source", label: "Copy source", icon: <Copy size={iconSize} /> },
    { id: "ask-source", label: "Ask about source", icon: <MessageSquare size={iconSize} /> },
    { id: "show-latex", label: "Show LaTeX", icon: <Terminal size={iconSize} /> }
  ],
  translation: [
    { id: "copy-translation", label: "Copy translation", icon: <Copy size={iconSize} /> },
    { id: "retranslate", label: "Retranslate", icon: <RefreshCw size={iconSize} /> },
    { id: "add-note-patch", label: "Add note patch", icon: <ScrollText size={iconSize} /> }
  ],
  environment: [
    { id: "copy-block", label: "Copy block", icon: <Copy size={iconSize} /> },
    { id: "explain-block", label: "Explain block", icon: <MessageSquare size={iconSize} /> },
    { id: "show-source", label: "Show source", icon: <Terminal size={iconSize} /> }
  ]
};
