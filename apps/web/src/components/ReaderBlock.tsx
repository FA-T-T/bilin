import { Badge, Button, Group, HoverCard, Select, Text, Textarea, Tooltip } from "@mantine/core";
import katex from "katex";
import { ExternalLink, Languages, Pencil, Pin, Send, Sparkles, Trash2, Upload } from "lucide-react";
import {
  Children,
  cloneElement,
  Fragment,
  memo,
  type CSSProperties,
  type FocusEvent,
  isValidElement,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
  useEffect,
  useCallback,
  useMemo,
  useRef,
  useState
} from "react";
import { createPortal } from "react-dom";
import ReactMarkdown from "react-markdown";

import type { AssetRecord, CitationEntry, DocumentBlock, ReaderCard } from "../api/types";
import { useT, type MessageKey } from "../i18n";
import type { ReaderViewMode } from "../state/ui";
import { HoverToolbar } from "./HoverToolbar";
import type { ReaderToolbarActionId } from "./readerToolbarActions";
import latexCompatibilityTable from "../../../../shared/latex-compatibility.json";

export interface ReferenceTarget {
  blockUid: string;
  blockType: string;
}

export type ReferenceTargets = Record<string, ReferenceTarget>;
export type CitationLookup = Record<string, CitationEntry>;
export type CitationImportMode = "add" | "add-and-translate";
export type ReaderBlockColor = "none" | "yellow" | "blue" | "green" | "pink" | "purple";

export interface ReaderAssetFile {
  index: number;
  originalReference: string;
  url: string;
  metadata?: AssetRecord["metadata"];
}

class BoundedCache<Value> {
  private readonly values = new Map<string, Value>();

  constructor(private readonly limit: number) {}

  get(key: string): Value | undefined {
    const value = this.values.get(key);
    if (value === undefined) return undefined;
    this.values.delete(key);
    this.values.set(key, value);
    return value;
  }

  set(key: string, value: Value): Value {
    if (this.values.has(key)) this.values.delete(key);
    this.values.set(key, value);
    if (this.values.size > this.limit) {
      const firstKey = this.values.keys().next().value;
      if (firstKey !== undefined) this.values.delete(firstKey);
    }
    return value;
  }
}

const katexRenderCache = new BoundedCache<string>(500);
const sentenceRangeCache = new BoundedCache<TextRange[]>(800);
const linkedContentCache = new BoundedCache<string>(600);
const sanitizedHtmlCache = new BoundedCache<string>(120);

interface LatexCommandGroupRule {
  commands: string[];
  group_count: number;
  strategy: "template" | "unwrap" | "keep_arg";
  replacement?: string;
  keep_arg_index?: number;
  allow_single_token?: boolean;
}

interface LegacyTextFontCommand {
  command: string;
  text_replacement: string;
  math_replacement: string;
}

const latexCompatibilityCommandGroupRules =
  latexCompatibilityTable.command_group_rules as LatexCommandGroupRule[];
const latexCompatibilitySingleTokenCommands = latexCompatibilityCommandGroupRules.flatMap((rule) =>
  rule.allow_single_token ? rule.commands : []
);
const legacyTextFontCommands = Object.fromEntries(
  (latexCompatibilityTable.legacy_text_font_commands as LegacyTextFontCommand[]).map((entry) => [
    entry.command,
    [entry.text_replacement, entry.math_replacement] as const
  ])
) as Record<string, readonly [string, string]>;

interface ReaderBlockProps {
  block: DocumentBlock;
  asset?: AssetRecord;
  assetUrl?: string;
  assetFileUrls?: ReaderAssetFile[];
  referenceTargets?: ReferenceTargets;
  citations?: CitationLookup;
  citationImportPending?: boolean;
  canImportCitationWithTranslation?: boolean;
  onCitationImport?: (citation: CitationEntry, mode: CitationImportMode) => void;
  translation?: string;
  translationVariantOptions?: { value: string; label: string }[];
  selectedTranslationVariantId?: string;
  glossaryAffected?: boolean;
  viewMode: ReaderViewMode;
  active?: boolean;
  controlsVisible?: boolean;
  blockToolsEnabled?: boolean;
  colorMarkersEnabled?: boolean;
  sentenceHoverAccentEnabled?: boolean;
  imageLightboxEnabled?: boolean;
  searchActive?: boolean;
  blockColor?: ReaderBlockColor;
  termWikiEnabled?: boolean;
  readerCards?: ReaderCard[];
  expandedReaderCardId?: string | null;
  onActivate?: (blockUid: string) => void;
  onBlockColorChange?: (blockUid: string, color: ReaderBlockColor) => void;
  onTranslationVariantChange?: (blockUid: string, variantId: string) => void;
  onReaderCardToggle?: (blockUid: string, cardId: string) => void;
  onReaderCardGenerate?: (card: ReaderCard) => void;
  onReaderCardEdit?: (card: ReaderCard) => void;
  onReaderCardPin?: (card: ReaderCard) => void;
  onReaderCardDelete?: (card: ReaderCard) => void;
  onReaderCardExport?: (card: ReaderCard) => void;
  canQuickAsk?: boolean;
  quickAskPending?: boolean;
  onQuickAsk?: (block: DocumentBlock, question: string) => void;
  onToolbarAction?: (
    actionId: ReaderToolbarActionId,
    block: DocumentBlock,
    content: string
  ) => void;
}

export const ReaderBlock = memo(function ReaderBlock({
  block,
  asset,
  assetUrl,
  assetFileUrls = [],
  referenceTargets = {},
  citations = {},
  citationImportPending = false,
  canImportCitationWithTranslation = false,
  onCitationImport,
  translation,
  translationVariantOptions = [],
  selectedTranslationVariantId,
  glossaryAffected = false,
  viewMode,
  active = false,
  controlsVisible = false,
  blockToolsEnabled = true,
  colorMarkersEnabled = true,
  sentenceHoverAccentEnabled = true,
  imageLightboxEnabled = true,
  searchActive = false,
  blockColor = "none",
  termWikiEnabled = false,
  readerCards = [],
  expandedReaderCardId = null,
  onActivate,
  onBlockColorChange,
  onTranslationVariantChange,
  onReaderCardToggle,
  onReaderCardGenerate,
  onReaderCardEdit,
  onReaderCardPin,
  onReaderCardDelete,
  onReaderCardExport,
  canQuickAsk = false,
  quickAskPending = false,
  onQuickAsk,
  onToolbarAction
}: ReaderBlockProps) {
  const t = useT();
  const displayBlock = displayBlockForReader(block, asset);
  const activateBlock = useCallback(
    () => onActivate?.(block.block_uid),
    [block.block_uid, onActivate]
  );
  const [translationExpanded, setTranslationExpanded] = useState(false);
  const [localControlsVisible, setLocalControlsVisible] = useState(false);
  const blockElementRef = useRef<HTMLElement | null>(null);
  const translationOpen = translationExpanded;
  const translationText = translation ?? "";
  const effectiveBlockColor = colorMarkersEnabled ? blockColor : "none";
  const colorClass =
    effectiveBlockColor === "none" ? "" : ` reader-block-color-${effectiveBlockColor}`;
  const visibleControls = controlsVisible || localControlsVisible;
  const visibleBlockTools = visibleControls && blockToolsEnabled;
  const visibleColorControls = visibleControls && colorMarkersEnabled;
  const controlsClass = visibleControls ? " reader-block-controls-visible" : "";
  const searchClass = searchActive ? " reader-block-search-current" : "";
  const cardRail = (
    <ReaderCardRail
      blockUid={block.block_uid}
      cards={readerCards}
      enabled={termWikiEnabled}
      expandedCardId={expandedReaderCardId}
      onToggle={onReaderCardToggle}
      onGenerate={onReaderCardGenerate}
      onEdit={onReaderCardEdit}
      onPin={onReaderCardPin}
      onDelete={onReaderCardDelete}
      onExport={onReaderCardExport}
    />
  );
  const quickAskCard =
    visibleControls && displayBlock.block_type === "paragraph" && onQuickAsk ? (
      <ReaderQuickAskCard
        block={displayBlock}
        canAsk={canQuickAsk}
        pending={quickAskPending}
        onAsk={onQuickAsk}
      />
    ) : null;
  const environmentTranslation = environmentTranslationForReader(displayBlock, translation);
  const sentenceHighlightPlan = sentenceHoverAccentEnabled
    ? createSentenceHighlightPlan(displayBlock, translationText, viewMode)
    : undefined;
  const lastPointerToggleAt = useRef(0);
  const showEnvironmentTranslation =
    Boolean(environmentTranslation) && displayBlock.block_type !== "equation";
  const toggleTranslationLabel = translationOpen
    ? t("reader.hideTranslation")
    : t("reader.showTranslation");
  const pointerInsideControlsBoundary = useCallback((clientX: number, clientY: number) => {
    const root = blockElementRef.current;
    if (!root) return false;
    const controlElements = root.querySelectorAll<HTMLElement>(
      ".hover-toolbar, .block-color-palette, .reader-quick-ask-card, .reader-card-rail"
    );
    const rects = [
      root.getBoundingClientRect(),
      ...Array.from(controlElements, (element) => element.getBoundingClientRect())
    ];
    if (!rects.some((rect) => measurableRect(rect))) return true;
    return rects.some((rect) => pointInExpandedRect(rect, clientX, clientY, 12));
  }, []);
  const showControls = () => {
    setLocalControlsVisible(true);
  };
  const hideControls = () => {
    setLocalControlsVisible(false);
  };
  useEffect(() => {
    if (!localControlsVisible) return undefined;
    const hideWhenPointerLeavesBoundary = (event: PointerEvent) => {
      if (!pointerInsideControlsBoundary(event.clientX, event.clientY)) {
        hideControls();
      }
    };
    window.addEventListener("pointermove", hideWhenPointerLeavesBoundary, { passive: true });
    window.addEventListener("pointerdown", hideWhenPointerLeavesBoundary, { passive: true });
    window.addEventListener("blur", hideControls);
    return () => {
      window.removeEventListener("pointermove", hideWhenPointerLeavesBoundary);
      window.removeEventListener("pointerdown", hideWhenPointerLeavesBoundary);
      window.removeEventListener("blur", hideControls);
    };
  }, [localControlsVisible, pointerInsideControlsBoundary]);
  const activateFromPointer = (event: ReactPointerEvent<HTMLElement>) => {
    if (
      event.target instanceof Element &&
      event.target.closest("a, button, [role='button'], .citation-link, .xref-link")
    ) {
      return;
    }
    showControls();
  };
  const activateFromMouse = (event: MouseEvent<HTMLElement>) => {
    if (
      event.target instanceof Element &&
      event.target.closest("a, button, [role='button'], .citation-link, .xref-link")
    ) {
      return;
    }
    showControls();
  };
  const activateFromFocus = () => {
    showControls();
    activateBlock();
  };
  const handleBlur = (event: FocusEvent<HTMLElement>) => {
    if (event.currentTarget.contains(event.relatedTarget as Node | null)) return;
    hideControls();
  };

  if (isStructuralBlock(displayBlock)) {
    return (
      <section
        ref={blockElementRef}
        className={`reader-block structural-block structural-block-${structuralRole(displayBlock)} structural-block-level-${structuralDisplayLevel(displayBlock)}${controlsClass}${active ? " reader-block-active" : ""}${searchClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onMouseEnter={activateFromMouse}
        onMouseOver={activateFromMouse}
        onPointerEnter={activateFromPointer}
        onPointerOver={activateFromPointer}
      >
        {visibleBlockTools ? (
          <HoverToolbar
            kind="environment"
            onAction={(actionId) =>
              onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
            }
          />
        ) : null}
        <StructuralContent block={displayBlock} />
        {cardRail}
      </section>
    );
  }

  if (isStandaloneParagraphHeading(displayBlock)) {
    return (
      <section
        ref={blockElementRef}
        className={`reader-block structural-block paragraph-heading-block${controlsClass}${active ? " reader-block-active" : ""}${searchClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onMouseEnter={activateFromMouse}
        onMouseOver={activateFromMouse}
        onPointerEnter={activateFromPointer}
        onPointerOver={activateFromPointer}
      >
        {visibleBlockTools ? (
          <HoverToolbar
            kind="environment"
            onAction={(actionId) =>
              onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
            }
          />
        ) : null}
        <h3 className="paragraph-heading">{paragraphHeadingText(displayBlock)}</h3>
        {cardRail}
      </section>
    );
  }

  if (["equation", "figure", "table", "algorithm"].includes(displayBlock.block_type)) {
    return (
      <section
        ref={blockElementRef}
        className={`reader-block environment-block environment-block-${displayBlock.block_type} environment-block-${viewMode}${controlsClass}${active ? " reader-block-active" : ""}${searchClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onMouseEnter={activateFromMouse}
        onMouseOver={activateFromMouse}
        onPointerEnter={activateFromPointer}
        onPointerOver={activateFromPointer}
      >
        {visibleBlockTools ? (
          <HoverToolbar
            kind="environment"
            onAction={(actionId) =>
              onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
            }
          />
        ) : null}
        {["figure", "table"].includes(displayBlock.block_type) ? (
          <AssetPreview
            kind={displayBlock.block_type}
            asset={asset}
            assetUrl={assetUrl}
            assetFileUrls={assetFileUrls}
            referenceTargets={referenceTargets}
            imageLightboxEnabled={imageLightboxEnabled}
          />
        ) : null}
        <BlockContent
          block={displayBlock}
          content={displayBlock.source_markdown}
          referenceTargets={referenceTargets}
          citations={citations}
          citationImportPending={citationImportPending}
          canImportCitationWithTranslation={canImportCitationWithTranslation}
          onCitationImport={onCitationImport}
        />
        {showEnvironmentTranslation ? (
          <div className="caption-translation">
            {glossaryAffected ? <GlossaryBadge /> : null}
            <MarkdownContent
              content={environmentTranslation ?? ""}
              referenceTargets={referenceTargets}
              citations={citations}
              citationImportPending={citationImportPending}
              canImportCitationWithTranslation={canImportCitationWithTranslation}
              onCitationImport={onCitationImport}
            />
            <TranslationVariantSelect
              blockUid={block.block_uid}
              options={translationVariantOptions}
              selectedVariantId={selectedTranslationVariantId}
              onChange={onTranslationVariantChange}
            />
          </div>
        ) : null}
        {cardRail}
      </section>
    );
  }

  if (viewMode === "study") {
    const toggleStudyTranslation = () => setTranslationExpanded((open) => !open);
    const manualStudyTranslationOpen = translationExpanded;
    const translationToggle = (
      <button
        type="button"
        className="study-translation-toggle"
        data-translation-open={translationOpen ? "true" : undefined}
        aria-label={toggleTranslationLabel}
        title={toggleTranslationLabel}
        onPointerDown={(event) => {
          event.preventDefault();
          event.stopPropagation();
          lastPointerToggleAt.current = Date.now();
          toggleStudyTranslation();
        }}
        onMouseDown={(event) => {
          event.preventDefault();
          event.stopPropagation();
          if (Date.now() - lastPointerToggleAt.current < 250) return;
          toggleStudyTranslation();
        }}
        onClick={(event) => {
          event.preventDefault();
          event.stopPropagation();
        }}
        onKeyDown={(event) => {
          if (event.key !== "Enter" && event.key !== " ") return;
          event.preventDefault();
          event.stopPropagation();
          toggleStudyTranslation();
        }}
      >
        <Languages size={14} aria-hidden="true" />
      </button>
    );
    return (
      <section
        ref={blockElementRef}
        className={`reader-block text-block study-block${manualStudyTranslationOpen ? " study-block-translation-open" : ""}${controlsClass}${active ? " reader-block-active" : ""}${searchClass}${colorClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onMouseEnter={activateFromMouse}
        onMouseOver={activateFromMouse}
        onPointerEnter={activateFromPointer}
        onPointerOver={activateFromPointer}
      >
        <article className="block-pane source-pane study-source-pane">
          <div className={`study-reading-grid${translationOpen ? " study-reading-grid-open" : ""}`}>
            <div className="study-source-content">
              <BlockColorMarker value={effectiveBlockColor} side="source" />
              {visibleColorControls ? (
                <BlockColorPalette
                  blockUid={block.block_uid}
                  value={effectiveBlockColor}
                  onChange={onBlockColorChange}
                  className="source-color-palette"
                />
              ) : null}
              {visibleBlockTools ? (
                <HoverToolbar
                  kind="source"
                  onAction={(actionId) =>
                    onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
                  }
                />
              ) : null}
              <BlockContent
                block={displayBlock}
                content={displayBlock.source_markdown}
                referenceTargets={referenceTargets}
                citations={citations}
                citationImportPending={citationImportPending}
                canImportCitationWithTranslation={canImportCitationWithTranslation}
                onCitationImport={onCitationImport}
                sentenceHighlightPlan={sentenceHighlightPlan}
                sentenceHighlightKind="source"
                trailingInline={displayBlock.block_type === "paragraph" ? translationToggle : null}
              />
            </div>
            {translationOpen ? (
              <aside className="study-translation-column">
                <section className="study-translation-panel translation-pane">
                  <BlockColorMarker value={effectiveBlockColor} side="translation" />
                  {visibleBlockTools ? (
                    <HoverToolbar
                      kind="translation"
                      disabledActions={translation ? [] : ["copy-translation"]}
                      onAction={(actionId) => onToolbarAction?.(actionId, block, translationText)}
                    />
                  ) : null}
                  {glossaryAffected ? <GlossaryBadge /> : null}
                  {translation ? (
                    <MarkdownContent
                      content={translation}
                      referenceTargets={referenceTargets}
                      citations={citations}
                      citationImportPending={citationImportPending}
                      canImportCitationWithTranslation={canImportCitationWithTranslation}
                      onCitationImport={onCitationImport}
                      sentenceHighlightPlan={sentenceHighlightPlan}
                      sentenceHighlightKind="translation"
                    />
                  ) : (
                    <p className="translation-placeholder">{t("reader.translationPending")}</p>
                  )}
                  <TranslationVariantSelect
                    blockUid={block.block_uid}
                    options={translationVariantOptions}
                    selectedVariantId={selectedTranslationVariantId}
                    onChange={onTranslationVariantChange}
                  />
                </section>
              </aside>
            ) : null}
          </div>
        </article>
        {quickAskCard}
        {cardRail}
      </section>
    );
  }

  const blockLayoutClass =
    viewMode === "bilingual" ? "paired-block" : `single-block single-block-${viewMode}`;

  return (
    <section
      ref={blockElementRef}
      className={`reader-block text-block ${blockLayoutClass}${controlsClass}${active ? " reader-block-active" : ""}${searchClass}${colorClass}`}
      id={block.block_uid}
      onBlur={handleBlur}
      onFocusCapture={activateFromFocus}
      onMouseEnter={activateFromMouse}
      onMouseOver={activateFromMouse}
      onPointerEnter={activateFromPointer}
      onPointerOver={activateFromPointer}
    >
      {viewMode !== "translation" ? (
        <article className="block-pane source-pane">
          <BlockColorMarker value={effectiveBlockColor} side="source" />
          {visibleColorControls ? (
            <BlockColorPalette
              blockUid={block.block_uid}
              value={effectiveBlockColor}
              onChange={onBlockColorChange}
              className="source-color-palette"
            />
          ) : null}
          {visibleBlockTools ? (
            <HoverToolbar
              kind="source"
              onAction={(actionId) =>
                onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
              }
            />
          ) : null}
          <BlockContent
            block={displayBlock}
            content={displayBlock.source_markdown}
            referenceTargets={referenceTargets}
            citations={citations}
            citationImportPending={citationImportPending}
            canImportCitationWithTranslation={canImportCitationWithTranslation}
            onCitationImport={onCitationImport}
            sentenceHighlightPlan={sentenceHighlightPlan}
            sentenceHighlightKind="source"
          />
        </article>
      ) : null}
      {viewMode !== "source" ? (
        <article className="block-pane translation-pane">
          <BlockColorMarker value={effectiveBlockColor} side="translation" />
          {viewMode === "translation" && visibleColorControls ? (
            <BlockColorPalette
              blockUid={block.block_uid}
              value={effectiveBlockColor}
              onChange={onBlockColorChange}
              className="translation-color-palette"
            />
          ) : null}
          {visibleBlockTools ? (
            <HoverToolbar
              kind="translation"
              disabledActions={translation ? [] : ["copy-translation"]}
              onAction={(actionId) => onToolbarAction?.(actionId, block, translation ?? "")}
            />
          ) : null}
          {glossaryAffected ? <GlossaryBadge /> : null}
          {translation ? (
            <MarkdownContent
              content={translation}
              referenceTargets={referenceTargets}
              citations={citations}
              citationImportPending={citationImportPending}
              canImportCitationWithTranslation={canImportCitationWithTranslation}
              onCitationImport={onCitationImport}
              sentenceHighlightPlan={sentenceHighlightPlan}
              sentenceHighlightKind="translation"
            />
          ) : (
            <p className="translation-placeholder">{t("reader.translationPending")}</p>
          )}
          <TranslationVariantSelect
            blockUid={block.block_uid}
            options={translationVariantOptions}
            selectedVariantId={selectedTranslationVariantId}
            onChange={onTranslationVariantChange}
          />
        </article>
      ) : null}
      {quickAskCard}
      {cardRail}
    </section>
  );
}, areReaderBlockPropsEqual);

function areReaderBlockPropsEqual(left: ReaderBlockProps, right: ReaderBlockProps) {
  return (
    left.block === right.block &&
    left.asset === right.asset &&
    left.assetUrl === right.assetUrl &&
    left.assetFileUrls === right.assetFileUrls &&
    left.referenceTargets === right.referenceTargets &&
    left.citations === right.citations &&
    left.citationImportPending === right.citationImportPending &&
    left.canImportCitationWithTranslation === right.canImportCitationWithTranslation &&
    left.onCitationImport === right.onCitationImport &&
    left.translation === right.translation &&
    left.translationVariantOptions === right.translationVariantOptions &&
    left.selectedTranslationVariantId === right.selectedTranslationVariantId &&
    left.glossaryAffected === right.glossaryAffected &&
    left.viewMode === right.viewMode &&
    left.active === right.active &&
    left.controlsVisible === right.controlsVisible &&
    left.blockToolsEnabled === right.blockToolsEnabled &&
    left.colorMarkersEnabled === right.colorMarkersEnabled &&
    left.sentenceHoverAccentEnabled === right.sentenceHoverAccentEnabled &&
    left.imageLightboxEnabled === right.imageLightboxEnabled &&
    left.searchActive === right.searchActive &&
    left.blockColor === right.blockColor &&
    left.termWikiEnabled === right.termWikiEnabled &&
    left.readerCards === right.readerCards &&
    left.expandedReaderCardId === right.expandedReaderCardId &&
    left.onActivate === right.onActivate &&
    left.onBlockColorChange === right.onBlockColorChange &&
    left.onTranslationVariantChange === right.onTranslationVariantChange &&
    left.onReaderCardToggle === right.onReaderCardToggle &&
    left.onReaderCardGenerate === right.onReaderCardGenerate &&
    left.onReaderCardEdit === right.onReaderCardEdit &&
    left.onReaderCardPin === right.onReaderCardPin &&
    left.onReaderCardDelete === right.onReaderCardDelete &&
    left.onReaderCardExport === right.onReaderCardExport &&
    left.canQuickAsk === right.canQuickAsk &&
    left.quickAskPending === right.quickAskPending &&
    left.onQuickAsk === right.onQuickAsk &&
    left.onToolbarAction === right.onToolbarAction
  );
}

function ReaderCardRail({
  blockUid,
  cards,
  enabled,
  expandedCardId,
  onToggle,
  onGenerate,
  onEdit,
  onPin,
  onDelete,
  onExport
}: {
  blockUid: string;
  cards: ReaderCard[];
  enabled: boolean;
  expandedCardId: string | null;
  onToggle?: (blockUid: string, cardId: string) => void;
  onGenerate?: (card: ReaderCard) => void;
  onEdit?: (card: ReaderCard) => void;
  onPin?: (card: ReaderCard) => void;
  onDelete?: (card: ReaderCard) => void;
  onExport?: (card: ReaderCard) => void;
}) {
  const t = useT();
  const [popoverPlacementByCardId, setPopoverPlacementByCardId] = useState<
    Record<string, CSSProperties>
  >({});
  if (!enabled || cards.length === 0) return null;
  return (
    <aside className="reader-card-rail" aria-label={t("reader.termWiki")}>
      {cards.map((card) => {
        const expanded = expandedCardId === card.id;
        return (
          <div
            className={`reader-card-slot reader-card-slot-${card.card_type}`}
            data-expanded={expanded ? "true" : undefined}
            key={card.id}
          >
            <button
              type="button"
              className="reader-card-tag"
              aria-expanded={expanded}
              aria-label={card.title}
              onClick={(event) => {
                event.stopPropagation();
                if (!expanded) {
                  const placement = readerCardPopoverPlacement(event.currentTarget);
                  setPopoverPlacementByCardId((current) => ({
                    ...current,
                    [card.id]: placement
                  }));
                }
                onToggle?.(blockUid, card.id);
              }}
            >
              {cardLabel(card)}
            </button>
            {onDelete ? (
              <Tooltip label={t("reader.cardDelete")}>
                <button
                  type="button"
                  className="reader-card-tag-delete"
                  aria-label={`${t("reader.cardDelete")}: ${card.title}`}
                  onClick={(event) => {
                    event.stopPropagation();
                    onDelete(card);
                  }}
                >
                  <Trash2 size={12} />
                </button>
              </Tooltip>
            ) : null}
            {expanded ? (
              <article className="reader-card-popover" style={popoverPlacementByCardId[card.id]}>
                <div className="reader-card-header">
                  <Text fw={700} size="sm">
                    {card.title}
                  </Text>
                  <Badge size="xs" variant="light" color={cardBadgeColor(card)}>
                    {sourceTypeLabel(card, t)}
                  </Badge>
                </div>
                {card.body_markdown.trim() ? (
                  <MarkdownContent content={card.body_markdown} referenceTargets={{}} />
                ) : (
                  <Text c="dimmed" size="sm">
                    {t("reader.termWikiEmpty")}
                  </Text>
                )}
                <div className="reader-card-footer">
                  {card.source_type === "wikipedia" && card.source_url ? (
                    <Button
                      component="a"
                      href={card.source_url}
                      target="_blank"
                      rel="noreferrer"
                      size="compact-xs"
                      variant="subtle"
                      leftSection={<ExternalLink size={13} />}
                    >
                      {t("reader.openWikiLink")}
                    </Button>
                  ) : (
                    <Text className="reader-card-ai-marker" size="xs">
                      {card.source_type === "ai_search"
                        ? t("reader.aiGeneratedMarker")
                        : t("reader.paperGeneratedMarker")}
                    </Text>
                  )}
                </div>
                <Group gap={4} wrap="nowrap" className="reader-card-actions">
                  {!card.body_markdown.trim() ? (
                    <Button
                      size="compact-xs"
                      variant="light"
                      leftSection={<Sparkles size={13} />}
                      onClick={(event) => {
                        event.stopPropagation();
                        onGenerate?.(card);
                      }}
                    >
                      {t("reader.generateCard")}
                    </Button>
                  ) : null}
                  <Tooltip label={t("reader.editCard")}>
                    <button
                      type="button"
                      className="reader-card-icon-button"
                      aria-label={t("reader.editCard")}
                      onClick={(event) => {
                        event.stopPropagation();
                        onEdit?.(card);
                      }}
                    >
                      <Pencil size={13} />
                    </button>
                  </Tooltip>
                  <Tooltip label={t("reader.cardPin")}>
                    <button
                      type="button"
                      className="reader-card-icon-button"
                      aria-label={t("reader.cardPin")}
                      onClick={(event) => {
                        event.stopPropagation();
                        onPin?.(card);
                      }}
                    >
                      <Pin size={13} />
                    </button>
                  </Tooltip>
                  <Tooltip label={t("reader.cardExport")}>
                    <button
                      type="button"
                      className="reader-card-icon-button"
                      aria-label={t("reader.cardExport")}
                      onClick={(event) => {
                        event.stopPropagation();
                        onExport?.(card);
                      }}
                    >
                      <Upload size={13} />
                    </button>
                  </Tooltip>
                  <Tooltip label={t("reader.cardDelete")}>
                    <button
                      type="button"
                      className="reader-card-icon-button reader-card-icon-danger"
                      aria-label={t("reader.cardDelete")}
                      onClick={(event) => {
                        event.stopPropagation();
                        onDelete?.(card);
                      }}
                    >
                      <Trash2 size={13} />
                    </button>
                  </Tooltip>
                </Group>
              </article>
            ) : null}
          </div>
        );
      })}
    </aside>
  );
}

function readerCardPopoverPlacement(target: HTMLElement): CSSProperties {
  if (typeof window === "undefined") return {};
  const rect = target.getBoundingClientRect();
  const viewportWidth = window.innerWidth || 1024;
  const viewportHeight = window.innerHeight || 768;
  const margin = 12;
  const gap = 10;
  const width = Math.min(340, Math.max(240, viewportWidth - margin * 2));
  const preferredLeft = rect.left - gap - width;
  const preferredRight = rect.right + gap;
  let left = preferredLeft >= margin ? preferredLeft : preferredRight;
  if (left + width > viewportWidth - margin) {
    left = viewportWidth - margin - width;
  }
  left = Math.max(margin, left);
  const maxTop = Math.max(margin, viewportHeight - 160);
  const top = Math.max(margin, Math.min(rect.top - 4, maxTop));
  return {
    left: Math.round(left),
    top: Math.round(top),
    width: Math.round(width),
    maxHeight: `calc(100vh - ${Math.round(top)}px - ${margin}px)`
  };
}

function ReaderQuickAskCard({
  block,
  canAsk,
  pending,
  onAsk
}: {
  block: DocumentBlock;
  canAsk: boolean;
  pending: boolean;
  onAsk: (block: DocumentBlock, question: string) => void;
}) {
  const t = useT();
  const [question, setQuestion] = useState("");
  const submit = () => {
    const trimmed = question.trim();
    if (!trimmed || !canAsk || pending) return;
    onAsk(block, trimmed);
    setQuestion("");
  };
  return (
    <form
      className="reader-quick-ask-card"
      aria-label={t("reader.quickAsk")}
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
      onPointerDown={(event) => event.stopPropagation()}
      onClick={(event) => event.stopPropagation()}
    >
      <Text fw={650} size="xs">
        {t("reader.quickAsk")}
      </Text>
      <Textarea
        aria-label={t("reader.quickAskQuestion")}
        autosize
        minRows={2}
        maxRows={4}
        size="xs"
        value={question}
        placeholder={t("reader.quickAskPlaceholder")}
        onChange={(event) => setQuestion(event.currentTarget.value)}
        onKeyDown={(event) => {
          if (event.key !== "Enter" || event.shiftKey) return;
          event.preventDefault();
          submit();
        }}
      />
      <Button
        type="submit"
        size="compact-xs"
        variant="light"
        leftSection={<Send size={13} aria-hidden="true" />}
        loading={pending}
        disabled={!canAsk || !question.trim()}
      >
        {t("reader.quickAskSubmit")}
      </Button>
    </form>
  );
}

function cardLabel(card: ReaderCard) {
  const abbreviation = card.abbreviation?.trim();
  if (abbreviation) return abbreviation.slice(0, 10);
  const words = card.title.split(/\s+/).filter(Boolean);
  if (words.length >= 2)
    return words
      .slice(0, 2)
      .map((word) => word[0])
      .join("")
      .toUpperCase();
  return card.title.slice(0, 8);
}

function cardBadgeColor(card: ReaderCard) {
  if (card.source_type === "wikipedia") return "teal";
  if (card.source_type === "ai_search") return "violet";
  if (card.source_type === "user_note") return "blue";
  return "gray";
}

function sourceTypeLabel(card: ReaderCard, t: (key: MessageKey) => string) {
  if (card.source_type === "wikipedia") return t("reader.cardWikiSource");
  if (card.source_type === "ai_search") return t("reader.cardAiSearchSource");
  if (card.source_type === "user_note") return t("reader.cardUserSource");
  return t("reader.cardPaperSource");
}

const blockColorOptions: { value: ReaderBlockColor; labelKey: MessageKey; swatch: string }[] = [
  { value: "none", labelKey: "reader.colorNone", swatch: "transparent" },
  { value: "yellow", labelKey: "reader.colorKeyIdea", swatch: "#ffd60a" },
  { value: "blue", labelKey: "reader.colorMethod", swatch: "#64a8ff" },
  { value: "green", labelKey: "reader.colorEvidence", swatch: "#30d158" },
  { value: "pink", labelKey: "reader.colorQuestion", swatch: "#ff6b9a" },
  { value: "purple", labelKey: "reader.colorReview", swatch: "#bf8cff" }
];

function BlockColorPalette({
  blockUid,
  value,
  onChange,
  className = ""
}: {
  blockUid: string;
  value: ReaderBlockColor;
  onChange?: (blockUid: string, color: ReaderBlockColor) => void;
  className?: string;
}) {
  const t = useT();
  if (!onChange) return null;
  return (
    <Group
      className={`block-color-palette${className ? ` ${className}` : ""}`}
      gap={4}
      aria-label={t("reader.blockColor")}
    >
      {blockColorOptions.map((option) => (
        <Tooltip key={option.value} label={t(option.labelKey)}>
          <button
            type="button"
            className={`block-color-swatch${value === option.value ? " block-color-swatch-active" : ""} block-color-swatch-${option.value}`}
            aria-label={t(option.labelKey)}
            onClick={(event) => {
              event.stopPropagation();
              onChange(blockUid, option.value);
            }}
            style={{ "--block-swatch": option.swatch } as CSSProperties}
          />
        </Tooltip>
      ))}
    </Group>
  );
}

function BlockColorMarker({
  value,
  side
}: {
  value: ReaderBlockColor;
  side: "source" | "translation";
}) {
  if (value === "none") return null;
  return (
    <span
      className={`block-color-marker block-color-marker-${side} block-color-marker-${value}`}
      aria-hidden="true"
    />
  );
}

function TranslationVariantSelect({
  blockUid,
  options,
  selectedVariantId,
  onChange
}: {
  blockUid: string;
  options: { value: string; label: string }[];
  selectedVariantId?: string;
  onChange?: (blockUid: string, variantId: string) => void;
}) {
  const t = useT();
  if (options.length < 2) return null;
  return (
    <Select
      className="translation-variant-select"
      label={t("reader.translationVariant", { blockUid })}
      size="xs"
      value={selectedVariantId ?? options[0]?.value}
      data={options}
      onChange={(value) => {
        if (value) onChange?.(blockUid, value);
      }}
    />
  );
}

function pointInExpandedRect(rect: DOMRect, clientX: number, clientY: number, margin: number) {
  if (!measurableRect(rect)) return false;
  return (
    clientX >= rect.left - margin &&
    clientX <= rect.right + margin &&
    clientY >= rect.top - margin &&
    clientY <= rect.bottom + margin
  );
}

function measurableRect(rect: DOMRect) {
  return rect.width > 0 || rect.height > 0;
}

function GlossaryBadge() {
  const t = useT();
  return (
    <Badge color="yellow" variant="light" size="sm" className="glossary-badge">
      {t("reader.glossaryChanged")}
    </Badge>
  );
}

function CitationLink({
  citation,
  citationImportPending,
  canImportCitationWithTranslation,
  onCitationImport,
  fallbackChildren
}: {
  citation: CitationEntry;
  citationImportPending: boolean;
  canImportCitationWithTranslation: boolean;
  onCitationImport?: (citation: CitationEntry, mode: CitationImportMode) => void;
  fallbackChildren: ReactNode;
}) {
  const t = useT();
  const linkLabel = citation.label ? `[${citation.label}]` : fallbackChildren;
  const importCitation = (mode: CitationImportMode) => {
    onCitationImport?.(citation, mode);
  };
  const importOnPointerDown = (
    event: ReactPointerEvent<HTMLButtonElement>,
    mode: CitationImportMode
  ) => {
    event.preventDefault();
    event.stopPropagation();
    importCitation(mode);
  };
  const importOnKeyboardClick = (
    event: MouseEvent<HTMLButtonElement>,
    mode: CitationImportMode
  ) => {
    if (event.detail !== 0) return;
    event.preventDefault();
    event.stopPropagation();
    importCitation(mode);
  };
  return (
    <HoverCard width={360} position="top" withArrow shadow="md" openDelay={120} closeDelay={160}>
      <HoverCard.Target>
        <a className="citation-link" href={citation.scholar_url} target="_blank" rel="noreferrer">
          {linkLabel}
        </a>
      </HoverCard.Target>
      <HoverCard.Dropdown className="citation-popover">
        <Text fw={650} size="sm" className="citation-popover-title">
          {citation.title}
        </Text>
        {citation.authors ? (
          <Text size="xs" c="dimmed">
            {citation.authors}
            {citation.year ? ` · ${citation.year}` : ""}
          </Text>
        ) : null}
        {citation.raw_text ? (
          <Text size="xs" c="dimmed" lineClamp={3}>
            {citation.raw_text}
          </Text>
        ) : null}
        <Group gap="xs" className="citation-actions">
          <Button
            component="a"
            href={citation.scholar_url}
            target="_blank"
            rel="noreferrer"
            size="xs"
            variant="light"
          >
            {t("reader.searchScholar")}
          </Button>
          <Button
            component="a"
            href={arxivSearchUrl(citation)}
            target="_blank"
            rel="noreferrer"
            size="xs"
            variant="light"
          >
            {t("reader.searchArxiv")}
          </Button>
          <Button
            size="xs"
            onPointerDown={(event) => importOnPointerDown(event, "add")}
            onClick={(event) => importOnKeyboardClick(event, "add")}
            loading={citationImportPending}
            disabled={!onCitationImport}
          >
            {t("reader.addToIliosLibrary")}
          </Button>
          {onCitationImport ? (
            <Button
              size="xs"
              variant="outline"
              onPointerDown={(event) => importOnPointerDown(event, "add-and-translate")}
              onClick={(event) => importOnKeyboardClick(event, "add-and-translate")}
              loading={citationImportPending}
              disabled={!canImportCitationWithTranslation}
            >
              {t("reader.addAndTranslate")}
            </Button>
          ) : null}
        </Group>
      </HoverCard.Dropdown>
    </HoverCard>
  );
}

function arxivSearchUrl(citation: CitationEntry) {
  if (citation.arxiv_id) return `https://arxiv.org/abs/${encodeURIComponent(citation.arxiv_id)}`;
  const query = citation.title || citation.raw_text;
  return `https://arxiv.org/search/?query=${encodeURIComponent(query)}&searchtype=all&source=header`;
}

function displayBlockForReader(block: DocumentBlock, asset?: AssetRecord): DocumentBlock {
  const html =
    stringMetadata(block.metadata, "html_fragment") ??
    stringMetadata(asset?.metadata, "html_fragment") ??
    "";
  if (isEquationLikeTableBlock(block, html)) {
    const latex = equationLatexFromLatexmlFragment(html);
    if (!latex) return block;
    const equationNumbers = equationNumbersFromLatexmlFragment(html);
    return {
      ...block,
      block_type: "equation",
      source_markdown: latex,
      source_latex: block.source_latex ?? latex,
      metadata: {
        ...block.metadata,
        display: "block",
        tex: latex,
        ...(equationNumbers.length > 0
          ? { equation_number: equationNumbers[0], equation_numbers: equationNumbers }
          : {})
      }
    };
  }
  if (isLatexmlTableFigureBlock(block, asset, html)) {
    return {
      ...block,
      block_type: "table",
      source_markdown: normalizedTableMarkdown(block, asset, html),
      metadata: {
        ...block.metadata,
        display_kind: "table"
      }
    };
  }
  if (block.block_type === "figure") {
    return {
      ...block,
      source_markdown: normalizedFigureMarkdown(block, asset, html)
    };
  }
  return block;
}

function isEquationLikeTableBlock(block: DocumentBlock, html: string): boolean {
  if (!["table", "figure"].includes(block.block_type)) return false;
  return /ltx_(?:equation|equationgroup|eqn_)/i.test(html);
}

function isLatexmlTableFigureBlock(
  block: DocumentBlock,
  asset: AssetRecord | undefined,
  html: string
): boolean {
  if (block.block_type === "table" || asset?.kind === "table") return true;
  if (block.block_type !== "figure") return false;
  const label = typeof block.metadata?.label === "string" ? block.metadata.label : "";
  return (
    /\bltx_table\b/i.test(html) ||
    /\bltx_tag_table\b/i.test(html) ||
    /(^tab:|\.T\d+$)/i.test(label) ||
    /^\*\*Figure\s+\d+\.\*\*\s*Table\s+\d+[:.]/i.test(block.source_markdown)
  );
}

function normalizedTableMarkdown(
  block: DocumentBlock,
  asset: AssetRecord | undefined,
  html: string
) {
  const caption =
    latexmlCaptionFromFragment(html) ?? captionFromLegacyMarkdown(block.source_markdown);
  const tableNumber =
    caption?.number ??
    tableNumberFromLabel(block.metadata?.label) ??
    tableNumberFromLabel(asset?.label);
  const captionText =
    caption?.text ??
    stripMarkdownEnvironmentPrefix(block.source_markdown) ??
    asset?.caption ??
    "Table";
  const prefix = tableNumber ? `Table ${tableNumber}.` : "Table.";
  return `**${prefix}** ${stripCaptionTag(captionText)}`;
}

function normalizedFigureMarkdown(
  block: DocumentBlock,
  asset: AssetRecord | undefined,
  html: string
) {
  const caption =
    latexmlCaptionFromFragment(html) ?? captionFromLegacyMarkdown(block.source_markdown);
  const figureNumber =
    caption?.number ??
    figureNumberFromLabel(block.metadata?.label) ??
    figureNumberFromLabel(asset?.label);
  const captionText =
    caption?.text ??
    stripMarkdownEnvironmentPrefix(block.source_markdown) ??
    asset?.caption ??
    "Figure";
  const prefix = figureNumber ? `Figure ${figureNumber}.` : "Figure.";
  return `**${prefix}** ${stripCaptionTag(captionText)}`;
}

function latexmlCaptionFromFragment(
  html: string
): { kind: "figure" | "table"; number?: string; text: string } | null {
  if (!html) return null;
  if (typeof DOMParser !== "undefined") {
    const parsed = new DOMParser().parseFromString(`<div>${html}</div>`, "text/html");
    const caption = parsed.body.querySelector("figcaption, caption, .ltx_caption");
    if (!caption) return null;
    const tag = caption.querySelector(".ltx_tag_table, .ltx_tag_figure");
    const tagText = tag?.textContent ?? "";
    tag?.remove();
    const kind = /table/i.test(tagText) ? "table" : /figure/i.test(tagText) ? "figure" : undefined;
    const number = tagText
      .match(/\b(?:Table|Figure)\s+([A-Za-z0-9.:-]+)/i)?.[1]
      ?.replace(/[:.]$/, "");
    const text = collapseWhitespace(caption.textContent ?? "");
    if (kind && text) return { kind, number, text };
    const fallback = collapseWhitespace(caption.textContent ?? "");
    const match = fallback.match(/^(Table|Figure)\s+([A-Za-z0-9.:-]+)[:.]\s*(.*)$/i);
    if (match?.[1] && match[3]) {
      return {
        kind: match[1].toLowerCase() === "table" ? "table" : "figure",
        number: match[2]?.replace(/[:.]$/, ""),
        text: match[3]
      };
    }
    return null;
  }
  const match = html.match(/(?:Table|Figure)\s+([A-Za-z0-9.:-]+)[:.]\s*([^<]+)/i);
  return match?.[2]
    ? {
        kind: /Table/i.test(match[0]) ? "table" : "figure",
        number: match[1],
        text: collapseWhitespace(match[2])
      }
    : null;
}

function captionFromLegacyMarkdown(
  markdown: string
): { kind: "figure" | "table"; number?: string; text: string } | null {
  const withoutOuterPrefix = stripMarkdownEnvironmentPrefix(markdown);
  if (!withoutOuterPrefix) return null;
  const match = withoutOuterPrefix.match(/^(Table|Figure)\s+([A-Za-z0-9.:-]+)[:.]\s*(.*)$/i);
  if (!match?.[1] || !match[3]) return null;
  return {
    kind: match[1].toLowerCase() === "table" ? "table" : "figure",
    number: match[2]?.replace(/[:.]$/, ""),
    text: match[3]
  };
}

function stripMarkdownEnvironmentPrefix(markdown: string): string | null {
  const stripped = markdown.replace(/^\*\*(?:Figure|Table)\s+\d+\.\*\*\s*/i, "").trim();
  return stripped || null;
}

function tableNumberFromLabel(label: unknown): string | undefined {
  if (typeof label !== "string") return undefined;
  return label.match(/(?:^tab:|\.T)(\d+)$/i)?.[1];
}

function figureNumberFromLabel(label: unknown): string | undefined {
  if (typeof label !== "string") return undefined;
  return label.match(/(?:^fig:|\.F)(\d+)$/i)?.[1];
}

function stripCaptionTag(text: string): string {
  return text.replace(/^\s*(?:Table|Figure|Fig\.)\s+[A-Za-z0-9.:-]+[:.]\s*/i, "").trim();
}

function collapseWhitespace(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function environmentTranslationForReader(
  displayBlock: DocumentBlock,
  translation: string | undefined
): string | undefined {
  if (!translation) return undefined;
  if (displayBlock.block_type === "table") return stripLegacyFigurePrefix(translation);
  if (displayBlock.block_type === "figure") return stripDuplicateFigurePrefix(translation);
  return translation;
}

function stripLegacyFigurePrefix(text: string): string {
  const originalLooksChinese = /^\s*(?:\*\*)?\s*[表图圖]/.test(text);
  return text
    .replace(/^\s*(?:\*\*)?\s*(?:Figure|Fig\.|图|圖)\s*\d+\s*[.:：。]\s*(?:\*\*)?\s*/i, "")
    .replace(
      /^\s*(?:\*\*)?\s*(?:表格|表|Table)\s*(\d+)\s*[.:：。]\s*(?:\*\*)?\s*/i,
      (_match, number: string) => (originalLooksChinese ? `表${number}：` : `Table ${number}. `)
    )
    .trim();
}

function stripDuplicateFigurePrefix(text: string): string {
  const firstPrefix = /^\s*(?:\*\*)?\s*(?:Figure|Fig\.|图|圖)\s*\d+\s*[.:：。]\s*(?:\*\*)?\s*/i;
  const withoutFirst = text.replace(firstPrefix, "");
  if (withoutFirst === text) return text;
  return /^\s*(?:Figure|Fig\.|图|圖)\s*\d+\s*[.:：。]\s*/i.test(withoutFirst)
    ? withoutFirst.trim()
    : text;
}

function equationLatexFromLatexmlFragment(html: string): string | null {
  const rows = extractLatexmlMathRows(html);
  if (rows.length === 0) return null;
  if (rows.length === 1 && rows[0].length === 1) return rows[0][0];
  const renderedRows = rows.map((row) => row.join(" "));
  return `\\begin{aligned}\n${renderedRows.join(" \\\\\n")}\n\\end{aligned}`;
}

function equationNumbersFromLatexmlFragment(html: string): string[] {
  if (typeof DOMParser !== "undefined") {
    const parsed = new DOMParser().parseFromString(`<div>${html}</div>`, "text/html");
    const root = parsed.body.firstElementChild;
    if (!root) return [];
    return uniqueStrings(
      [...root.querySelectorAll(".ltx_eqn_eqno, .ltx_tag_equation")]
        .map((element) => cleanTextContent(element.textContent ?? ""))
        .filter(Boolean)
    );
  }
  return uniqueStrings(
    [...html.matchAll(/class=(["'])[^"']*(?:ltx_eqn_eqno|ltx_tag_equation)[^"']*\1[^>]*>(.*?)</gis)]
      .map((match) => cleanHtmlText(match[2] ?? ""))
      .filter(Boolean)
  );
}

function uniqueStrings(values: string[]) {
  return [...new Set(values)];
}

function cleanHtmlText(value: string) {
  return cleanTextContent(value.replace(/<[^>]+>/g, ""));
}

function cleanTextContent(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function extractLatexmlMathRows(html: string): string[][] {
  if (typeof DOMParser !== "undefined") {
    const parsed = new DOMParser().parseFromString(`<div>${html}</div>`, "text/html");
    const root = parsed.body.firstElementChild;
    if (!root) return [];
    const tableRows = [...root.querySelectorAll("tr")];
    if (tableRows.length > 0) {
      return tableRows
        .map((row) => mathElementsFor(row).map((math) => normalizeExtractedLatex(math)))
        .filter((row) => row.length > 0);
    }
    const values = mathElementsFor(root).map((math) => normalizeExtractedLatex(math));
    return values.length > 0 ? [values] : [];
  }
  const values = [...html.matchAll(/<math\b[^>]*\balttext=(["'])(.*?)\1/gis)]
    .map((match) => decodeHtmlAttribute(match[2] ?? ""))
    .map((value) => normalizeExtractedLatex(value))
    .filter(Boolean);
  return values.length > 0 ? [values] : [];
}

function mathElementsFor(element: Element): string[] {
  return [...element.querySelectorAll("math")]
    .map((math) => math.getAttribute("alttext") || math.textContent || "")
    .filter(Boolean);
}

function normalizeExtractedLatex(value: string): string {
  return normalizeLatex(value);
}

function decodeHtmlAttribute(value: string): string {
  if (typeof document === "undefined") return value;
  const textarea = document.createElement("textarea");
  textarea.innerHTML = value;
  return textarea.value;
}

function StructuralContent({ block }: { block: DocumentBlock }) {
  const displayLevel = structuralDisplayLevel(block);
  const text = structuralText(block);
  if (displayLevel === 1) return <h1 className="structural-heading">{text}</h1>;
  if (displayLevel === 2) return <h2 className="structural-heading">{text}</h2>;
  if (displayLevel === 3) return <h3 className="structural-heading">{text}</h3>;
  if (displayLevel === 4) return <h4 className="structural-heading">{text}</h4>;
  if (displayLevel === 5) return <h5 className="structural-heading">{text}</h5>;
  return <h6 className="structural-heading">{text}</h6>;
}

function BlockContent({
  block,
  content,
  referenceTargets,
  citations,
  citationImportPending,
  canImportCitationWithTranslation,
  onCitationImport,
  sentenceHighlightPlan,
  sentenceHighlightKind,
  trailingInline = null
}: {
  block: DocumentBlock;
  content: string;
  referenceTargets: ReferenceTargets;
  citations: CitationLookup;
  citationImportPending: boolean;
  canImportCitationWithTranslation: boolean;
  onCitationImport?: (citation: CitationEntry, mode: CitationImportMode) => void;
  sentenceHighlightPlan?: SentenceHighlightPlan;
  sentenceHighlightKind?: SentenceHighlightKind;
  trailingInline?: ReactNode;
}) {
  const displayContent = cleanLatexmlDisplayMarkdown(content);
  if (block.block_type === "equation") {
    const equationNumber = equationNumberForBlock(block);
    return (
      <div className="math-block-row">
        <div
          className="math-block"
          dangerouslySetInnerHTML={{
            __html: renderKatexCached(displayContent, true)
          }}
        />
        {equationNumber ? (
          <span className="equation-number" aria-label={`Equation ${equationNumber}`}>
            {equationNumber}
          </span>
        ) : null}
      </div>
    );
  }
  return (
    <MarkdownContent
      content={linkDocumentReferencesCached(displayContent, block, referenceTargets, citations)}
      referenceTargets={referenceTargets}
      citations={citations}
      citationImportPending={citationImportPending}
      canImportCitationWithTranslation={canImportCitationWithTranslation}
      onCitationImport={onCitationImport}
      sentenceHighlightPlan={sentenceHighlightPlan}
      sentenceHighlightKind={sentenceHighlightKind}
      trailingInline={trailingInline}
    />
  );
}

function equationNumberForBlock(block: DocumentBlock): string | undefined {
  return (
    stringMetadata(block.metadata, "equation_number") ??
    arrayStringMetadata(block.metadata, "equation_numbers") ??
    equationNumbersFromLatexmlFragment(stringMetadata(block.metadata, "html_fragment") ?? "")[0]
  );
}

function MarkdownContent({
  content,
  referenceTargets,
  citations,
  citationImportPending = false,
  canImportCitationWithTranslation = false,
  onCitationImport,
  sentenceHighlightPlan,
  sentenceHighlightKind,
  trailingInline = null
}: {
  content: string;
  referenceTargets: ReferenceTargets;
  citations?: CitationLookup;
  citationImportPending?: boolean;
  canImportCitationWithTranslation?: boolean;
  onCitationImport?: (citation: CitationEntry, mode: CitationImportMode) => void;
  sentenceHighlightPlan?: SentenceHighlightPlan;
  sentenceHighlightKind?: SentenceHighlightKind;
  trailingInline?: ReactNode;
}) {
  const preparedMarkdown = useMemo(() => prepareInlineMathMarkdown(content), [content]);
  const sentenceCursor = { value: 0 };
  return (
    <ReactMarkdown
      components={{
        a({ href, children }) {
          const citation = citationForHref(href, citations);
          if (citation) {
            return (
              <CitationLink
                citation={citation}
                citationImportPending={citationImportPending}
                canImportCitationWithTranslation={canImportCitationWithTranslation}
                onCitationImport={onCitationImport}
                fallbackChildren={children}
              />
            );
          }
          const resolvedHref = resolveReferenceHref(href, referenceTargets);
          const linked = resolvedHref !== href && resolvedHref?.startsWith("#");
          const external = isExternalHref(resolvedHref);
          return (
            <a
              className={linked ? "xref-link" : undefined}
              href={resolvedHref}
              rel={external ? "noreferrer" : undefined}
              target={external ? "_blank" : undefined}
            >
              {children}
            </a>
          );
        },
        p({ children }) {
          const inlineChildren =
            sentenceHighlightPlan && sentenceHighlightKind
              ? renderSentenceHighlightedChildren(
                  children,
                  sentenceHighlightPlan,
                  sentenceHighlightKind,
                  preparedMarkdown.inlineMathByToken,
                  sentenceCursor
                )
              : renderInlineMathChildren(children, preparedMarkdown.inlineMathByToken);
          return (
            <p>
              {inlineChildren}
              {trailingInline}
            </p>
          );
        },
        li({ children }) {
          const inlineChildren =
            sentenceHighlightPlan && sentenceHighlightKind
              ? renderSentenceHighlightedChildren(
                  children,
                  sentenceHighlightPlan,
                  sentenceHighlightKind,
                  preparedMarkdown.inlineMathByToken,
                  sentenceCursor
                )
              : renderInlineMathChildren(children, preparedMarkdown.inlineMathByToken);
          return <li>{inlineChildren}</li>;
        },
        td({ children }) {
          const inlineChildren =
            sentenceHighlightPlan && sentenceHighlightKind
              ? renderSentenceHighlightedChildren(
                  children,
                  sentenceHighlightPlan,
                  sentenceHighlightKind,
                  preparedMarkdown.inlineMathByToken,
                  sentenceCursor
                )
              : renderInlineMathChildren(children, preparedMarkdown.inlineMathByToken);
          return <td>{inlineChildren}</td>;
        },
        th({ children }) {
          const inlineChildren =
            sentenceHighlightPlan && sentenceHighlightKind
              ? renderSentenceHighlightedChildren(
                  children,
                  sentenceHighlightPlan,
                  sentenceHighlightKind,
                  preparedMarkdown.inlineMathByToken,
                  sentenceCursor
                )
              : renderInlineMathChildren(children, preparedMarkdown.inlineMathByToken);
          return <th>{inlineChildren}</th>;
        }
      }}
    >
      {preparedMarkdown.markdown}
    </ReactMarkdown>
  );
}

type SentenceHighlightKind = "source" | "translation";

interface SentenceHighlightPlan {
  sourceSentenceCount: number;
  translationSentenceCount: number;
}

const sentenceHighlightColorCount = 6;

function createSentenceHighlightPlan(
  block: DocumentBlock,
  translation: string,
  viewMode: ReaderViewMode
): SentenceHighlightPlan | undefined {
  if (block.block_type !== "paragraph") return undefined;
  const sourceSentenceCount = cachedSentenceRanges(
    plainTextForSentenceHighlight(block.source_markdown)
  ).length;
  const translationSentenceCount = cachedSentenceRanges(
    plainTextForSentenceHighlight(translation)
  ).length;
  if (sourceSentenceCount === 0) return undefined;
  if (viewMode !== "source" && translationSentenceCount === 0) return undefined;
  return { sourceSentenceCount, translationSentenceCount };
}

function renderSentenceHighlightedChildren(
  children: ReactNode,
  plan: SentenceHighlightPlan,
  kind: SentenceHighlightKind,
  inlineMathByToken: Map<string, string>,
  sentenceCursor: { value: number }
): ReactNode {
  const text = textContentOf(children);
  const ranges = cachedSentenceRanges(text);
  if (ranges.length === 0) return renderInlineMathChildren(children, inlineMathByToken);
  const baseSentenceIndex = sentenceCursor.value;
  sentenceCursor.value += ranges.length;
  const offset = { value: 0 };
  return renderHighlightedNode(
    children,
    ranges,
    baseSentenceIndex,
    plan,
    kind,
    inlineMathByToken,
    offset
  );
}

function renderHighlightedNode(
  node: ReactNode,
  ranges: TextRange[],
  baseSentenceIndex: number,
  plan: SentenceHighlightPlan,
  kind: SentenceHighlightKind,
  inlineMathByToken: Map<string, string>,
  offset: { value: number }
): ReactNode {
  return Children.map(node, (child) => {
    if (typeof child === "string") {
      const startOffset = offset.value;
      offset.value += child.length;
      return renderHighlightedText(
        child,
        startOffset,
        ranges,
        baseSentenceIndex,
        plan,
        kind,
        inlineMathByToken
      );
    }
    if (typeof child === "number" || typeof child === "bigint") {
      const text = String(child);
      const startOffset = offset.value;
      offset.value += text.length;
      return renderHighlightedText(
        text,
        startOffset,
        ranges,
        baseSentenceIndex,
        plan,
        kind,
        inlineMathByToken
      );
    }
    if (isValidElement<{ children?: ReactNode }>(child)) {
      const childTextLength = textContentOf(child.props.children).length;
      const renderedChildren =
        childTextLength > 0
          ? renderHighlightedNode(
              child.props.children,
              ranges,
              baseSentenceIndex,
              plan,
              kind,
              inlineMathByToken,
              offset
            )
          : child.props.children;
      return cloneElement(child, undefined, renderedChildren);
    }
    return child;
  });
}

function renderHighlightedText(
  text: string,
  textStartOffset: number,
  ranges: TextRange[],
  baseSentenceIndex: number,
  plan: SentenceHighlightPlan,
  kind: SentenceHighlightKind,
  inlineMathByToken: Map<string, string>
): ReactNode {
  const parts: ReactNode[] = [];
  let cursor = 0;
  for (const [rangeIndex, range] of ranges.entries()) {
    const overlapStart = Math.max(textStartOffset, range.start);
    const overlapEnd = Math.min(textStartOffset + text.length, range.end);
    if (overlapEnd <= overlapStart) continue;
    const localStart = overlapStart - textStartOffset;
    const localEnd = overlapEnd - textStartOffset;
    if (localStart > cursor) {
      parts.push(
        <Fragment key={`${textStartOffset}-${cursor}-${localStart}-plain`}>
          {renderInlineMathText(text.slice(cursor, localStart), inlineMathByToken)}
        </Fragment>
      );
    }
    const absoluteSentenceIndex = baseSentenceIndex + rangeIndex;
    const accentIndex = sentenceAccentIndex(absoluteSentenceIndex);
    const highlightedText = text.slice(localStart, localEnd);
    parts.push(
      <span
        className={`sentence-highlight sentence-highlight-${accentIndex % sentenceHighlightColorCount}`}
        data-sentence-accent={accentIndex % sentenceHighlightColorCount}
        data-sentence-kind={kind}
        key={`${textStartOffset}-${localStart}-${localEnd}-${accentIndex}`}
      >
        {renderInlineMathText(highlightedText, inlineMathByToken)}
      </span>
    );
    cursor = localEnd;
  }
  if (cursor < text.length) {
    parts.push(
      <Fragment key={`${textStartOffset}-${cursor}-${text.length}-plain`}>
        {renderInlineMathText(text.slice(cursor), inlineMathByToken)}
      </Fragment>
    );
  }
  return parts.length > 0 ? (
    <Fragment>{parts}</Fragment>
  ) : (
    renderInlineMathText(text, inlineMathByToken)
  );
}

function sentenceAccentIndex(absoluteSentenceIndex: number): number {
  return absoluteSentenceIndex;
}

interface TextRange {
  start: number;
  end: number;
}

function sentenceRanges(text: string): TextRange[] {
  const ranges: TextRange[] = [];
  let start = nextNonWhitespace(text, 0);
  for (let index = start; index < text.length; index += 1) {
    if (!isSentenceTerminator(text, index)) continue;
    let end = index + 1;
    while (end < text.length && /["'”’)\]}]/.test(text[end] ?? "")) end += 1;
    const trimmed = trimRange(text, start, end);
    if (trimmed.end > trimmed.start) ranges.push(trimmed);
    start = nextNonWhitespace(text, end);
    index = start - 1;
  }
  const tail = trimRange(text, start, text.length);
  if (tail.end > tail.start) ranges.push(tail);
  return ranges;
}

function cachedSentenceRanges(text: string): TextRange[] {
  const cached = sentenceRangeCache.get(text);
  if (cached) return cached;
  return sentenceRangeCache.set(text, sentenceRanges(text));
}

function isSentenceTerminator(text: string, index: number): boolean {
  const value = text[index] ?? "";
  if (/[。！？；]/.test(value)) return true;
  if (!/[.!?;]/.test(value)) return false;
  if (value === "." && isDecimalPoint(text, index)) return false;
  if (value === "." && isKnownAbbreviation(text, index)) return false;
  return true;
}

function isDecimalPoint(text: string, index: number): boolean {
  return /\d/.test(text[index - 1] ?? "") && /\d/.test(text[index + 1] ?? "");
}

function isKnownAbbreviation(text: string, index: number): boolean {
  const prefix = text.slice(Math.max(0, index - 18), index + 1).toLowerCase();
  return /\b(?:e\.g|i\.e|fig|eq|eqn|sec|ref|dr|prof|vs|no|al)\.$/.test(prefix);
}

function nextNonWhitespace(text: string, start: number): number {
  let index = start;
  while (index < text.length && /\s/.test(text[index] ?? "")) index += 1;
  return index;
}

function trimRange(text: string, start: number, end: number): TextRange {
  let trimmedStart = start;
  let trimmedEnd = end;
  while (trimmedStart < trimmedEnd && /\s/.test(text[trimmedStart] ?? "")) trimmedStart += 1;
  while (trimmedEnd > trimmedStart && /\s/.test(text[trimmedEnd - 1] ?? "")) trimmedEnd -= 1;
  return { start: trimmedStart, end: trimmedEnd };
}

function textContentOf(node: ReactNode): string {
  let text = "";
  Children.forEach(node, (child) => {
    if (typeof child === "string" || typeof child === "number" || typeof child === "bigint") {
      text += String(child);
      return;
    }
    if (isValidElement<{ children?: ReactNode }>(child)) {
      text += textContentOf(child.props.children);
    }
  });
  return text;
}

function plainTextForSentenceHighlight(markdown: string): string {
  return markdown
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_~#>|-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function renderInlineMathChildren(
  children: ReactNode,
  inlineMathByToken: Map<string, string>
): ReactNode {
  return Children.map(children, (child) =>
    typeof child === "string" ? renderInlineMathText(child, inlineMathByToken) : child
  );
}

function renderInlineMathText(text: string, inlineMathByToken = emptyInlineMathByToken): ReactNode {
  const parts: ReactNode[] = [];
  const pattern = /BILININLINE\d+MATH|\\\((.+?)\\\)|\$([^$\n]+)\$/g;
  let cursor = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text))) {
    if (match.index > cursor) parts.push(text.slice(cursor, match.index));
    const tokenLatex = inlineMathByToken.get(match[0]);
    const latex = tokenLatex ?? match[1] ?? match[2] ?? "";
    if (latex) {
      parts.push(<InlineMath latex={latex} key={`${match.index}-${latex}`} />);
    } else {
      parts.push(match[0]);
    }
    cursor = match.index + match[0].length;
  }
  if (cursor < text.length) parts.push(text.slice(cursor));
  return parts.length > 0 ? <Fragment>{parts}</Fragment> : text;
}

const emptyInlineMathByToken = new Map<string, string>();

interface PreparedInlineMathMarkdown {
  markdown: string;
  inlineMathByToken: Map<string, string>;
}

function prepareInlineMathMarkdown(content: string): PreparedInlineMathMarkdown {
  const inlineMathByToken = new Map<string, string>();
  let index = 0;
  const markdown = content.replace(/\\\((.+?)\\\)|\$([^$\n]+)\$/g, (match, paren, dollar) => {
    const latex = String(paren ?? dollar ?? "");
    if (!latex.trim()) return match;
    const token = `BILININLINE${index}MATH`;
    index += 1;
    inlineMathByToken.set(token, latex);
    return token;
  });
  return { markdown, inlineMathByToken };
}

function InlineMath({ latex }: { latex: string }) {
  return (
    <span
      className="inline-math"
      dangerouslySetInnerHTML={{
        __html: renderKatexCached(latex, false)
      }}
    />
  );
}

function renderKatexCached(latex: string, displayMode: boolean) {
  const normalized = normalizeLatex(latex);
  const key = `${displayMode ? "block" : "inline"}:${normalized}`;
  const cached = katexRenderCache.get(key);
  if (cached) return cached;
  return katexRenderCache.set(
    key,
    katex.renderToString(normalized, {
      displayMode,
      throwOnError: false
    })
  );
}

function isStructuralBlock(block: DocumentBlock): boolean {
  return ["section", "title", "abstract", "subsection", "subsubsection"].includes(block.block_type);
}

function structuralRole(block: DocumentBlock): string {
  const normalized = structuralText(block).toLowerCase();
  if (block.block_type === "abstract" || normalized === "abstract") return "abstract";
  if (block.block_type === "title") return "title";
  const level = structuralLevel(block);
  if (level === 1 && !/^\d+(\.\d+)*\s+/.test(normalized)) return "title";
  return "section";
}

function structuralDisplayLevel(block: DocumentBlock): 1 | 2 | 3 | 4 | 5 | 6 {
  const role = structuralRole(block);
  if (role === "title") return 1;
  if (role === "abstract") return 2;
  return Math.min(Math.max(structuralLevel(block), 2), 5) as 2 | 3 | 4 | 5;
}

function structuralLevel(block: DocumentBlock): number {
  const level = block.metadata?.level;
  return typeof level === "number" && Number.isFinite(level) ? level : 2;
}

function structuralText(block: DocumentBlock): string {
  return block.source_markdown
    .replace(/^#+\s*/, "")
    .replace(/\*\*/g, "")
    .replace(/`/g, "")
    .trim();
}

function isStandaloneParagraphHeading(block: DocumentBlock): boolean {
  if (block.block_type !== "paragraph") return false;
  const raw = block.source_markdown.trim();
  if (!raw || raw.includes("\n")) return false;
  if (/[`$[\]]/.test(raw)) return false;
  if (/[*_]{1,2}.+[*_]{1,2}\s+/.test(raw)) return false;
  const text = paragraphHeadingText(block);
  if (!text || text.length < 3 || text.length > 72) return false;
  if (/[.!?。！？,;；]$/.test(text) || /[:：]$/.test(text)) return false;
  const words = text.split(/\s+/).filter(Boolean);
  if (words.length > 5) return false;
  if (words.some((word) => word.length > 28)) return false;
  return words.some((word) => paragraphHeadingWordShape(word));
}

function paragraphHeadingText(block: DocumentBlock): string {
  return block.source_markdown
    .replace(/^#+\s*/, "")
    .replace(/\*\*/g, "")
    .replace(/[_`]/g, "")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function paragraphHeadingWordShape(word: string): boolean {
  const cleaned = word.replace(/[()]/g, "");
  if (/^[A-Z0-9-]{2,}$/.test(cleaned)) return true;
  if (/^[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]+)+$/.test(cleaned)) return true;
  return /^[A-Z][A-Za-z0-9-]{2,}$/.test(cleaned);
}

function AssetPreview({
  kind,
  asset,
  assetUrl,
  assetFileUrls,
  referenceTargets,
  imageLightboxEnabled
}: {
  kind: string;
  asset?: AssetRecord;
  assetUrl?: string;
  assetFileUrls: ReaderAssetFile[];
  referenceTargets: ReferenceTargets;
  imageLightboxEnabled: boolean;
}) {
  const htmlFragment = stringMetadata(asset?.metadata, "html_fragment");
  if (assetUrl) {
    if (assetFileUrls.length > 1) {
      return (
        <figure className="asset-figure-grid">
          {assetFileUrls.map((file) => (
            <AdaptiveAssetImage
              src={file.url}
              alt={asset?.caption ?? `${kind} asset ${file.index}`}
              metadata={metadataForAssetFile(asset?.metadata, file.metadata)}
              lightboxEnabled={imageLightboxEnabled}
              key={`${file.originalReference}-${file.index}`}
            />
          ))}
        </figure>
      );
    }
    return (
      <AdaptiveAssetImage
        src={assetUrl}
        alt={asset?.caption ?? kind}
        metadata={asset?.metadata}
        lightboxEnabled={imageLightboxEnabled}
      />
    );
  }
  if (htmlFragment && /<(?:table|svg)\b/i.test(htmlFragment)) {
    return (
      <LatexmlFragmentPreview
        html={htmlFragment}
        assetUrl={assetUrl}
        assetFileUrls={assetFileUrls}
        referenceTargets={referenceTargets}
      />
    );
  }
  return null;
}

function metadataForAssetFile(
  assetMetadata: AssetRecord["metadata"] | undefined,
  fileMetadata: AssetRecord["metadata"] | undefined
): AssetRecord["metadata"] | undefined {
  if (!assetMetadata && !fileMetadata) return undefined;
  const panelWidth = numericMetadata(fileMetadata, "panel_width_pt", "display_width_pt");
  const groupWidth = numericMetadata(
    assetMetadata,
    "total_panel_width_pt",
    "subfigure_group_width_pt",
    "display_width_pt"
  );
  return {
    ...(assetMetadata ?? {}),
    ...(fileMetadata ?? {}),
    asset_files: undefined,
    image_count: fileMetadata ? 1 : assetMetadata?.image_count,
    ...(panelWidth
      ? {
          display_width_pt: panelWidth,
          max_panel_width_pt: panelWidth
        }
      : {}),
    ...(groupWidth ? { subfigure_group_width_pt: groupWidth } : {})
  };
}

type AssetImageLayout = "unknown" | "narrow" | "single" | "wide";
type AssetArticleLayout = "unknown" | "single-column" | "double-column" | "multi-panel";

interface LatexmlImageMetrics {
  imageCount: number;
  firstWidth?: number;
  firstHeight?: number;
  maxPanelWidthPt?: number;
  totalPanelWidthPt?: number;
  displayWidthPt?: number;
  hasFlexLayout: boolean;
}

const assetLightboxStyle: CSSProperties = {
  position: "fixed",
  inset: 0,
  zIndex: 2147483647,
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  width: "100vw",
  height: "100vh",
  boxSizing: "border-box",
  padding: "32px",
  background: "rgba(0, 0, 0, 0.88)",
  cursor: "zoom-out",
  isolation: "isolate"
};

const assetLightboxImageStyle: CSSProperties = {
  position: "fixed",
  top: "50%",
  left: "50%",
  transform: "translate(-50%, -50%)",
  zIndex: 2147483647,
  display: "block",
  maxWidth: "min(96vw, 1600px)",
  maxHeight: "92vh",
  objectFit: "contain",
  background: "#ffffff",
  borderRadius: 6,
  boxShadow: "0 24px 80px rgba(0, 0, 0, 0.55)"
};

function AdaptiveAssetImage({
  src,
  alt,
  metadata,
  lightboxEnabled
}: {
  src: string;
  alt: string;
  metadata?: AssetRecord["metadata"];
  lightboxEnabled: boolean;
}) {
  const articleLayout = articleImageLayoutFromMetadata(metadata);
  const [layout, setLayout] = useState<AssetImageLayout>(() => imageLayoutFromMetadata(metadata));
  const [lightboxOpen, setLightboxOpen] = useState(false);
  useEffect(() => {
    if (!lightboxOpen || typeof document === "undefined") return undefined;
    const previousOverflow = document.body.style.overflow;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setLightboxOpen(false);
    };
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", closeOnEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeOnEscape);
    };
  }, [lightboxOpen]);
  const openLightbox = () => {
    if (lightboxEnabled) setLightboxOpen(true);
  };
  const toggleFromKeyboard = (event: ReactKeyboardEvent<HTMLImageElement>) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    openLightbox();
  };
  const lightbox =
    lightboxOpen && typeof document !== "undefined"
      ? createPortal(
          <div
            className="asset-image-lightbox"
            role="dialog"
            aria-modal="true"
            aria-label={alt}
            style={assetLightboxStyle}
            onClick={() => setLightboxOpen(false)}
          >
            <img
              className="asset-image-lightbox-image"
              src={src}
              alt={alt}
              style={assetLightboxImageStyle}
              onClick={(event) => {
                event.stopPropagation();
                setLightboxOpen(false);
              }}
            />
          </div>,
          document.body
        )
      : null;
  return (
    <>
      <img
        className={`asset-image asset-image-${layout} asset-image-article-${articleLayout}`}
        data-article-layout={articleLayout}
        data-asset-layout={layout}
        style={assetImageStyleFromMetadata(metadata)}
        src={src}
        alt={alt}
        tabIndex={lightboxEnabled ? 0 : undefined}
        onClick={openLightbox}
        onKeyDown={toggleFromKeyboard}
        onLoad={(event) => {
          const image = event.currentTarget;
          setLayout(classifyImageLayout(image.naturalWidth, image.naturalHeight));
        }}
      />
      {lightbox}
    </>
  );
}

function imageLayoutFromMetadata(metadata: AssetRecord["metadata"] | undefined): AssetImageLayout {
  const metrics = latexmlImageMetricsFromMetadata(metadata);
  const width =
    numericMetadata(metadata, "width", "natural_width", "pixel_width") ?? metrics.firstWidth;
  const height =
    numericMetadata(metadata, "height", "natural_height", "pixel_height") ?? metrics.firstHeight;
  return width && height ? classifyImageLayout(width, height) : "unknown";
}

function articleImageLayoutFromMetadata(
  metadata: AssetRecord["metadata"] | undefined
): AssetArticleLayout {
  const explicitLayout = stringMetadata(metadata, "article_layout");
  if (isAssetArticleLayout(explicitLayout)) return explicitLayout;
  const metrics = latexmlImageMetricsFromMetadata(metadata);
  if (metrics.imageCount > 1 || metrics.hasFlexLayout) return "multi-panel";
  if (metrics.maxPanelWidthPt && metrics.maxPanelWidthPt >= 330) return "double-column";
  if (metrics.maxPanelWidthPt && metrics.maxPanelWidthPt > 0) return "single-column";
  const width = numericMetadata(metadata, "width", "natural_width", "pixel_width");
  const height = numericMetadata(metadata, "height", "natural_height", "pixel_height");
  if (width && height && width / height >= 1.45) return "double-column";
  return "unknown";
}

function isAssetArticleLayout(value: string | undefined): value is AssetArticleLayout {
  return (
    value === "unknown" ||
    value === "single-column" ||
    value === "double-column" ||
    value === "multi-panel"
  );
}

function assetImageStyleFromMetadata(metadata: AssetRecord["metadata"] | undefined): CSSProperties {
  const metrics = latexmlImageMetricsFromMetadata(metadata);
  const articleLayout = articleImageLayoutFromMetadata(metadata);
  const firstWidth =
    metrics.firstWidth ?? numericMetadata(metadata, "width", "natural_width", "pixel_width");
  const firstHeight =
    metrics.firstHeight ?? numericMetadata(metadata, "height", "natural_height", "pixel_height");
  const ratio = firstWidth && firstHeight ? firstWidth / firstHeight : undefined;
  const displayWidthPt =
    metrics.displayWidthPt ??
    metrics.maxPanelWidthPt ??
    numericMetadata(metadata, "panel_width_pt");
  let maxInlineSize = 480;
  let maxBlockSize = 520;
  let renderInlineSize: number | undefined;

  if (articleLayout === "multi-panel") {
    const explicitPanelWidth = numericMetadata(metadata, "panel_width_pt");
    const panelWidth =
      explicitPanelWidth ??
      metrics.maxPanelWidthPt ??
      displayWidthPt ??
      (firstWidth ? firstWidth * 0.62 : 220);
    maxInlineSize = Math.round(panelWidth * multiPanelGroupScaleFromMetadata(metadata));
    renderInlineSize = maxInlineSize;
    maxBlockSize = clampNumber(maxInlineSize * (ratio && ratio < 0.8 ? 1.55 : 1.25), 260, 360);
  } else if (articleLayout === "double-column") {
    maxInlineSize = clampNumber(displayWidthPt ?? firstWidth ?? 640, 380, 760);
    renderInlineSize = displayWidthPt ? maxInlineSize : undefined;
    maxBlockSize = 560;
  } else if (articleLayout === "single-column") {
    maxInlineSize = clampNumber(displayWidthPt ?? firstWidth ?? 460, 220, 520);
    renderInlineSize = displayWidthPt ? maxInlineSize : undefined;
    maxBlockSize = ratio && ratio < 0.8 ? 520 : 460;
  } else if (ratio && ratio <= 0.9) {
    maxInlineSize = 340;
  } else if (ratio && ratio >= 1.35) {
    maxInlineSize = 820;
    maxBlockSize = 560;
  }

  return {
    ...(renderInlineSize
      ? { "--asset-render-inline-size": `${Math.round(renderInlineSize)}px` }
      : {}),
    "--asset-max-inline-size": `${Math.round(maxInlineSize)}px`,
    "--asset-max-block-size": `${Math.round(maxBlockSize)}px`
  } as CSSProperties;
}

const MULTI_PANEL_GROUP_MAX_INLINE_SIZE = 760;

function multiPanelGroupScaleFromMetadata(metadata: AssetRecord["metadata"] | undefined) {
  const groupWidth = numericMetadata(metadata, "subfigure_group_width_pt", "total_panel_width_pt");
  if (!groupWidth || groupWidth <= MULTI_PANEL_GROUP_MAX_INLINE_SIZE) return 1;
  return MULTI_PANEL_GROUP_MAX_INLINE_SIZE / groupWidth;
}

function classifyImageLayout(width: number, height: number): AssetImageLayout {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return "unknown";
  }
  const ratio = width / height;
  if (ratio >= 1.35) return "wide";
  if (ratio <= 0.9) return "narrow";
  return "single";
}

function latexmlImageMetricsFromMetadata(
  metadata: AssetRecord["metadata"] | undefined
): LatexmlImageMetrics {
  const metadataImageCount = numericMetadata(metadata, "image_count");
  const metadataFirstWidth = numericMetadata(metadata, "image_width", "width", "natural_width");
  const metadataFirstHeight = numericMetadata(metadata, "image_height", "height", "natural_height");
  const metadataMaxPanelWidth = numericMetadata(metadata, "max_panel_width_pt", "panel_width_pt");
  const metadataTotalPanelWidth = numericMetadata(metadata, "total_panel_width_pt");
  const metadataDisplayWidth = numericMetadata(metadata, "display_width_pt", "panel_width_pt");
  const metadataHasFlexLayout = booleanMetadata(metadata, "has_flex_layout");
  const html = stringMetadata(metadata, "html_fragment") ?? "";
  if (!html) {
    return {
      imageCount: Math.round(metadataImageCount ?? 0),
      firstWidth: metadataFirstWidth,
      firstHeight: metadataFirstHeight,
      maxPanelWidthPt: metadataMaxPanelWidth,
      totalPanelWidthPt: metadataTotalPanelWidth,
      displayWidthPt: metadataDisplayWidth,
      hasFlexLayout: Boolean(metadataHasFlexLayout)
    };
  }
  const imageTags = [...html.matchAll(/<img\b[^>]*>/gi)].map((match) => match[0]);
  const imageSizes = imageTags.flatMap((tag) => {
    const width = numberAttributeFromHtmlTag(tag, "width");
    const height = numberAttributeFromHtmlTag(tag, "height");
    return width && height ? [{ width, height }] : [];
  });
  const panelWidthsPt = [...html.matchAll(/width\s*:\s*([0-9.]+)\s*pt/gi)]
    .map((match) => Number.parseFloat(match[1] ?? ""))
    .filter((value) => Number.isFinite(value) && value > 0);
  return {
    imageCount: Math.round(metadataImageCount ?? imageTags.length),
    firstWidth: metadataFirstWidth ?? imageSizes[0]?.width,
    firstHeight: metadataFirstHeight ?? imageSizes[0]?.height,
    maxPanelWidthPt:
      metadataMaxPanelWidth ?? (panelWidthsPt.length > 0 ? Math.max(...panelWidthsPt) : undefined),
    totalPanelWidthPt:
      metadataTotalPanelWidth ??
      (panelWidthsPt.length > 0
        ? panelWidthsPt.reduce((total, value) => total + value, 0)
        : undefined),
    displayWidthPt:
      metadataDisplayWidth ??
      (panelWidthsPt.length > 0
        ? panelWidthsPt.reduce((total, value) => total + value, 0)
        : undefined),
    hasFlexLayout: Boolean(metadataHasFlexLayout) || /\bltx_flex_(?:figure|cell|size_)/i.test(html)
  };
}

function numberAttributeFromHtmlTag(tag: string, attribute: string): number | undefined {
  const match = tag.match(new RegExp(`\\b${attribute}=(["']?)([0-9.]+)\\1`, "i"));
  if (!match?.[2]) return undefined;
  const parsed = Number.parseFloat(match[2]);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

function clampNumber(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function LatexmlFragmentPreview({
  html,
  assetUrl,
  assetFileUrls,
  referenceTargets
}: {
  html: string;
  assetUrl?: string;
  assetFileUrls: ReaderAssetFile[];
  referenceTargets: ReferenceTargets;
}) {
  const sanitizedHtml = useMemo(
    () => sanitizeLatexmlFragmentCached(html, assetUrl, assetFileUrls, referenceTargets),
    [assetFileUrls, assetUrl, html, referenceTargets]
  );
  if (!sanitizedHtml) return null;
  return (
    <div className="latexml-fragment-preview" dangerouslySetInnerHTML={{ __html: sanitizedHtml }} />
  );
}

interface BlockReference {
  href: string;
  text: string;
}

function linkDocumentReferencesCached(
  content: string,
  block: DocumentBlock,
  referenceTargets: ReferenceTargets,
  citations: CitationLookup
) {
  if (content.includes("](")) return content;
  const references = blockReferences(block);
  if (references.length === 0) return content;
  const key = [
    block.content_hash,
    hashString(content),
    references.map((reference) => `${reference.href}:${reference.text}`).join("|"),
    Object.keys(referenceTargets).length,
    Object.keys(citations).join(",")
  ].join("::");
  const cached = linkedContentCache.get(key);
  if (cached) return cached;
  return linkedContentCache.set(
    key,
    linkDocumentReferencesWithReferences(content, references, referenceTargets, citations)
  );
}

function linkDocumentReferencesWithReferences(
  content: string,
  references: BlockReference[],
  referenceTargets: ReferenceTargets,
  citations: CitationLookup
) {
  let linked = linkBibliographyReferences(content, references, citations);
  for (const reference of references) {
    if (isBibliographyHref(reference.href)) continue;
    const target = referenceTargetForHref(reference.href, referenceTargets);
    if (!target) continue;
    const escapedText = escapeRegExp(reference.text);
    const patterns = referencePatternsForTarget(target.blockType, escapedText);
    for (const pattern of patterns) {
      const next = linked.replace(pattern, (match) => `[${match}](${reference.href})`);
      if (next !== linked) {
        linked = next;
        break;
      }
    }
  }
  return linked;
}

function linkBibliographyReferences(
  content: string,
  references: BlockReference[],
  citations: CitationLookup
) {
  const citationHrefByLabel = new Map<string, string>();
  for (const reference of references) {
    if (!isBibliographyHref(reference.href)) continue;
    const citation = citationForHref(reference.href, citations);
    if (!citation) continue;
    citationHrefByLabel.set(reference.text.trim(), reference.href);
  }
  if (citationHrefByLabel.size === 0) return content;
  return content.replace(/\[([0-9,\s–-]+)\]/g, (_match, body: string) =>
    body
      .split(/(\s*,\s*)/)
      .map((part) => {
        const trimmed = part.trim();
        const href = citationHrefByLabel.get(trimmed);
        if (!href) return part;
        return `[\\[${trimmed}\\]](${href})`;
      })
      .join("")
  );
}

function blockReferences(block: DocumentBlock): BlockReference[] {
  const references = block.metadata?.references;
  if (!Array.isArray(references)) return [];
  return references.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const href = "href" in item ? item.href : undefined;
    const text = "text" in item ? item.text : undefined;
    if (typeof href !== "string" || typeof text !== "string" || !text.trim()) return [];
    return [{ href, text }];
  });
}

function referencePatternsForTarget(blockType: string, escapedText: string): RegExp[] {
  if (blockType === "figure") {
    return [
      new RegExp(`\\bFigure\\s+${escapedText}\\b`),
      new RegExp(`\\bFig\\.\\s*${escapedText}\\b`)
    ];
  }
  if (blockType === "table") {
    return [new RegExp(`\\bTable\\s+${escapedText}\\b`)];
  }
  if (blockType === "section" || blockType === "subsection" || blockType === "subsubsection") {
    return [new RegExp(`\\b[Ss]ection\\s+${escapedText}\\b`)];
  }
  if (blockType === "equation") {
    return [new RegExp(`\\b[Ee]quation\\s+${escapedText}\\b`)];
  }
  return [];
}

function resolveReferenceHref(href: string | undefined, referenceTargets: ReferenceTargets) {
  if (!href?.startsWith("#")) return href;
  const target = referenceTargetForHref(href, referenceTargets);
  return target ? `#${target.blockUid}` : href;
}

function isExternalHref(href: string | undefined) {
  return /^https?:\/\//i.test(href ?? "");
}

function citationForHref(
  href: string | undefined,
  citations: CitationLookup | undefined
): CitationEntry | undefined {
  if (!href || !citations || !isBibliographyHref(href)) return undefined;
  const key = href.startsWith("#") ? href.slice(1) : href;
  return citations[key];
}

function isBibliographyHref(href: string) {
  const key = href.startsWith("#") ? href.slice(1) : href;
  return key.startsWith("bib.");
}

function referenceTargetForHref(href: string, referenceTargets: ReferenceTargets) {
  const key = href.startsWith("#") ? href.slice(1) : href;
  return referenceTargets[key];
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stringMetadata(
  metadata: AssetRecord["metadata"] | DocumentBlock["metadata"] | undefined,
  key: string
) {
  const value = metadata?.[key];
  return typeof value === "string" ? value : undefined;
}

function arrayStringMetadata(
  metadata: AssetRecord["metadata"] | DocumentBlock["metadata"] | undefined,
  key: string
) {
  const value = metadata?.[key];
  if (!Array.isArray(value)) return undefined;
  const strings = value.filter((item): item is string => typeof item === "string");
  return strings.length > 0 ? strings.join(", ") : undefined;
}

function numericMetadata(
  metadata: AssetRecord["metadata"] | DocumentBlock["metadata"] | undefined,
  ...keys: string[]
) {
  for (const key of keys) {
    const value = metadata?.[key];
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string") {
      const parsed = Number.parseFloat(value);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return undefined;
}

function booleanMetadata(
  metadata: AssetRecord["metadata"] | DocumentBlock["metadata"] | undefined,
  key: string
) {
  const value = metadata?.[key];
  return typeof value === "boolean" ? value : undefined;
}

function sanitizeLatexmlFragment(
  html: string,
  assetUrl: string | undefined,
  assetFileUrls: ReaderAssetFile[],
  referenceTargets: ReferenceTargets
) {
  if (typeof DOMParser === "undefined") return "";
  const imageUrls = new Map<string, string>();
  if (assetUrl) imageUrls.set("", assetUrl);
  for (const file of assetFileUrls) {
    imageUrls.set(file.originalReference, file.url);
  }
  const document = new DOMParser().parseFromString(
    `<div>${normalizeLatexmlTableFragmentHtml(html)}</div>`,
    "text/html"
  );
  const root = document.body.firstElementChild;
  if (!root) return "";
  for (const element of [...root.querySelectorAll("script, style, iframe, object, embed")]) {
    element.remove();
  }
  removeLatexmlTableRuleArtifacts(root);
  const mathFragments = new Map<string, string>();
  let mathIndex = 0;
  for (const math of [...root.querySelectorAll("math")]) {
    const latex = math.getAttribute("alttext") || math.textContent || "";
    const placeholderIndex = String(mathIndex++);
    mathFragments.set(
      placeholderIndex,
      `<span class="table-math">${renderKatexCached(latex, false)}</span>`
    );
    const placeholder = document.createElement("span");
    placeholder.setAttribute("data-bilin-math-index", placeholderIndex);
    math.replaceWith(placeholder);
  }
  for (const caption of [...root.querySelectorAll("figcaption, caption")]) {
    caption.remove();
  }
  sanitizeElement(root, document, imageUrls, referenceTargets);
  for (const placeholder of [...root.querySelectorAll("[data-bilin-math-index]")]) {
    const index = placeholder.getAttribute("data-bilin-math-index");
    const rendered = index ? mathFragments.get(index) : undefined;
    if (!rendered) {
      placeholder.remove();
      continue;
    }
    const template = document.createElement("template");
    template.innerHTML = rendered;
    placeholder.replaceWith(template.content.cloneNode(true));
  }
  const tablePreview = academicTablePreviewHtml(root, document);
  if (tablePreview) return tablePreview;
  return root.innerHTML.trim();
}

function sanitizeLatexmlFragmentCached(
  html: string,
  assetUrl: string | undefined,
  assetFileUrls: ReaderAssetFile[],
  referenceTargets: ReferenceTargets
) {
  const key = [
    hashString(html),
    assetUrl ?? "",
    assetFileUrls.map((file) => `${file.originalReference}:${file.url}`).join("|"),
    Object.keys(referenceTargets).length
  ].join("::");
  const cached = sanitizedHtmlCache.get(key);
  if (cached !== undefined) return cached;
  return sanitizedHtmlCache.set(
    key,
    sanitizeLatexmlFragment(html, assetUrl, assetFileUrls, referenceTargets)
  );
}

function normalizeLatexmlTableFragmentHtml(html: string) {
  return html.replace(
    /<span\b([^>]*\bltx_transformed_inner\b[^>]*)>([\s\S]*?<table\b[\s\S]*?<\/table>[\s\S]*?)<\/span>/gi,
    "<div$1>$2</div>"
  );
}

function hashString(value: string) {
  let hash = 5381;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 33) ^ value.charCodeAt(index);
  }
  return (hash >>> 0).toString(36);
}

function cleanLatexmlDisplayMarkdown(value: string) {
  const withoutCiteauthor = value.replace(
    /\\citeauthor\*?(?:\s*\[[^\]]*])*\s*\{?[\w:./-]+\}?\s*/g,
    ""
  );
  const compactedCitations = withoutCiteauthor.replace(
    /\[([^\]]*?\(\d{4}[a-z]?\)[^\]]*?)]\((#bib\.[^)]+)\)/gi,
    (_match: string, label: string, href: string) =>
      `[${compactLatexmlCitationLabel(label)}](${href})`
  );
  return compactedCitations
    .replace(/\s+([,.;:])/g, "$1")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function compactLatexmlCitationLabel(label: string) {
  let normalized = collapseWhitespace(label.replace(/\u00a0/g, " "));
  const yearMatch = normalized.match(/^(.+?\(\d{4}[a-z]?\))/i);
  if (yearMatch?.[1]) normalized = yearMatch[1];
  return normalized.replace(/\s*\((\d{4}[a-z]?)\)/i, " ($1)");
}

function removeLatexmlTableRuleArtifacts(root: Element) {
  for (const row of [...root.querySelectorAll("tr")]) {
    const stripped = stripLatexmlTableRuleCommands(row.textContent ?? "");
    if (!stripped.trim()) row.remove();
  }
  for (const element of [...root.querySelectorAll("td, th, span")]) {
    const text = element.textContent ?? "";
    const stripped = stripLatexmlTableRuleCommands(text);
    if (stripped === text) continue;
    if (stripped.trim()) {
      element.textContent = stripped;
    } else {
      element.remove();
    }
  }
}

function stripLatexmlTableRuleCommands(value: string) {
  return value
    .replace(
      /\\(?:toprule|midrule|bottomrule|cmidrule)(?:\s*\{[^}]*}|\s*\([^)]*\)|\s*\[[^\]]*])?/gi,
      ""
    )
    .replace(/\s+/g, " ");
}

function academicTablePreviewHtml(root: Element, document: Document) {
  const tables = [...root.querySelectorAll("table")];
  if (tables.length === 0) return "";
  const container = document.createElement("div");
  container.setAttribute("class", "academic-table-set");
  for (const sourceTable of tables) {
    const table = sourceTable.cloneNode(true) as HTMLTableElement;
    promoteHeaderRow(table, document);
    const wrapper = document.createElement("div");
    wrapper.setAttribute("class", "academic-table-scroll");
    wrapper.appendChild(table);
    container.appendChild(wrapper);
  }
  return container.innerHTML.trim();
}

function promoteHeaderRow(table: HTMLTableElement, document: Document) {
  if (table.querySelector("th")) return;
  const rows = [...table.querySelectorAll("tr")];
  const headerRow = rows.find((row) => collapseWhitespace(row.textContent ?? ""));
  if (!headerRow) return;
  for (const cell of [...headerRow.children]) {
    if (cell.tagName.toLowerCase() !== "td") continue;
    const header = document.createElement("th");
    for (const attribute of [...cell.attributes]) {
      header.setAttribute(attribute.name, attribute.value);
    }
    while (cell.firstChild) header.appendChild(cell.firstChild);
    cell.replaceWith(header);
  }
}

function normalizeLatex(value: string) {
  return normalizeLatexCommandGroups(value)
    .trim()
    .replace(/^\\\(/, "")
    .replace(/\\\)$/, "")
    .replace(/^\$\$/, "")
    .replace(/\$\$$/, "")
    .replace(/^\$/, "")
    .replace(/\$$/, "")
    .replace(/%\s*[\r\n]\s*/g, "")
    .replace(/\\displaystyle\s*/g, "")
    .replace(/\\coloneqq\b/g, ":=")
    .replace(/\\eqqcolon\b/g, "\\mathrel{=:}")
    .replace(/\\buildrel\s*{([^{}]+)}\s*\\over\s*{([^{}]+)}/g, "\\overset{$1}{$2}")
    .replace(/\\expectationvalue\s*\{((?:[^{}]|\{[^{}]*})+)}/g, "\\left\\langle $1 \\right\\rangle")
    .replace(/(\\begin\{(?:[pbvVB]?matrix|smallmatrix|matrix)})\s*\[[^\]]+]/g, "$1")
    .replace(/(\\begin\{array})\s*\[\]\s*(\{[^}]+})/g, "$1$2")
    .replace(/\\begin\{(?:split|eqnarray\*?|IEEEeqnarray\*?)}/g, "\\begin{aligned}")
    .replace(/\\end\{(?:split|eqnarray\*?|IEEEeqnarray\*?)}/g, "\\end{aligned}")
    .replace(/\\begin\{(?:equation|equation\*)}/g, "")
    .replace(/\\end\{(?:equation|equation\*)}/g, "")
    .replace(/\\(big|Big|bigg|Bigg)([lrm]?)\s*\{\s*(\\?[{}()[\]|.])\s*}/g, "\\$1$2$3")
    .replace(/\{\\rm\s+([^{}]+)}/g, "\\mathrm{$1}")
    .replace(/\\mspace\s*{[^{}]*}/g, "")
    .replace(/\\strut\b/g, "")
    .replace(/\\xspace\b|\\protect\b/g, "")
    .replace(/\\(?:label|vref|pageref|autoref|cref|Cref)\s*{[^{}]*}/g, "")
    .replace(/\\eqref\s*{[^{}]*}/g, "(\\text{?})")
    .replace(/\\ref\s*{[^{}]*}/g, "\\text{?}")
    .replace(/\\iddots\b/g, "\\ddots")
    .replace(/\\hline\s*\\cr\s*(?:\\\\\s*(?:\[[^\]]+])?)?/g, "\\\\")
    .replace(/\\(?:cline|cmidrule)\s*(?:\[[^\]]+])?\s*{[^{}]*}/g, "")
    .replace(/\\vline\b/g, "|")
    .replace(/\\hfill\b|\\dotfill\b|\\hrulefill\b/g, "")
    .replace(/\\\\\s*\[[^\]]+]/g, "\\\\")
    .replace(/\\cr/g, "\\\\")
    .replace(/\\(?:no)?pagebreak\s*(?:\[[^\]]+])?/g, "")
    .replace(/\\(?:linebreak|break)\s*(?:\[[^\]]+])?/g, "")
    .replace(/\\\\\s*\\\\/g, "\\\\")
    .trim();
}

function normalizeLatexCommandGroups(value: string) {
  let normalized = normalizeLegacyTextFontCommands(value);
  normalized = applyLatexCommandGroupRules(normalized);
  normalized = replaceLatexCommandGroup(normalized, "pmatrix", (body) => {
    return `\\begin{pmatrix}${body}\\end{pmatrix}`;
  });
  normalized = replaceLatexCommandGroup(normalized, "textsc", (body) => {
    return `\\text{${body.toUpperCase()}}`;
  });
  normalized = replaceLatexCommandGroup(normalized, "mbox", normalizeMboxCommand);
  normalized = stripRaiseboxWrappers(normalized);
  return normalized;
}

function applyLatexCommandGroupRules(value: string) {
  let normalized = value;
  for (const rule of latexCompatibilityCommandGroupRules) {
    for (const command of rule.commands) {
      normalized = replaceLatexCommandGroups(normalized, command, rule.group_count, (groups) =>
        renderLatexCommandRule(rule, groups)
      );
    }
  }
  if (latexCompatibilitySingleTokenCommands.length > 0) {
    const commands = latexCompatibilitySingleTokenCommands
      .map((command) => escapeRegex(command))
      .join("|");
    normalized = normalized.replace(
      new RegExp(`\\\\(?:${commands})\\s+([A-Za-z0-9])`, "g"),
      "\\mathbb{$1}"
    );
  }
  return normalized;
}

function renderLatexCommandRule(rule: LatexCommandGroupRule, groups: string[]) {
  if (rule.strategy === "template") {
    return renderLatexTemplate(rule.replacement ?? "", groups);
  }
  if (rule.strategy === "unwrap") {
    return groups[0] ?? "";
  }
  if (rule.strategy === "keep_arg") {
    return groups[rule.keep_arg_index ?? 0] ?? "";
  }
  return "";
}

function renderLatexTemplate(template: string, groups: string[]) {
  return groups.reduce((result, group, index) => {
    return result.replaceAll(`#${index + 1}`, group);
  }, template);
}

function escapeRegex(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function replaceLatexCommandGroups(
  value: string,
  command: string,
  groupCount: number,
  replace: (groups: string[]) => string
) {
  const marker = `\\${command}`;
  const parts: string[] = [];
  let index = 0;
  while (index < value.length) {
    if (
      value.startsWith(marker, index) &&
      !isLatexCommandChar(value.slice(index + marker.length, index + marker.length + 1))
    ) {
      let cursor = skipSpaces(value, index + marker.length);
      const groups: string[] = [];
      for (let groupIndex = 0; groupIndex < groupCount; groupIndex += 1) {
        const parsed = readLatexBracedGroup(value, cursor);
        if (!parsed) break;
        groups.push(parsed.body);
        cursor = skipSpaces(value, parsed.end);
      }
      if (groups.length === groupCount) {
        parts.push(replace(groups));
        index = cursor;
        continue;
      }
    }
    parts.push(value[index] ?? "");
    index += 1;
  }
  return parts.join("");
}

function normalizeLegacyTextFontCommands(value: string) {
  const legacyCommandNames = "bf|it|rm|sf|sl|tt";
  return value
    .replace(
      new RegExp(`\\\\text\\{\\s*\\\\(${legacyCommandNames})\\s+([^{}]+)\\}`, "g"),
      (_match, commandName: keyof typeof legacyTextFontCommands, body: string) => {
        const command = legacyTextFontCommands[commandName][0];
        return `\\${command}{${body.trim()}}`;
      }
    )
    .replace(
      new RegExp(`\\{\\\\(${legacyCommandNames})\\s+([^{}]+)\\}`, "g"),
      (_match, commandName: keyof typeof legacyTextFontCommands, body: string) => {
        const command = legacyTextFontCommands[commandName][1];
        return `\\${command}{${body.trim()}}`;
      }
    );
}

function replaceLatexCommandGroup(
  value: string,
  command: string,
  replace: (body: string) => string
) {
  const marker = `\\${command}`;
  const parts: string[] = [];
  let index = 0;
  while (index < value.length) {
    if (
      value.startsWith(marker, index) &&
      !isLatexCommandChar(value.slice(index + marker.length, index + marker.length + 1))
    ) {
      const groupStart = skipSpaces(value, index + marker.length);
      const parsed = readLatexBracedGroup(value, groupStart);
      if (parsed) {
        parts.push(replace(parsed.body));
        index = parsed.end;
        continue;
      }
    }
    parts.push(value[index] ?? "");
    index += 1;
  }
  return parts.join("");
}

function stripRaiseboxWrappers(value: string) {
  const marker = "\\raisebox";
  const parts: string[] = [];
  let index = 0;
  while (index < value.length) {
    if (
      value.startsWith(marker, index) &&
      !isLatexCommandChar(value.slice(index + marker.length, index + marker.length + 1))
    ) {
      let cursor = skipSpaces(value, index + marker.length);
      const height = readLatexBracedGroup(value, cursor);
      if (height) {
        cursor = skipOptionalLatexGroups(value, height.end);
        const body = readLatexBracedGroup(value, cursor);
        if (body) {
          parts.push(stripMathDelimiters(body.body));
          index = body.end;
          continue;
        }
      }
    }
    parts.push(value[index] ?? "");
    index += 1;
  }
  return parts.join("");
}

function normalizeMboxCommand(body: string) {
  if (!body) return "";
  return splitLatexDollarSegments(body)
    .map(({ text, math }) => {
      if (!text) return "";
      return math ? text : `\\text{${text}}`;
    })
    .join("");
}

function splitLatexDollarSegments(value: string) {
  const segments: Array<{ text: string; math: boolean }> = [];
  let start = 0;
  let math = false;
  for (let index = 0; index < value.length; index += 1) {
    if (value[index] !== "$" || value[index - 1] === "\\") continue;
    segments.push({ text: value.slice(start, index), math });
    math = !math;
    start = index + 1;
  }
  segments.push({ text: value.slice(start), math });
  return segments;
}

function stripMathDelimiters(value: string) {
  const stripped = value.trim();
  if (stripped.startsWith("$") && stripped.endsWith("$") && stripped.length >= 2) {
    return stripped.slice(1, -1);
  }
  return stripped;
}

function readLatexBracedGroup(value: string, openIndex: number) {
  if (openIndex >= value.length || value[openIndex] !== "{") return null;
  let depth = 0;
  for (let index = openIndex; index < value.length; index += 1) {
    const char = value[index];
    if (char === "\\") {
      index += 1;
      continue;
    }
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return { body: value.slice(openIndex + 1, index), end: index + 1 };
      }
    }
  }
  return null;
}

function skipOptionalLatexGroups(value: string, index: number) {
  let cursor = skipSpaces(value, index);
  while (value[cursor] === "[") {
    const end = value.indexOf("]", cursor + 1);
    if (end < 0) return cursor;
    cursor = skipSpaces(value, end + 1);
  }
  return cursor;
}

function skipSpaces(value: string, index: number) {
  let cursor = index;
  while (/\s/.test(value[cursor] ?? "")) cursor += 1;
  return cursor;
}

function isLatexCommandChar(value: string) {
  return /^[A-Za-z@]$/.test(value);
}

function sanitizeElement(
  element: Element,
  document: Document,
  imageUrls: Map<string, string>,
  referenceTargets: ReferenceTargets
) {
  for (const child of [...element.children]) {
    sanitizeElement(child, document, imageUrls, referenceTargets);
  }
  const tag = element.tagName.toLowerCase();
  const originalAttributes = new Map(
    [...element.attributes].map((attribute) => [attribute.name.toLowerCase(), attribute.value])
  );
  const allowedTags = new Set([
    "a",
    "b",
    "br",
    "div",
    "em",
    "figure",
    "i",
    "img",
    "p",
    "small",
    "span",
    "strong",
    "sub",
    "sup",
    "table",
    "tbody",
    "td",
    "tfoot",
    "th",
    "thead",
    "tr",
    "svg",
    "g",
    "path",
    "circle",
    "rect",
    "line",
    "polyline",
    "polygon",
    "ellipse",
    "text",
    "tspan",
    "defs",
    "marker",
    "foreignobject"
  ]);
  if (!allowedTags.has(tag)) {
    const fragment = document.createDocumentFragment();
    while (element.firstChild) fragment.appendChild(element.firstChild);
    element.replaceWith(fragment);
    return;
  }
  const href = element.getAttribute("href");
  const originalReference = element.getAttribute("src") ?? "";
  const alt = element.getAttribute("alt") ?? "article asset";
  const colspan = element.getAttribute("colspan");
  const rowspan = element.getAttribute("rowspan");
  const mathIndex = element.getAttribute("data-bilin-math-index");
  for (const attribute of [...element.attributes]) {
    element.removeAttribute(attribute.name);
  }
  if (tag === "span" && mathIndex && /^\d+$/.test(mathIndex)) {
    element.setAttribute("data-bilin-math-index", mathIndex);
  }
  if (tag === "a") {
    const resolvedHref = resolveReferenceHref(href ?? undefined, referenceTargets);
    if (resolvedHref?.startsWith("#")) {
      element.setAttribute("href", resolvedHref);
      element.setAttribute("class", "xref-link");
    }
  }
  if (tag === "img") {
    const url = imageUrls.get(originalReference);
    if (!url) {
      element.remove();
      return;
    }
    element.setAttribute("src", url);
    element.setAttribute("alt", alt);
    element.setAttribute("class", "asset-image");
  }
  if (tag === "td" || tag === "th") {
    copyTableSpanAttribute(element, "colspan", colspan);
    copyTableSpanAttribute(element, "rowspan", rowspan);
  }
  copySafeSvgAttributes(element, tag, originalAttributes);
}

const SVG_TAGS = new Set([
  "svg",
  "g",
  "path",
  "circle",
  "rect",
  "line",
  "polyline",
  "polygon",
  "ellipse",
  "text",
  "tspan",
  "defs",
  "marker",
  "foreignobject"
]);

const SAFE_SVG_ATTRIBUTES = new Set([
  "class",
  "cx",
  "cy",
  "d",
  "fill",
  "height",
  "id",
  "marker-end",
  "marker-mid",
  "marker-start",
  "overflow",
  "points",
  "r",
  "rx",
  "ry",
  "stroke",
  "stroke-dasharray",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-miterlimit",
  "stroke-width",
  "transform",
  "version",
  "viewbox",
  "width",
  "x",
  "x1",
  "x2",
  "y",
  "y1",
  "y2"
]);

function copySafeSvgAttributes(
  element: Element,
  tag: string,
  originalAttributes: Map<string, string>
) {
  if (!SVG_TAGS.has(tag)) return;
  for (const [name, value] of originalAttributes) {
    if (!SAFE_SVG_ATTRIBUTES.has(name)) continue;
    if (!safeSvgAttributeValue(value)) continue;
    element.setAttribute(name === "viewbox" ? "viewBox" : name, value);
  }
  if (tag === "svg") {
    element.classList.add("latexml-inline-svg");
    element.setAttribute("aria-hidden", "true");
    element.removeAttribute("id");
  }
}

function safeSvgAttributeValue(value: string) {
  return !/(?:javascript:|data:|url\s*\()/i.test(value);
}

function copyTableSpanAttribute(
  element: Element,
  name: "colspan" | "rowspan",
  value: string | null
) {
  if (!value) return;
  const parsed = Number.parseInt(value, 10);
  if (Number.isFinite(parsed) && parsed > 1 && parsed < 100) {
    element.setAttribute(name, String(parsed));
  }
}
