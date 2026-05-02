import { Badge, Button, Group, Select, Text } from "@mantine/core";
import katex from "katex";
import { Languages } from "lucide-react";
import { useMemo, useState } from "react";
import ReactMarkdown from "react-markdown";

import type { AssetRecord, DocumentBlock } from "../api/types";
import type { ReaderViewMode } from "../state/ui";
import { HoverToolbar } from "./HoverToolbar";
import type { ReaderToolbarActionId } from "./readerToolbarActions";

export interface ReferenceTarget {
  blockUid: string;
  blockType: string;
}

export type ReferenceTargets = Record<string, ReferenceTarget>;

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
  onActivate?: (blockUid: string) => void;
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
  onActivate,
  onTranslationVariantChange,
  onToolbarAction
}: ReaderBlockProps) {
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

  if (isStructuralBlock(block)) {
    return (
      <section
        className={`reader-block structural-block structural-block-${structuralRole(block)} structural-block-level-${structuralDisplayLevel(block)}${active ? " reader-block-active" : ""}${focusClass}`}
        id={block.block_uid}
        onFocusCapture={activateBlock}
        onMouseEnter={activateBlock}
      >
        <HoverToolbar
          kind="environment"
          onAction={(actionId) => onToolbarAction?.(actionId, block, block.source_markdown)}
        />
        <StructuralContent block={block} />
      </section>
    );
  }

  if (["equation", "figure", "table", "algorithm"].includes(block.block_type)) {
    return (
      <section
        className={`reader-block environment-block${active ? " reader-block-active" : ""}${focusClass}`}
        id={block.block_uid}
        onFocusCapture={activateBlock}
        onMouseEnter={activateBlock}
      >
        <HoverToolbar
          kind="environment"
          onAction={(actionId) => onToolbarAction?.(actionId, block, block.source_markdown)}
        />
        {["figure", "table"].includes(block.block_type) ? (
          <AssetPreview
            kind={block.block_type}
            asset={asset}
            assetUrl={assetUrl}
            assetFileUrls={assetFileUrls}
            referenceTargets={referenceTargets}
          />
        ) : null}
        <BlockContent
          block={block}
          content={block.source_markdown}
          referenceTargets={referenceTargets}
        />
        {translation ? (
          <div className="caption-translation">
            {glossaryAffected ? <GlossaryBadge /> : null}
            <MarkdownContent content={translation} referenceTargets={referenceTargets} />
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
    return (
      <section
        className={`reader-block text-block study-block${active ? " reader-block-active" : ""}${focusClass}`}
        id={block.block_uid}
        onFocusCapture={activateBlock}
        onMouseEnter={activateBlock}
      >
        <article className="block-pane source-pane study-source-pane">
          <HoverToolbar
            kind="source"
            onAction={(actionId) => onToolbarAction?.(actionId, block, block.source_markdown)}
          />
          <BlockContent
            block={block}
            content={block.source_markdown}
            referenceTargets={referenceTargets}
          />
          <Group className="study-translation-controls" justify="space-between">
            <Button
              size="xs"
              variant={translationOpen ? "light" : "subtle"}
              leftSection={<Languages size={14} />}
              disabled={activeFocus}
              onClick={() => setTranslationExpanded((open) => !open)}
            >
              {activeFocus
                ? "Translation open"
                : translationOpen
                  ? "Hide translation"
                  : "Show translation"}
            </Button>
            {activeFocus ? (
              <Text size="xs" c="dimmed">
                Focus auto-expanded
              </Text>
            ) : null}
          </Group>
          {translationOpen ? (
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
                <p className="translation-placeholder">Translation pending.</p>
              )}
              <TranslationVariantSelect
                blockUid={block.block_uid}
                options={translationVariantOptions}
                selectedVariantId={selectedTranslationVariantId}
                onChange={onTranslationVariantChange}
              />
            </section>
          ) : null}
        </article>
      </section>
    );
  }

  const blockLayoutClass =
    viewMode === "bilingual" ? "paired-block" : `single-block single-block-${viewMode}`;

  return (
    <section
      className={`reader-block text-block ${blockLayoutClass}${active ? " reader-block-active" : ""}`}
      id={block.block_uid}
      onFocusCapture={activateBlock}
      onMouseEnter={activateBlock}
    >
      {viewMode !== "translation" ? (
        <article className="block-pane source-pane">
          <HoverToolbar
            kind="source"
            onAction={(actionId) => onToolbarAction?.(actionId, block, block.source_markdown)}
          />
          <BlockContent
            block={block}
            content={block.source_markdown}
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
            <p className="translation-placeholder">Translation pending.</p>
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
  if (options.length < 2) return null;
  return (
    <Select
      className="translation-variant-select"
      label={`Translation variant for ${blockUid}`}
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
  return (
    <Badge color="yellow" variant="light" size="sm" className="glossary-badge">
      Glossary changed
    </Badge>
  );
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
  referenceTargets
}: {
  block: DocumentBlock;
  content: string;
  referenceTargets: ReferenceTargets;
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
    />
  );
}

function MarkdownContent({
  content,
  referenceTargets
}: {
  content: string;
  referenceTargets: ReferenceTargets;
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
        }
      }}
    >
      {content}
    </ReactMarkdown>
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
            <img
              className="asset-image"
              src={file.url}
              alt={asset?.caption ?? `${kind} asset ${file.index}`}
              key={`${file.originalReference}-${file.index}`}
            />
          ))}
        </figure>
      );
    }
    return <img className="asset-image" src={assetUrl} alt={asset?.caption ?? kind} />;
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
  for (const math of [...root.querySelectorAll("math")]) {
    const text = math.getAttribute("alttext") || math.textContent || "";
    math.replaceWith(document.createTextNode(text));
  }
  for (const caption of [...root.querySelectorAll("figcaption, caption")]) {
    caption.remove();
  }
  sanitizeElement(root, document, imageUrls, referenceTargets);
  return root.innerHTML.trim();
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
  for (const attribute of [...element.attributes]) {
    element.removeAttribute(attribute.name);
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
