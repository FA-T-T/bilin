import type { MouseEvent, ReactNode } from "react";
import { useCallback, useEffect, useMemo, useRef } from "react";

import type { DocumentBlock } from "../api/types";

interface ReaderBlockListProps {
  blocks: DocumentBlock[];
  activeBlockUid: string | null;
  fontScale?: number;
  paragraphSpacingEm?: number;
  virtualization?: ReaderVirtualizationOptions;
  forcedBlockUid?: string | null;
  searchTargetBlockUid?: string | null;
  getBlockText?: (block: DocumentBlock) => string;
  onActiveBlockChange: (blockUid: string) => void;
  onNavigateToBlock?: (blockUid: string) => void;
  renderBlock: (block: DocumentBlock) => ReactNode;
}

export interface ReaderVirtualizationOptions {
  enabled?: boolean;
  overscanBefore?: number;
  overscanAfter?: number;
  forceRenderFirstBlocks?: number;
}

export type MeasuredBlockHeights = Record<string, number>;

interface VisibleBlock {
  uid: string;
  ratio: number;
  top: number;
}

interface MaterializedUidInput {
  blocks: DocumentBlock[];
  blockIndexByUid: Map<string, number>;
  activeBlockUid: string | null;
  forcedBlockUid: string | null;
  searchTargetBlockUid: string | null;
  options: Required<ReaderVirtualizationOptions>;
}

const defaultGetBlockText = (block: DocumentBlock) => block.source_markdown;

const defaultVirtualizationOptions: Required<ReaderVirtualizationOptions> = {
  enabled: true,
  overscanBefore: 20,
  overscanAfter: 30,
  forceRenderFirstBlocks: 8
};

const READER_ESTIMATED_LINE_HEIGHT = 28.5;

export function ReaderBlockList({
  blocks,
  activeBlockUid,
  fontScale = 1,
  paragraphSpacingEm = 0.34,
  virtualization,
  forcedBlockUid = null,
  searchTargetBlockUid = null,
  getBlockText = defaultGetBlockText,
  onActiveBlockChange,
  onNavigateToBlock,
  renderBlock
}: ReaderBlockListProps) {
  const listElement = useRef<HTMLDivElement | null>(null);
  const blockElements = useRef(new Map<string, HTMLDivElement>());
  const visibleBlocks = useRef(new Map<string, VisibleBlock>());
  const measuredBlockHeights = useRef<MeasuredBlockHeights>({});
  const activeBlockUidRef = useRef(activeBlockUid);
  const virtualizationOptions = useMemo(
    () => ({ ...defaultVirtualizationOptions, ...virtualization }),
    [virtualization]
  );
  const blockIndexByUid = useMemo(() => blockIndexMap(blocks), [blocks]);
  const materializedBlockUids = useMemo(
    () =>
      materializedUidsForReader({
        blocks,
        blockIndexByUid,
        activeBlockUid,
        forcedBlockUid,
        searchTargetBlockUid,
        options: virtualizationOptions
      }),
    [
      activeBlockUid,
      blockIndexByUid,
      blocks,
      forcedBlockUid,
      searchTargetBlockUid,
      virtualizationOptions
    ]
  );

  useEffect(() => {
    activeBlockUidRef.current = activeBlockUid;
  }, [activeBlockUid]);

  useEffect(() => {
    if (typeof IntersectionObserver === "undefined") return undefined;
    const visible = visibleBlocks.current;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const blockUid = (entry.target as HTMLElement).dataset.readerBlockUid;
          if (!blockUid) continue;
          if (!entry.isIntersecting) {
            visible.delete(blockUid);
            continue;
          }
          visible.set(blockUid, {
            uid: blockUid,
            ratio: entry.intersectionRatio,
            top: entry.boundingClientRect.top
          });
        }

        const anchorY = window.innerHeight * 0.24;
        const next = [...visible.values()].sort(
          (left, right) =>
            Math.abs(left.top - anchorY) - Math.abs(right.top - anchorY) || right.ratio - left.ratio
        )[0];
        if (next && next.uid !== activeBlockUidRef.current) {
          activeBlockUidRef.current = next.uid;
          onActiveBlockChange(next.uid);
        }
      },
      {
        root: null,
        rootMargin: "-12% 0px -60% 0px",
        threshold: [0, 0.15, 0.5, 0.85]
      }
    );

    for (const block of blocks) {
      const element = blockElements.current.get(block.block_uid);
      if (element) observer.observe(element);
    }

    return () => {
      visible.clear();
      observer.disconnect();
    };
  }, [blocks, onActiveBlockChange]);

  const navigateToHashTarget = useCallback(
    (blockUid: string) => {
      if (!blockIndexByUid.has(blockUid)) return;
      onNavigateToBlock?.(blockUid);
    },
    [blockIndexByUid, onNavigateToBlock]
  );

  const handleClickCapture = useCallback(
    (event: MouseEvent<HTMLDivElement>) => {
      if (!onNavigateToBlock) return;
      const target = event.target instanceof Element ? event.target.closest("a[href^='#']") : null;
      if (!target) return;
      const href = target.getAttribute("href");
      if (!href?.startsWith("#")) return;
      const blockUid = decodeURIComponent(href.slice(1));
      if (!blockIndexByUid.has(blockUid)) return;
      event.preventDefault();
      navigateToHashTarget(blockUid);
    },
    [blockIndexByUid, navigateToHashTarget, onNavigateToBlock]
  );

  const renderShell = (block: DocumentBlock) => (
    <div
      className="reader-block-virtual-shell"
      data-active={activeBlockUid === block.block_uid ? "true" : undefined}
      data-reader-block-uid={block.block_uid}
      data-reader-block-rendered="true"
      data-testid={`reader-block-shell-${block.block_uid}`}
      key={block.block_uid}
      ref={(element) => {
        if (element) {
          blockElements.current.set(block.block_uid, element);
          measureRenderedBlock(block.block_uid, element, measuredBlockHeights.current);
        } else {
          blockElements.current.delete(block.block_uid);
        }
      }}
    >
      {renderBlock(block)}
    </div>
  );

  const renderPlaceholder = (block: DocumentBlock) => (
    <div
      aria-hidden="true"
      className="reader-block-virtual-shell reader-block-placeholder"
      data-reader-block-placeholder="true"
      data-reader-block-uid={block.block_uid}
      data-testid={`reader-block-placeholder-${block.block_uid}`}
      id={block.block_uid}
      key={block.block_uid}
      ref={(element) => {
        if (element) {
          blockElements.current.set(block.block_uid, element);
        } else {
          blockElements.current.delete(block.block_uid);
        }
      }}
      style={{
        height: `${placeholderHeightForBlock(
          block,
          measuredBlockHeights.current,
          getBlockText,
          fontScale,
          paragraphSpacingEm
        )}px`
      }}
    />
  );

  return (
    <div
      className="reader-block-list"
      data-testid="reader-block-list"
      data-virtualization={virtualizationOptions.enabled ? "progressive" : "browser-native"}
      onClickCapture={handleClickCapture}
      ref={listElement}
    >
      {blocks.map((block) =>
        materializedBlockUids.has(block.block_uid) ? renderShell(block) : renderPlaceholder(block)
      )}
    </div>
  );
}

function blockIndexMap(blocks: DocumentBlock[]) {
  const map = new Map<string, number>();
  blocks.forEach((block, index) => map.set(block.block_uid, index));
  return map;
}

function materializedUidsForReader({
  blocks,
  blockIndexByUid,
  activeBlockUid,
  forcedBlockUid,
  searchTargetBlockUid,
  options
}: MaterializedUidInput) {
  const materialized = new Set<string>();
  if (!options.enabled) {
    blocks.forEach((block) => materialized.add(block.block_uid));
    return materialized;
  }

  const activeIndex = activeBlockUid ? (blockIndexByUid.get(activeBlockUid) ?? 0) : 0;
  const start = Math.max(0, activeIndex - options.overscanBefore);
  const end = Math.min(blocks.length - 1, activeIndex + options.overscanAfter);
  for (
    let index = 0;
    index <= Math.min(options.forceRenderFirstBlocks - 1, blocks.length - 1);
    index += 1
  ) {
    materialized.add(blocks[index].block_uid);
  }
  for (let index = start; index <= end; index += 1) {
    materialized.add(blocks[index].block_uid);
  }
  for (const block of blocks) {
    if (isStructuralBlock(block)) materialized.add(block.block_uid);
  }
  if (activeBlockUid) materialized.add(activeBlockUid);
  if (forcedBlockUid) materialized.add(forcedBlockUid);
  if (searchTargetBlockUid) materialized.add(searchTargetBlockUid);
  return materialized;
}

function measureRenderedBlock(
  blockUid: string,
  element: HTMLDivElement,
  measuredHeights: MeasuredBlockHeights
) {
  requestAnimationFrame(() => {
    const height = element.getBoundingClientRect().height;
    if (height > 0) measuredHeights[blockUid] = Math.round(height);
  });
}

function placeholderHeightForBlock(
  block: DocumentBlock,
  measuredHeights: MeasuredBlockHeights,
  getBlockText: (block: DocumentBlock) => string,
  fontScale: number,
  paragraphSpacingEm: number
) {
  const measuredHeight = measuredHeights[block.block_uid];
  if (measuredHeight && measuredHeight > 0) return measuredHeight;
  return estimatePlaceholderHeight(block, getBlockText(block), fontScale, paragraphSpacingEm);
}

function estimatePlaceholderHeight(
  block: DocumentBlock,
  text: string,
  fontScale: number,
  paragraphSpacingEm: number
) {
  const spacing = paragraphSpacingEm * 16 * fontScale * 2;
  if (isStructuralBlock(block))
    return Math.round((block.block_type === "section" ? 52 : 68) * fontScale);
  if (block.block_type === "figure") return Math.round(340 * fontScale);
  if (block.block_type === "table") return Math.round(220 * fontScale);
  if (block.block_type === "equation") return Math.round(74 * fontScale + spacing);
  const plainLength = Math.max(1, plainTextForEstimate(text).length);
  const lines = Math.max(1, Math.ceil(plainLength / 92));
  return Math.round(lines * READER_ESTIMATED_LINE_HEIGHT * fontScale + spacing + 18);
}

function isStructuralBlock(block: DocumentBlock) {
  return ["title", "abstract", "section", "subsection", "subsubsection"].includes(block.block_type);
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
