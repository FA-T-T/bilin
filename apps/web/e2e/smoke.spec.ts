import { expect, test, type Page, type Route } from "@playwright/test";

const timestamp = "2026-04-30T00:00:00.000Z";

test("opens the reader shell", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Library", exact: true })).toBeVisible();

  await page.goto("/libraries/smoke-library");
  await expect(page.getByRole("heading", { name: "Add article" })).toBeVisible();
  await page.getByLabel("arXiv ID").fill("2401.00001");
  await expect(page.getByRole("button", { name: "Add article" })).toBeEnabled();

  await mockArticleApi(page);
  await page.goto("/articles/revision-smoke?libraryId=library-smoke");
  await expect(page.getByRole("heading", { name: "A Playwright Parsed Paper" })).toBeVisible();
  await expect(page.getByText("A parsed paragraph from the mocked article API.")).toBeVisible();
  await expect(page.getByText("来自 mocked article API 的译文。")).toHaveCount(0);
  await page.getByRole("button", { name: "Show translation" }).click();
  await expect(page.getByText("来自 mocked article API 的译文。")).toBeVisible();
  await page.getByLabel("Show LaTeX").first().click();
  await expect(page.getByRole("dialog", { name: "Source inspector" })).toBeVisible();
  await expect(page.getByText("A parsed paragraph from source LaTeX.")).toBeVisible();
  await page.getByLabel("Close source inspector").click();
  await page.getByTestId("reader-view-mode").getByText("Source").click();
  await expect(page.getByText("Translation pending.")).toHaveCount(0);
  await page.getByLabel("Open task drawer").click();
  await expect(page.getByText("Background tasks")).toBeVisible();

  await page.goto("/settings");
  await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
});

async function mockArticleApi(page: Page) {
  await page.route("http://127.0.0.1:8000/**", async (route) => {
    const url = new URL(route.request().url());
    const pathname = url.pathname;
    if (pathname === "/providers") {
      return fulfillJson(route, [
        {
          id: "provider-smoke",
          name: "Smoke Provider",
          protocol: "openai-compatible",
          base_url: "https://api.example.com/v1",
          key_ref: "app_settings:provider_api_key:provider-smoke",
          default_model: "smoke-model",
          max_concurrent_requests: 1,
          requests_per_minute: null,
          capabilities: {},
          created_at: timestamp,
          updated_at: timestamp
        }
      ]);
    }
    if (pathname === "/doctor") {
      return fulfillJson(route, { bilin_home: "/tmp/bilin", capabilities: [] });
    }
    if (pathname === "/jobs") {
      return fulfillJson(route, []);
    }
    if (pathname.endsWith("/articles/revision-smoke/document")) {
      return fulfillJson(route, smokeDocument());
    }
    if (pathname.endsWith("/articles/revision-smoke/translations")) {
      return fulfillJson(route, {
        article_revision_id: "revision-smoke",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        variants: [
          {
            id: "translation-smoke",
            block_id: "block-p-smoke",
            target_language: "zh-CN",
            provider_profile_id: "provider-smoke",
            model: "smoke-model",
            raw_markdown: "来自 mocked article API 的译文。",
            render_ast: null,
            validation_status: "ok",
            glossary_version: null,
            is_default: true,
            metadata: { block_uid: "p-smoke" },
            created_at: timestamp,
            updated_at: timestamp
          }
        ]
      });
    }
    if (pathname.endsWith("/articles/revision-smoke/glossary")) {
      return fulfillJson(route, {
        article_revision_id: "revision-smoke",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        active_version: "glossary:none",
        affected_block_uids: [],
        terms: []
      });
    }
    if (pathname.endsWith("/articles/revision-smoke/chat")) {
      return fulfillJson(route, { article_revision_id: "revision-smoke", messages: [] });
    }
    if (pathname.endsWith("/articles/revision-smoke/notes/templates")) {
      return fulfillJson(route, [
        {
          id: "deep_reading",
          name: "精读模板",
          description: "Smoke note template."
        }
      ]);
    }
    if (pathname.endsWith("/articles/revision-smoke/notes/patches")) {
      return fulfillJson(route, { article_revision_id: "revision-smoke", patches: [] });
    }
    return fulfillJson(route, []);
  });
}

function fulfillJson(route: Route, body: unknown, status = 200) {
  return route.fulfill({
    status,
    contentType: "application/json",
    body: JSON.stringify(body)
  });
}

function smokeDocument() {
  return {
    article_revision: {
      id: "revision-smoke",
      family_id: "family-smoke",
      version: "v1",
      bundle_path: "/tmp/library/articles/arxiv/2401.00001/v1",
      status: "parsed",
      manifest_version: 1,
      metadata: {},
      created_at: timestamp,
      updated_at: timestamp
    },
    manifest: {
      schema_version: 1,
      article_revision_id: "revision-smoke",
      arxiv_id: "2401.00001v1",
      source: "arxiv",
      arxiv_metadata: { title: "A Playwright Parsed Paper" },
      parse_status: "parsed",
      errors: [],
      metadata: {}
    },
    blocks: [
      {
        id: "block-sec-smoke",
        article_revision_id: "revision-smoke",
        block_uid: "sec-smoke",
        structural_path: "00001",
        block_type: "section",
        parent_uid: null,
        content_hash: "hash-section-smoke",
        context_hash: null,
        source_markdown: "Introduction",
        source_latex: null,
        metadata: { level: 1 },
        created_at: timestamp,
        updated_at: timestamp
      },
      {
        id: "block-p-smoke",
        article_revision_id: "revision-smoke",
        block_uid: "p-smoke",
        structural_path: "00002",
        block_type: "paragraph",
        parent_uid: null,
        content_hash: "hash-paragraph-smoke",
        context_hash: null,
        source_markdown: "A parsed paragraph from the mocked article API.",
        source_latex: "A parsed paragraph from source LaTeX.",
        metadata: {},
        created_at: timestamp,
        updated_at: timestamp
      }
    ],
    assets: []
  };
}
