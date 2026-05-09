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
  await expect(page.locator(".reader-bottom-chapters")).toBeVisible();
  await expect(page.locator(".reader-command-center")).toBeVisible();
  const sourceContent = page.locator(".study-block-translation-open .study-source-content").first();
  const translationPanel = page
    .locator(".study-block-translation-open .study-translation-panel")
    .first();
  await sourceContent.hover();
  const sourceCopyButton = page.getByLabel("Copy source").first();
  await expect(sourceCopyButton).toBeVisible();
  const [sourceCopyBox, translationBox] = await Promise.all([
    sourceCopyButton.boundingBox(),
    translationPanel.boundingBox()
  ]);
  expect(sourceCopyBox).not.toBeNull();
  expect(translationBox).not.toBeNull();
  expect(sourceCopyBox!.x + sourceCopyBox!.width).toBeLessThanOrEqual(translationBox!.x);
  await page.getByLabel("Show LaTeX").first().click();
  await expect(page.getByRole("dialog", { name: "Source inspector" })).toBeVisible();
  await expect(page.getByText("A parsed paragraph from source LaTeX.")).toBeVisible();
  await page.getByLabel("Close source inspector").click();
  await page.getByLabel("Reading mode").click();
  await page.getByRole("button", { name: "Source" }).click();
  await expect(page.getByText("Translation pending.")).toHaveCount(0);
  await page.getByLabel("Open task drawer").click();
  await expect(page.getByText("Background tasks")).toBeVisible();

  await page.goto("/settings");
  await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
});

test("keeps long reader pages bounded while searching and scrolling", async ({ page }) => {
  await mockLongArticleApi(page);
  await page.goto("/articles/revision-long?libraryId=library-smoke");
  await expect(page.getByRole("heading", { name: "A Long Performance Paper" })).toBeVisible();
  await expect(page.getByTestId("reader-block-list")).toHaveAttribute(
    "data-virtualization",
    "progressive"
  );

  const nodeCount = await page.locator("*").count();
  const buttonCount = await page.getByRole("button").count();
  expect(nodeCount).toBeLessThan(4_600);
  expect(buttonCount).toBeLessThan(250);

  await page.getByLabel("Search paper").fill("far performance needle");
  await expect(page.getByText("1/1 matches")).toBeVisible();
  await expect(
    page.getByText("This far-off paragraph contains a far performance needle.")
  ).toBeVisible();
  await page.mouse.wheel(0, 5000);
  await expect
    .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 2))
    .toBe(true);
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

async function mockLongArticleApi(page: Page) {
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
    if (pathname.endsWith("/articles/revision-long/document")) {
      return fulfillJson(route, longSmokeDocument());
    }
    if (pathname.endsWith("/articles/revision-long/translations")) {
      return fulfillJson(route, {
        article_revision_id: "revision-long",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        variants: []
      });
    }
    if (pathname.endsWith("/articles/revision-long/glossary")) {
      return fulfillJson(route, {
        article_revision_id: "revision-long",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        active_version: "glossary:none",
        affected_block_uids: [],
        terms: []
      });
    }
    if (pathname.endsWith("/articles/revision-long/chat")) {
      return fulfillJson(route, { article_revision_id: "revision-long", messages: [] });
    }
    if (pathname.endsWith("/articles/revision-long/notes/templates")) {
      return fulfillJson(route, [
        {
          id: "deep_reading",
          name: "精读模板",
          description: "Long smoke note template."
        }
      ]);
    }
    if (pathname.endsWith("/articles/revision-long/notes/patches")) {
      return fulfillJson(route, { article_revision_id: "revision-long", patches: [] });
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

function longSmokeDocument() {
  return {
    article_revision: {
      id: "revision-long",
      family_id: "family-long",
      version: "v1",
      bundle_path: "/tmp/library/articles/arxiv/2401.99999/v1",
      status: "parsed",
      manifest_version: 1,
      metadata: {},
      created_at: timestamp,
      updated_at: timestamp
    },
    manifest: {
      schema_version: 1,
      article_revision_id: "revision-long",
      arxiv_id: "2401.99999v1",
      source: "arxiv",
      arxiv_metadata: { title: "A Long Performance Paper" },
      parse_status: "parsed",
      errors: [],
      metadata: {}
    },
    blocks: Array.from({ length: 300 }, (_, index) => {
      if (index % 50 === 0) {
        return {
          id: `block-sec-${index}`,
          article_revision_id: "revision-long",
          block_uid: `sec-${String(index).padStart(4, "0")}`,
          structural_path: String(index).padStart(5, "0"),
          block_type: "section",
          parent_uid: null,
          content_hash: `hash-sec-${index}`,
          context_hash: null,
          source_markdown: `Section ${index / 50 + 1}`,
          source_latex: null,
          metadata: { level: 1 },
          created_at: timestamp,
          updated_at: timestamp
        };
      }
      return {
        id: `block-p-${index}`,
        article_revision_id: "revision-long",
        block_uid: `p-${String(index).padStart(4, "0")}`,
        structural_path: String(index).padStart(5, "0"),
        block_type: "paragraph",
        parent_uid: null,
        content_hash: `hash-p-${index}`,
        context_hash: null,
        source_markdown:
          index === 251
            ? "This far-off paragraph contains a far performance needle."
            : `Performance paragraph ${index} with enough article-like text to exercise scrolling.`,
        source_latex: null,
        metadata: {},
        created_at: timestamp,
        updated_at: timestamp
      };
    }),
    assets: []
  };
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
