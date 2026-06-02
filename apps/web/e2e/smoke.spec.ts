import { expect, test, type Page, type Route } from "@playwright/test";

const timestamp = "2026-04-30T00:00:00.000Z";

test("opens the reader shell", async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem(
      "iiios-reader-feature-preferences",
      JSON.stringify({ bottomProgressVisible: true })
    );
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Library", exact: true })).toBeVisible();

  await page.goto("/libraries/smoke-library");
  await expect(page.getByRole("heading", { name: "Add article" })).toBeVisible();
  await page.getByLabel("arXiv ID").fill("2401.00001");
  await expect(page.getByRole("button", { name: "Add article" })).toBeEnabled();

  await mockArticleApi(page);
  await page.goto("/articles/revision-smoke?libraryId=library-smoke");
  await expect(page.getByRole("region", { name: "A Playwright Parsed Paper" })).toBeVisible();
  await expect(page.getByRole("complementary", { name: "Chapters" })).toBeVisible();
  await expect(page.getByRole("complementary", { name: "Reader workspace" })).toBeVisible();
  await expectReaderFrameBounded(page);
  await expect(page.locator(".reader-workspace-tab")).toHaveCount(3);
  await expect(page.locator(".reader-workspace-tab", { hasText: "Translate" })).toHaveCount(0);
  await page.getByRole("button", { name: "Assist", exact: true }).click();
  await expect(page.locator(".reader-workspace-tab", { hasText: "Translate" })).toHaveAttribute(
    "data-tone",
    "teal"
  );
  await expect(page.locator(".reader-workspace-tab", { hasText: "Terms" })).toHaveAttribute(
    "data-tone",
    "amber"
  );
  await page.getByRole("button", { name: "Output", exact: true }).click();
  await expect(page.locator(".reader-workspace-tab", { hasText: "Export" })).toHaveAttribute(
    "data-tone",
    "blue"
  );
  await expectWorkspaceMotionHooks(page);
  await page.getByRole("button", { name: "Assist", exact: true }).click();
  await page.locator(".reader-workspace-tab", { hasText: "Terms" }).click();
  await expect(page.locator(".reader-glossary-panel")).toBeVisible();
  await expectNoHorizontalOverflow(page);
  await expectWorkspacePanelBounded(page);
  await page.getByRole("button", { name: "Output", exact: true }).click();
  await page.locator(".reader-workspace-tab", { hasText: "Export" }).click();
  await expect(page.locator(".reader-export-panel")).toBeVisible();
  await expectNoHorizontalOverflow(page);
  await expectWorkspacePanelBounded(page);
  await page.getByRole("button", { name: "Library" }).click();
  await expect(page.getByRole("dialog", { name: "Library papers" })).toBeVisible();
  await page.getByRole("button", { name: /A Switchable Library Paper/ }).click();
  await expect(page).toHaveURL(/revision-alt/);
  await expect(page.getByRole("region", { name: "A Switchable Library Paper" })).toBeVisible();
  await page.getByRole("button", { name: "Library" }).click();
  await expect(page.getByRole("dialog", { name: "Library papers" })).toBeVisible();
  await page.getByRole("button", { name: /A Playwright Parsed Paper/ }).click();
  await expect(page).toHaveURL(/revision-smoke/);
  await page.getByRole("button", { name: "Assist", exact: true }).click();
  await expect(page.locator(".reader-workspace-tab", { hasText: "Tasks" })).toBeVisible();
  await page.getByRole("button", { name: "Read", exact: true }).click();
  await page.locator(".reader-workspace-tab", { hasText: "Full paper Q&A" }).click();
  await expect(page.locator(".reader-chat-panel")).toBeVisible();
  await expectWorkspacePanelBounded(page);
  await page.getByRole("textbox", { name: "Question" }).fill("What is the main point?");
  await expect(page.getByRole("button", { name: "Ask paper" })).toBeEnabled();
  await expect(page.getByText("A parsed paragraph from the mocked article API.")).toBeVisible();
  await expect(page.getByText("来自 mocked article API 的译文。")).toHaveCount(0);
  await page.getByRole("button", { name: "Show translation" }).click();
  await expect(page.getByText("来自 mocked article API 的译文。")).toBeVisible();
  await expect(page.locator(".reader-bottom-status")).toBeVisible();
  await expect(page.locator(".reader-progress-milestone-label")).toHaveText("Paper complete");
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
  await page.getByRole("button", { name: "Assist", exact: true }).click();
  await page.locator(".reader-workspace-tab", { hasText: "Tasks" }).click();
  await expectWorkspacePanelBounded(page);
  await expect(page.getByRole("button", { name: "Manage tasks" })).toBeVisible();

  await page.goto("/settings");
  await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
  await expectNoHorizontalOverflow(page);
});

test("keeps long reader pages bounded while scrolling", async ({ page }) => {
  await mockLongArticleApi(page);
  await page.goto("/articles/revision-long?libraryId=library-smoke");
  await expect(page.getByRole("region", { name: "A Long Performance Paper" })).toBeVisible();
  await expect(page.getByTestId("reader-block-list")).toHaveAttribute(
    "data-virtualization",
    "progressive"
  );

  const nodeCount = await page.locator("*").count();
  const buttonCount = await page.getByRole("button").count();
  expect(nodeCount).toBeLessThan(4_600);
  expect(buttonCount).toBeLessThan(250);

  await expect(page.getByLabel("Search paper")).toBeVisible();
  await page.mouse.wheel(0, 5000);
  await expectNoHorizontalOverflow(page);
  await expectReaderFrameBounded(page, { checkTop: false });
  const postScrollMetrics = await page.evaluate(() => ({
    nodeCount: document.querySelectorAll("*").length,
    renderedBlocks: document.querySelectorAll("[data-reader-block-rendered='true']").length,
    placeholders: document.querySelectorAll("[data-reader-block-placeholder='true']").length
  }));
  expect(postScrollMetrics.nodeCount).toBeLessThan(4_600);
  expect(postScrollMetrics.renderedBlocks).toBeLessThan(60);
  expect(postScrollMetrics.placeholders).toBeGreaterThan(20);
  expect(postScrollMetrics.placeholders).toBeLessThan(90);
});

test.describe("mobile reader adaptation", () => {
  test.use({
    hasTouch: true,
    isMobile: true,
    viewport: { width: 390, height: 844 }
  });

  test("keeps core reader controls touchable on mobile", async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem(
        "iiios-reader-feature-preferences",
        JSON.stringify({ bottomProgressVisible: true, termCardsEnabled: true })
      );
    });
    await mockArticleApi(page);
    await page.goto("/articles/revision-smoke?libraryId=library-smoke");
    await expect(page.getByRole("region", { name: "A Playwright Parsed Paper" })).toBeVisible();
    await expect(page.locator(".reader-card-tag")).toBeVisible();
    await expect(page.locator(".reader-card-tag-delete")).toBeVisible();

    const metrics = await page.evaluate(() => {
      const isVisible = (element: Element) => {
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return (
          style.display !== "none" &&
          style.visibility !== "hidden" &&
          Number(style.opacity) > 0.01 &&
          rect.width > 0 &&
          rect.height > 0
        );
      };
      const targets = [
        ...document.querySelectorAll(
          [
            ".reader-command-center button",
            ".reader-chapter-rail-tab",
            ".reader-study-rail-spine",
            ".study-translation-toggle",
            ".reader-workspace-tab",
            ".reader-card-tag",
            ".reader-card-tag-delete"
          ].join(", ")
        )
      ]
        .filter(isVisible)
        .map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            label:
              element.getAttribute("aria-label") ||
              element.getAttribute("title") ||
              element.textContent?.trim() ||
              element.className.toString(),
            className: element.className.toString(),
            readerCardControl: element.matches(".reader-card-tag, .reader-card-tag-delete"),
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          };
        });
      return {
        coarsePointer: matchMedia("(pointer: coarse)").matches,
        overflowX: document.documentElement.scrollWidth - window.innerWidth,
        viewportWidth: window.innerWidth,
        paper: (() => {
          const rect = document.querySelector(".reader-paper-shell")?.getBoundingClientRect();
          return rect
            ? {
                left: Math.round(rect.left),
                right: Math.round(rect.right),
                width: Math.round(rect.width)
              }
            : null;
        })(),
        collapsedRails: [
          ...document.querySelectorAll(
            ".reader-chapter-rail-collapsed, .reader-right-rail.reader-side-rail-collapsed"
          )
        ].map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            width: Math.round(rect.width),
            top: Math.round(rect.top),
            bottom: Math.round(rect.bottom)
          };
        }),
        readerCardTargetCount: targets.filter((target) => target.readerCardControl).length,
        smallTargets: targets.filter((target) => target.width < 44 || target.height < 44)
      };
    });

    expect(metrics.coarsePointer).toBe(true);
    expect(metrics.overflowX).toBeLessThanOrEqual(2);
    expect(metrics.paper?.left).toBeGreaterThanOrEqual(0);
    expect(metrics.paper?.right).toBeLessThanOrEqual(metrics.viewportWidth + 2);
    expect(metrics.paper?.width).toBeGreaterThanOrEqual(metrics.viewportWidth - 4);
    for (const rail of metrics.collapsedRails) {
      expect(rail.width).toBeLessThanOrEqual(132);
      expect(rail.top).toBeGreaterThan(640);
    }
    expect(metrics.readerCardTargetCount).toBeGreaterThanOrEqual(2);
    expect(metrics.smallTargets).toEqual([]);

    await page.getByRole("button", { name: "Reader workspace", exact: true }).click();
    await expect(page.locator(".reader-workspace-panel")).toBeVisible();
    const workspaceSheet = await page.evaluate(() => {
      const rect = document.querySelector(".reader-right-rail")?.getBoundingClientRect();
      return rect
        ? {
            left: Math.round(rect.left),
            right: Math.round(rect.right),
            bottom: Math.round(rect.bottom),
            width: Math.round(rect.width),
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight
          }
        : null;
    });
    expect(workspaceSheet?.left).toBeLessThanOrEqual(10);
    expect(workspaceSheet?.right).toBeGreaterThanOrEqual((workspaceSheet?.viewportWidth ?? 0) - 10);
    expect(workspaceSheet?.width).toBeGreaterThanOrEqual((workspaceSheet?.viewportWidth ?? 0) - 20);
    expect(workspaceSheet?.bottom).toBeLessThanOrEqual((workspaceSheet?.viewportHeight ?? 0) - 56);
  });
});

async function expectNoHorizontalOverflow(page: Page) {
  await expect
    .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 2))
    .toBe(true);
}

async function expectReaderFrameBounded(page: Page, options: { checkTop?: boolean } = {}) {
  const { checkTop = true } = options;
  const metrics = await page.evaluate(() => {
    const paper = document.querySelector(".reader-paper-shell")?.getBoundingClientRect();
    const chrome = document.querySelector(".reader-command-center")?.getBoundingClientRect();
    return {
      viewportWidth: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      paperLeft: paper?.left ?? -1,
      paperRight: paper?.right ?? Number.POSITIVE_INFINITY,
      paperTop: paper?.top ?? -1,
      chromeBottom: chrome?.bottom ?? 0
    };
  });
  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 2);
  expect(metrics.paperLeft).toBeGreaterThanOrEqual(0);
  expect(metrics.paperRight).toBeLessThanOrEqual(metrics.viewportWidth + 2);
  if (checkTop) {
    expect(metrics.paperTop).toBeGreaterThanOrEqual(metrics.chromeBottom - 1);
  }
}

async function expectWorkspacePanelBounded(page: Page) {
  const metrics = await page.evaluate(() => {
    const rail = document.querySelector(".reader-right-rail")?.getBoundingClientRect();
    const panel = document.querySelector(".reader-workspace-panel")?.getBoundingClientRect();
    return {
      railLeft: rail?.left ?? 0,
      railRight: rail?.right ?? 0,
      panelLeft: panel?.left ?? Number.POSITIVE_INFINITY,
      panelRight: panel?.right ?? Number.NEGATIVE_INFINITY
    };
  });
  expect(metrics.panelLeft).toBeGreaterThanOrEqual(metrics.railLeft - 1);
  expect(metrics.panelRight).toBeLessThanOrEqual(metrics.railRight + 1);
}

async function expectWorkspaceMotionHooks(page: Page) {
  const motion = await page.evaluate(() => {
    const tab = document.querySelector(".reader-workspace-tab");
    const panelContent = document.querySelector(
      ".reader-workspace-body > .panel, .reader-workspace-body > .mantine-Stack-root"
    );
    const tabStyle = tab ? getComputedStyle(tab) : null;
    const panelStyle = panelContent ? getComputedStyle(panelContent) : null;
    return {
      tabTransitionDuration: tabStyle?.transitionDuration ?? "",
      panelAnimationName: panelStyle?.animationName ?? ""
    };
  });
  expect(motion.tabTransitionDuration).not.toBe("0s");
  expect(motion.panelAnimationName).toContain("reader-workspace-panel-in");
}

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
    if (pathname === "/libraries/library-smoke") {
      return fulfillJson(route, smokeLibrary());
    }
    if (pathname === "/libraries/library-smoke/articles") {
      return fulfillJson(route, [
        smokeArticleListItem(
          "revision-smoke",
          "family-smoke",
          "A Playwright Parsed Paper",
          "2401.00001"
        ),
        smokeArticleListItem(
          "revision-alt",
          "family-alt",
          "A Switchable Library Paper",
          "2401.00002"
        )
      ]);
    }
    if (pathname.endsWith("/articles/revision-smoke/document")) {
      return fulfillJson(route, smokeDocument());
    }
    if (pathname.endsWith("/articles/revision-alt/document")) {
      return fulfillJson(
        route,
        smokeDocument("revision-alt", "family-alt", "A Switchable Library Paper", "2401.00002v1")
      );
    }
    if (pathname.endsWith("/articles/revision-smoke/translations")) {
      const targetLanguage = url.searchParams.get("target_language") ?? "zh-CN";
      return fulfillJson(route, {
        article_revision_id: "revision-smoke",
        target_language: targetLanguage,
        variants: [
          {
            id: "translation-smoke",
            block_id: "block-p-smoke",
            target_language: targetLanguage,
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
    if (pathname.endsWith("/articles/revision-alt/translations")) {
      return fulfillJson(route, {
        article_revision_id: "revision-alt",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        variants: []
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
    if (pathname.endsWith("/articles/revision-alt/glossary")) {
      return fulfillJson(route, {
        article_revision_id: "revision-alt",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        active_version: "glossary:none",
        affected_block_uids: [],
        terms: []
      });
    }
    if (pathname.endsWith("/articles/revision-smoke/cards")) {
      const targetLanguage = url.searchParams.get("target_language") ?? "zh-CN";
      return fulfillJson(route, smokeReaderCards("revision-smoke", targetLanguage));
    }
    if (pathname.endsWith("/articles/revision-alt/cards")) {
      return fulfillJson(route, {
        article_revision_id: "revision-alt",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        cards: []
      });
    }
    if (pathname.endsWith("/articles/revision-smoke/chat")) {
      return fulfillJson(route, { article_revision_id: "revision-smoke", messages: [] });
    }
    if (pathname.endsWith("/articles/revision-alt/chat")) {
      return fulfillJson(route, { article_revision_id: "revision-alt", messages: [] });
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
    if (pathname.endsWith("/articles/revision-alt/notes/templates")) {
      return fulfillJson(route, [
        {
          id: "deep_reading",
          name: "精读模板",
          description: "Switch note template."
        }
      ]);
    }
    if (pathname.endsWith("/articles/revision-smoke/notes/patches")) {
      return fulfillJson(route, { article_revision_id: "revision-smoke", patches: [] });
    }
    if (pathname.endsWith("/articles/revision-alt/notes/patches")) {
      return fulfillJson(route, { article_revision_id: "revision-alt", patches: [] });
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
    if (pathname === "/libraries/library-smoke") {
      return fulfillJson(route, smokeLibrary());
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

function smokeLibrary() {
  return {
    id: "library-smoke",
    name: "Papers",
    path: "/tmp/library",
    status: "active",
    metadata: {},
    created_at: timestamp,
    updated_at: timestamp
  };
}

function smokeReaderCards(articleRevisionId: string, targetLanguage: string) {
  return {
    article_revision_id: articleRevisionId,
    target_language: targetLanguage,
    cards: [
      {
        id: "card-pqc-smoke",
        article_revision_id: articleRevisionId,
        card_type: "term",
        anchor_block_uid: "p-smoke",
        anchor_text: "PQC",
        canonical_key: "term:pqc",
        abbreviation: "PQC",
        full_form: "Parametrized Quantum Circuit",
        title: "PQC",
        body_markdown: "A parametrized quantum circuit used in variational quantum algorithms.",
        target_language: targetLanguage,
        source_type: "paper_local",
        source_url: null,
        position: "right",
        status: "candidate",
        metadata: {},
        created_at: timestamp,
        updated_at: timestamp
      }
    ]
  };
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

function smokeArticleListItem(
  revisionId: string,
  familyId: string,
  title: string,
  externalId: string
) {
  return {
    article_revision: {
      id: revisionId,
      family_id: familyId,
      version: "v1",
      bundle_path: `/tmp/library/articles/arxiv/${externalId}/v1`,
      status: "parsed",
      manifest_version: 1,
      metadata: {},
      created_at: timestamp,
      updated_at: timestamp
    },
    family: {
      id: familyId,
      library_id: "library-smoke",
      source: "arxiv",
      external_id: externalId,
      title,
      metadata: {},
      created_at: timestamp,
      updated_at: timestamp
    },
    manifest: {
      schema_version: 1,
      article_revision_id: revisionId,
      arxiv_id: `${externalId}v1`,
      source: "arxiv",
      arxiv_metadata: { title },
      parse_status: "parsed",
      errors: [],
      metadata: {}
    },
    block_count: 2,
    asset_count: 0,
    translation_status: {
      target_language: "zh-CN",
      status: revisionId === "revision-smoke" ? "translated" : "not_started",
      translatable_blocks: 1,
      translated_blocks: revisionId === "revision-smoke" ? 1 : 0,
      queued_jobs: 0,
      running_jobs: 0,
      paused_jobs: 0,
      failed_jobs: 0
    },
    reading_progress: {
      article_revision_id: revisionId,
      active_block_uid: "p-smoke",
      active_segment_index: revisionId === "revision-smoke" ? 1 : 0,
      segment_count: 2,
      total_seconds: revisionId === "revision-smoke" ? 180 : 0,
      segments: revisionId === "revision-smoke" ? [20, 160] : [0, 0],
      updated_at: timestamp
    }
  };
}

function smokeDocument(
  revisionId = "revision-smoke",
  familyId = "family-smoke",
  title = "A Playwright Parsed Paper",
  arxivId = "2401.00001v1"
) {
  return {
    article_revision: {
      id: revisionId,
      family_id: familyId,
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
      article_revision_id: revisionId,
      arxiv_id: arxivId,
      source: "arxiv",
      arxiv_metadata: { title },
      parse_status: "parsed",
      errors: [],
      metadata: {}
    },
    blocks: [
      {
        id: "block-sec-smoke",
        article_revision_id: revisionId,
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
        article_revision_id: revisionId,
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
