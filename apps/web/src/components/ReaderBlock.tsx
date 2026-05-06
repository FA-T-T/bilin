import { Badge, Button, Group, HoverCard, Select, Text, Tooltip } from "@mantine/core";
import katex from "katex";
import { Languages } from "lucide-react";
import {
  Children,
  cloneElement,
  Fragment,
  memo,
  type CSSProperties,
  type FocusEvent,
  isValidElement,
  type MouseEvent,
  type PointerEvent,
  type ReactNode,
  useCallback,
  useMemo,
  useRef,
  useState
} from "react";
import ReactMarkdown from "react-markdown";

import type { AssetRecord, CitationEntry, DocumentBlock } from "../api/types";
import { useT, type MessageKey } from "../i18n";
import type { ReaderViewMode } from "../state/ui";
import { HoverToolbar } from "./HoverToolbar";
import type { ReaderToolbarActionId } from "./readerToolbarActions";

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
  searchActive?: boolean;
  blockColor?: ReaderBlockColor;
  onActivate?: (blockUid: string) => void;
  onBlockColorChange?: (blockUid: string, color: ReaderBlockColor) => void;
  onTranslationVariantChange?: (blockUid: string, variantId: string) => void;
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
  searchActive = false,
  blockColor = "none",
  onActivate,
  onBlockColorChange,
  onTranslationVariantChange,
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
  const translationOpen = translationExpanded;
  const translationText = translation ?? "";
  const colorClass = blockColor === "none" ? "" : ` reader-block-color-${blockColor}`;
  const visibleControls = controlsVisible || localControlsVisible;
  const searchClass = searchActive ? " reader-block-search-current" : "";
  const environmentTranslation = environmentTranslationForReader(displayBlock, translation);
  const sentenceHighlightPlan = createSentenceHighlightPlan(
    displayBlock,
    translationText,
    viewMode
  );
  const lastPointerToggleAt = useRef(0);
  const showEnvironmentTranslation =
    Boolean(environmentTranslation) && displayBlock.block_type !== "equation";
  const toggleTranslationLabel = translationOpen
    ? t("reader.hideTranslation")
    : t("reader.showTranslation");
  const showControls = () => setLocalControlsVisible(true);
  const hideControls = () => setLocalControlsVisible(false);
  const activateFromPointer = (event: PointerEvent<HTMLElement>) => {
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
        className={`reader-block structural-block structural-block-${structuralRole(displayBlock)} structural-block-level-${structuralDisplayLevel(displayBlock)}${active ? " reader-block-active" : ""}${searchClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onPointerEnter={activateFromPointer}
        onPointerLeave={hideControls}
      >
        {visibleControls ? (
          <HoverToolbar
            kind="environment"
            onAction={(actionId) =>
              onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
            }
          />
        ) : null}
        <StructuralContent block={displayBlock} />
      </section>
    );
  }

  if (["equation", "figure", "table", "algorithm"].includes(displayBlock.block_type)) {
    return (
      <section
        className={`reader-block environment-block environment-block-${displayBlock.block_type} environment-block-${viewMode}${active ? " reader-block-active" : ""}${searchClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onPointerEnter={activateFromPointer}
        onPointerLeave={hideControls}
      >
        {visibleControls ? (
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
        className={`reader-block text-block study-block${manualStudyTranslationOpen ? " study-block-translation-open" : ""}${active ? " reader-block-active" : ""}${searchClass}${colorClass}`}
        id={block.block_uid}
        onBlur={handleBlur}
        onFocusCapture={activateFromFocus}
        onPointerEnter={activateFromPointer}
        onPointerLeave={hideControls}
      >
        <article className="block-pane source-pane study-source-pane">
          <div className={`study-reading-grid${translationOpen ? " study-reading-grid-open" : ""}`}>
            <div className="study-source-content">
              <BlockColorMarker value={blockColor} side="source" />
              {visibleControls ? (
                <BlockColorPalette
                  blockUid={block.block_uid}
                  value={blockColor}
                  onChange={onBlockColorChange}
                  className="source-color-palette"
                />
              ) : null}
              {visibleControls ? (
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
                  <BlockColorMarker value={blockColor} side="translation" />
                  {visibleControls ? (
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
      </section>
    );
  }

  const blockLayoutClass =
    viewMode === "bilingual" ? "paired-block" : `single-block single-block-${viewMode}`;

  return (
    <section
      className={`reader-block text-block ${blockLayoutClass}${active ? " reader-block-active" : ""}${searchClass}${colorClass}`}
      id={block.block_uid}
      onBlur={handleBlur}
      onFocusCapture={activateFromFocus}
      onPointerEnter={activateFromPointer}
      onPointerLeave={hideControls}
    >
      {viewMode !== "translation" ? (
        <article className="block-pane source-pane">
          <BlockColorMarker value={blockColor} side="source" />
          {visibleControls ? (
            <BlockColorPalette
              blockUid={block.block_uid}
              value={blockColor}
              onChange={onBlockColorChange}
              className="source-color-palette"
            />
          ) : null}
          {visibleControls ? (
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
          <BlockColorMarker value={blockColor} side="translation" />
          {viewMode === "translation" && visibleControls ? (
            <BlockColorPalette
              blockUid={block.block_uid}
              value={blockColor}
              onChange={onBlockColorChange}
              className="translation-color-palette"
            />
          ) : null}
          {visibleControls ? (
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
    left.searchActive === right.searchActive &&
    left.blockColor === right.blockColor &&
    left.onActivate === right.onActivate &&
    left.onBlockColorChange === right.onBlockColorChange &&
    left.onTranslationVariantChange === right.onTranslationVariantChange &&
    left.onToolbarAction === right.onToolbarAction
  );
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
    event: PointerEvent<HTMLButtonElement>,
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
    return {
      ...block,
      block_type: "equation",
      source_markdown: latex,
      source_latex: block.source_latex ?? latex,
      metadata: {
        ...block.metadata,
        display: "block",
        tex: latex
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
  return value
    .replace(/%\s*[\r\n]\s*/g, "")
    .replace(/\\displaystyle\s*/g, "")
    .trim();
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
  if (block.block_type === "equation") {
    return (
      <div
        className="math-block"
        dangerouslySetInnerHTML={{
          __html: renderKatexCached(content, true)
        }}
      />
    );
  }
  return (
    <MarkdownContent
      content={linkDocumentReferencesCached(content, block, referenceTargets, citations)}
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
          return (
            <a className={linked ? "xref-link" : undefined} href={resolvedHref}>
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

function AssetPreview({
  kind,
  asset,
  assetUrl,
  assetFileUrls,
  referenceTargets
}: {
  kind: string;
  asset?: AssetRecord;
  assetUrl?: string;
  assetFileUrls: ReaderAssetFile[];
  referenceTargets: ReferenceTargets;
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
              key={`${file.originalReference}-${file.index}`}
            />
          ))}
        </figure>
      );
    }
    return (
      <AdaptiveAssetImage src={assetUrl} alt={asset?.caption ?? kind} metadata={asset?.metadata} />
    );
  }
  if (htmlFragment && htmlFragment.includes("<table")) {
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

function AdaptiveAssetImage({
  src,
  alt,
  metadata
}: {
  src: string;
  alt: string;
  metadata?: AssetRecord["metadata"];
}) {
  const articleLayout = articleImageLayoutFromMetadata(metadata);
  const [layout, setLayout] = useState<AssetImageLayout>(() => imageLayoutFromMetadata(metadata));
  return (
    <img
      className={`asset-image asset-image-${layout} asset-image-article-${articleLayout}`}
      data-article-layout={articleLayout}
      data-asset-layout={layout}
      style={assetImageStyleFromMetadata(metadata)}
      src={src}
      alt={alt}
      onLoad={(event) => {
        const image = event.currentTarget;
        setLayout(classifyImageLayout(image.naturalWidth, image.naturalHeight));
      }}
    />
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
  const document = new DOMParser().parseFromString(`<div>${html}</div>`, "text/html");
  const root = document.body.firstElementChild;
  if (!root) return "";
  for (const element of [...root.querySelectorAll("script, style, iframe, object, embed")]) {
    element.remove();
  }
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

function hashString(value: string) {
  let hash = 5381;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 33) ^ value.charCodeAt(index);
  }
  return (hash >>> 0).toString(36);
}

function normalizeLatex(value: string) {
  return value
    .trim()
    .replace(/^\\\(/, "")
    .replace(/\\\)$/, "")
    .replace(/^\$\$/, "")
    .replace(/\$\$$/, "")
    .replace(/^\$/, "")
    .replace(/\$$/, "")
    .replace(/\\displaystyle\s*/g, "")
    .trim();
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
    "tr"
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
