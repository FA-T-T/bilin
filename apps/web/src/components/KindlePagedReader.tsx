import type { CSSProperties, MouseEvent, ReactNode } from "react";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";

import type { DocumentBlock } from "../api/types";

interface KindlePagedReaderProps {
  blocks: DocumentBlock[];
  activeBlockUid: string | null;
  title: string;
  fontScale?: number;
  pageLayout?: "auto" | "landscape";
  getBlockText?: (block: DocumentBlock) => string;
  renderBlock: (block: DocumentBlock) => ReactNode;
  onPageBlockChange: (blockUid: string) => void;
  onNavigateToBlock?: (blockUid: string) => void;
  onPageTurn?: () => void;
  previousLabel: string;
  nextLabel: string;
  pageLabel: (current: number, total: number) => string;
}

interface KindlePage {
  id: string;
  contextBlocks: DocumentBlock[];
  blocks: DocumentBlock[];
  startBlockUid: string;
}

interface KindlePageMetrics {
  charBudget: number;
  contentHeight: number;
  measureWidth: number;
}

interface MeasuredKindleBlocks {
  key: string;
  heights: Record<string, number>;
}

const defaultGetBlockText = (block: DocumentBlock) => block.source_markdown;

export function KindlePagedReader({
  blocks,
  activeBlockUid,
  title,
  fontScale = 1,
  pageLayout = "auto",
  getBlockText = defaultGetBlockText,
  renderBlock,
  onPageBlockChange,
  onNavigateToBlock,
  onPageTurn,
  previousLabel,
  nextLabel,
  pageLabel
}: KindlePagedReaderProps) {
  const viewport = useViewportSize();
  const measureRoot = useRef<HTMLDivElement | null>(null);
  const metrics = useMemo(
    () => kindlePageMetrics(viewport.width, viewport.height, fontScale),
    [fontScale, viewport.height, viewport.width]
  );
  const measureKey = useMemo(
    () =>
      [
        Math.round(metrics.measureWidth),
        Math.round(metrics.contentHeight),
        fontScale,
        blocks.map((block) => block.block_uid).join(":")
      ].join("|"),
    [blocks, fontScale, metrics.contentHeight, metrics.measureWidth]
  );
  const [measuredBlocks, setMeasuredBlocks] = useState<MeasuredKindleBlocks | null>(null);
  const estimatedPages = useMemo(
    () => paginateKindlePages(blocks, getBlockText, metrics.charBudget),
    [blocks, getBlockText, metrics.charBudget]
  );
  const measuredPages = useMemo(
    () =>
      measuredBlocks?.key === measureKey
        ? paginateMeasuredKindlePages(blocks, getBlockText, measuredBlocks.heights, metrics)
        : [],
    [blocks, getBlockText, measureKey, measuredBlocks, metrics]
  );
  const pages = measuredPages.length > 0 ? measuredPages : estimatedPages;
  const activePageIndex = useMemo(
    () => pageIndexForBlock(pages, activeBlockUid),
    [activeBlockUid, pages]
  );
  const currentPage = pages[activePageIndex];
  const canGoPrevious = activePageIndex > 0;
  const canGoNext = activePageIndex < pages.length - 1;

  const goToPage = useCallback(
    (pageIndex: number) => {
      const page = pages[Math.min(Math.max(pageIndex, 0), Math.max(pages.length - 1, 0))];
      if (!page) return;
      onPageBlockChange(page.startBlockUid);
      onPageTurn?.();
    },
    [onPageBlockChange, onPageTurn, pages]
  );

  const goPrevious = useCallback(() => {
    if (canGoPrevious) goToPage(activePageIndex - 1);
  }, [activePageIndex, canGoPrevious, goToPage]);

  const goNext = useCallback(() => {
    if (canGoNext) goToPage(activePageIndex + 1);
  }, [activePageIndex, canGoNext, goToPage]);

  useEffect(() => {
    const firstBlockUid = currentPage?.startBlockUid;
    if (firstBlockUid && firstBlockUid !== activeBlockUid) {
      onPageBlockChange(firstBlockUid);
    }
  }, [activeBlockUid, currentPage?.startBlockUid, onPageBlockChange]);

  const updateMeasuredBlocks = useCallback(() => {
    const root = measureRoot.current;
    if (!root) return;
    const nextHeights = measureKindleBlockHeights(root);
    const hasEnoughMeasurements = blocks.every((block) => (nextHeights[block.block_uid] ?? 0) > 0);
    if (!hasEnoughMeasurements) return;
    setMeasuredBlocks((current) => {
      if (current?.key === measureKey && shallowNumberRecordEqual(current.heights, nextHeights)) {
        return current;
      }
      return { key: measureKey, heights: nextHeights };
    });
  }, [blocks, measureKey]);

  useLayoutEffect(() => {
    updateMeasuredBlocks();
  }, [updateMeasuredBlocks]);

  useEffect(() => {
    const root = measureRoot.current;
    if (!root || typeof ResizeObserver === "undefined") return undefined;
    let frame = 0;
    const observer = new ResizeObserver(() => {
      if (frame) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(updateMeasuredBlocks);
    });
    observer.observe(root);
    for (const element of root.querySelectorAll("[data-kindle-measure-block-uid]")) {
      observer.observe(element);
    }
    return () => {
      if (frame) cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [updateMeasuredBlocks]);

  useEffect(() => {
    if (typeof window === "undefined") return undefined;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      const target = event.target;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        (target instanceof HTMLElement && target.isContentEditable)
      ) {
        return;
      }
      if (["ArrowRight", "PageDown", " "].includes(event.key)) {
        event.preventDefault();
        goNext();
      } else if (["ArrowLeft", "PageUp"].includes(event.key)) {
        event.preventDefault();
        goPrevious();
      } else if (event.key === "Home") {
        event.preventDefault();
        goToPage(0);
      } else if (event.key === "End") {
        event.preventDefault();
        goToPage(pages.length - 1);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [goNext, goPrevious, goToPage, pages.length]);

  const handleClickCapture = useCallback(
    (event: MouseEvent<HTMLElement>) => {
      if (!onNavigateToBlock) return;
      const target = event.target instanceof Element ? event.target.closest("a[href^='#']") : null;
      if (!target) return;
      const href = target.getAttribute("href");
      if (!href?.startsWith("#")) return;
      const blockUid = decodeURIComponent(href.slice(1));
      if (!blocks.some((block) => block.block_uid === blockUid)) return;
      event.preventDefault();
      onNavigateToBlock(blockUid);
    },
    [blocks, onNavigateToBlock]
  );

  if (blocks.length === 0 || pages.length === 0) {
    return (
      <section
        className={`kindle-reader kindle-reader-layout-${pageLayout} kindle-reader-empty`}
        data-testid="kindle-paged-reader"
      >
        <article className="kindle-page-body" aria-label={title} />
      </section>
    );
  }

  return (
    <section
      className={`kindle-reader kindle-reader-layout-${pageLayout}`}
      data-page-layout={pageLayout}
      data-page-mode="paged"
      data-testid="kindle-paged-reader"
      aria-label={title}
    >
      <div className="kindle-page-frame">
        <button
          type="button"
          className="kindle-page-turn kindle-page-turn-previous"
          aria-label={previousLabel}
          disabled={!canGoPrevious}
          onClick={goPrevious}
        >
          <span aria-hidden="true">‹</span>
        </button>
        <article className="kindle-page-body" onClickCapture={handleClickCapture}>
          <div className="kindle-page-content">
            {currentPage.contextBlocks.map((block) => (
              <div
                className="kindle-page-block kindle-page-context-block"
                data-kindle-context="true"
                data-reader-block-uid={block.block_uid}
                data-testid={`kindle-context-block-${block.block_uid}`}
                key={`context-${block.block_uid}`}
              >
                {renderBlock(block)}
              </div>
            ))}
            {currentPage.blocks.map((block) => (
              <div
                className="kindle-page-block"
                data-reader-block-uid={block.block_uid}
                data-testid={`kindle-page-block-${block.block_uid}`}
                key={block.block_uid}
              >
                {renderBlock(block)}
              </div>
            ))}
          </div>
        </article>
        <button
          type="button"
          className="kindle-page-turn kindle-page-turn-next"
          aria-label={nextLabel}
          disabled={!canGoNext}
          onClick={goNext}
        >
          <span aria-hidden="true">›</span>
        </button>
      </div>
      <footer className="kindle-page-footer">
        <button type="button" disabled={!canGoPrevious} onClick={goPrevious}>
          {previousLabel}
        </button>
        <span data-testid="kindle-page-counter">
          {pageLabel(activePageIndex + 1, pages.length)}
        </span>
        <button type="button" disabled={!canGoNext} onClick={goNext}>
          {nextLabel}
        </button>
      </footer>
      <div
        ref={measureRoot}
        aria-hidden="true"
        className="kindle-measure-root"
        style={{ "--kindle-measure-width": `${metrics.measureWidth}px` } as CSSProperties}
      >
        {blocks.map((block) => (
          <div
            className="kindle-measure-block"
            data-kindle-measure-block-uid={block.block_uid}
            key={`measure-${block.block_uid}`}
          >
            {renderBlock(block)}
          </div>
        ))}
      </div>
    </section>
  );
}

function useViewportSize() {
  const [size, setSize] = useState(() => ({
    width: typeof window === "undefined" ? 900 : window.innerWidth,
    height: typeof window === "undefined" ? 760 : window.innerHeight
  }));

  useEffect(() => {
    if (typeof window === "undefined") return undefined;
    const update = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  return size;
}

function kindlePageMetrics(width: number, height: number, fontScale: number): KindlePageMetrics {
  const safeWidth = Math.max(360, width);
  const safeHeight = Math.max(520, height);
  const sideTurnWidth = Math.max(36, safeWidth * 0.046);
  const frameGap = 6;
  const readerPaddingX = 16;
  const pagePaddingX = Math.min(38, Math.max(14, safeWidth * 0.03)) * 2;
  const contentWidth = Math.max(
    320,
    safeWidth - readerPaddingX - sideTurnWidth * 2 - frameGap * 2 - pagePaddingX
  );
  const lineChars = Math.max(42, Math.min(82, Math.floor(contentWidth / (8.8 * fontScale))));
  const lineHeight = 24 * fontScale;
  const reservedHeight = safeHeight >= 760 ? 106 : 96;
  const usableLines = Math.max(16, Math.floor((safeHeight - reservedHeight) / lineHeight));
  return {
    charBudget: Math.max(840, Math.round(lineChars * usableLines * 0.88)),
    contentHeight: Math.max(360, safeHeight - reservedHeight),
    measureWidth: Math.round(contentWidth)
  };
}

function paginateKindlePages(
  blocks: DocumentBlock[],
  getBlockText: (block: DocumentBlock) => string,
  charBudget: number
): KindlePage[] {
  const pages: KindlePage[] = [];
  let current: DocumentBlock[] = [];
  let currentContext: DocumentBlock | null = null;
  let usedChars = 0;

  const pushCurrent = () => {
    if (current.length === 0) return;
    const contextBlocks = currentContext ? [currentContext] : [];
    pages.push({
      id: [...contextBlocks, ...current].map((block) => block.block_uid).join(":"),
      contextBlocks,
      blocks: current,
      startBlockUid: current[0].block_uid
    });
    currentContext = contextBlockForNextPage(current, getBlockText);
    current = [];
    usedChars = currentContext ? estimateKindleContextCost(currentContext, getBlockText) : 0;
  };

  for (const block of blocks) {
    const blockCost = estimateKindleBlockCost(block, getBlockText(block));
    const currentLastBlock = current.at(-1);
    const shouldKeepWithPrevious =
      current.length === 1 &&
      ((current[0].block_type === "title" && ["abstract", "section"].includes(block.block_type)) ||
        isSectionLike(current[0]));
    const shouldKeepAfterHeading = currentLastBlock ? isSectionLike(currentLastBlock) : false;
    const shouldStartNewPage =
      current.length > 0 &&
      !shouldKeepWithPrevious &&
      !shouldKeepAfterHeading &&
      (usedChars + blockCost > charBudget ||
        (isSectionLike(block) && usedChars > Math.round(charBudget * 0.72)));
    if (shouldStartNewPage) pushCurrent();
    current.push(block);
    usedChars += blockCost;
    if (!isSectionLike(block) && usedChars >= charBudget * 1.14) pushCurrent();
  }

  pushCurrent();
  return pages;
}

function paginateMeasuredKindlePages(
  blocks: DocumentBlock[],
  getBlockText: (block: DocumentBlock) => string,
  measuredHeights: Record<string, number>,
  metrics: KindlePageMetrics
): KindlePage[] {
  const pages: KindlePage[] = [];
  let current: DocumentBlock[] = [];
  let currentContext: DocumentBlock | null = null;
  let usedHeight = 0;
  const pageHeight = metrics.contentHeight;

  const measuredBlockHeight = (block: DocumentBlock) =>
    measuredHeights[block.block_uid] ??
    estimateKindleBlockCost(block, getBlockText(block)) /
      Math.max(1, metrics.charBudget / pageHeight);

  const pushCurrent = () => {
    if (current.length === 0) return;
    const contextBlocks = currentContext ? [currentContext] : [];
    pages.push({
      id: [...contextBlocks, ...current].map((block) => block.block_uid).join(":"),
      contextBlocks,
      blocks: current,
      startBlockUid: current[0].block_uid
    });
    currentContext = contextBlockForNextPage(current, getBlockText);
    current = [];
    usedHeight = currentContext ? measuredBlockHeight(currentContext) * 0.58 + 16 : 0;
  };

  for (const block of blocks) {
    const blockHeight = measuredBlockHeight(block);
    const currentLastBlock = current.at(-1);
    const shouldKeepWithPrevious =
      current.length === 1 &&
      ((current[0].block_type === "title" && ["abstract", "section"].includes(block.block_type)) ||
        isSectionLike(current[0]));
    const shouldKeepAfterHeading = currentLastBlock ? isSectionLike(currentLastBlock) : false;
    const shouldStartNewPage =
      current.length > 0 &&
      !shouldKeepWithPrevious &&
      !shouldKeepAfterHeading &&
      (usedHeight + blockHeight > pageHeight ||
        (isSectionLike(block) && usedHeight > pageHeight * 0.72));
    if (shouldStartNewPage) pushCurrent();
    current.push(block);
    usedHeight += blockHeight;
    if (!isSectionLike(block) && usedHeight >= pageHeight * 1.08) pushCurrent();
  }

  pushCurrent();
  return pages;
}

function pageIndexForBlock(pages: KindlePage[], activeBlockUid: string | null) {
  if (pages.length === 0 || !activeBlockUid) return 0;
  const index = pages.findIndex((page) =>
    page.blocks.some((block) => block.block_uid === activeBlockUid)
  );
  return index >= 0 ? index : 0;
}

function measureKindleBlockHeights(root: HTMLElement) {
  const heights: Record<string, number> = {};
  for (const element of root.querySelectorAll<HTMLElement>("[data-kindle-measure-block-uid]")) {
    const blockUid = element.dataset.kindleMeasureBlockUid;
    if (!blockUid) continue;
    const rect = element.getBoundingClientRect();
    const height = Math.max(rect.height, element.scrollHeight);
    if (height > 0) heights[blockUid] = Math.ceil(height);
  }
  return heights;
}

function shallowNumberRecordEqual(left: Record<string, number>, right: Record<string, number>) {
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length) return false;
  return leftKeys.every((key) => left[key] === right[key]);
}

function contextBlockForNextPage(
  blocks: DocumentBlock[],
  getBlockText: (block: DocumentBlock) => string
) {
  const tailParagraph = findLastBlockOfType(blocks, "paragraph");
  const tailBlock = tailParagraph ?? findLastBlockOfType(blocks, "abstract");
  if (!tailBlock) return null;
  const contextMarkdown = tailSentencesForContext(getBlockText(tailBlock));
  if (!contextMarkdown) return null;
  return {
    ...tailBlock,
    id: `${tailBlock.id}:kindle-context`,
    block_uid: `${tailBlock.block_uid}:kindle-context`,
    source_markdown: contextMarkdown,
    source_latex: null
  };
}

function findLastBlockOfType(blocks: DocumentBlock[], blockType: DocumentBlock["block_type"]) {
  for (let index = blocks.length - 1; index >= 0; index -= 1) {
    if (blocks[index].block_type === blockType) return blocks[index];
  }
  return null;
}

function estimateKindleContextCost(
  block: DocumentBlock,
  getBlockText: (block: DocumentBlock) => string
) {
  return Math.round(estimateKindleBlockCost(block, getBlockText(block)) * 0.52) + 48;
}

function tailSentencesForContext(markdown: string) {
  const normalized = markdown.replace(/\s+/g, " ").trim();
  if (!normalized) return "";
  const sentences = markdownSentences(normalized);
  if (sentences.length <= 2) return sentences.join(" ");
  return sentences.slice(-2).join(" ");
}

function markdownSentences(markdown: string) {
  const sentences: string[] = [];
  let start = 0;

  for (let index = 0; index < markdown.length; index += 1) {
    if (!isSentencePunctuation(markdown[index])) continue;
    let end = index + 1;
    while (end < markdown.length && isSentenceClosingMarkdown(markdown[end])) {
      end += 1;
    }
    if (end < markdown.length && !/\s/.test(markdown[end])) continue;
    const sentence = markdown.slice(start, end).trim();
    if (sentence) sentences.push(sentence);
    while (end < markdown.length && /\s/.test(markdown[end])) {
      end += 1;
    }
    start = end;
    index = end - 1;
  }

  const tail = markdown.slice(start).trim();
  if (tail) sentences.push(tail);
  return sentences.length > 0 ? sentences : [markdown];
}

function isSentencePunctuation(character: string) {
  return [".", "!", "?", "。", "！", "？"].includes(character);
}

function isSentenceClosingMarkdown(character: string) {
  return ['"', "'", "”", "’", "）", ")", "]", "*", "_", "`"].includes(character);
}

function estimateKindleBlockCost(block: DocumentBlock, text: string) {
  const plainLength = Math.max(1, plainTextForEstimate(text).length);
  if (block.block_type === "title") return Math.max(260, Math.round(plainLength * 1.15));
  if (block.block_type === "abstract") return Math.max(380, Math.round(plainLength * 1.02));
  if (isSectionLike(block)) return Math.max(96, Math.round(plainLength * 1.05));
  if (block.block_type === "figure") return Math.max(620, Math.round(plainLength * 1.18));
  if (block.block_type === "table") return Math.max(540, Math.round(plainLength * 1.12));
  if (block.block_type === "algorithm") return Math.max(500, Math.round(plainLength * 1.06));
  if (block.block_type === "equation") return Math.max(150, Math.round(plainLength * 0.82));
  return Math.round(plainLength * 0.98) + 64;
}

function isSectionLike(block: DocumentBlock) {
  return ["section", "subsection", "subsubsection"].includes(block.block_type);
}

function plainTextForEstimate(markdown: string) {
  return markdown
    .replace(/!\[[^\]]*]\([^)]*\)/g, " ")
    .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/\\\((.*?)\\\)/g, "$1")
    .replace(/\\\[(.*?)\\\]/gs, "$1")
    .replace(/\$([^$]+)\$/g, "$1")
    .replace(/^#+\s+/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}
