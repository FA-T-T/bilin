import type {
  CSSProperties,
  MouseEvent,
  ReactNode,
  TouchEvent as ReactTouchEvent,
  WheelEvent as ReactWheelEvent
} from "react";
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
const KINDLE_MEASURE_WINDOW_RADIUS = 36;
const KINDLE_MEASURE_INITIAL_LIMIT = 80;
const KINDLE_PAGE_SLICE_OVERLAP_PX = 28;
const KINDLE_WHEEL_PAGE_TURN_DELTA_PX = 18;
const KINDLE_TOUCH_PAGE_TURN_DELTA_PX = 34;

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
  const pageContentRoot = useRef<HTMLDivElement | null>(null);
  const touchStartY = useRef<number | null>(null);
  const [pageContentOffset, setPageContentOffset] = useState(0);
  const [pageOverflow, setPageOverflow] = useState({ clientHeight: 0, scrollHeight: 0 });
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
        blocks
          .map((block) =>
            [
              block.block_uid,
              block.content_hash,
              block.context_hash ?? "",
              getBlockText(block).length
            ].join(":")
          )
          .join("|")
      ].join("|"),
    [blocks, fontScale, getBlockText, metrics.contentHeight, metrics.measureWidth]
  );
  const [measuredBlocks, setMeasuredBlocks] = useState<MeasuredKindleBlocks | null>(null);
  const measuredBlockCount =
    measuredBlocks?.key === measureKey ? Object.keys(measuredBlocks.heights).length : 0;
  const estimatedPages = useMemo(
    () => paginateKindlePages(blocks, getBlockText, metrics.charBudget),
    [blocks, getBlockText, metrics.charBudget]
  );
  const measuredPages = useMemo(
    () =>
      measuredBlocks?.key === measureKey && Object.keys(measuredBlocks.heights).length > 0
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
  const maxPageContentOffset = Math.max(0, pageOverflow.scrollHeight - pageOverflow.clientHeight);
  const pageSliceStep = Math.max(
    1,
    pageOverflow.clientHeight - KINDLE_PAGE_SLICE_OVERLAP_PX
  );
  const canTurnPrevious = pageContentOffset > 0 || canGoPrevious;
  const canTurnNext = pageContentOffset < maxPageContentOffset || canGoNext;
  const measurementBlocks = useMemo(
    () => kindleMeasurementBlocks(blocks, pages, activePageIndex),
    [activePageIndex, blocks, pages]
  );

  const goToPage = useCallback(
    (pageIndex: number) => {
      const page = pages[Math.min(Math.max(pageIndex, 0), Math.max(pages.length - 1, 0))];
      if (!page) return;
      onPageBlockChange(page.startBlockUid);
      onPageTurn?.();
    },
    [onPageBlockChange, onPageTurn, pages]
  );

  useLayoutEffect(() => {
    setPageContentOffset(0);
  }, [currentPage?.id]);

  const updatePageOverflow = useCallback(() => {
    const root = pageContentRoot.current;
    if (!root) return;
    const nextOverflow = {
      clientHeight: root.clientHeight,
      scrollHeight: root.scrollHeight
    };
    setPageOverflow((current) =>
      current.clientHeight === nextOverflow.clientHeight &&
      current.scrollHeight === nextOverflow.scrollHeight
        ? current
        : nextOverflow
    );
    setPageContentOffset((current) =>
      Math.min(current, Math.max(0, nextOverflow.scrollHeight - nextOverflow.clientHeight))
    );
  }, []);

  useLayoutEffect(() => {
    updatePageOverflow();
  }, [currentPage?.id, pageLayout, updatePageOverflow]);

  useEffect(() => {
    const root = pageContentRoot.current;
    if (!root || typeof ResizeObserver === "undefined") return undefined;
    let frame = 0;
    const observer = new ResizeObserver(() => {
      if (frame) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(updatePageOverflow);
    });
    observer.observe(root);
    for (const element of root.children) observer.observe(element);
    return () => {
      if (frame) cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [currentPage?.id, updatePageOverflow]);

  useLayoutEffect(() => {
    if (pageContentRoot.current) pageContentRoot.current.scrollTop = pageContentOffset;
  }, [pageContentOffset]);

  const turnPrevious = useCallback(() => {
    if (pageContentOffset > 0) {
      setPageContentOffset((current) => Math.max(0, current - pageSliceStep));
      onPageTurn?.();
      return;
    }
    if (canGoPrevious) goToPage(activePageIndex - 1);
  }, [activePageIndex, canGoPrevious, goToPage, onPageTurn, pageContentOffset, pageSliceStep]);

  const turnNext = useCallback(() => {
    if (pageContentOffset < maxPageContentOffset) {
      setPageContentOffset((current) =>
        Math.min(maxPageContentOffset, current + pageSliceStep)
      );
      onPageTurn?.();
      return;
    }
    if (canGoNext) goToPage(activePageIndex + 1);
  }, [
    activePageIndex,
    canGoNext,
    goToPage,
    maxPageContentOffset,
    onPageTurn,
    pageContentOffset,
    pageSliceStep
  ]);

  const goPrevious = useCallback(() => {
    turnPrevious();
  }, [turnPrevious]);

  const goNext = useCallback(() => {
    turnNext();
  }, [turnNext]);

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
    if (Object.keys(nextHeights).length === 0) return;
    setMeasuredBlocks((current) => {
      const baseHeights = current?.key === measureKey ? current.heights : {};
      const mergedHeights = { ...baseHeights, ...nextHeights };
      if (current?.key === measureKey && shallowNumberRecordEqual(current.heights, mergedHeights)) {
        return current;
      }
      return { key: measureKey, heights: mergedHeights };
    });
  }, [measureKey]);

  useLayoutEffect(() => {
    updateMeasuredBlocks();
  }, [measurementBlocks, updateMeasuredBlocks]);

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
  }, [measurementBlocks, updateMeasuredBlocks]);

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
      if (["ArrowRight", "ArrowDown", "PageDown", " "].includes(event.key)) {
        event.preventDefault();
        goNext();
      } else if (["ArrowLeft", "ArrowUp", "PageUp"].includes(event.key)) {
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

  const handleWheel = useCallback(
    (event: ReactWheelEvent<HTMLElement>) => {
      if (Math.abs(event.deltaY) < Math.abs(event.deltaX)) return;
      if (Math.abs(event.deltaY) < KINDLE_WHEEL_PAGE_TURN_DELTA_PX) return;
      event.preventDefault();
      if (event.deltaY > 0) {
        goNext();
      } else {
        goPrevious();
      }
    },
    [goNext, goPrevious]
  );

  const handleTouchStart = useCallback((event: ReactTouchEvent<HTMLElement>) => {
    touchStartY.current = event.touches[0]?.clientY ?? null;
  }, []);

  const handleTouchEnd = useCallback(
    (event: ReactTouchEvent<HTMLElement>) => {
      const startY = touchStartY.current;
      touchStartY.current = null;
      const endY = event.changedTouches[0]?.clientY;
      if (startY === null || typeof endY !== "number") return;
      const deltaY = startY - endY;
      if (Math.abs(deltaY) < KINDLE_TOUCH_PAGE_TURN_DELTA_PX) return;
      event.preventDefault();
      if (deltaY > 0) {
        goNext();
      } else {
        goPrevious();
      }
    },
    [goNext, goPrevious]
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
      data-measured-block-count={measuredBlockCount}
      data-measure-window-size={measurementBlocks.length}
      data-page-content-offset={pageContentOffset}
      data-page-content-max-offset={maxPageContentOffset}
      data-testid="kindle-paged-reader"
      aria-label={title}
      onWheel={handleWheel}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      <div className="kindle-page-frame">
        <button
          type="button"
          className="kindle-page-turn kindle-page-turn-previous"
          aria-label={previousLabel}
          disabled={!canTurnPrevious}
          onClick={goPrevious}
        >
          <span aria-hidden="true">‹</span>
        </button>
        <article className="kindle-page-body" onClickCapture={handleClickCapture}>
          <div ref={pageContentRoot} className="kindle-page-content">
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
          disabled={!canTurnNext}
          onClick={goNext}
        >
          <span aria-hidden="true">›</span>
        </button>
      </div>
      <footer className="kindle-page-footer">
        <button type="button" disabled={!canTurnPrevious} onClick={goPrevious}>
          {previousLabel}
        </button>
        <span data-testid="kindle-page-counter">
          {pageLabel(activePageIndex + 1, pages.length)}
        </span>
        <button type="button" disabled={!canTurnNext} onClick={goNext}>
          {nextLabel}
        </button>
      </footer>
      <div
        ref={measureRoot}
        aria-hidden="true"
        className="kindle-measure-root"
        style={{ "--kindle-measure-width": `${metrics.measureWidth}px` } as CSSProperties}
      >
        {measurementBlocks.map((block) => (
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
  let usedChars = 0;

  const pushCurrent = () => {
    if (current.length === 0) return;
    pages.push({
      id: current.map((block) => block.block_uid).join(":"),
      blocks: current,
      startBlockUid: current[0].block_uid
    });
    current = [];
    usedChars = 0;
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
  let usedHeight = 0;
  const pageHeight = metrics.contentHeight;

  const measuredBlockHeight = (block: DocumentBlock) =>
    measuredHeights[block.block_uid] ??
    estimateKindleBlockCost(block, getBlockText(block)) /
      Math.max(1, metrics.charBudget / pageHeight);

  const pushCurrent = () => {
    if (current.length === 0) return;
    pages.push({
      id: current.map((block) => block.block_uid).join(":"),
      blocks: current,
      startBlockUid: current[0].block_uid
    });
    current = [];
    usedHeight = 0;
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

function kindleMeasurementBlocks(
  blocks: DocumentBlock[],
  pages: KindlePage[],
  activePageIndex: number
) {
  if (blocks.length <= KINDLE_MEASURE_INITIAL_LIMIT) return blocks;
  const activePage = pages[Math.min(Math.max(activePageIndex, 0), Math.max(pages.length - 1, 0))];
  const firstVisibleBlock = activePage?.blocks[0];
  const lastVisibleBlock = activePage?.blocks.at(-1) ?? firstVisibleBlock;
  const firstVisibleIndex = firstVisibleBlock
    ? blocks.findIndex((block) => block.block_uid === firstVisibleBlock.block_uid)
    : -1;
  const lastVisibleIndex = lastVisibleBlock
    ? blocks.findIndex((block) => block.block_uid === lastVisibleBlock.block_uid)
    : firstVisibleIndex;

  if (firstVisibleIndex < 0) {
    return blocks.slice(0, Math.min(KINDLE_MEASURE_INITIAL_LIMIT, blocks.length));
  }

  const start = Math.max(0, firstVisibleIndex - KINDLE_MEASURE_WINDOW_RADIUS);
  const end = Math.min(
    blocks.length,
    Math.max(lastVisibleIndex, firstVisibleIndex) + KINDLE_MEASURE_WINDOW_RADIUS + 1
  );
  const nearbyBlockUids = new Set<string>();
  const pageStart = Math.max(0, activePageIndex - 1);
  const pageEnd = Math.min(pages.length, activePageIndex + 2);
  for (let pageIndex = pageStart; pageIndex < pageEnd; pageIndex += 1) {
    for (const block of pages[pageIndex]?.blocks ?? []) {
      nearbyBlockUids.add(block.block_uid);
    }
  }
  return blocks.filter(
    (block, index) =>
      (index >= start && index < end) || nearbyBlockUids.has(block.block_uid)
  );
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
