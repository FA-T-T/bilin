import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type React from "react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { LibraryHomePage } from "../src/pages/LibraryHomePage";
import { ReaderBlock } from "../src/components/ReaderBlock";
import { TaskDrawer } from "../src/components/TaskDrawer";
import { LibraryDetailPage } from "../src/pages/LibraryDetailPage";
import { ReaderPage } from "../src/pages/ReaderPage";
import { SettingsPage } from "../src/pages/SettingsPage";
import type { DocumentBlock } from "../src/api/types";
import { useUiStore } from "../src/state/ui";

beforeEach(() => {
  Object.defineProperty(Element.prototype, "scrollIntoView", {
    value: vi.fn(),
    configurable: true
  });
});

afterEach(() => {
  cleanup();
  useUiStore.getState().closeTaskDrawer();
  useUiStore.getState().setReaderViewMode("study");
  vi.unstubAllGlobals();
});

function renderWithProviders(node: React.ReactNode) {
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

function renderRoute(route: string, path: string, node: React.ReactNode) {
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

async function openReaderTool(name: "Translate" | "Terms" | "Ask" | "Notes" | "Export") {
  await userEvent.click(await screen.findByRole("tab", { name }));
}

async function expandFirstTranslation() {
  const buttons = await screen.findAllByRole("button", { name: "Show translation" });
  await userEvent.click(buttons[0]);
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
  block_count: 5,
  asset_count: 2
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
      block_uid: "tbl-0001",
      structural_path: "00005",
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
      metadata: { original_reference: "figures/pipeline.png" },
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

  it("renders the reader empty state without article context", async () => {
    renderWithProviders(<ReaderPage />);
    expect(screen.getByText("Article reader")).toBeInTheDocument();
    expect(
      screen.getByText("Open an article from a library so the reader can load its parsed document.")
    ).toBeInTheDocument();
  });

  it("renders real asset images when an asset URL is available", () => {
    renderWithProviders(
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
          source_markdown: "**Figure 1.** Asset caption.",
          source_latex: null,
          metadata: { asset_id: "fig-0001" },
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
          metadata: {},
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }}
        assetUrl="http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-0001"
        viewMode="bilingual"
      />
    );

    expect(screen.getByRole("img", { name: "Asset caption" })).toHaveAttribute(
      "src",
      "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-0001"
    );
    expect(screen.queryByText("Structured asset placeholder")).not.toBeInTheDocument();
  });

  it("submits an arXiv import job and renders article rows", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      void init;
      const url = String(input);
      if (url.endsWith("/libraries/library-1")) return jsonResponse(library);
      if (url.endsWith("/libraries/library-1/articles")) return jsonResponse([article]);
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
    expect(await screen.findByText("A Minimal Bilin Test Paper")).toBeInTheDocument();
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
        if (url.endsWith("/jobs")) {
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
    expect(await screen.findByText("A Minimal Bilin Test Paper")).toBeInTheDocument();
    expect(await screen.findByTestId("reader-block-list")).toHaveAttribute(
      "data-virtualization",
      "browser-native"
    );
    expect(
      await screen.findByText("First paragraph with inline technical content.")
    ).toBeInTheDocument();
    expect(await screen.findByRole("img", { name: "An overview pipeline." })).toHaveAttribute(
      "src",
      "http://127.0.0.1:8000/libraries/library-1/articles/revision-1/assets/fig-0001"
    );
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
    await userEvent.click(within(screen.getByTestId("reader-view-mode")).getByText("Focus"));
    expect(await screen.findByText("第一段 技术内容 的译文。")).toBeInTheDocument();
    expect(paragraphShell.querySelector(".reader-block-focus-current")).not.toBeNull();
    expect(
      screen.getByTestId("reader-block-shell-sec-001").querySelector(".reader-block-dimmed")
    ).not.toBeNull();
    expect(screen.getByRole("button", { name: "Translation open" })).toBeDisabled();
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
    expect(sourcePane).not.toBeNull();
    await userEvent.click(
      within(sourcePane as HTMLElement).getByRole("button", { name: "Show translation" })
    );
    const translation = await screen.findByText("第一段 技术内容 的译文。");
    const translationPane = translation.closest(".translation-pane");
    expect(translationPane).not.toBeNull();

    await userEvent.hover(sourcePane as HTMLElement);
    expect(sourcePane?.closest(".text-block")).toHaveClass("reader-block-active");

    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Copy source"));
    expect(writeText).toHaveBeenCalledWith("First paragraph with inline technical content.");
    expect(await screen.findByRole("status")).toHaveTextContent("Source block copied.");

    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Show LaTeX"));
    expect(await screen.findByText("Source inspector")).toBeInTheDocument();
    expect(await screen.findByText("First paragraph source LaTeX.")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Close source inspector" }));

    await userEvent.click(within(sourcePane as HTMLElement).getByLabelText("Ask about source"));
    await openReaderTool("Ask");
    expect(await screen.findByRole("button", { name: "Current block p-0001" })).toBeInTheDocument();
    await openReaderTool("Translate");

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
    expect(await screen.findByText("A Minimal Bilin Test Paper")).toBeInTheDocument();
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
    expect(await screen.findByText("A Minimal Bilin Test Paper")).toBeInTheDocument();
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
    await userEvent.click(await screen.findByRole("button", { name: "Export artifact" }));

    expect(await screen.findByText(/Wrote bilingual.zh-CN.md/)).toBeInTheDocument();
    expect(await screen.findByText("Missing translations: fig-0001")).toBeInTheDocument();
    await waitFor(() => {
      expect(
        fetchMock.mock.calls.some(
          ([url, init]) =>
            String(url).includes("/libraries/library-1/articles/revision-1/exports") &&
            init?.method === "POST"
        )
      ).toBe(true);
    });
  });
});
