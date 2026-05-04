import {
  layout,
  layoutNextLineRange,
  prepare,
  prepareWithSegments,
  type LayoutCursor
} from "@chenglou/pretext";
import type { CSSProperties, ReactNode } from "react";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";

import type { DocumentBlock } from "../api/types";

interface ReaderBlockListProps {
  blocks: DocumentBlock[];
  activeBlockUid: string | null;
  enableMediaFlow?: boolean;
  getFlowText?: (block: DocumentBlock) => string;
  onActiveBlockChange: (blockUid: string) => void;
  renderBlock: (block: DocumentBlock) => ReactNode;
}

interface VisibleBlock {
  uid: string;
  ratio: number;
  top: number;
}

type ReaderFlowUnit =
  | { kind: "single"; block: DocumentBlock }
  | {
      kind: "media-flow";
      media: DocumentBlock;
      textBlocks: DocumentBlock[];
      flowPlan: PretextFlowPlan;
    };

interface PretextFlowPlan {
  count: number;
  mediaWidth: number;
  regionWidth: number;
  engine: "line-routing" | "fixed-width";
}

export function ReaderBlockList({
  blocks,
  activeBlockUid,
  enableMediaFlow = false,
  getFlowText = (block) => block.source_markdown,
  onActiveBlockChange,
  renderBlock
}: ReaderBlockListProps) {
  const listElement = useRef<HTMLDivElement | null>(null);
  const blockElements = useRef(new Map<string, HTMLDivElement>());
  const visibleBlocks = useRef(new Map<string, VisibleBlock>());
  const [pretextFlowPlans, setPretextFlowPlans] = useState<Record<string, PretextFlowPlan>>({});
  const flowUnits = useMemo(
    () =>
      enableMediaFlow
        ? buildReaderFlowUnits(blocks, pretextFlowPlans, getFlowText)
        : blocks.map((block) => ({ kind: "single", block }) as const),
    [blocks, enableMediaFlow, getFlowText, pretextFlowPlans]
  );

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
        if (next) onActiveBlockChange(next.uid);
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

  useLayoutEffect(() => {
    if (!enableMediaFlow) {
      setPretextFlowPlans({});
      return undefined;
    }

    let frame = 0;
    const updatePlans = () => {
      if (frame) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        frame = 0;
        const nextPlans = buildPretextFlowPlans(blocks, blockElements.current, getFlowText);
        setPretextFlowPlans((current) => (samePlans(current, nextPlans) ? current : nextPlans));
      });
    };

    updatePlans();
    if (typeof ResizeObserver === "undefined") {
      return () => {
        if (frame) cancelAnimationFrame(frame);
      };
    }

    const observer = new ResizeObserver(updatePlans);
    if (listElement.current) observer.observe(listElement.current);
    for (const block of blocks) {
      const element = blockElements.current.get(block.block_uid);
      if (element) observer.observe(element);
    }

    return () => {
      if (frame) cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [blocks, enableMediaFlow, getFlowText]);

  const renderShell = (block: DocumentBlock, className = "") => (
    <div
      className={`reader-block-virtual-shell${className ? ` ${className}` : ""}`}
      data-active={activeBlockUid === block.block_uid ? "true" : undefined}
      data-reader-block-uid={block.block_uid}
      data-testid={`reader-block-shell-${block.block_uid}`}
      key={block.block_uid}
      ref={(element) => {
        if (element) {
          blockElements.current.set(block.block_uid, element);
        } else {
          blockElements.current.delete(block.block_uid);
        }
      }}
    >
      {renderBlock(block)}
    </div>
  );

  return (
    <div
      className="reader-block-list"
      data-testid="reader-block-list"
      data-virtualization="browser-native"
      ref={listElement}
    >
      {flowUnits.map((unit) => {
        if (unit.kind === "single") {
          return renderShell(unit.block);
        }
        return (
          <div
            className="reader-flow-region"
            data-pretext-flow-engine={unit.flowPlan.engine}
            data-pretext-flow-count={unit.textBlocks.length}
            data-pretext-flow-media-width={Math.round(unit.flowPlan.mediaWidth)}
            data-testid={`reader-flow-region-${unit.media.block_uid}`}
            key={unit.media.block_uid}
            style={flowRegionStyle(unit.flowPlan)}
          >
            {renderShell(unit.media, "reader-flow-media")}
            {unit.textBlocks.map((textBlock) => renderShell(textBlock, "reader-flow-text"))}
          </div>
        );
      })}
    </div>
  );
}

function buildReaderFlowUnits(
  blocks: DocumentBlock[],
  flowPlans: Record<string, PretextFlowPlan>,
  getFlowText: (block: DocumentBlock) => string
): ReaderFlowUnit[] {
  const units: ReaderFlowUnit[] = [];
  for (let index = 0; index < blocks.length; index += 1) {
    const block = blocks[index];
    if (isFlowMediaBlock(block) && isFlowCompanionBlock(blocks[index + 1])) {
      const candidateBlocks: DocumentBlock[] = [];
      let cursor = index + 1;
      while (isFlowCompanionBlock(blocks[cursor])) {
        candidateBlocks.push(blocks[cursor]);
        cursor += 1;
      }
      const flowPlan =
        flowPlans[block.block_uid] ??
        estimatePretextFlowPlan(block, candidateBlocks, getFlowText, undefined);
      const textBlocks = candidateBlocks.slice(0, flowPlan.count);
      units.push({
        kind: "media-flow",
        media: block,
        textBlocks,
        flowPlan
      });
      index += Math.max(0, textBlocks.length);
      continue;
    }
    units.push({ kind: "single", block });
  }
  return units;
}

function buildPretextFlowPlans(
  blocks: DocumentBlock[],
  blockElements: Map<string, HTMLDivElement>,
  getFlowText: (block: DocumentBlock) => string
) {
  const plans: Record<string, PretextFlowPlan> = {};
  for (let index = 0; index < blocks.length; index += 1) {
    const block = blocks[index];
    if (!isFlowMediaBlock(block)) continue;
    const candidateBlocks: DocumentBlock[] = [];
    let cursor = index + 1;
    while (isFlowCompanionBlock(blocks[cursor])) {
      candidateBlocks.push(blocks[cursor]);
      cursor += 1;
    }
    if (candidateBlocks.length === 0) continue;
    plans[block.block_uid] = estimatePretextFlowPlan(
      block,
      candidateBlocks,
      getFlowText,
      flowMeasurementFor(block, blockElements)
    );
  }
  return plans;
}

interface FlowMeasurement {
  mediaHeight: number;
  mediaWidth: number;
  regionWidth: number;
  textWidth: number;
}

const FLOW_REGION_WIDTH = 820;
const FLOW_MEDIA_RATIO = 0.36;
const FLOW_MEDIA_MIN = 220;
const FLOW_MEDIA_MAX = 330;
const FLOW_GAP = 18;

function flowMeasurementFor(
  mediaBlock: DocumentBlock,
  blockElements: Map<string, HTMLDivElement>
): FlowMeasurement | undefined {
  const mediaElement = blockElements.get(mediaBlock.block_uid);
  const region = mediaElement?.closest(".reader-flow-region");
  if (!mediaElement || !region) return undefined;
  const mediaRect = mediaElement.getBoundingClientRect();
  const regionRect = region.getBoundingClientRect();
  if (mediaRect.height <= 0 || regionRect.width <= 0) return undefined;
  const sideWidth =
    mediaRect.width > 0 ? mediaRect.width : estimatedFlowMediaWidth(regionRect.width);
  const textWidth = Math.max(300, regionRect.width - sideWidth - FLOW_GAP);
  return {
    mediaHeight: mediaRect.height,
    mediaWidth: sideWidth,
    regionWidth: regionRect.width,
    textWidth
  };
}

function estimatePretextFlowPlan(
  mediaBlock: DocumentBlock,
  candidateBlocks: DocumentBlock[],
  getFlowText: (block: DocumentBlock) => string,
  measurement: FlowMeasurement | undefined
) {
  const regionWidth = measurement?.regionWidth ?? FLOW_REGION_WIDTH;
  const mediaWidth = measurement?.mediaWidth ?? estimatedFlowMediaWidth(regionWidth);
  const mediaHeight = measurement?.mediaHeight ?? estimatedMediaHeight(mediaBlock, mediaWidth);
  const textWidth = measurement?.textWidth ?? Math.max(300, regionWidth - mediaWidth - FLOW_GAP);
  const resolvedMeasurement: FlowMeasurement = {
    mediaHeight,
    mediaWidth,
    regionWidth,
    textWidth
  };
  const targetHeight = Math.max(160, mediaHeight - 36);
  let consumedHeight = 0;
  let count = 0;
  const engine: PretextFlowPlan["engine"] = canUsePretextLineRouting()
    ? "line-routing"
    : "fixed-width";
  for (let index = 0; index < candidateBlocks.length; index += 1) {
    const block = candidateBlocks[index];
    const equationLike = isEquationLikeFlowBlock(block);
    const blockHeight = estimateFlowBlockHeight(
      block,
      getFlowText(block),
      resolvedMeasurement,
      consumedHeight
    );
    if (count > 0 && consumedHeight >= targetHeight * 1.08 && !equationLike) break;
    if (count > 0 && consumedHeight >= targetHeight * 1.5) break;
    if (count > 0 && consumedHeight + blockHeight > targetHeight * 1.42 && !equationLike) {
      break;
    }
    consumedHeight += blockHeight;
    count += 1;
    const nextBlock = candidateBlocks[index + 1];
    if (consumedHeight >= targetHeight && !isEquationLikeFlowBlock(nextBlock)) break;
  }
  return {
    count: Math.max(1, Math.min(count || 1, candidateBlocks.length)),
    mediaWidth,
    regionWidth,
    engine
  };
}

function flowRegionStyle(plan: PretextFlowPlan): CSSProperties {
  return {
    "--flow-media-rail-width": `${Math.round(plan.mediaWidth)}px`
  } as CSSProperties;
}

const PRETEXT_READER_FONT =
  '17px Georgia, "Times New Roman", "Songti SC", "STSong", "PingFang SC", serif';
const PRETEXT_READER_LINE_HEIGHT = 28.5;

function estimateFlowBlockHeight(
  block: DocumentBlock,
  markdown: string,
  measurement: FlowMeasurement,
  startY: number
) {
  if (isStructuralBlock(block)) {
    return block.block_type === "section" ? 44 : 36;
  }
  if (isEquationLikeFlowBlock(block)) {
    return estimateEquationHeight(markdown, availableFlowTextWidth(measurement, startY));
  }
  const plainText = plainTextForPretext(markdown);
  if (!plainText) return PRETEXT_READER_LINE_HEIGHT;
  if (canUsePretextLineRouting()) {
    return estimateVariableWidthTextHeight(plainText, measurement, startY);
  }
  const width = availableFlowTextWidth(measurement, startY);
  if (canUsePretextLayout()) {
    const prepared = prepare(plainText, PRETEXT_READER_FONT, { wordBreak: "normal" });
    const result = layout(prepared, Math.max(220, width), PRETEXT_READER_LINE_HEIGHT);
    return result.height + 7;
  }
  const fallbackLines = Math.max(1, Math.ceil(plainText.length / 82));
  return fallbackLines * PRETEXT_READER_LINE_HEIGHT + 7;
}

function estimateVariableWidthTextHeight(
  text: string,
  measurement: FlowMeasurement,
  startY: number
) {
  const prepared = prepareWithSegments(text, PRETEXT_READER_FONT, { wordBreak: "normal" });
  let cursor: LayoutCursor = { segmentIndex: 0, graphemeIndex: 0 };
  let lineCount = 0;
  while (true) {
    const lineTop = startY + lineCount * PRETEXT_READER_LINE_HEIGHT;
    const width = availableFlowTextWidth(measurement, lineTop);
    const next = layoutNextLineRange(prepared, cursor, Math.max(220, width));
    if (next === null) break;
    cursor = next.end;
    lineCount += 1;
  }
  return Math.max(1, lineCount) * PRETEXT_READER_LINE_HEIGHT + 7;
}

function availableFlowTextWidth(measurement: FlowMeasurement, y: number) {
  if (y < measurement.mediaHeight) {
    return Math.max(260, measurement.regionWidth - measurement.mediaWidth - FLOW_GAP);
  }
  return Math.max(300, measurement.regionWidth);
}

function estimateEquationHeight(markdown: string, width: number) {
  const normalized = markdown.replace(/\s+/g, " ").trim();
  const explicitRows = Math.max(1, markdown.split(/\\\\|\n/).filter(Boolean).length);
  const wrappedRows = Math.max(1, Math.ceil(normalized.length / Math.max(34, width / 10)));
  return Math.max(46, Math.max(explicitRows, wrappedRows) * 30 + 16);
}

function canUsePretextLayout() {
  if (typeof document === "undefined") return false;
  if (typeof navigator !== "undefined" && /jsdom/i.test(navigator.userAgent)) return false;
  try {
    const canvas = document.createElement("canvas");
    return Boolean(canvas.getContext("2d"));
  } catch {
    return false;
  }
}

function canUsePretextLineRouting() {
  return canUsePretextLayout() && typeof Intl !== "undefined" && "Segmenter" in Intl;
}

function plainTextForPretext(markdown: string) {
  return markdown
    .replace(/!\[[^\]]*]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/\\\((.*?)\\\)/g, "$1")
    .replace(/\$([^$]+)\$/g, "$1")
    .replace(/^#+\s+/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}

function estimatedMediaHeight(block: DocumentBlock, mediaWidth = estimatedFlowMediaWidth()) {
  const width = numericMetadata(block.metadata, "width", "natural_width", "pixel_width");
  const height = numericMetadata(block.metadata, "height", "natural_height", "pixel_height");
  if (width && height) {
    return Math.min(520, Math.max(180, (height / width) * mediaWidth + 76));
  }
  return 430;
}

function estimatedFlowMediaWidth(regionWidth = FLOW_REGION_WIDTH) {
  return Math.min(Math.max(regionWidth * FLOW_MEDIA_RATIO, FLOW_MEDIA_MIN), FLOW_MEDIA_MAX);
}

function numericMetadata(metadata: DocumentBlock["metadata"] | undefined, ...keys: string[]) {
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

function isStructuralBlock(block: DocumentBlock) {
  return ["section", "title", "abstract", "subsection", "subsubsection"].includes(block.block_type);
}

function samePlans(left: Record<string, PretextFlowPlan>, right: Record<string, PretextFlowPlan>) {
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length) return false;
  return leftKeys.every((key) => {
    const leftPlan = left[key];
    const rightPlan = right[key];
    return (
      leftPlan?.count === rightPlan?.count &&
      Math.round(leftPlan?.mediaWidth ?? 0) === Math.round(rightPlan?.mediaWidth ?? 0) &&
      Math.round(leftPlan?.regionWidth ?? 0) === Math.round(rightPlan?.regionWidth ?? 0) &&
      leftPlan?.engine === rightPlan?.engine
    );
  });
}

function isFlowMediaBlock(block: DocumentBlock | undefined): block is DocumentBlock {
  if (!block) return false;
  if (block.block_type !== "figure") return false;
  const html =
    typeof block.metadata?.html_fragment === "string" ? block.metadata.html_fragment : "";
  const label = typeof block.metadata?.label === "string" ? block.metadata.label : "";
  return !(
    /\bltx_table\b/i.test(html) ||
    /\bltx_tag_table\b/i.test(html) ||
    /\bltx_(?:equation|equationgroup|eqn_)/i.test(html) ||
    /(^tab:|\.T\d+$)/i.test(label)
  );
}

function isFlowCompanionBlock(block: DocumentBlock | undefined): block is DocumentBlock {
  if (!block) return false;
  return block.block_type === "paragraph" || isEquationLikeFlowBlock(block);
}

function isEquationLikeFlowBlock(block: DocumentBlock | undefined): block is DocumentBlock {
  if (!block) return false;
  if (block.block_type === "equation") return true;
  if (!["table", "figure"].includes(block.block_type)) return false;
  const html =
    typeof block.metadata?.html_fragment === "string" ? block.metadata.html_fragment : "";
  return /\bltx_(?:equation|equationgroup|eqn_)/i.test(html);
}
