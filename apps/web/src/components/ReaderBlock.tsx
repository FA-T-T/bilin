import { Badge, Group, Select, Tooltip } from "@mantine/core";
import katex from "katex";
import { Languages } from "lucide-react";
import {
  Children,
  Fragment,
  type CSSProperties,
  type ReactNode,
  useMemo,
  useRef,
  useState
} from "react";
import ReactMarkdown from "react-markdown";

import type { AssetRecord, DocumentBlock } from "../api/types";
import { useT, type MessageKey } from "../i18n";
import type { ReaderViewMode } from "../state/ui";
import { HoverToolbar } from "./HoverToolbar";
import type { ReaderToolbarActionId } from "./readerToolbarActions";

export interface ReferenceTarget {
  blockUid: string;
  blockType: string;
}

export type ReferenceTargets = Record<string, ReferenceTarget>;
export type ReaderBlockColor = "none" | "yellow" | "blue" | "green" | "pink" | "purple";

export interface ReaderAssetFile {
  index: number;
  originalReference: string;
  url: string;
}

interface ReaderBlockProps {
  block: DocumentBlock;
  asset?: AssetRecord;
  assetUrl?: string;
  assetFileUrls?: ReaderAssetFile[];
  referenceTargets?: ReferenceTargets;
  translation?: string;
  translationVariantOptions?: { value: string; label: string }[];
  selectedTranslationVariantId?: string;
  glossaryAffected?: boolean;
  viewMode: ReaderViewMode;
  active?: boolean;
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

export function ReaderBlock({
  block,
  asset,
  assetUrl,
  assetFileUrls = [],
  referenceTargets = {},
  translation,
  translationVariantOptions = [],
  selectedTranslationVariantId,
  glossaryAffected = false,
  viewMode,
  active = false,
  blockColor = "none",
  onActivate,
  onBlockColorChange,
  onTranslationVariantChange,
  onToolbarAction
}: ReaderBlockProps) {
  const t = useT();
  const displayBlock = displayBlockForReader(block, asset);
  const activateBlock = () => onActivate?.(block.block_uid);
  const [translationExpanded, setTranslationExpanded] = useState(false);
  const focusMode = viewMode === "focus";
  const activeFocus = focusMode && active;
  const translationOpen = translationExpanded || activeFocus;
  const translationText = translation ?? "";
  const focusClass = focusMode
    ? active
      ? " reader-block-focus-current"
      : " reader-block-dimmed"
    : "";
  const colorClass = blockColor === "none" ? "" : ` reader-block-color-${blockColor}`;
  const hoverActivate = focusMode ? undefined : activateBlock;
  const environmentTranslation = environmentTranslationForReader(displayBlock, translation);
  const lastPointerToggleAt = useRef(0);
  const showEnvironmentTranslation =
    Boolean(environmentTranslation) && displayBlock.block_type !== "equation";
  const toggleTranslationLabel = translationOpen
    ? t("reader.hideTranslation")
    : t("reader.showTranslation");

  if (isStructuralBlock(displayBlock)) {
    return (
      <section
        className={`reader-block structural-block structural-block-${structuralRole(displayBlock)} structural-block-level-${structuralDisplayLevel(displayBlock)}${active ? " reader-block-active" : ""}${focusClass}`}
        id={block.block_uid}
        onFocusCapture={activateBlock}
        onMouseEnter={hoverActivate}
      >
        <HoverToolbar
          kind="environment"
          onAction={(actionId) =>
            onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
          }
        />
        <StructuralContent block={displayBlock} />
      </section>
    );
  }

  if (["equation", "figure", "table", "algorithm"].includes(displayBlock.block_type)) {
    return (
      <section
        className={`reader-block environment-block environment-block-${displayBlock.block_type} environment-block-${viewMode}${active ? " reader-block-active" : ""}${focusClass}`}
        id={block.block_uid}
        onFocusCapture={activateBlock}
        onMouseEnter={hoverActivate}
      >
        <HoverToolbar
          kind="environment"
          onAction={(actionId) =>
            onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
          }
        />
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
        />
        {showEnvironmentTranslation ? (
          <div className="caption-translation">
            {glossaryAffected ? <GlossaryBadge /> : null}
            <MarkdownContent
              content={environmentTranslation ?? ""}
              referenceTargets={referenceTargets}
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

  if (viewMode === "study" || viewMode === "focus") {
    const toggleStudyTranslation = () => setTranslationExpanded((open) => !open);
    const manualStudyTranslationOpen = viewMode === "study" && translationExpanded;
    const translationToggle = (
      <button
        type="button"
        className="study-translation-toggle"
        data-translation-open={translationOpen ? "true" : undefined}
        aria-label={activeFocus ? t("reader.translationOpen") : toggleTranslationLabel}
        title={activeFocus ? t("reader.translationOpen") : toggleTranslationLabel}
        disabled={activeFocus}
        onPointerDown={(event) => {
          if (activeFocus) return;
          event.preventDefault();
          event.stopPropagation();
          lastPointerToggleAt.current = Date.now();
          toggleStudyTranslation();
        }}
        onMouseDown={(event) => {
          if (activeFocus) return;
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
        className={`reader-block text-block study-block${manualStudyTranslationOpen ? " study-block-translation-open" : ""}${focusMode ? " focus-study-block" : ""}${active ? " reader-block-active" : ""}${focusClass}${colorClass}`}
        id={block.block_uid}
        onFocusCapture={activateBlock}
        onMouseEnter={hoverActivate}
      >
        <BlockColorPalette
          blockUid={block.block_uid}
          value={blockColor}
          onChange={onBlockColorChange}
        />
        <article className="block-pane source-pane study-source-pane">
          <HoverToolbar
            kind="source"
            onAction={(actionId) =>
              onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
            }
          />
          <div className={`study-reading-grid${translationOpen ? " study-reading-grid-open" : ""}`}>
            <div className="study-source-content">
              <BlockContent
                block={displayBlock}
                content={displayBlock.source_markdown}
                referenceTargets={referenceTargets}
                trailingInline={displayBlock.block_type === "paragraph" ? translationToggle : null}
              />
            </div>
            {translationOpen ? (
              <aside className="study-translation-column">
                <section className="study-translation-panel translation-pane">
                  <HoverToolbar
                    kind="translation"
                    disabledActions={translation ? [] : ["copy-translation"]}
                    onAction={(actionId) => onToolbarAction?.(actionId, block, translationText)}
                  />
                  {glossaryAffected ? <GlossaryBadge /> : null}
                  {translation ? (
                    <MarkdownContent content={translation} referenceTargets={referenceTargets} />
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
      className={`reader-block text-block ${blockLayoutClass}${active ? " reader-block-active" : ""}${colorClass}`}
      id={block.block_uid}
      onFocusCapture={activateBlock}
      onMouseEnter={hoverActivate}
    >
      <BlockColorPalette
        blockUid={block.block_uid}
        value={blockColor}
        onChange={onBlockColorChange}
      />
      {viewMode !== "translation" ? (
        <article className="block-pane source-pane">
          <HoverToolbar
            kind="source"
            onAction={(actionId) =>
              onToolbarAction?.(actionId, displayBlock, displayBlock.source_markdown)
            }
          />
          <BlockContent
            block={displayBlock}
            content={displayBlock.source_markdown}
            referenceTargets={referenceTargets}
          />
        </article>
      ) : null}
      {viewMode !== "source" ? (
        <article className="block-pane translation-pane">
          <HoverToolbar
            kind="translation"
            disabledActions={translation ? [] : ["copy-translation"]}
            onAction={(actionId) => onToolbarAction?.(actionId, block, translation ?? "")}
          />
          {glossaryAffected ? <GlossaryBadge /> : null}
          {translation ? (
            <MarkdownContent content={translation} referenceTargets={referenceTargets} />
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
  onChange
}: {
  blockUid: string;
  value: ReaderBlockColor;
  onChange?: (blockUid: string, color: ReaderBlockColor) => void;
}) {
  const t = useT();
  if (!onChange) return null;
  return (
    <Group className="block-color-palette" gap={4} aria-label={t("reader.blockColor")}>
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
  trailingInline = null
}: {
  block: DocumentBlock;
  content: string;
  referenceTargets: ReferenceTargets;
  trailingInline?: ReactNode;
}) {
  if (block.block_type === "equation") {
    return (
      <div
        className="math-block"
        dangerouslySetInnerHTML={{
          __html: katex.renderToString(content, {
            displayMode: true,
            throwOnError: false
          })
        }}
      />
    );
  }
  return (
    <MarkdownContent
      content={linkDocumentReferences(content, block, referenceTargets)}
      referenceTargets={referenceTargets}
      trailingInline={trailingInline}
    />
  );
}

function MarkdownContent({
  content,
  referenceTargets,
  trailingInline = null
}: {
  content: string;
  referenceTargets: ReferenceTargets;
  trailingInline?: ReactNode;
}) {
  return (
    <ReactMarkdown
      components={{
        a({ href, children }) {
          const resolvedHref = resolveReferenceHref(href, referenceTargets);
          const linked = resolvedHref !== href && resolvedHref?.startsWith("#");
          return (
            <a className={linked ? "xref-link" : undefined} href={resolvedHref}>
              {children}
            </a>
          );
        },
        p({ children }) {
          return (
            <p>
              {renderInlineMathChildren(children)}
              {trailingInline}
            </p>
          );
        },
        li({ children }) {
          return <li>{renderInlineMathChildren(children)}</li>;
        },
        td({ children }) {
          return <td>{renderInlineMathChildren(children)}</td>;
        },
        th({ children }) {
          return <th>{renderInlineMathChildren(children)}</th>;
        }
      }}
    >
      {content}
    </ReactMarkdown>
  );
}

function renderInlineMathChildren(children: ReactNode): ReactNode {
  return Children.map(children, (child) =>
    typeof child === "string" ? renderInlineMathText(child) : child
  );
}

function renderInlineMathText(text: string): ReactNode {
  const parts: ReactNode[] = [];
  const pattern = /\\\((.+?)\\\)|\$([^$\n]+)\$/g;
  let cursor = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text))) {
    if (match.index > cursor) parts.push(text.slice(cursor, match.index));
    const latex = match[1] ?? match[2] ?? "";
    parts.push(<InlineMath latex={latex} key={`${match.index}-${latex}`} />);
    cursor = match.index + match[0].length;
  }
  if (cursor < text.length) parts.push(text.slice(cursor));
  return parts.length > 0 ? <Fragment>{parts}</Fragment> : text;
}

function InlineMath({ latex }: { latex: string }) {
  return (
    <span
      className="inline-math"
      dangerouslySetInnerHTML={{
        __html: katex.renderToString(normalizeLatex(latex), {
          displayMode: false,
          throwOnError: false
        })
      }}
    />
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
              metadata={asset?.metadata}
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

type AssetImageLayout = "unknown" | "narrow" | "single" | "wide";
type AssetArticleLayout = "unknown" | "single-column" | "double-column" | "multi-panel";

interface LatexmlImageMetrics {
  imageCount: number;
  firstWidth?: number;
  firstHeight?: number;
  maxPanelWidthPt?: number;
  totalPanelWidthPt?: number;
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
  const metrics = latexmlImageMetricsFromMetadata(metadata);
  if (metrics.imageCount > 1 || metrics.hasFlexLayout) return "multi-panel";
  if (metrics.maxPanelWidthPt && metrics.maxPanelWidthPt >= 330) return "double-column";
  if (metrics.maxPanelWidthPt && metrics.maxPanelWidthPt > 0) return "single-column";
  const width = numericMetadata(metadata, "width", "natural_width", "pixel_width");
  const height = numericMetadata(metadata, "height", "natural_height", "pixel_height");
  if (width && height && width / height >= 1.45) return "double-column";
  return "unknown";
}

function assetImageStyleFromMetadata(metadata: AssetRecord["metadata"] | undefined): CSSProperties {
  const metrics = latexmlImageMetricsFromMetadata(metadata);
  const articleLayout = articleImageLayoutFromMetadata(metadata);
  const firstWidth =
    metrics.firstWidth ?? numericMetadata(metadata, "width", "natural_width", "pixel_width");
  const firstHeight =
    metrics.firstHeight ?? numericMetadata(metadata, "height", "natural_height", "pixel_height");
  const ratio = firstWidth && firstHeight ? firstWidth / firstHeight : undefined;
  let maxInlineSize = 480;
  let maxBlockSize = 520;

  if (articleLayout === "multi-panel") {
    const panelWidth = metrics.maxPanelWidthPt ?? (firstWidth ? firstWidth * 0.62 : 220);
    maxInlineSize = clampNumber(panelWidth, 160, 240);
    maxBlockSize = clampNumber(maxInlineSize * (ratio && ratio < 0.8 ? 1.55 : 1.25), 260, 360);
  } else if (articleLayout === "double-column") {
    maxInlineSize = 820;
    maxBlockSize = 560;
  } else if (articleLayout === "single-column") {
    maxInlineSize = clampNumber(metrics.maxPanelWidthPt ?? firstWidth ?? 460, 300, 520);
    maxBlockSize = ratio && ratio < 0.8 ? 520 : 460;
  } else if (ratio && ratio <= 0.9) {
    maxInlineSize = 340;
  } else if (ratio && ratio >= 1.35) {
    maxInlineSize = 820;
    maxBlockSize = 560;
  }

  return {
    "--asset-max-inline-size": `${Math.round(maxInlineSize)}px`,
    "--asset-max-block-size": `${Math.round(maxBlockSize)}px`
  } as CSSProperties;
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
  const html = stringMetadata(metadata, "html_fragment") ?? "";
  if (!html) return { imageCount: 0, hasFlexLayout: false };
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
    imageCount: imageTags.length,
    firstWidth: imageSizes[0]?.width,
    firstHeight: imageSizes[0]?.height,
    maxPanelWidthPt: panelWidthsPt.length > 0 ? Math.max(...panelWidthsPt) : undefined,
    totalPanelWidthPt:
      panelWidthsPt.length > 0
        ? panelWidthsPt.reduce((total, value) => total + value, 0)
        : undefined,
    hasFlexLayout: /\bltx_flex_(?:figure|cell|size_)/i.test(html)
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
    () => sanitizeLatexmlFragment(html, assetUrl, assetFileUrls, referenceTargets),
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

function linkDocumentReferences(
  content: string,
  block: DocumentBlock,
  referenceTargets: ReferenceTargets
) {
  if (content.includes("](")) return content;
  let linked = content;
  for (const reference of blockReferences(block)) {
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
      `<span class="table-math">${katex.renderToString(normalizeLatex(latex), {
        displayMode: false,
        throwOnError: false
      })}</span>`
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
