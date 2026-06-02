import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page, type Route } from "@playwright/test";

const timestamp = "2026-04-30T00:00:00.000Z";

test.describe("accessibility hardening", () => {
  test("keeps library and settings free of critical axe violations", async ({ page }) => {
    await mockAccessibilityApi(page);

    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Library", exact: true })).toBeVisible();
    await expectNoAxeViolations(page, "library home");

    await page.goto("/settings");
    await expect(page.getByRole("heading", { name: "Settings", exact: true })).toBeVisible();
    await expectNoAxeViolations(page, "settings");
  });

  test("keeps the desktop reader shell free of critical axe violations", async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem(
        "iiios-reader-feature-preferences",
        JSON.stringify({ bottomProgressVisible: true, termCardsEnabled: true })
      );
    });
    await mockAccessibilityApi(page);

    await page.goto("/articles/revision-a11y?libraryId=library-a11y");
    await expect(page.getByRole("region", { name: "An Accessible Reader Paper" })).toBeVisible();
    await expect(page.locator(".reader-card-tag")).toBeVisible();
    await expectNoAxeViolations(page, "desktop reader");
  });

  test.describe("mobile reader accessibility", () => {
    test.use({
      hasTouch: true,
      isMobile: true,
      viewport: { width: 390, height: 844 }
    });

    test("keeps mobile reader controls free of critical axe violations", async ({ page }) => {
      await page.addInitScript(() => {
        localStorage.setItem(
          "iiios-reader-feature-preferences",
          JSON.stringify({ bottomProgressVisible: true, termCardsEnabled: true })
        );
      });
      await mockAccessibilityApi(page);

      await page.goto("/articles/revision-a11y?libraryId=library-a11y");
      await expect(page.getByRole("region", { name: "An Accessible Reader Paper" })).toBeVisible();
      await expect(page.locator(".reader-card-tag")).toBeVisible();
      await page.getByRole("button", { name: "Reader workspace", exact: true }).click();
      await expect(page.locator(".reader-workspace-panel")).toBeVisible();
      await expectNoAxeViolations(page, "mobile reader");
    });
  });
});

async function expectNoAxeViolations(page: Page, label: string) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  const violations = results.violations.map((violation) => ({
    id: violation.id,
    impact: violation.impact,
    description: violation.description,
    nodes: violation.nodes.map((node) => ({
      target: node.target,
      summary: node.failureSummary
    }))
  }));
  expect(violations, `${label} accessibility violations`).toEqual([]);
}

async function mockAccessibilityApi(page: Page) {
  await page.route("http://127.0.0.1:8000/**", async (route) => {
    const url = new URL(route.request().url());
    const pathname = url.pathname;

    if (pathname === "/providers/presets") {
      return fulfillJson(route, [
        {
          id: "openai-compatible",
          name: "OpenAI Compatible",
          protocol: "openai-compatible",
          base_url: "https://api.example.com/v1",
          default_model: "a11y-model",
          requests_per_minute: null,
          max_concurrent_requests: 1,
          capabilities: {}
        }
      ]);
    }
    if (pathname === "/providers") {
      return fulfillJson(route, [providerProfile()]);
    }
    if (pathname === "/doctor") {
      return fulfillJson(route, { bilin_home: "/tmp/bilin", capabilities: [] });
    }
    if (pathname === "/jobs") {
      return fulfillJson(route, []);
    }
    if (pathname === "/jobs/summary") {
      return fulfillJson(route, { active: 0, queued: 0, failed: 0, completed: 0 });
    }
    if (pathname === "/translation-memory") {
      return fulfillJson(route, { entries: [] });
    }
    if (pathname === "/libraries") {
      return fulfillJson(route, [library()]);
    }
    if (pathname === "/libraries/library-a11y") {
      return fulfillJson(route, library());
    }
    if (pathname === "/libraries/library-a11y/articles") {
      return fulfillJson(route, [articleListItem()]);
    }
    if (pathname.endsWith("/articles/revision-a11y/document")) {
      return fulfillJson(route, articleDocument());
    }
    if (pathname.endsWith("/articles/revision-a11y/translations")) {
      const targetLanguage = url.searchParams.get("target_language") ?? "zh-CN";
      return fulfillJson(route, {
        article_revision_id: "revision-a11y",
        target_language: targetLanguage,
        variants: [
          {
            id: "translation-a11y",
            block_id: "block-p-a11y",
            target_language: targetLanguage,
            provider_profile_id: "provider-a11y",
            model: "a11y-model",
            raw_markdown: "Accessible translated paragraph.",
            render_ast: null,
            validation_status: "ok",
            glossary_version: null,
            is_default: true,
            metadata: { block_uid: "p-a11y" },
            created_at: timestamp,
            updated_at: timestamp
          }
        ]
      });
    }
    if (pathname.endsWith("/articles/revision-a11y/glossary")) {
      return fulfillJson(route, {
        article_revision_id: "revision-a11y",
        target_language: url.searchParams.get("target_language") ?? "zh-CN",
        active_version: "glossary:none",
        affected_block_uids: [],
        terms: []
      });
    }
    if (pathname.endsWith("/articles/revision-a11y/cards")) {
      return fulfillJson(route, readerCards(url.searchParams.get("target_language") ?? "zh-CN"));
    }
    if (pathname.endsWith("/articles/revision-a11y/chat")) {
      return fulfillJson(route, { article_revision_id: "revision-a11y", messages: [] });
    }
    if (pathname.endsWith("/articles/revision-a11y/notes/templates")) {
      return fulfillJson(route, [
        {
          id: "deep_reading",
          name: "Deep reading",
          description: "Accessibility note template."
        }
      ]);
    }
    if (pathname.endsWith("/articles/revision-a11y/notes/patches")) {
      return fulfillJson(route, { article_revision_id: "revision-a11y", patches: [] });
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

function providerProfile() {
  return {
    id: "provider-a11y",
    name: "Accessibility Provider",
    protocol: "openai-compatible",
    base_url: "https://api.example.com/v1",
    key_ref: "app_settings:provider_api_key:provider-a11y",
    default_model: "a11y-model",
    max_concurrent_requests: 1,
    requests_per_minute: null,
    capabilities: {},
    created_at: timestamp,
    updated_at: timestamp
  };
}

function library() {
  return {
    id: "library-a11y",
    name: "Accessibility Papers",
    path: "/tmp/a11y-library",
    status: "active",
    metadata: {},
    created_at: timestamp,
    updated_at: timestamp
  };
}

function articleListItem() {
  return {
    article_revision: {
      id: "revision-a11y",
      family_id: "family-a11y",
      version: "v1",
      bundle_path: "/tmp/a11y-library/articles/arxiv/2501.00001/v1",
      status: "parsed",
      manifest_version: 1,
      metadata: {},
      created_at: timestamp,
      updated_at: timestamp
    },
    family: {
      id: "family-a11y",
      library_id: "library-a11y",
      source: "arxiv",
      external_id: "2501.00001",
      title: "An Accessible Reader Paper",
      metadata: {},
      created_at: timestamp,
      updated_at: timestamp
    },
    manifest: {
      schema_version: 1,
      article_revision_id: "revision-a11y",
      arxiv_id: "2501.00001v1",
      source: "arxiv",
      arxiv_metadata: { title: "An Accessible Reader Paper" },
      parse_status: "parsed",
      errors: [],
      metadata: {}
    },
    block_count: 2,
    asset_count: 0,
    translation_status: {
      target_language: "zh-CN",
      status: "translated",
      translatable_blocks: 1,
      translated_blocks: 1,
      queued_jobs: 0,
      running_jobs: 0,
      paused_jobs: 0,
      failed_jobs: 0
    },
    reading_progress: {
      article_revision_id: "revision-a11y",
      active_block_uid: "p-a11y",
      active_segment_index: 1,
      segment_count: 2,
      total_seconds: 120,
      segments: [20, 100],
      updated_at: timestamp
    }
  };
}

function articleDocument() {
  return {
    article_revision: articleListItem().article_revision,
    manifest: articleListItem().manifest,
    blocks: [
      {
        id: "block-sec-a11y",
        article_revision_id: "revision-a11y",
        block_uid: "sec-a11y",
        structural_path: "00001",
        block_type: "section",
        parent_uid: null,
        content_hash: "hash-sec-a11y",
        context_hash: null,
        source_markdown: "Introduction",
        source_latex: null,
        metadata: { level: 1 },
        created_at: timestamp,
        updated_at: timestamp
      },
      {
        id: "block-p-a11y",
        article_revision_id: "revision-a11y",
        block_uid: "p-a11y",
        structural_path: "00002",
        block_type: "paragraph",
        parent_uid: null,
        content_hash: "hash-p-a11y",
        context_hash: null,
        source_markdown: "PQC readers need keyboard and screen-reader access to every tool.",
        source_latex: null,
        metadata: {},
        created_at: timestamp,
        updated_at: timestamp
      }
    ],
    assets: []
  };
}

function readerCards(targetLanguage: string) {
  return {
    article_revision_id: "revision-a11y",
    target_language: targetLanguage,
    cards: [
      {
        id: "card-pqc-a11y",
        article_revision_id: "revision-a11y",
        card_type: "term",
        anchor_block_uid: "p-a11y",
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
