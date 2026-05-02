import { Stack } from "@mantine/core";
import type { ReactNode } from "react";
import { useEffect, useRef } from "react";

import type { DocumentBlock } from "../api/types";

interface ReaderBlockListProps {
  blocks: DocumentBlock[];
  activeBlockUid: string | null;
  onActiveBlockChange: (blockUid: string) => void;
  renderBlock: (block: DocumentBlock) => ReactNode;
}

interface VisibleBlock {
  uid: string;
  ratio: number;
  top: number;
}

export function ReaderBlockList({
  blocks,
  activeBlockUid,
  onActiveBlockChange,
  renderBlock
}: ReaderBlockListProps) {
  const blockElements = useRef(new Map<string, HTMLDivElement>());
  const visibleBlocks = useRef(new Map<string, VisibleBlock>());

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

  return (
    <Stack
      className="reader-block-list"
      data-testid="reader-block-list"
      data-virtualization="browser-native"
      gap="md"
    >
      {blocks.map((block) => (
        <div
          className="reader-block-virtual-shell"
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
      ))}
    </Stack>
  );
}
