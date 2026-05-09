import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState, type ReactNode } from "react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { LibraryHomePage } from "../src/pages/LibraryHomePage";
import { ReaderBlock } from "../src/components/ReaderBlock";
import { ReaderBlockList } from "../src/components/ReaderBlockList";
import { TaskDrawer } from "../src/components/TaskDrawer";
import { LibraryDetailPage } from "../src/pages/LibraryDetailPage";
import { ReaderPage } from "../src/pages/ReaderPage";
import { SettingsPage } from "../src/pages/SettingsPage";
import type { DocumentBlock, ReaderCard } from "../src/api/types";
import { useUiStore } from "../src/state/ui";

beforeEach(() => {
  useUiStore.getState().setLocale("en");
  useUiStore.getState().resetReaderPreferences();
  useUiStore.getState().resetReaderFeaturePreferences();
  useUiStore.getState().setTranslationTargetLanguage("zh-CN");
  useUiStore.getState().setAutoTranslateOnLanguageSwitch(true);
  Object.defineProperty(Element.prototype, "scrollIntoView", {
    value: vi.fn(),
    configurable: true
  });
});

afterEach(() => {
  cleanup();
  useUiStore.getState().closeTaskDrawer();
  useUiStore.getState().setReaderViewMode("study");
  useUiStore.getState().setLocale("en");
  useUiStore.getState().resetReaderPreferences();
  useUiStore.getState().resetReaderFeaturePreferences();
  useUiStore.getState().setTranslationTargetLanguage("zh-CN");
  useUiStore.getState().setAutoTranslateOnLanguageSwitch(true);
  vi.unstubAllGlobals();
});

function renderWithProviders(node: ReactNode) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } }
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MantineProvider>{node}</MantineProvider>
    </QueryClientProvider>,
    { wrapper: MemoryRouter }
  );
}

function renderRoute(route: string, path: string, node: ReactNode) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } }
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MantineProvider>
        <MemoryRouter initialEntries={[route]}>
          <Routes>
            <Route path={path} element={node} />
          </Routes>
        </MemoryRouter>
      </MantineProvider>
    </QueryClientProvider>
  );
}

function mockElementRect(
  element: Element,
  rect: { left: number; top: number; right: number; bottom: number }
) {
  Object.defineProperty(element, "getBoundingClientRect", {
    configurable: true,
    value: () =>
      ({
        ...rect,
        x: rect.left,
        y: rect.top,
        width: rect.right - rect.left,
        height: rect.bottom - rect.top,
        toJSON: () => ({})
      }) as DOMRect
  });
}

function dispatchWindowPointerMove(clientX: number, clientY: number) {
  const event = new Event("pointermove");
  Object.defineProperty(event, "clientX", { value: clientX });
  Object.defineProperty(event, "clientY", { value: clientY });
  window.dispatchEvent(event);
}

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body)
  };
}

function sseResponse(events: string, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => events,
    json: async () => ({})
  };
}

function sseEvent(event: string, data: unknown) {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

function readerTestBlock(
  blockUid: string,
  blockType: DocumentBlock["block_type"],
  sourceMarkdown: string,
  metadata: DocumentBlock["metadata"] = {}
): DocumentBlock {
  return {
    id: `block-${blockUid}`,
    article_revision_id: "revision-1",
    block_uid: blockUid,
    structural_path: blockUid,
    block_type: blockType,
    parent_uid: null,
    content_hash: `hash-${blockUid}`,
    context_hash: null,
    source_markdown: sourceMarkdown,
    source_latex: null,
    metadata,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };
}

function syntheticReaderBlocks(count = 300): DocumentBlock[] {
  const blocks: DocumentBlock[] = [];
  for (let index = 0; index < count; index += 1) {
    if (index % 50 === 0) {
      blocks.push(
        readerTestBlock(
          `sec-${String(index).padStart(4, "0")}`,
          "section",
          `Section ${index / 50 + 1}`,
          { level: 1 }
        )
      );
      continue;
    }
    const uid = `p-${String(index).padStart(4, "0")}`;
    blocks.push(
      readerTestBlock(
        uid,
        "paragraph",
        index === 251
          ? "This far-off paragraph contains a distant source needle."
          : `Synthetic paragraph ${index} with enough article-like text to estimate line height.`
      )
    );
  }
  return blocks;
}

function syntheticDocumentPayload(count = 300) {
  return {
    ...documentPayload,
    blocks: syntheticReaderBlocks(count),
    assets: []
  };
}

async function openReaderTool(name: "Translate" | "Terms" | "Ask" | "Notes" | "Export") {
  await userEvent.click(await screen.findByRole("button", { name: "Reader tools" }));
  await userEvent.click(await screen.findByRole("button", { name }));
}

async function expandFirstTranslation() {
  const buttons = await screen.findAllByRole("button", { name: "Show translation" });
  fireEvent.pointerDown(buttons[0]);
}

const library = {
  id: "library-1",
  name: "Papers",
  path: "/tmp/papers",
  status: "active",
  metadata: {},
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString()
};

const article = {
  article_revision: {
    id: "revision-1",
    family_id: "family-1",
    version: "v2",
    bundle_path: "/tmp/papers/articles/arxiv/2401.00001/v2",
    status: "parsed",
    manifest_version: 1,
    metadata: {},
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  },
  family: {
    id: "family-1",
    source: "arxiv",
    external_id: "2401.00001",
    title: "A Minimal Bilin Test Paper",
    metadata: {},
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  },
  manifest: {
    schema_version: 1,
    article_revision_id: "revision-1",
    arxiv_id: "2401.00001v2",
    source: "arxiv",
    arxiv_metadata: { title: "A Minimal Bilin Test Paper" },
    parse_status: "parsed",
    errors: [],
    metadata: {}
  },
  block_count: 6,
  asset_count: 2,
  translation_status: {
    target_language: "zh-CN",
    status: "not_started",
    translatable_blocks: 4,
    translated_blocks: 0,
    queued_jobs: 0,
    running_jobs: 0,
    paused_jobs: 0,
    failed_jobs: 0
  }
};

const documentPayload = {
  article_revision: article.article_revision,
  manifest: article.manifest,
  blocks: [
    {
      id: "block-1",
      article_revision_id: "revision-1",
      block_uid: "sec-001",
      structural_path: "00001",
      block_type: "section",
      parent_uid: null,
      content_hash: "hash-section",
      context_hash: null,
      source_markdown: "Introduction",
      source_latex: null,
      metadata: { level: 1 },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "block-2",
      article_revision_id: "revision-1",
      block_uid: "p-0001",
      structural_path: "00002",
      block_type: "paragraph",
      parent_uid: null,
      content_hash: "hash-paragraph",
      context_hash: null,
      source_markdown: "First paragraph with inline technical content.",
      source_latex: "First paragraph source LaTeX.",
      metadata: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "block-3",
      article_revision_id: "revision-1",
      block_uid: "fig-0001",
      structural_path: "00003",
      block_type: "figure",
      parent_uid: null,
      content_hash: "hash-figure",
      context_hash: null,
      source_markdown: "**Figure 1.** An overview pipeline.",
      source_latex: null,
      metadata: { asset_id: "fig-0001", label: "fig:overview" },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "block-4",
      article_revision_id: "revision-1",
      block_uid: "p-0002",
      structural_path: "00004",
      block_type: "paragraph",
      parent_uid: null,
      content_hash: "hash-reference-paragraph",
      context_hash: null,
      source_markdown: "See Figure 1 and Table 1 for parsed assets.",
      source_latex: null,
      metadata: {
        references: [
          { href: "#fig:overview", text: "1" },
          { href: "#tab:results", text: "1" }
        ]
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "block-5",
      article_revision_id: "revision-1",
      block_uid: "p-0003",
      structural_path: "00005",
      block_type: "paragraph",
      parent_uid: null,
      content_hash: "hash-flow-paragraph",
      context_hash: null,
      source_markdown: "The same figure should let later prose continue beside it.",
      source_latex: null,
      metadata: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "block-6",
      article_revision_id: "revision-1",
      block_uid: "tbl-0001",
      structural_path: "00006",
      block_type: "table",
      parent_uid: null,
      content_hash: "hash-table",
      context_hash: null,
      source_markdown: "**Table 1.** Regression table.",
      source_latex: null,
      metadata: {
        asset_id: "tbl-0001",
        label: "tab:results",
        html_fragment:
          '<figure class="ltx_table" id="tab:results"><figcaption>Regression table.</figcaption><table><tr><th>Model</th><th>Score</th></tr><tr><td>Bilin</td><td>1.0</td></tr></table></figure>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ],
  assets: [
    {
      id: "asset-row-1",
      article_revision_id: "revision-1",
      asset_id: "fig-0001",
      kind: "figure",
      source_path: null,
      web_path: "/tmp/web/fig-0001.png",
      caption: "An overview pipeline.",
      label: "fig:overview",
      metadata: { original_reference: "figures/pipeline.png", width: 420, height: 720 },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "asset-row-2",
      article_revision_id: "revision-1",
      asset_id: "tbl-0001",
      kind: "table",
      source_path: null,
      web_path: null,
      caption: "Regression table.",
      label: "tab:results",
      metadata: {
        html_fragment:
          '<figure class="ltx_table" id="tab:results"><figcaption>Regression table.</figcaption><table><tr><th>Model</th><th>Score</th></tr><tr><td>Bilin</td><td>1.0</td></tr></table></figure>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ]
};

const provider = {
  id: "provider-1",
  name: "Mock Provider",
  protocol: "openai-compatible",
  base_url: "https://api.example.com/v1",
  key_ref: "app_settings:provider_api_key:provider-1",
  default_model: "mock-model",
  max_concurrent_requests: 2,
  requests_per_minute: 120,
  capabilities: {},
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString()
};

const translationsPayload = {
  article_revision_id: "revision-1",
  target_language: "zh-CN",
  variants: [
    {
      id: "translation-1",
      block_id: "block-2",
      target_language: "zh-CN",
      provider_profile_id: "provider-1",
      model: "mock-model",
      raw_markdown: "第一段 technical content 的译文。",
      render_ast: null,
      validation_status: "ok",
      glossary_version: null,
      is_default: true,
      metadata: { block_uid: "p-0001" },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "translation-2",
      block_id: "block-2",
      target_language: "zh-CN",
      provider_profile_id: "provider-1",
      model: "mock-model",
      raw_markdown: "备用译文。",
      render_ast: null,
      validation_status: "ok",
      glossary_version: null,
      is_default: false,
      metadata: { block_uid: "p-0001" },
      created_at: new Date().toISOString(),
      updated_at: new Date(Date.now() - 1000).toISOString()
    }
  ]
};

const translationMemoryEntry = {
  id: "memory-1",
  source_hash: "hash-memory",
  source_markdown: "A source paragraph for memory.",
  target_language: "zh-CN",
  raw_markdown: "待审核的记忆译文。",
  provider_profile_id: "provider-1",
  model: "mock-model",
  validation_status: "ok",
  review_status: "pending",
  reuse_enabled: false,
  glossary_version: "glossary:none",
  metadata: { block_uid: "p-0001" },
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString()
};

const glossaryPayload = {
  article_revision_id: "revision-1",
  target_language: "zh-CN",
  active_version: "glossary:active",
  affected_block_uids: ["p-0001"],
  terms: [
    {
      id: "term-1",
      scope: "article",
      source_term: "technical content",
      target_term: "技术内容",
      language_direction: "en->zh-CN",
      status: "active",
      metadata: { target_language: "zh-CN", article_revision_id: "revision-1" },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ]
};

const glossaryCandidatePayload = {
  ...glossaryPayload,
  active_version: "glossary:none",
  affected_block_uids: [],
  terms: [
    {
      id: "term-candidate-1",
      scope: "article",
      source_term: "technical content",
      target_term: "",
      language_direction: "en->zh-CN",
      status: "candidate",
      metadata: {
        target_language: "zh-CN",
        article_revision_id: "revision-1",
        occurrence_count: 2,
        block_uids: ["p-0001"]
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ]
};

const readerCardsPayload = {
  article_revision_id: "revision-1",
  target_language: "zh-CN",
  cards: [
    {
      id: "card-cnn",
      article_revision_id: "revision-1",
      card_type: "term",
      anchor_block_uid: "p-0001",
      anchor_text: "CNN",
      canonical_key: "CNN::convolutional neural network",
      abbreviation: "CNN",
      full_form: "Convolutional Neural Networks",
      title: "Convolutional Neural Networks (CNN)",
      body_markdown: "卷积神经网络是一类用于网格结构数据的神经网络。",
      target_language: "zh-CN",
      source_type: "wikipedia",
      source_url: "https://zh.wikipedia.org/wiki/卷积神经网络",
      position: "right",
      status: "candidate",
      metadata: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "card-sa",
      article_revision_id: "revision-1",
      card_type: "term",
      anchor_block_uid: "p-0001",
      anchor_text: "SA",
      canonical_key: "SA::self attention",
      abbreviation: "SA",
      full_form: "Self Attention",
      title: "Self Attention (SA)",
      body_markdown: "自注意力用序列内部的相关性来更新表示。",
      target_language: "zh-CN",
      source_type: "paper_local",
      source_url: null,
      position: "right",
      status: "candidate",
      metadata: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ]
};

const chatPayload = {
  article_revision_id: "revision-1",
  messages: [
    {
      id: "chat-1",
      article_revision_id: "revision-1",
      role: "assistant",
      content: "It is grounded in the paragraph [p-0001].",
      source_refs: ["p-0001"],
      external_refs: [
        {
          source: "external_native_search",
          title: "External source",
          url: "https://example.com/source",
          doi: null,
          arxiv_id: "2401.00001",
          retrieved_at: new Date().toISOString(),
          model: "mock-model",
          raw_snippet: "External snippet.",
          metadata: {}
        }
      ],
      metadata: {},
      created_at: new Date().toISOString()
    }
  ]
};

const noteTemplatesPayload = [
  {
    id: "deep_reading",
    name: "精读模板",
    description: "Cover background, motivation, method, evidence, limitations, and questions.",
    custom: false,
    metadata: {}
  }
];

const notePatchesPayload = {
  article_revision_id: "revision-1",
  patches: [
    {
      id: "patch-1",
      article_revision_id: "revision-1",
      status: "proposed",
      title: "精读模板",
      patch_markdown: "## Background\n\nThis paper studies technical content [p-0001].",
      source_refs: ["p-0001"],
      metadata: { template_id: "deep_reading" },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ]
};

describe("Bilin web shell", () => {
  it("renders the library empty state", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({
        ok: true,
        json: async () => []
      }))
    );
    renderWithProviders(<LibraryHomePage />);
    expect(
      await screen.findByText("No libraries have been registered in this local profile.")
    ).toBeInTheDocument();
  });

  it("archives and deletes libraries from the library home", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/libraries") && !init?.method) return jsonResponse([library]);
      if (url.endsWith("/libraries/library-1/archive")) {
        return jsonResponse({ ...library, status: "archived" });
      }
      if (url.endsWith("/libraries/library-1")) {
        return jsonResponse({
          library_id: "library-1",
          path: "/tmp/papers",
          deleted_cache: true
        });
      }
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderWithProviders(<LibraryHomePage />);

    expect(await screen.findByRole("link", { name: "Papers" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Archive" }));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).endsWith("/libraries/library-1/archive") && init?.method === "POST"
        )
      ).toBe(true);
    });
    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(await screen.findByText("Delete library and local cache?")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Delete permanently" }));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) => String(url).endsWith("/libraries/library-1") && init?.method === "DELETE"
        )
      ).toBe(true);
    });
  });

  it("renders the reader empty state without article context", async () => {
    renderWithProviders(<ReaderPage />);
    expect(
      screen.getByText("Open an article from a library so the reader can load its parsed document.")
    ).toBeInTheDocument();
  });

  it("renders real asset images when an asset URL is available", () => {
    const { container } = renderWithProviders(
      <ReaderBlock
        block={{
          id: "block-asset",
          article_revision_id: "revision-1",
          block_uid: "fig-0001",
          structural_path: "00003",
          block_type: "figure",
          parent_uid: null,
          content_hash: "hash-figure",
          context_hash: null,
          source_markdown: "**Figure 1.** Figure 1: Asset caption.",
          source_latex: null,
          metadata: {
            asset_id: "fig-0001",
            html_fragment:
              '<figure class="ltx_figure"><figcaption><span class="ltx_tag ltx_tag_figure">Figure 1: </span>Asset caption.</figcaption></figure>'
          },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        asset={{
          id: "asset-1",
          article_revision_id: "revision-1",
          asset_id: "fig-0001",
          kind: "figure",
          source_path: "/tmp/source.png",
          web_path: "/tmp/web.png",
          caption: "Asset caption",
          label: "fig:asset",
          metadata: { width: 360, height: 720 },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-0001"
        translation="**图1.** 图1：资产说明。"
        viewMode="bilingual"
      />
    );

    expect(screen.getByRole("img", { name: "Asset caption" })).toHaveAttribute(
      "src",
      "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-0001"
    );
    expect(container.querySelector(".asset-image-narrow")).not.toBeNull();
    expect(container).toHaveTextContent("Figure 1. Asset caption.");
    expect(container).not.toHaveTextContent("Figure 1. Figure 1");
    expect(container).toHaveTextContent("图1：资产说明。");
    expect(container).not.toHaveTextContent("图1. 图1");
    expect(screen.queryByText("Structured asset placeholder")).not.toBeInTheDocument();
  });

  it("prepares independent hover sentence accents for source and translation", () => {
    const { container } = renderWithProviders(
      <ReaderBlock
        block={readerTestBlock(
          "p-sentences",
          "paragraph",
          "Self-attention links sequence positions."
        )}
        translation="自注意力连接序列位置。它让表示保持并行。"
        viewMode="bilingual"
      />
    );

    const sourceHighlights = [
      ...container.querySelectorAll<HTMLElement>(".source-pane .sentence-highlight")
    ];
    const translationHighlights = [
      ...container.querySelectorAll<HTMLElement>(".translation-pane .sentence-highlight")
    ];
    expect(sourceHighlights).toHaveLength(1);
    expect(translationHighlights).toHaveLength(2);
    expect(sourceHighlights[0]).toHaveTextContent("Self-attention links sequence positions.");
    expect(translationHighlights[0]).toHaveTextContent("自注意力连接序列位置。");
    expect(translationHighlights[0].dataset.sentenceAccent).toBe("0");
    expect(translationHighlights[1].dataset.sentenceAccent).toBe("1");
    expect(sourceHighlights[0].className).not.toMatch(/yellow|blue|green|pink|purple/);
  });

  it("renders inline math in paragraph markdown", () => {
    const { container } = renderWithProviders(
      <ReaderBlock
        block={readerTestBlock(
          "p-inline-math",
          "paragraph",
          "Most models cite [5](#bib.bib5), [2](#bib.bib2). Here, the encoder maps $(x_{1},...,x_{n})$ to a sequence of continuous representations $\\mathbf{z}=(z_{1},...,z_{n})$."
        )}
        citations={{
          "bib.bib5": {
            id: "bib.bib5",
            label: "5",
            title: "Neural machine translation",
            raw_text: "Fixture citation.",
            authors: null,
            year: null,
            arxiv_id: null,
            scholar_query: "Neural machine translation",
            scholar_url: "https://scholar.google.com/scholar?q=Neural+machine+translation",
            metadata: {}
          },
          "bib.bib2": {
            id: "bib.bib2",
            label: "2",
            title: "Sequence to sequence learning",
            raw_text: "Fixture citation.",
            authors: null,
            year: null,
            arxiv_id: null,
            scholar_query: "Sequence to sequence learning",
            scholar_url: "https://scholar.google.com/scholar?q=Sequence+to+sequence+learning",
            metadata: {}
          }
        }}
        viewMode="source"
      />
    );

    expect(container.querySelectorAll(".inline-math .katex")).toHaveLength(2);
    expect(container).toHaveTextContent("Here, the encoder maps");
    expect(container).toHaveTextContent("[5], [2]");
    expect(container).not.toHaveTextContent("[[5]");
    expect(container).not.toHaveTextContent("$(x_1");
    expect(container).not.toHaveTextContent("$ to a sequence of continuous representations $");
  });

  it("normalizes LaTeXML math dialects before KaTeX rendering", () => {
    const { container } = renderWithProviders(
      <ReaderBlock
        block={readerTestBlock(
          "eq-latexml-dialects",
          "equation",
          String.raw`\sigma_{x}=\pmatrix{0&1\cr 1&0},\ {\rm and}\ \sigma_{z}=\pmatrix{1&0\cr 0&-1}.
f_{M}(E)=\left\{\begin{array}{ll}0&\mbox{if $[M,E]=0$}\\ 1&\mbox{if $\{M,E\}=0$}\end{array}\right.
\begin{array}{r}r\{\\ n-k-r\{\end{array}\left(\begin{array}{cc|cc}\raisebox{0.0pt}[6.45831pt]{$\overbrace{I}^{r}$}&\raisebox{0.0pt}[6.45831pt]{$\overbrace{A}^{n-r}$}&B&C\\ 0&0&D&E\end{array}\right).
L\eqqcolon \textsc{mask}
\vmathbb{1}+\varmathbb{N}+\vvmathbb{C}+\mathds{R}+\mathbbm{Z}+\mathbbold{Q}+\text{\sl N}_{\mathrm{BN}}\nopagebreak
\wideparen{AB}+\buildrel{d}\over{=}+\cancelto{0}{x}+\mspace{2mu}y+\strut z+\rotatebox{90}{r}+\scalebox{2}{s}+\resizebox{1cm}{!}{t}+\multicolumn{2}{c}{u}+\ensuremath{v}+w\xspace+\label{eq:w}+\iddots+\begin{split}a&=b\end{split}`
        )}
        viewMode="source"
      />
    );

    expect(container.querySelector(".math-block .katex")).toBeInTheDocument();
    expect(container.querySelector(".katex-error")).not.toBeInTheDocument();
    expect(container.textContent).not.toContain("\\vmathbb");
    expect(container.textContent).not.toContain("\\mathds");
    expect(container.textContent).not.toContain("\\mathbbm");
    expect(container.textContent).not.toContain("\\sl");
    expect(container.textContent).not.toContain("\\nopagebreak");
    expect(container.textContent).not.toContain("\\wideparen");
    expect(container.textContent).not.toContain("\\cancelto");
    expect(container.textContent).not.toContain("\\mspace");
    expect(container.textContent).not.toContain("\\rotatebox");
    expect(container.textContent).not.toContain("\\multicolumn");
  });

  it("shows equation numbers from parser metadata", () => {
    renderWithProviders(
      <ReaderBlock
        block={readerTestBlock("eq-numbered", "equation", String.raw`E=mc^2`, {
          label: "eq.energy",
          equation_number: "(2.1)",
          equation_numbers: ["(2.1)"]
        })}
        viewMode="source"
      />
    );

    expect(screen.getByText("(2.1)")).toHaveClass("equation-number");
  });

  it("mounts block toolbars only after hover for ordinary paragraphs", async () => {
    const { container } = renderWithProviders(
      <ReaderBlock
        block={readerTestBlock("p-lazy-toolbar", "paragraph", "A paragraph with lazy controls.")}
        viewMode="source"
        onToolbarAction={() => undefined}
      />
    );

    expect(screen.queryByLabelText("Copy source")).not.toBeInTheDocument();
    await userEvent.hover(container.querySelector(".reader-block") as HTMLElement);
    expect(screen.getByLabelText("Copy source")).toBeInTheDocument();
  });

  it("keeps block toolbars alive while the pointer stays inside the operation boundary", async () => {
    const { container } = renderWithProviders(
      <ReaderBlock
        block={readerTestBlock(
          "p-toolbar-boundary",
          "paragraph",
          "A paragraph with outside tools."
        )}
        viewMode="source"
        onToolbarAction={() => undefined}
      />
    );
    const block = container.querySelector(".reader-block") as HTMLElement;

    fireEvent.pointerEnter(block);
    expect(screen.getByLabelText("Copy source")).toBeInTheDocument();
    const toolbar = container.querySelector(".hover-toolbar") as HTMLElement;
    mockElementRect(block, { left: 100, top: 100, right: 500, bottom: 180 });
    mockElementRect(toolbar, { left: 54, top: 112, right: 90, bottom: 168 });

    fireEvent.pointerLeave(block, { clientX: 72, clientY: 130, relatedTarget: toolbar });
    expect(screen.getByLabelText("Copy source")).toBeInTheDocument();
    await waitFor(() => expect(screen.getByLabelText("Copy source")).toBeInTheDocument());
    act(() => dispatchWindowPointerMove(70, 130));
    expect(screen.getByLabelText("Copy source")).toBeInTheDocument();
    act(() => dispatchWindowPointerMove(24, 48));
    await waitFor(() => expect(screen.queryByLabelText("Copy source")).not.toBeInTheDocument());
  });

  it("shows paragraph quick ask only while the matching block is active", async () => {
    const onQuickAsk = vi.fn();
    const block = readerTestBlock("p-quick-ask", "paragraph", "A paragraph worth asking about.");
    const { container } = renderWithProviders(
      <ReaderBlock block={block} viewMode="source" canQuickAsk onQuickAsk={onQuickAsk} />
    );

    expect(screen.queryByLabelText("Paragraph question")).not.toBeInTheDocument();
    await userEvent.hover(container.querySelector(".reader-block") as HTMLElement);
    await userEvent.type(screen.getByLabelText("Paragraph question"), "Why does this matter?");
    await userEvent.click(screen.getByRole("button", { name: "Ask" }));

    expect(onQuickAsk).toHaveBeenCalledWith(block, "Why does this matter?");
  });

  it("places opened reader cards inside the viewport even when the tag sits outside the page", async () => {
    const originalInnerWidth = window.innerWidth;
    const originalInnerHeight = window.innerHeight;
    Object.defineProperty(window, "innerWidth", { value: 360, configurable: true });
    Object.defineProperty(window, "innerHeight", { value: 420, configurable: true });
    try {
      function CardHarness() {
        const [expandedCardId, setExpandedCardId] = useState<string | null>(null);
        return (
          <ReaderBlock
            block={readerTestBlock("p-card-edge", "paragraph", "A paragraph with a concept card.")}
            viewMode="source"
            termWikiEnabled
            expandedReaderCardId={expandedCardId}
            readerCards={readerCardsPayload.cards as ReaderCard[]}
            onReaderCardToggle={(_blockUid, cardId) =>
              setExpandedCardId((current) => (current === cardId ? null : cardId))
            }
          />
        );
      }
      renderWithProviders(<CardHarness />);
      const cardButton = screen.getByRole("button", {
        name: "Convolutional Neural Networks (CNN)"
      });
      Object.defineProperty(cardButton, "getBoundingClientRect", {
        value: () => ({ left: 8, right: 50, top: 120, bottom: 148, width: 42, height: 28 }),
        configurable: true
      });

      await userEvent.click(cardButton);

      const popover = screen
        .getByText("卷积神经网络是一类用于网格结构数据的神经网络。")
        .closest(".reader-card-popover") as HTMLElement;
      expect(popover.style.left).toBe("12px");
      expect(popover.style.width).toBe("336px");
    } finally {
      Object.defineProperty(window, "innerWidth", {
        value: originalInnerWidth,
        configurable: true
      });
      Object.defineProperty(window, "innerHeight", {
        value: originalInnerHeight,
        configurable: true
      });
    }
  });

  it("deletes a collapsed reader card directly from its tag", async () => {
    const onDelete = vi.fn();
    renderWithProviders(
      <ReaderBlock
        block={readerTestBlock("p-card-delete", "paragraph", "A paragraph with a question card.")}
        viewMode="source"
        termWikiEnabled
        readerCards={[
          {
            ...(readerCardsPayload.cards[0] as ReaderCard),
            id: "card-question",
            card_type: "question",
            abbreviation: "Q",
            title: "hello",
            source_type: "paper_local"
          }
        ]}
        onReaderCardDelete={onDelete}
      />
    );

    await userEvent.click(screen.getByRole("button", { name: "Delete card: hello" }));

    expect(onDelete).toHaveBeenCalledWith(expect.objectContaining({ id: "card-question" }));
  });

  it("shows citation metadata and library actions on hover", async () => {
    const onCitationImport = vi.fn();
    renderWithProviders(
      <ReaderBlock
        block={readerTestBlock("p-cite", "paragraph", "Residual blocks use normalization [1].", {
          references: [{ href: "#bib.bib1", text: "1" }]
        })}
        citations={{
          "bib.bib1": {
            id: "bib.bib1",
            label: "1",
            title: "Layer normalization",
            raw_text: "Jimmy Lei Ba. Layer normalization. 2016.",
            authors: "Jimmy Lei Ba",
            year: "2016",
            arxiv_id: "1607.06450",
            scholar_query: "Layer normalization Jimmy Lei Ba",
            scholar_url: "https://scholar.google.com/scholar?q=Layer+normalization",
            metadata: {}
          }
        }}
        canImportCitationWithTranslation
        onCitationImport={onCitationImport}
        viewMode="source"
      />
    );

    const citation = screen.getByRole("link", { name: "[1]" });
    expect(citation).toHaveAttribute(
      "href",
      "https://scholar.google.com/scholar?q=Layer+normalization"
    );
    await userEvent.hover(citation);
    expect(await screen.findByText("Layer normalization")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Search Google Scholar" })).toHaveAttribute(
      "href",
      "https://scholar.google.com/scholar?q=Layer+normalization"
    );
    expect(screen.getByRole("link", { name: "Search arXiv" })).toHaveAttribute(
      "href",
      "https://arxiv.org/abs/1607.06450"
    );
    await userEvent.click(screen.getByRole("button", { name: "Add to Ilios library" }));
    expect(onCitationImport).toHaveBeenCalledWith(
      expect.objectContaining({ id: "bib.bib1" }),
      "add"
    );
    await userEvent.click(screen.getByRole("button", { name: "Add and translate" }));
    expect(onCitationImport).toHaveBeenCalledWith(
      expect.objectContaining({ id: "bib.bib1" }),
      "add-and-translate"
    );
  });

  it("sizes LaTeXML multi-panel figures from article layout metadata", () => {
    const htmlFragment =
      '<figure class="ltx_figure"><div class="ltx_flex_figure"><div class="ltx_flex_cell"><div style="width:216.8pt;"><img src="left.png" width="267" height="531"></div></div><div class="ltx_flex_cell"><div style="width:216.8pt;"><img src="right.png" width="501" height="770"></div></div></div><figcaption><span class="ltx_tag ltx_tag_figure">Figure 2: </span>Two-panel attention diagram.</figcaption></figure>';
    renderWithProviders(
      <ReaderBlock
        block={{
          id: "block-multipanel",
          article_revision_id: "revision-1",
          block_uid: "fig-multipanel",
          structural_path: "00007",
          block_type: "figure",
          parent_uid: null,
          content_hash: "hash-multipanel",
          context_hash: null,
          source_markdown: "**Figure 2.** Two-panel attention diagram.",
          source_latex: null,
          metadata: { asset_id: "fig-multipanel", html_fragment: htmlFragment },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        asset={{
          id: "asset-multipanel",
          article_revision_id: "revision-1",
          asset_id: "fig-multipanel",
          kind: "figure",
          source_path: "/tmp/left.png",
          web_path: "/tmp/left.png",
          caption: "Two-panel attention diagram.",
          label: "S3.F2",
          metadata: {
            original_reference: "left.png",
            html_fragment: htmlFragment
          },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-multipanel"
        viewMode="study"
      />
    );

    const image = screen.getByRole("img", { name: "Two-panel attention diagram." });
    expect(image).toHaveAttribute("data-article-layout", "multi-panel");
    expect(image).toHaveAttribute("data-asset-layout", "narrow");
    expect(image).toHaveClass("asset-image-article-multi-panel");
    expect((image as HTMLElement).style.getPropertyValue("--asset-max-inline-size")).toBe("217px");
    expect((image as HTMLElement).style.getPropertyValue("--asset-max-block-size")).toBe("336px");
  });

  it("toggles article images into a full-screen lightbox", async () => {
    renderWithProviders(
      <ReaderBlock
        block={{
          id: "block-lightbox",
          article_revision_id: "revision-1",
          block_uid: "fig-lightbox",
          structural_path: "00009",
          block_type: "figure",
          parent_uid: null,
          content_hash: "hash-lightbox",
          context_hash: null,
          source_markdown: "**Figure 6.** Training curves.",
          source_latex: null,
          metadata: { asset_id: "fig-lightbox" },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        asset={{
          id: "asset-lightbox",
          article_revision_id: "revision-1",
          asset_id: "fig-lightbox",
          kind: "figure",
          source_path: "/tmp/figure.png",
          web_path: "/tmp/figure.png",
          caption: "Training curves.",
          label: "S4.F6",
          metadata: {},
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-lightbox"
        viewMode="source"
      />
    );

    await userEvent.click(screen.getByRole("img", { name: "Training curves." }));
    const dialog = screen.getByRole("dialog", { name: "Training curves." });
    expect(dialog).toHaveClass("asset-image-lightbox");
    expect(dialog.parentElement).toBe(document.body);
    const previewImage = within(dialog).getByRole("img", { name: "Training curves." });
    expect(previewImage).toHaveAttribute(
      "src",
      "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-lightbox"
    );
    await userEvent.click(previewImage);
    expect(screen.queryByRole("dialog", { name: "Training curves." })).not.toBeInTheDocument();
  });

  it("respects the image lightbox feature switch", async () => {
    renderWithProviders(
      <ReaderBlock
        block={{
          id: "block-lightbox-disabled",
          article_revision_id: "revision-1",
          block_uid: "fig-lightbox-disabled",
          structural_path: "00009",
          block_type: "figure",
          parent_uid: null,
          content_hash: "hash-lightbox-disabled",
          context_hash: null,
          source_markdown: "**Figure 6.** Training curves.",
          source_latex: null,
          metadata: { asset_id: "fig-lightbox-disabled" },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        asset={{
          id: "asset-lightbox-disabled",
          article_revision_id: "revision-1",
          asset_id: "fig-lightbox-disabled",
          kind: "figure",
          source_path: "/tmp/figure.png",
          web_path: "/tmp/figure.png",
          caption: "Training curves.",
          label: "S4.F6",
          metadata: {},
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-lightbox-disabled"
        imageLightboxEnabled={false}
        viewMode="source"
      />
    );

    await userEvent.click(screen.getByRole("img", { name: "Training curves." }));
    expect(screen.queryByRole("dialog", { name: "Training curves." })).not.toBeInTheDocument();
  });

  it("keeps side-by-side subfigure widths on the same parsed scale", () => {
    renderWithProviders(
      <ReaderBlock
        block={{
          id: "block-panels",
          article_revision_id: "revision-1",
          block_uid: "fig-panels",
          structural_path: "00008",
          block_type: "figure",
          parent_uid: null,
          content_hash: "hash-panels",
          context_hash: null,
          source_markdown: "**Figure 3.** Unequal panels.",
          source_latex: null,
          metadata: { asset_id: "fig-panels" },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        asset={{
          id: "asset-panels",
          article_revision_id: "revision-1",
          asset_id: "fig-panels",
          kind: "figure",
          source_path: "/tmp/left.png",
          web_path: "/tmp/left.png",
          caption: "Unequal panels.",
          label: "S3.F3",
          metadata: {
            article_layout: "multi-panel",
            total_panel_width_pt: 360,
            max_panel_width_pt: 216
          },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-panels"
        assetFileUrls={[
          {
            index: 1,
            originalReference: "left.png",
            url: "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-panels/files/1",
            metadata: {
              article_layout: "multi-panel",
              panel_width_pt: 144,
              display_width_pt: 144,
              subfigure_group_width_pt: 360,
              width: 288,
              height: 180
            }
          },
          {
            index: 2,
            originalReference: "right.png",
            url: "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-panels/files/2",
            metadata: {
              article_layout: "multi-panel",
              panel_width_pt: 216,
              display_width_pt: 216,
              subfigure_group_width_pt: 360,
              width: 432,
              height: 270
            }
          }
        ]}
        viewMode="source"
      />
    );

    const images = screen.getAllByRole("img", { name: "Unequal panels." });
    expect(images).toHaveLength(2);
    expect((images[0] as HTMLElement).style.getPropertyValue("--asset-render-inline-size")).toBe(
      "144px"
    );
    expect((images[1] as HTMLElement).style.getPropertyValue("--asset-render-inline-size")).toBe(
      "216px"
    );
  });

  it("centers double-column figures without stretching them beyond parsed width", () => {
    renderWithProviders(
      <ReaderBlock
        block={{
          id: "block-wide",
          article_revision_id: "revision-1",
          block_uid: "fig-wide",
          structural_path: "00008",
          block_type: "figure",
          parent_uid: null,
          content_hash: "hash-wide",
          context_hash: null,
          source_markdown: "**Figure 3.** A double-column architecture figure.",
          source_latex: null,
          metadata: { asset_id: "fig-wide" },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        asset={{
          id: "asset-wide",
          article_revision_id: "revision-1",
          asset_id: "fig-wide",
          kind: "figure",
          source_path: "/tmp/wide.png",
          web_path: "/tmp/wide.png",
          caption: "A double-column architecture figure.",
          label: "S3.F3",
          metadata: {
            article_layout: "double-column",
            display_width_pt: 432.5,
            image_width: 1200,
            image_height: 460
          },
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-wide"
        viewMode="source"
      />
    );

    const image = screen.getByRole("img", { name: "A double-column architecture figure." });
    expect(image).toHaveAttribute("data-article-layout", "double-column");
    expect((image as HTMLElement).style.getPropertyValue("--asset-render-inline-size")).toBe(
      "433px"
    );
    expect((image as HTMLElement).style.getPropertyValue("--asset-max-inline-size")).toBe("433px");
  });

  it("renders figures, equations, and following prose as stable linear blocks", () => {
    const blocks = [
      readerTestBlock("fig-flow", "figure", "**Figure 2.** Linear figure."),
      readerTestBlock("p-flow", "paragraph", "A paragraph should remain below the figure."),
      readerTestBlock("eq-flow", "equation", "E = mc^2"),
      readerTestBlock("p-after", "paragraph", "The next paragraph should not be floated.")
    ];

    renderWithProviders(
      <ReaderBlockList
        blocks={blocks}
        activeBlockUid={null}
        onActiveBlockChange={() => undefined}
        renderBlock={(block) => <div>{block.source_markdown}</div>}
      />
    );

    expect(screen.getByTestId("reader-block-shell-fig-flow")).toBeInTheDocument();
    expect(screen.getByTestId("reader-block-shell-p-flow")).toBeInTheDocument();
    expect(screen.getByTestId("reader-block-shell-eq-flow")).toBeInTheDocument();
    expect(screen.getByTestId("reader-block-shell-p-after")).toBeInTheDocument();
  });

  it("keeps legacy LaTeXML equation tables as regular table blocks", () => {
    const equationHtml =
      '<table class="ltx_equationgroup ltx_eqn_align ltx_eqn_table"><tr><td><math alttext="\\mathrm{MultiHead}(Q,K,V)"></math></td><td><math alttext="=\\mathrm{Concat}(head_1,head_h)W^O"></math></td></tr></table>';
    const blocks = [
      readerTestBlock("fig-flow", "figure", "**Figure 2.** Flow figure."),
      readerTestBlock(
        "p-flow",
        "paragraph",
        "The paragraph beside the figure introduces the formula."
      ),
      readerTestBlock("tbl-equation", "table", "**Table 2.** MultiHead(Q,K,V)", {
        html_fragment: equationHtml
      }),
      readerTestBlock("p-after", "paragraph", "The next paragraph can continue after the formula.")
    ];

    renderWithProviders(
      <ReaderBlockList
        blocks={blocks}
        activeBlockUid={null}
        onActiveBlockChange={() => undefined}
        renderBlock={(block) => <div>{block.source_markdown}</div>}
      />
    );

    expect(screen.getByTestId("reader-block-shell-p-flow")).toBeInTheDocument();
    expect(screen.getByTestId("reader-block-shell-tbl-equation")).toBeInTheDocument();
  });

  it("progressively virtualizes long reader documents around the active block", () => {
    const blocks = syntheticReaderBlocks(300);
    const renderBlock = (block: DocumentBlock) => (
      <div className="synthetic-block">{block.block_uid}</div>
    );
    const { container, rerender } = render(
      <ReaderBlockList
        blocks={blocks}
        activeBlockUid="p-0001"
        onActiveBlockChange={() => undefined}
        renderBlock={renderBlock}
      />
    );

    expect(container.querySelectorAll("[data-reader-block-rendered='true']").length).toBeLessThan(
      90
    );
    expect(
      container.querySelectorAll("[data-reader-block-placeholder='true']").length
    ).toBeGreaterThan(180);
    expect(screen.queryByTestId("reader-block-shell-p-0251")).not.toBeInTheDocument();

    rerender(
      <ReaderBlockList
        blocks={blocks}
        activeBlockUid="p-0251"
        onActiveBlockChange={() => undefined}
        renderBlock={renderBlock}
      />
    );

    expect(screen.getByTestId("reader-block-shell-p-0251")).toBeInTheDocument();
    expect(screen.queryByTestId("reader-block-shell-p-0040")).not.toBeInTheDocument();
  });

  it("materializes virtualized hash targets before navigation callbacks finish", async () => {
    const blocks = syntheticReaderBlocks(300);
    function Harness() {
      const [activeUid, setActiveUid] = useState("p-0001");
      const [forcedUid, setForcedUid] = useState<string | null>(null);
      return (
        <ReaderBlockList
          blocks={blocks}
          activeBlockUid={activeUid}
          forcedBlockUid={forcedUid}
          onActiveBlockChange={setActiveUid}
          onNavigateToBlock={(blockUid) => {
            setForcedUid(blockUid);
            setActiveUid(blockUid);
          }}
          renderBlock={(block) =>
            block.block_uid === "p-0001" ? (
              <a href="#p-0251">Jump to distant block</a>
            ) : (
              <div>{block.block_uid}</div>
            )
          }
        />
      );
    }

    render(<Harness />);
    expect(screen.queryByTestId("reader-block-shell-p-0251")).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole("link", { name: "Jump to distant block" }));
    expect(screen.getByTestId("reader-block-shell-p-0251")).toBeInTheDocument();
  });

  it("submits an arXiv import job and renders article rows", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      void init;
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1")) return jsonResponse(library);
      if (url.includes("/libraries/library-1/articles?target_language=")) {
        return jsonResponse([article]);
      }
      if (url.endsWith("/libraries/library-1/translations/missing")) {
        return jsonResponse({
          library_id: "library-1",
          target_language: "zh-CN",
          articles_considered: 1,
          articles_queued: 1,
          jobs_created: 4,
          existing_jobs: 0,
          cached_blocks: 0,
          skipped_blocks: 0,
          job_ids: ["job-translation-1"],
          article_results: []
        });
      }
      if (url.endsWith("/libraries/library-1/articles/revision-1/archive")) {
        return jsonResponse({
          ...article,
          article_revision: { ...article.article_revision, status: "archived" }
        });
      }
      if (url.endsWith("/libraries/library-1/articles/revision-1")) {
        return jsonResponse({
          library_id: "library-1",
          article_family_id: "family-1",
          article_revision_id: "revision-1",
          bundle_path: "/tmp/papers/articles/arxiv/2401.00001/v2",
          deleted_cache: true,
          removed_family: true
        });
      }
      if (url.endsWith("/libraries/library-1/imports/arxiv")) {
        return jsonResponse(
          {
            id: "job-1",
            type: "import_arxiv",
            status: "queued",
            priority: 0,
            payload: {},
            result: null,
            error: null,
            progress: 0,
            attempts: 0,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            started_at: null,
            finished_at: null,
            lease_owner: null
          },
          201
        );
      }
      if (url.includes("/libraries/library-1/imports/file")) {
        return jsonResponse(
          {
            library_id: "library-1",
            article_family_id: "family-upload-1",
            article_revision_id: "revision-upload-1",
            bundle_path: "/tmp/papers/articles/uploads/upload/v1",
            source_kind: "tex_archive",
            parse_job_id: "job-parse-upload-1"
          },
          201
        );
      }
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/libraries/library-1", "/libraries/:libraryId", <LibraryDetailPage />);
    const titleLink = await screen.findByRole("link", { name: "A Minimal Bilin Test Paper" });
    expect(titleLink).toHaveAttribute("href", "/articles/revision-1?libraryId=library-1");
    expect(screen.getByText("Not translated")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Open" })).not.toBeInTheDocument();
    const translateMissingButton = screen.getByRole("button", { name: "Translate missing" });
    await waitFor(() => expect(translateMissingButton).not.toBeDisabled());
    await userEvent.click(translateMissingButton);
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).endsWith("/libraries/library-1/translations/missing") &&
            init?.method === "POST" &&
            String(init.body).includes("provider-1")
        )
      ).toBe(true);
    });
    await userEvent.type(screen.getByLabelText("arXiv ID"), "2401.00001");
    await userEvent.click(screen.getByRole("button", { name: "Add article" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).endsWith("/libraries/library-1/imports/arxiv") && init?.method === "POST"
        )
      ).toBe(true);
    });

    await userEvent.click(screen.getByRole("button", { name: "Archive" }));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).endsWith("/libraries/library-1/articles/revision-1/archive") &&
            init?.method === "POST"
        )
      ).toBe(true);
    });

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(await screen.findByText("Delete article and cache?")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Delete permanently" }));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).endsWith("/libraries/library-1/articles/revision-1") &&
            init?.method === "DELETE"
        )
      ).toBe(true);
    });

    await userEvent.click(screen.getByText("Local file"));
    const file = new File(["fake tar"], "paper.tar.gz", { type: "application/gzip" });
    const fileInput = document.querySelector<HTMLInputElement>('input[type="file"]');
    expect(fileInput).not.toBeNull();
    await userEvent.upload(fileInput!, file);
    await userEvent.click(screen.getByRole("button", { name: "Import file" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/imports/file") &&
            String(url).includes("kind=tex_archive") &&
            init?.method === "POST"
        )
      ).toBe(true);
    });
  });

  it("shows parse dependency failures in the task drawer", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/jobs/summary")) {
          return jsonResponse({
            total: 1,
            queued: 0,
            running: 0,
            paused: 0,
            succeeded: 0,
            failed: 1,
            cancelled: 0,
            active: 0,
            updated_at: new Date().toISOString()
          });
        }
        if (url.includes("/jobs?limit=")) {
          return jsonResponse([
            {
              id: "job-parse-1",
              type: "parse_article",
              status: "failed",
              priority: 0,
              payload: { article_revision_id: "revision-1" },
              result: null,
              error: {
                code: "missing_dependency:latexml",
                message: "latexml was not found on PATH. Install LaTeXML to parse TeX sources.",
                details: {
                  install_hint: "Install LaTeXML so both latexml and latexmlpost are on PATH."
                }
              },
              progress: 0.1,
              attempts: 1,
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
              started_at: new Date().toISOString(),
              finished_at: new Date().toISOString(),
              lease_owner: "worker-test"
            }
          ]);
        }
        return jsonResponse([]);
      })
    );
    useUiStore.getState().openTaskDrawer();

    renderWithProviders(<TaskDrawer />);

    expect(await screen.findByText("Background tasks")).toBeInTheDocument();
    expect(await screen.findByText("parse_article")).toBeInTheDocument();
    expect(await screen.findByText(/missing_dependency:latexml/)).toBeInTheDocument();
    expect(await screen.findByText(/Install LaTeXML/)).toBeInTheDocument();
  });

  it("keeps the task drawer bounded when the queue is large", async () => {
    const recentJobs = Array.from({ length: 120 }, (_, index) => ({
      id: `job-${index}`,
      type: "translate_block",
      status: index === 0 ? "running" : "queued",
      priority: 0,
      payload: { index },
      result: null,
      error: null,
      progress: index === 0 ? 0.4 : 0,
      attempts: index === 0 ? 1 : 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      started_at: index === 0 ? new Date().toISOString() : null,
      finished_at: null,
      lease_owner: index === 0 ? "worker-test" : null
    }));
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith("/jobs/summary")) {
        return jsonResponse({
          total: 1550,
          queued: 1549,
          running: 1,
          paused: 0,
          succeeded: 0,
          failed: 0,
          cancelled: 0,
          active: 1550,
          updated_at: new Date().toISOString()
        });
      }
      if (url.includes("/jobs?limit=120")) return jsonResponse(recentJobs);
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);
    useUiStore.getState().openTaskDrawer();

    renderWithProviders(<TaskDrawer />);

    expect(await screen.findByText("Queued 1549")).toBeInTheDocument();
    expect(await screen.findByText("Showing latest 120 of 1550 tasks.")).toBeInTheDocument();
    expect(await screen.findAllByText("translate_block")).toHaveLength(120);
    expect(fetchMock.mock.calls.some(([url]) => String(url).includes("/jobs?limit=120"))).toBe(
      true
    );
  });

  it("renders a real article document from the API", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(documentPayload);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse(translationsPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse(glossaryPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse(chatPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse(notePatchesPayload);
        }
        return jsonResponse([]);
      })
    );

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    expect(await screen.findByText(/LLM-generated content may be inaccurate/)).toBeInTheDocument();
    expect(await screen.findByTestId("reader-block-list")).toHaveAttribute(
      "data-virtualization",
      "progressive"
    );
    expect(
      await screen.findByText("First paragraph with inline technical content.")
    ).toBeInTheDocument();
    expect(await screen.findByRole("img", { name: "An overview pipeline." })).toHaveAttribute(
      "src",
      "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-0001"
    );
    expect(await screen.findByTestId("reader-block-shell-fig-0001")).toBeInTheDocument();
    expect(screen.queryByText(/Structured asset placeholder/)).not.toBeInTheDocument();
    expect(await screen.findByText("Model")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Figure 1" })).toHaveAttribute("href", "#fig-0001");
    expect(screen.getByRole("link", { name: "Table 1" })).toHaveAttribute("href", "#tbl-0001");
    expect(screen.queryByText("第一段 技术内容 的译文。")).not.toBeInTheDocument();
    await expandFirstTranslation();
    expect(await screen.findByText("第一段 技术内容 的译文。")).toBeInTheDocument();
    expect(await screen.findByText("Glossary changed")).toBeInTheDocument();
    await openReaderTool("Ask");
    expect(await screen.findByText("External source")).toBeInTheDocument();
  });

  it("does not display invalid source-copy translations", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(documentPayload);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse({
            ...translationsPayload,
            variants: [
              {
                ...translationsPayload.variants[0],
                raw_markdown: "First paragraph with inline technical content.",
                validation_status: "unchanged_source"
              }
            ]
          });
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse(glossaryPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse({ article_revision_id: "revision-1", messages: [] });
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse({ article_revision_id: "revision-1", patches: [] });
        }
        return jsonResponse([]);
      })
    );

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    const paragraph = await screen.findByText("First paragraph with inline technical content.");
    const sourcePane = paragraph.closest(".source-pane");
    expect(sourcePane).not.toBeNull();
    fireEvent.pointerDown(
      within(sourcePane as HTMLElement).getByRole("button", { name: "Show translation" })
    );

    expect(await screen.findByText("Translation pending.")).toBeInTheDocument();
    expect(screen.queryByText("第一段 technical content 的译文。")).not.toBeInTheDocument();
  });

  it("searches offscreen source and translation blocks without relying on rendered DOM", async () => {
    const longDocument = syntheticDocumentPayload(300);
    const longTranslations = {
      ...translationsPayload,
      variants: [
        {
          ...translationsPayload.variants[0],
          id: "translation-offscreen",
          block_id: "block-p-0251",
          raw_markdown: "离屏译文 contains translation needle.",
          metadata: { block_uid: "p-0251" }
        }
      ]
    };
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(longDocument);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse(longTranslations);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse({ article_revision_id: "revision-1", terms: [] });
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse({ article_revision_id: "revision-1", messages: [] });
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse({ article_revision_id: "revision-1", patches: [] });
        }
        return jsonResponse([]);
      })
    );

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    const searchInput = await screen.findByLabelText("Search paper");
    expect(screen.queryByTestId("reader-block-shell-p-0251")).not.toBeInTheDocument();
    await userEvent.type(searchInput, "translation needle");

    expect(await screen.findByText("1/1 matches")).toBeInTheDocument();
    expect(screen.getByTestId("reader-block-shell-p-0251")).toBeInTheDocument();
    await userEvent.keyboard("{Enter}");
    await waitFor(() => expect(Element.prototype.scrollIntoView).toHaveBeenCalled());
  });

  it("renders the term wiki card layer without changing the reader body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(documentPayload);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/cards")) {
          return jsonResponse(readerCardsPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse(translationsPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse(glossaryPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse(chatPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse(notePatchesPayload);
        }
        return jsonResponse([]);
      })
    );

    const { container } = renderRoute(
      "/articles/revision-1?libraryId=library-1",
      "/articles/:articleId",
      <ReaderPage />
    );
    expect(await screen.findByText("First paragraph with inline technical content.")).toBeVisible();
    expect(container.querySelector(".reader-card-rail")).not.toBeNull();
    expect(
      await screen.findByRole("button", { name: "Convolutional Neural Networks (CNN)" })
    ).toBeInTheDocument();
    await userEvent.click(
      screen.getByRole("button", { name: "Convolutional Neural Networks (CNN)" })
    );
    expect(await screen.findByText("卷积神经网络是一类用于网格结构数据的神经网络。")).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "Self Attention (SA)" }));
    expect(
      screen.queryByText("卷积神经网络是一类用于网格结构数据的神经网络。")
    ).not.toBeInTheDocument();
    expect(screen.getByText("自注意力用序列内部的相关性来更新表示。")).toBeVisible();
  });

  it("applies saved reading preferences to the reader layout", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(documentPayload);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse(translationsPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse(glossaryPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse(chatPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse(notePatchesPayload);
        }
        return jsonResponse([]);
      })
    );

    useUiStore.getState().setReaderPreference("lineWidthPercent", 76);
    useUiStore.getState().setReaderPreference("fontScale", 1.08);
    useUiStore.getState().setReaderPreference("paragraphSpacingEm", 0.5);
    useUiStore.getState().setReaderPreference("bilingualSourceRatio", 0.64);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);

    expect(
      await screen.findByText("First paragraph with inline technical content.")
    ).toBeInTheDocument();
    const page = document.querySelector(".reader-page") as HTMLElement;
    expect(page.style.getPropertyValue("--reader-line-width")).toBe("76%");
    expect(page.style.getPropertyValue("--reader-paragraph-spacing")).toBe("0.5em");
    expect(page.style.getPropertyValue("--reader-source-column")).toBe("0.64fr");
    expect(page.style.getPropertyValue("--reader-translation-column")).toBe("0.36fr");
    await userEvent.click(screen.getByRole("button", { name: "Reading preferences" }));
    expect(await screen.findByRole("slider", { name: "Line width" })).toBeInTheDocument();
  });

  it("persists reading preferences in local storage", () => {
    const entries = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: vi.fn((key: string) => entries.get(key) ?? null),
      setItem: vi.fn((key: string, value: string) => entries.set(key, value)),
      removeItem: vi.fn((key: string) => entries.delete(key)),
      clear: vi.fn(() => entries.clear())
    });

    useUiStore.getState().setReaderPreference("lineWidthPercent", 74);
    useUiStore.getState().setReaderPreference("bilingualSourceRatio", 0.62);

    expect(JSON.parse(entries.get("iiios-reader-preferences") ?? "{}")).toMatchObject({
      lineWidthPercent: 74,
      bilingualSourceRatio: 0.62
    });
  });

  it("persists reader feature preferences in local storage", () => {
    const entries = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: vi.fn((key: string) => entries.get(key) ?? null),
      setItem: vi.fn((key: string, value: string) => entries.set(key, value)),
      removeItem: vi.fn((key: string) => entries.delete(key)),
      clear: vi.fn(() => entries.clear())
    });

    useUiStore.getState().setReaderFeaturePreference("termCardsEnabled", false);
    useUiStore.getState().setReaderFeaturePreference("quickAskEnabled", false);
    useUiStore.getState().setReaderFeaturePreference("includeUntranslatedInExport", false);

    expect(JSON.parse(entries.get("iiios-reader-feature-preferences") ?? "{}")).toMatchObject({
      termCardsEnabled: false,
      quickAskEnabled: false,
      includeUntranslatedInExport: false
    });
  });

  it("creates a note patch from an assistant chat answer", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat/chat-1/note-patch")) {
        return jsonResponse({
          ...notePatchesPayload.patches[0],
          metadata: {
            source: "chat_message",
            chat_message_id: "chat-1"
          }
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse(chatPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse({ article_revision_id: "revision-1", patches: [] });
      }
      void init;
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    await openReaderTool("Ask");
    await userEvent.click(await screen.findByRole("button", { name: "Create note patch" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes(
              "/libraries/library-1/articles/revision-1/chat/chat-1/note-patch"
            ) && init?.method === "POST"
        )
      ).toBe(true);
    });
  });

  it("selects a translation variant from the reader", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (
        url.includes("/libraries/library-1/articles/revision-1/translations/translation-2/select")
      ) {
        return jsonResponse({
          ...translationsPayload.variants[1],
          is_default: true
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse({ article_revision_id: "revision-1", patches: [] });
      }
      void init;
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    await expandFirstTranslation();
    expect(await screen.findByText("第一段 技术内容 的译文。")).toBeInTheDocument();
    const variantSelect = (await screen.findAllByLabelText("Translation variant for p-0001"))[0];
    await userEvent.click(variantSelect);
    await userEvent.click(
      await screen.findByRole("option", { name: "Variant 2 · mock-model · ok" })
    );

    expect(await screen.findByText("备用译文。")).toBeInTheDocument();
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes(
              "/libraries/library-1/articles/revision-1/translations/translation-2/select"
            ) && init?.method === "POST"
        )
      ).toBe(true);
    });
  });

  it("syncs the active reader block from scroll visibility", async () => {
    const observers: MockIntersectionObserver[] = [];
    class MockIntersectionObserver {
      readonly callback: IntersectionObserverCallback;
      readonly elements: Element[] = [];

      constructor(callback: IntersectionObserverCallback) {
        this.callback = callback;
        observers.push(this);
      }

      observe(element: Element) {
        this.elements.push(element);
      }

      unobserve(element: Element) {
        const index = this.elements.indexOf(element);
        if (index >= 0) this.elements.splice(index, 1);
      }

      disconnect() {
        this.elements.length = 0;
      }

      takeRecords(): IntersectionObserverEntry[] {
        return [];
      }

      trigger(entry: Partial<IntersectionObserverEntry> & { target: Element }) {
        this.callback(
          [entry as IntersectionObserverEntry],
          this as unknown as IntersectionObserver
        );
      }
    }
    vi.stubGlobal("IntersectionObserver", MockIntersectionObserver);
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(documentPayload);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse(translationsPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse(glossaryPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse(chatPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse(notePatchesPayload);
        }
        return jsonResponse([]);
      })
    );

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    const paragraphShell = await screen.findByTestId("reader-block-shell-p-0001");
    await waitFor(() =>
      expect(observers.some((observer) => observer.elements.length > 0)).toBe(true)
    );
    const observer = observers.find((candidate) => candidate.elements.length > 0);
    expect(observer).toBeDefined();

    act(() => {
      observer!.trigger({
        target: paragraphShell,
        isIntersecting: true,
        intersectionRatio: 0.9,
        boundingClientRect: { top: window.innerHeight * 0.24 } as DOMRectReadOnly
      });
    });

    await waitFor(() =>
      expect(paragraphShell.querySelector(".reader-block-active")).not.toBeNull()
    );
    expect(
      within(screen.getByTestId("reader-view-mode")).queryByText("Focus")
    ).not.toBeInTheDocument();
    expect(screen.queryByText("第一段 技术内容 的译文。")).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Chapters" }));
    expect(screen.getByRole("link", { name: "1 Introduction" })).toHaveAttribute(
      "aria-current",
      "location"
    );
  });

  it("runs reader toolbar actions for a real article block", async () => {
    const writeText = vi.fn(async () => undefined);
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText },
      configurable: true
    });
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/blocks/p-0001/translate")) {
        return jsonResponse({
          library_id: "library-1",
          article_revision_id: "revision-1",
          target_language: "zh-CN",
          jobs_created: 1,
          existing_jobs: 0,
          cached_blocks: 0,
          skipped_blocks: 0,
          job_ids: ["job-translate-block-1"]
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/obsidian/clips")) {
        return jsonResponse({
          vault_path: "/Users/test/OneDrive/Obsidian/Ilios",
          note_path: "/Users/test/OneDrive/Obsidian/Ilios/Library.md",
          article_heading: "Fixture paper",
          block_uid: "p-0001",
          created_file: true,
          updated_existing: false
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse({ article_revision_id: "revision-1", patches: [] });
      }
      void init;
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    const paragraph = await screen.findByText("First paragraph with inline technical content.");
    const sourcePane = paragraph.closest(".source-pane");
    const textBlock = sourcePane?.closest(".text-block");
    expect(sourcePane).not.toBeNull();
    expect(textBlock).not.toBeNull();
    fireEvent.pointerDown(
      within(sourcePane as HTMLElement).getByRole("button", { name: "Show translation" })
    );
    const translation = await screen.findByText("第一段 技术内容 的译文。");
    const translationPane = translation.closest(".translation-pane");
    expect(translationPane).not.toBeNull();

    await userEvent.hover(sourcePane as HTMLElement);
    const sourceControlLayer =
      sourcePane?.querySelector(".study-source-content") ?? (sourcePane as HTMLElement);
    expect(
      within(sourceControlLayer as HTMLElement).getByLabelText("Key idea")
    ).toBeInTheDocument();
    expect(sourceControlLayer?.querySelector(":scope > .source-color-palette")).not.toBeNull();
    expect(sourceControlLayer?.querySelector(":scope > .hover-toolbar")).not.toBeNull();
    expect(textBlock?.querySelector(":scope > .block-color-palette")).toBeNull();

    await userEvent.click(within(sourceControlLayer as HTMLElement).getByLabelText("Key idea"));
    expect(textBlock).toHaveClass("reader-block-color-yellow");
    expect(
      sourcePane?.querySelector(".block-color-marker-source.block-color-marker-yellow")
    ).not.toBeNull();
    expect(
      translationPane?.querySelector(".block-color-marker-translation.block-color-marker-yellow")
    ).not.toBeNull();

    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Copy source"));
    expect(writeText).toHaveBeenCalledWith("First paragraph with inline technical content.");
    expect(await screen.findByRole("status")).toHaveTextContent("Source block copied.");

    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Save to Obsidian"));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/obsidian/clips") &&
            init?.method === "POST" &&
            String(init.body).includes('"block_uid":"p-0001"') &&
            String(init.body).includes('"color":"yellow"')
        )
      ).toBe(true);
    });
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Saved to Obsidian: /Users/test/OneDrive/Obsidian/Ilios/Library.md"
    );

    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Show LaTeX"));
    expect(await screen.findByText("Source inspector")).toBeInTheDocument();
    expect(await screen.findByText("First paragraph source LaTeX.")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Close source inspector" }));

    await userEvent.hover(sourcePane as HTMLElement);
    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Ask about source"));
    await openReaderTool("Ask");
    expect(await screen.findByRole("button", { name: "Current block p-0001" })).toBeInTheDocument();
    await openReaderTool("Translate");

    await userEvent.hover(translationPane as HTMLElement);
    expect(translationPane?.querySelector(":scope > .hover-toolbar")).not.toBeNull();
    expect(translationPane?.querySelector(":scope > .block-color-palette")).toBeNull();
    await userEvent.click(
      within(translationPane as HTMLElement).getByLabelText("Copy translation")
    );
    expect(writeText).toHaveBeenCalledWith("第一段 技术内容 的译文。");

    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Translate paper" })).not.toBeDisabled()
    );
    await userEvent.click(within(translationPane as HTMLElement).getByLabelText("Retranslate"));
    expect(await screen.findByText("Retranslate block p-0001")).toBeInTheDocument();
    await userEvent.type(screen.getByLabelText("Custom prompt"), "Use compact academic Chinese.");
    await userEvent.click(screen.getByRole("button", { name: "Queue retranslation" }));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes(
              "/libraries/library-1/articles/revision-1/blocks/p-0001/translate"
            ) && init?.method === "POST"
        )
      ).toBe(true);
    });
    const [, init] =
      fetchMock.mock.calls.find(
        ([url, init]) =>
          String(url).includes(
            "/libraries/library-1/articles/revision-1/blocks/p-0001/translate"
          ) && init?.method === "POST"
      ) ?? [];
    expect(JSON.parse(String(init?.body))).toMatchObject({
      custom_prompt: "Use compact academic Chinese.",
      force: true,
      block_uids: ["p-0001"]
    });
  });

  it("uses a single reading column for source-only and translation-only modes", () => {
    const block: DocumentBlock = {
      id: "block-p-single",
      article_revision_id: "revision-1",
      block_uid: "p-single",
      structural_path: "00004",
      block_type: "paragraph",
      parent_uid: null,
      content_hash: "hash-single",
      context_hash: null,
      source_markdown: "A single-column source paragraph.",
      source_latex: null,
      metadata: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const { unmount } = renderWithProviders(
      <ReaderBlock block={block} viewMode="source" translation="单栏译文。" />
    );
    expect(
      screen.getByText("A single-column source paragraph.").closest(".reader-block")
    ).toHaveClass("single-block-source");
    expect(screen.queryByText("单栏译文。")).not.toBeInTheDocument();
    expect(
      screen.getByText("A single-column source paragraph.").closest(".paired-block")
    ).toBeNull();
    unmount();

    renderWithProviders(
      <ReaderBlock block={block} viewMode="translation" translation="单栏译文。" />
    );
    expect(screen.getByText("单栏译文。").closest(".reader-block")).toHaveClass(
      "single-block-translation"
    );
    expect(screen.queryByText("A single-column source paragraph.")).not.toBeInTheDocument();
    expect(screen.getByText("单栏译文。").closest(".paired-block")).toBeNull();
  });

  it("renders structural title and section blocks as emphasized single-column headings", () => {
    const titleBlock: DocumentBlock = {
      id: "block-title",
      article_revision_id: "revision-1",
      block_uid: "sec-title",
      structural_path: "00001",
      block_type: "section",
      parent_uid: null,
      content_hash: "hash-title",
      context_hash: null,
      source_markdown: "Attention Is All You Need",
      source_latex: null,
      metadata: { level: 1 },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    const abstractBlock: DocumentBlock = {
      ...titleBlock,
      id: "block-abstract",
      block_uid: "sec-abstract",
      structural_path: "00002",
      content_hash: "hash-abstract",
      source_markdown: "Abstract",
      metadata: { level: 6 }
    };

    const { unmount } = renderWithProviders(
      <ReaderBlock block={titleBlock} viewMode="bilingual" translation="跳过的标题译文。" />
    );
    expect(
      screen.getByRole("heading", { name: "Attention Is All You Need", level: 1 })
    ).toBeInTheDocument();
    expect(screen.getByText("Attention Is All You Need").closest(".reader-block")).toHaveClass(
      "structural-block-title"
    );
    expect(screen.queryByText("跳过的标题译文。")).not.toBeInTheDocument();
    expect(screen.getByText("Attention Is All You Need").closest(".paired-block")).toBeNull();
    unmount();

    renderWithProviders(
      <ReaderBlock block={abstractBlock} viewMode="bilingual" translation="跳过的摘要译文。" />
    );
    expect(screen.getByRole("heading", { name: "Abstract", level: 2 })).toBeInTheDocument();
    expect(screen.getByText("Abstract").closest(".reader-block")).toHaveClass(
      "structural-block-abstract"
    );
    expect(screen.queryByText("跳过的摘要译文。")).not.toBeInTheDocument();
    expect(screen.getByText("Abstract").closest(".paired-block")).toBeNull();
  });

  it("renders short standalone bold-topic paragraphs as in-flow headings", () => {
    const headingBlock: DocumentBlock = {
      id: "block-topic-heading",
      article_revision_id: "revision-1",
      block_uid: "p-topic-heading",
      structural_path: "00063",
      block_type: "paragraph",
      parent_uid: null,
      content_hash: "hash-topic-heading",
      context_hash: null,
      source_markdown: "PASCAL VOC",
      source_latex: null,
      metadata: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    renderWithProviders(
      <ReaderBlock block={headingBlock} viewMode="study" translation="帕斯卡视觉对象类别。" />
    );

    expect(screen.getByRole("heading", { name: "PASCAL VOC", level: 3 })).toBeInTheDocument();
    expect(screen.getByText("PASCAL VOC").closest(".reader-block")).toHaveClass(
      "paragraph-heading-block"
    );
    expect(screen.queryByText("帕斯卡视觉对象类别。")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Show translation")).not.toBeInTheDocument();
  });

  it("renders formulas inside LaTeXML table fragments", () => {
    const tableBlock = documentPayload.blocks.find((block) => block.block_type === "table")!;
    const tableAsset = {
      id: "asset-table-math",
      article_revision_id: "revision-1",
      asset_id: "asset-table-math",
      kind: "table",
      source_path: null,
      web_path: null,
      caption: "Regression table.",
      label: "tab:math",
      metadata: {
        html_fragment:
          '<figure class="ltx_table" id="tab:math"><table><tr><th>Loss</th><td><math alttext="L = x_i^2"></math></td></tr><tr><th>Complexity</th><td><math alttext="O(k\\cdot n\\cdot d^{2})"></math></td></tr><tr><th>Block</th><td><math alttext="\\left[\\begin{array}[]{c}\\text{3$\\times$3, 64}\\\\[-1.00006pt]\\text{3$\\times$3, 64}\\end{array}\\right]\\times2"></math></td></tr></table></figure>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const { container } = renderWithProviders(
      <ReaderBlock block={tableBlock} asset={tableAsset} viewMode="bilingual" />
    );
    expect(container.querySelector(".environment-block-table")).not.toBeNull();
    expect(container.querySelector(".academic-table-scroll")).not.toBeNull();
    expect(container.querySelector(".latexml-fragment-preview table")).not.toBeNull();
    expect(container.querySelector(".latexml-fragment-preview .katex")).not.toBeNull();
    expect(container.querySelector(".latexml-fragment-preview .katex-error")).toBeNull();
    expect(container.querySelector(".latexml-fragment-preview")).toHaveTextContent(
      "O(k\\cdot n\\cdot d^{2})"
    );
    expect(container.querySelector(".latexml-fragment-preview")).not.toHaveTextContent(/ddd\d/);
  });

  it("renders LaTeXML inline SVG figures when no bitmap asset exists", () => {
    const figureBlock: DocumentBlock = {
      id: "block-svg-figure",
      article_revision_id: "revision-1",
      block_uid: "fig-svg",
      structural_path: "00060",
      block_type: "figure",
      parent_uid: null,
      content_hash: "hash-svg-figure",
      context_hash: null,
      source_markdown: "**Figure 1.** Quantum gate network.",
      source_latex: null,
      metadata: {
        asset_id: "fig-svg",
        label: "Ch2.F1"
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    const figureAsset = {
      id: "asset-svg-figure",
      article_revision_id: "revision-1",
      asset_id: "fig-svg",
      kind: "figure",
      source_path: null,
      web_path: null,
      caption: "Quantum gate network.",
      label: "Ch2.F1",
      metadata: {
        html_fragment:
          '<figure class="ltx_figure"><svg width="166" height="83" overflow="visible"><script>alert(1)</script><g transform="translate(0,83) scale(1,-1)"><path d="M 0,0 40,0" stroke="#000000" stroke-width="0.4"></path><text x="4" y="12">q</text></g></svg><figcaption>Figure 1: Quantum gate network.</figcaption></figure>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const { container } = renderWithProviders(
      <ReaderBlock block={figureBlock} asset={figureAsset} viewMode="source" />
    );

    const svg = container.querySelector(".latexml-fragment-preview svg");
    expect(svg).not.toBeNull();
    expect(svg).toHaveClass("latexml-inline-svg");
    expect(svg).toHaveAttribute("width", "166");
    expect(container.querySelector(".latexml-fragment-preview path")).toHaveAttribute(
      "d",
      "M 0,0 40,0"
    );
    expect(container.querySelector(".latexml-fragment-preview script")).toBeNull();
  });

  it("keeps CIFAR-style LaTeXML tables structured instead of flattening rows", () => {
    const tableBlock: DocumentBlock = {
      id: "block-cifar-table",
      article_revision_id: "revision-1",
      block_uid: "tbl-cifar",
      structural_path: "00076",
      block_type: "table",
      parent_uid: null,
      content_hash: "hash-cifar-table",
      context_hash: null,
      source_markdown:
        "**Table 6.** Classification error on the CIFAR-10 test set. All methods are with data augmentation.",
      source_latex: null,
      metadata: {
        asset_id: "tbl-cifar",
        label: "S4.T6"
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    const tableAsset = {
      id: "asset-cifar-table",
      article_revision_id: "revision-1",
      asset_id: "tbl-cifar",
      kind: "table",
      source_path: null,
      web_path: null,
      caption: "Classification error on the CIFAR-10 test set.",
      label: "S4.T6",
      metadata: {
        html_fragment:
          '<figure class="ltx_table" id="S4.T6"><div class="ltx_transformed_outer"><span class="ltx_transformed_inner" style="transform:scale(1.2);"><table class="ltx_tabular"><tbody><tr><td colspan="3">method</td><td>error (%)</td></tr><tr><td colspan="3">Maxout <cite>[Goodfellow2013]</cite></td><td>9.38</td></tr><tr><td></td><td># layers</td><td># params</td><td></td></tr><tr><td>ResNet</td><td>110</td><td>1.7M</td><td>6.43 <math alttext="6.61\\pm0.16"></math></td></tr></tbody></table></span></div><figcaption><span class="ltx_tag ltx_tag_table">Table 6: </span>Classification error on the CIFAR-10 test set.</figcaption></figure>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const { container } = renderWithProviders(
      <ReaderBlock block={tableBlock} asset={tableAsset} viewMode="source" />
    );
    const table = container.querySelector(".latexml-fragment-preview table");
    expect(table).not.toBeNull();
    expect(container.querySelector(".latexml-fragment-preview figure")).toBeNull();
    expect(container.querySelectorAll(".latexml-fragment-preview tr")).toHaveLength(4);
    expect(container.querySelectorAll(".latexml-fragment-preview th")).toHaveLength(2);
    expect(container.querySelector(".latexml-fragment-preview th")).toHaveAttribute("colspan", "3");
    expect(container.querySelector(".latexml-fragment-preview .katex")).not.toBeNull();
    expect(screen.getByText("Table 6.").closest("p")).toHaveTextContent(
      "Table 6. Classification error on the CIFAR-10 test set."
    );
  });

  it("renders LaTeXML equation tables as equations for existing parsed articles", () => {
    const equationTableBlock: DocumentBlock = {
      id: "block-equation-table",
      article_revision_id: "revision-1",
      block_uid: "tbl-equation",
      structural_path: "00006",
      block_type: "table",
      parent_uid: null,
      content_hash: "hash-equation-table",
      context_hash: null,
      source_markdown: "**Table 1.** Attention(Q,K,V)=V (1)",
      source_latex: null,
      metadata: {
        asset_id: "tbl-equation",
        label: "S3.E1",
        html_fragment:
          '<table class="ltx_equation ltx_eqn_table" id="S3.E1"><tr><td><math display="block" alttext="\\mathrm{Attention}(Q,K,V)=V"></math></td><td class="ltx_eqn_cell ltx_eqn_eqno">(1)</td></tr></table>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    const equationTableAsset = {
      id: "asset-equation-table",
      article_revision_id: "revision-1",
      asset_id: "tbl-equation",
      kind: "table",
      source_path: null,
      web_path: null,
      caption: "Attention equation.",
      label: "S3.E1",
      metadata: equationTableBlock.metadata,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const { container } = renderWithProviders(
      <ReaderBlock
        block={equationTableBlock}
        asset={equationTableAsset}
        viewMode="bilingual"
        translation="表1. Attention 方程的旧翻译。"
      />
    );

    expect(container.querySelector(".math-block .katex")).not.toBeNull();
    expect(screen.getByText("(1)")).toHaveClass("equation-number");
    expect(container.querySelector(".latexml-fragment-preview table")).toBeNull();
    expect(screen.queryByText(/Table 1/)).not.toBeInTheDocument();
    expect(screen.queryByText(/表1/)).not.toBeInTheDocument();
  });

  it("renders legacy LaTeXML table figures with table captions", () => {
    const legacyTableFigureBlock: DocumentBlock = {
      id: "block-legacy-table",
      article_revision_id: "revision-1",
      block_uid: "fig-legacy-table",
      structural_path: "00007",
      block_type: "figure",
      parent_uid: null,
      content_hash: "hash-legacy-table",
      context_hash: null,
      source_markdown:
        "**Figure 3.** Table 1: Maximum path lengths, per-layer complexity and minimum number of sequential operations.",
      source_latex: null,
      metadata: {
        asset_id: "fig-legacy-table",
        label: "S4.T1",
        html_fragment:
          '<figure class="ltx_table" id="S4.T1"><figcaption class="ltx_caption"><span class="ltx_tag ltx_tag_table">Table 1: </span>Maximum path lengths, per-layer complexity and minimum number of sequential operations.</figcaption><table class="ltx_tabular"><tr><th>Layer Type</th><th>Complexity</th></tr><tr><td>Self-Attention</td><td><math alttext="O(n^2 d)"></math></td></tr></table></figure>'
      },
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    const legacyTableAsset = {
      id: "asset-legacy-table",
      article_revision_id: "revision-1",
      asset_id: "fig-legacy-table",
      kind: "figure",
      source_path: null,
      web_path: null,
      caption:
        "Table 1: Maximum path lengths, per-layer complexity and minimum number of sequential operations.",
      label: "S4.T1",
      metadata: legacyTableFigureBlock.metadata,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const { container } = renderWithProviders(
      <ReaderBlock
        block={legacyTableFigureBlock}
        asset={legacyTableAsset}
        viewMode="bilingual"
        translation="**图3.** 表1：不同层类型的最大路径长度、每层复杂度和最少顺序操作数。"
      />
    );

    const caption = screen.getByText("Table 1.").closest("p");
    expect(caption).toHaveTextContent(
      "Table 1. Maximum path lengths, per-layer complexity and minimum number of sequential operations."
    );
    expect(screen.queryByText(/Figure 3/)).not.toBeInTheDocument();
    expect(screen.queryByText(/图3/)).not.toBeInTheDocument();
    expect(screen.getByText(/表1：不同层类型/)).toBeInTheDocument();
    expect(container.querySelector(".latexml-fragment-preview table")).not.toBeNull();
    expect(container.querySelector(".latexml-fragment-preview .katex")).not.toBeNull();
  });

  it("falls back to DOM copy when the async clipboard API is unavailable", async () => {
    Object.defineProperty(navigator, "clipboard", {
      value: undefined,
      configurable: true
    });
    const execCommand = vi.fn(() => true);
    Object.defineProperty(document, "execCommand", {
      value: execCommand,
      configurable: true
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
          return jsonResponse(documentPayload);
        }
        if (url.endsWith("/providers")) return jsonResponse([provider]);
        if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
          return jsonResponse(translationsPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
          return jsonResponse(glossaryPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
          return jsonResponse(chatPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
          return jsonResponse(noteTemplatesPayload);
        }
        if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
          return jsonResponse(notePatchesPayload);
        }
        return jsonResponse([]);
      })
    );

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    const paragraph = await screen.findByText("First paragraph with inline technical content.");
    const sourcePane = paragraph.closest(".source-pane");
    expect(sourcePane).not.toBeNull();
    await userEvent.hover(sourcePane as HTMLElement);
    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Copy source"));

    expect(execCommand).toHaveBeenCalledWith("copy");
    expect(await screen.findByRole("status")).toHaveTextContent("Source block copied.");
  });

  it("saves provider profiles from settings", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/providers/discover-models") && init?.method === "POST") {
        return jsonResponse({
          protocol: "openai-compatible",
          base_url: "https://api.example.com/v1",
          default_model: "mock-model",
          capabilities: { model_discovery: true, model_count: 2 },
          models: [
            {
              id: "text-embedding-3-large",
              display_name: "Embedding Model",
              owned_by: "example",
              created_at: null,
              capabilities: { chat: false, translation: false, streaming: true },
              metadata: {}
            },
            {
              id: "mock-model",
              display_name: "Mock Model",
              owned_by: "example",
              created_at: null,
              capabilities: { chat: true, translation: true, streaming: true, native_search: true },
              metadata: {}
            },
            {
              id: "other-model",
              display_name: "Other Model",
              owned_by: "example",
              created_at: null,
              capabilities: { streaming: true },
              metadata: {}
            }
          ]
        });
      }
      if (url.endsWith("/providers") && init?.method === "POST") return jsonResponse(provider, 201);
      if (url.endsWith("/providers")) return jsonResponse([]);
      if (url.endsWith("/doctor")) return jsonResponse({ bilin_home: "/tmp", capabilities: [] });
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderWithProviders(<SettingsPage />);
    await userEvent.click(screen.getByText("Advanced"));
    await userEvent.type(screen.getByLabelText("Profile label"), "Mock Provider");
    await userEvent.type(screen.getByLabelText("API key"), "test-key");
    await userEvent.clear(screen.getByLabelText("Concurrency"));
    await userEvent.type(screen.getByLabelText("Concurrency"), "2");
    await userEvent.type(screen.getByLabelText("Requests per minute"), "120");
    await userEvent.click(screen.getByRole("button", { name: "Find models" }));
    expect(await screen.findByText("Mock Model")).toBeInTheDocument();
    expect(screen.getByText("Embedding Model")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Embedding Model unavailable" })).toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Use selected model" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) => String(url).endsWith("/providers") && init?.method === "POST"
        )
      ).toBe(true);
    });
    const [, init] =
      fetchMock.mock.calls.find(
        ([url, init]) => String(url).endsWith("/providers") && init?.method === "POST"
      ) ?? [];
    expect(JSON.parse(String(init?.body))).toMatchObject({
      name: "Mock Provider",
      default_model: "mock-model",
      max_concurrent_requests: 2,
      requests_per_minute: 120,
      capabilities: {
        model_discovery: true,
        native_search: true
      }
    });
  });

  it("reviews translation memory entries from settings", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes("/translation-memory/memory-1") && init?.method === "PATCH") {
        return jsonResponse({
          ...translationMemoryEntry,
          review_status: "approved",
          reuse_enabled: true
        });
      }
      if (url.includes("/translation-memory")) {
        return jsonResponse({ entries: [translationMemoryEntry] });
      }
      if (url.endsWith("/providers")) return jsonResponse([]);
      if (url.endsWith("/doctor")) return jsonResponse({ bilin_home: "/tmp", capabilities: [] });
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderWithProviders(<SettingsPage />);
    await userEvent.click(screen.getByRole("tab", { name: "Translation memory" }));
    expect(await screen.findByText("A source paragraph for memory.")).toBeInTheDocument();
    expect(screen.getByText("待审核的记忆译文。")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/translation-memory/memory-1") && init?.method === "PATCH"
        )
      ).toBe(true);
    });
    const [, init] =
      fetchMock.mock.calls.find(
        ([url, init]) =>
          String(url).includes("/translation-memory/memory-1") && init?.method === "PATCH"
      ) ?? [];
    expect(JSON.parse(String(init?.body))).toMatchObject({
      review_status: "approved",
      reuse_enabled: true
    });
  });

  it("switches interface language from settings without product design copy", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/providers")) return jsonResponse([]);
        if (url.endsWith("/doctor")) return jsonResponse({ bilin_home: "/tmp", capabilities: [] });
        if (url.includes("/translation-memory")) return jsonResponse({ entries: [] });
        return jsonResponse([]);
      })
    );

    renderWithProviders(<SettingsPage />);
    await userEvent.click(screen.getByRole("tab", { name: "Interface" }));
    expect(screen.getByText("Reading preferences")).toBeInTheDocument();
    expect(screen.getByRole("slider", { name: "Line width" })).toBeInTheDocument();
    expect(screen.queryByText("Product names")).not.toBeInTheDocument();
    expect(screen.queryByText("Ilios")).not.toBeInTheDocument();
    expect(screen.queryByText("Core")).not.toBeInTheDocument();
    await userEvent.click(screen.getAllByLabelText("Language")[0]);
    await userEvent.click(await screen.findByRole("option", { name: "简体中文" }));
    expect(await screen.findByText("界面语言")).toBeInTheDocument();
    expect(screen.queryByText("产品名称")).not.toBeInTheDocument();
  });

  it("queues article translation from the reader", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        if (init?.method === "POST") {
          return jsonResponse({
            library_id: "library-1",
            article_revision_id: "revision-1",
            target_language: "zh-CN",
            jobs_created: 1,
            existing_jobs: 0,
            cached_blocks: 0,
            skipped_blocks: 1,
            job_ids: ["job-translate-1"]
          });
        }
        return jsonResponse({
          article_revision_id: "revision-1",
          target_language: "zh-CN",
          variants: []
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse({ article_revision_id: "revision-1", patches: [] });
      }
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    expect(
      await screen.findByText("First paragraph with inline technical content.")
    ).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Translate paper" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/translations") &&
            init?.method === "POST"
        )
      ).toBe(true);
    });

    await userEvent.click(screen.getByRole("textbox", { name: "Target language" }));
    await userEvent.click(await screen.findByRole("option", { name: "日本語" }));
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/translations") &&
            init?.method === "POST" &&
            String(init.body).includes('"target_language":"ja"')
        )
      ).toBe(true);
    });
  });

  it("confirms glossary candidates from the reader", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      void init;
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary/term-candidate-1")) {
        return jsonResponse({
          ...glossaryCandidatePayload.terms[0],
          target_term: "技术内容",
          status: "active"
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryCandidatePayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse({ article_revision_id: "revision-1", patches: [] });
      }
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    await openReaderTool("Terms");
    expect(await screen.findByText("technical content")).toBeInTheDocument();
    await userEvent.type(screen.getByLabelText("Target term for technical content"), "技术内容");
    await userEvent.click(screen.getByRole("button", { name: "Confirm" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes(
              "/libraries/library-1/articles/revision-1/glossary/term-candidate-1"
            ) && init?.method === "PUT"
        )
      ).toBe(true);
    });
  });

  it("asks an article-grounded question from the reader", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat/ask-stream")) {
        const result = {
          article_revision_id: "revision-1",
          user_message: {
            id: "chat-user-1",
            article_revision_id: "revision-1",
            role: "user",
            content: "What is the paragraph about?",
            source_refs: [],
            external_refs: [],
            metadata: {},
            created_at: new Date().toISOString()
          },
          assistant_message: {
            id: "chat-assistant-1",
            article_revision_id: "revision-1",
            role: "assistant",
            content: "It explains technical content [p-0001].",
            source_refs: ["p-0001"],
            external_refs: [],
            metadata: {},
            created_at: new Date().toISOString()
          },
          cited_blocks: [
            {
              block_uid: "p-0001",
              block_type: "paragraph",
              structural_path: "00002",
              source_markdown: "First paragraph with inline technical content.",
              score: -1,
              evidence_type: "current_paper"
            }
          ],
          external_refs: [],
          native_search_used: false
        };
        return sseResponse(
          [
            sseEvent("evidence", { cited_blocks: result.cited_blocks }),
            sseEvent("delta", { text: "It explains technical content [p-0001]." }),
            sseEvent("done", result)
          ].join("")
        );
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse({ article_revision_id: "revision-1", patches: [] });
      }
      void init;
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    expect(
      await screen.findByText("First paragraph with inline technical content.")
    ).toBeInTheDocument();
    await openReaderTool("Ask");
    await userEvent.type(screen.getByLabelText("Question"), "What is the paragraph about?");
    await userEvent.click(screen.getByRole("button", { name: "Ask paper" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/chat/ask-stream") &&
            init?.method === "POST"
        )
      ).toBe(true);
    });
    expect(await screen.findByText("Current-paper evidence")).toBeInTheDocument();
  });

  it("generates and accepts lecture note patches from the reader", async () => {
    let customTemplate: {
      id: string;
      name: string;
      description: string;
      custom: boolean;
      metadata: Record<string, unknown>;
    } | null = null;
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (
        url.includes("/libraries/library-1/articles/revision-1/notes/templates") &&
        init?.method === "POST"
      ) {
        const body = JSON.parse(String(init.body)) as {
          name: string;
          description: string;
          metadata?: Record<string, unknown>;
        };
        customTemplate = {
          id: "custom-template-1",
          name: body.name,
          description: body.description,
          custom: true,
          metadata: body.metadata ?? {}
        };
        return jsonResponse(customTemplate);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(
          customTemplate ? [...noteTemplatesPayload, customTemplate] : noteTemplatesPayload
        );
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/generate")) {
        return jsonResponse({
          article_revision_id: "revision-1",
          patch: notePatchesPayload.patches[0],
          template: customTemplate ?? noteTemplatesPayload[0]
        });
      }
      if (
        url.includes("/libraries/library-1/articles/revision-1/notes/patches/patch-1") &&
        init?.method === "PUT"
      ) {
        const body = JSON.parse(String(init.body)) as {
          title?: string;
          patch_markdown?: string;
          status?: string;
        };
        return jsonResponse({
          ...notePatchesPayload.patches[0],
          title: body.title ?? notePatchesPayload.patches[0].title,
          patch_markdown: body.patch_markdown ?? notePatchesPayload.patches[0].patch_markdown,
          status: body.status ?? "proposed",
          metadata: { ...notePatchesPayload.patches[0].metadata, notes_path: "/tmp/notes.md" }
        });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse(notePatchesPayload);
      }
      void init;
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    await openReaderTool("Notes");
    expect(await screen.findByRole("heading", { name: "Lecture notes" })).toBeInTheDocument();

    await userEvent.type(screen.getByLabelText("Custom template name"), "Seminar template");
    await userEvent.type(
      screen.getByLabelText("Custom template prompt"),
      "Focus on discussion questions."
    );
    await userEvent.click(screen.getByRole("button", { name: "Save template" }));

    const generateButton = await screen.findByRole("button", { name: "Generate patch" });
    await waitFor(() => expect(generateButton).not.toBeDisabled());
    await userEvent.click(generateButton);
    const patchMarkdown = await screen.findByLabelText("Patch markdown for patch-1");
    await userEvent.clear(patchMarkdown);
    await userEvent.click(patchMarkdown);
    await userEvent.paste("## Edited\n\nEdited note body [p-0001].");
    await userEvent.click(await screen.findByRole("button", { name: "Accept edited" }));

    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/notes/templates") &&
            init?.method === "POST"
        )
      ).toBe(true);
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/notes/generate") &&
            init?.method === "POST"
        )
      ).toBe(true);
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes(
              "/libraries/library-1/articles/revision-1/notes/patches/patch-1"
            ) &&
            init?.method === "PUT" &&
            String(init.body).includes("Edited note body") &&
            String(init.body).includes("accepted")
        )
      ).toBe(true);
    });
  });

  it("exports article artifacts from the reader", async () => {
    const anchorClick = vi
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => undefined);
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/providers")) return jsonResponse([provider]);
      if (url.endsWith("/libraries/library-1/articles/revision-1/document")) {
        return jsonResponse(documentPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/translations")) {
        return jsonResponse(translationsPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/glossary")) {
        return jsonResponse(glossaryPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/chat")) {
        return jsonResponse({ article_revision_id: "revision-1", messages: [] });
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/templates")) {
        return jsonResponse(noteTemplatesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/notes/patches")) {
        return jsonResponse(notePatchesPayload);
      }
      if (url.includes("/libraries/library-1/articles/revision-1/exports")) {
        return jsonResponse({
          article_revision_id: "revision-1",
          kind: "bilingual_markdown",
          target_language: "zh-CN",
          file_name: "bilingual.zh-CN.md",
          path: "/tmp/bilingual.zh-CN.md",
          bytes_written: 128,
          missing_translation_block_uids: ["fig-0001"],
          created_at: new Date().toISOString()
        });
      }
      void init;
      return jsonResponse([]);
    });
    vi.stubGlobal("fetch", fetchMock);

    renderRoute("/articles/revision-1?libraryId=library-1", "/articles/:articleId", <ReaderPage />);
    await openReaderTool("Export");
    await userEvent.click(await screen.findByRole("button", { name: "Export and download" }));

    expect(await screen.findByText(/Ready: bilingual.zh-CN.md/)).toBeInTheDocument();
    expect(await screen.findByText("Missing translations: fig-0001")).toBeInTheDocument();
    const downloadLink = await screen.findByRole("link", { name: "Download file" });
    expect(downloadLink).toHaveAttribute("download", "bilingual.zh-CN.md");
    expect(downloadLink).toHaveAttribute(
      "href",
      "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/exports/bilingual.zh-CN.md"
    );
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/exports") &&
            init?.method === "POST"
        )
      ).toBe(true);
      expect(anchorClick).toHaveBeenCalledTimes(1);
    });
    anchorClick.mockRestore();
  });
});
