# Research Workbench Implementation Dispatch

This document turns the updated product and design direction into executable
work packages. It does not replace `docs/mvp-plan.md` or
`docs/macos-app-task-breakdown.md`. Those documents still describe the TeX
reader and native macOS foundation. This dispatch describes the next product
layer: reading to Obsidian Markdown notes, then to Typst or TeX writing, with
Agent assistance gated by explicit action plans.

## Core Decision

The next build should not start with a chat-like Agent surface. That would put
the assistant at the center while the file and permission contracts remain weak.
The implementation should start with durable local contracts, then confirmed
side-effect execution, then reader-adjacent UI.

The order is strict. `AgentActionPlan` must exist in backend execution paths
before UI drawers claim that writes, downloads, imports, or skill installs are
confirmed. `NoteBridge` and `WritingProject` must model external file ownership
before macOS or web views write Markdown, Typst, or TeX files. `ResearchSkill`
must be discoverable and auditable before the app can execute any skill script.

## Current Baseline

The repo already has a strong structured reader base. The canonical artifact is
the article bundle with `manifest.json`, `document.json`, `source.md`, assets,
logs, exports, and SQLite rows. Web behavior already covers arXiv import,
LaTeXML parsing, reader blocks, translation variants, article QA, reader cards,
Obsidian clips, lecture-note patches, and Markdown exports.

The macOS app is a native SwiftUI prototype, not a WebView shell. It can open a
local Bilin library, read articles, blocks, `zh-CN` translations, reading
progress, and note patches from SQLite, inspect Zotero metadata read-only, and
render equations through the RaTeX CLI adapter boundary. The missing layer is
the new workbench contract: `ReadingOutline`, `NoteBridge`, `WritingProject`,
`ResearchSkill`, and `AgentActionPlan`.

The weak point is not parsing. The weak point is the claim that reading artifacts
can flow into user-owned Obsidian, Typst, and TeX files under confirmed Agent
control. Today, Obsidian and exports still have direct write paths, while Typst
and TeX writing projects are mostly product contracts.

## Non-Negotiable Constraints

- External files remain user-owned. Bilin stores indexes, anchors, pending
  patches, provenance, and action state.
- Obsidian Markdown is v1's first external note target. Typora compatibility
  comes from opening the same Markdown file.
- Typst and TeX are linked writing projects. V1 supports root selection, main
  file detection, bibliography detection, patch preview, patch acceptance, and
  provenance. It does not promise complex bidirectional sync.
- Any action that writes files, downloads papers, imports a library, installs or
  enables a skill, runs external tools, calls providers, or edits manuscripts
  must be represented as an `AgentActionPlan` before execution.
- Local skill discovery may run automatically. Remote skill download, skill
  enablement, and any high-risk permission grant require confirmation.
- Legacy Codex skills without permission manifests are metadata-only until the
  user grants coarse permissions. V1 should not execute arbitrary skill scripts.

## Phase Plan

| Phase | Goal | Blocking Rule |
| --- | --- | --- |
| 0 | Align docs and stale facts | Do not claim Typst/TeX writing is implemented until tests exist. |
| 1 | Add backend `ResearchSkill`, `ResearchPlan`, and `AgentActionPlan` storage | No side-effect endpoint should be gated only in the frontend. |
| 2 | Add ActionPlan API, worker execution, and job observability | Action payloads are immutable after approval. |
| 3 | Gate existing backend side effects | Pending action plans must not create files, exports, imports, or jobs. |
| 4 | Add external file bridge persistence | Do not reuse `note_patches` for user-owned Obsidian files. |
| 5 | Add macOS `BilinWorkspaceKit` and right rail modes | Keep contracts Foundation-only before wiring SwiftUI. |
| 6 | Build NoteBridge vertical slice | Preview first, accept or reject second, write only after drift checks. |
| 7 | Build Research Plan and Skill Registry UI | Plans propose work; accepted plans create jobs or patches. |
| 8 | Build Writing Dock prototype | Insert patches into Typst or TeX only after explicit acceptance. |

## Backend Dispatch

These backend packages are not all parallel. `B-01`, `B-02`, and `B-03` touch
shared schema and migration surfaces, so they should land serially. Once the
ActionPlan state machine and API are stable, side-effect gates can be split
across workers.

| ID | Package | Owner Files | Depends On | Acceptance | Verification |
| --- | --- | --- | --- | --- | --- |
| B-01 | Durable ResearchSkill catalog | `apps/api/src/bilin_api/migrations/global/006_research_skills.sql`, `schemas.py`, `repositories.py`, new `research_skill_service.py` | None | Skills persist with slug, title, description, digest, source path, cache path, status, permissions, input/output shape, supported tasks, and audit timestamps. Local `.agents/skills/*/SKILL.md` and `~/.codex/skills/*/SKILL.md` can be indexed idempotently. | `rtk uv run --project apps/api pytest apps/api/tests/test_research_skills.py -q` |
| B-02 | ResearchPlan and ActionPlan tables | `apps/api/src/bilin_api/migrations/global/006_research_skills.sql` if global plans are chosen, `apps/api/src/bilin_api/migrations/library/007_research_plans.sql`, `schemas.py`, `tests/test_database.py` | B-01 | Libraries can store research plans, linked article revisions, candidate papers, `ReadingOutline` payloads, action plans, action steps, status history, idempotency keys, previews, results, errors, and job ids. | `rtk uv run --project apps/api pytest apps/api/tests/test_database.py apps/api/tests/test_research_plans.py -q` |
| B-03 | ActionPlan state machine | new `action_plan_service.py`, `research_plan_service.py`, `article_store.py`, `schemas.py` | B-02 | Create, list, get, approve, reject, cancel, start, succeed, and fail are transactional. Invalid transitions fail. Duplicate idempotency keys return the existing plan. Payload hashes prevent mutated approvals. | `rtk uv run --project apps/api pytest apps/api/tests/test_research_action_store.py -q` |
| B-04 | Research and action API | new `apps/api/src/bilin_api/api/research.py`, `main.py`, `schemas.py` | B-03 | Clients can create and read research plans, list action plans by article/status/kind, approve or reject actions, and see all models in OpenAPI. | `rtk uv run --project apps/api pytest apps/api/tests/test_research_api.py -q` |
| B-05 | ExecuteActionPlan worker job | `schemas.py`, `repositories.py`, `worker.py`, `api/jobs.py` | B-04 | `JobType.execute_action_plan` exists. Approval queues at most one execution job. Worker dispatch updates action and job status together. Cancellation does not execute pending side effects. | `rtk uv run --project apps/api pytest apps/api/tests/test_action_plan_worker.py apps/api/tests/test_jobs.py -q` |
| B-06 | Gate lecture-note patch acceptance | `note_service.py`, `api/articles.py`, `article_store.py` | B-05 | Accepting a note patch creates or requires an approved ActionPlan. Pending approval does not write `lecture-notes.md`. Approved execution writes once. Rejection is durable. | `rtk uv run --project apps/api pytest apps/api/tests/test_notes.py apps/api/tests/test_research_note_actions.py -q` |
| B-07 | Gate exports | `export_service.py`, `api/articles.py`, `worker.py` | B-05 | Export requests can produce a preview without creating export directories. Approved execution writes the artifact. Retries return the same artifact. `/exports` and `/exports/jobs` cannot bypass the gate. | `rtk uv run --project apps/api pytest apps/api/tests/test_export.py apps/api/tests/test_research_export_actions.py -q` |
| B-08 | Gate Obsidian writes | `obsidian_service.py`, `reader_card_service.py`, `api/articles.py` | B-05 | Clips and reader-card exports preview first. No vault file is created before approval. Approved execution writes through locking and atomic write. Duplicate approval does not duplicate anchors. | `rtk uv run --project apps/api pytest apps/api/tests/test_obsidian.py apps/api/tests/test_research_obsidian_actions.py -q` |
| B-09 | Gate citation arXiv imports | `citation_service.py`, `api/articles.py`, `repositories.py` | B-05 | Citation import stores candidates in an ActionPlan. No import job is queued before approval. Approval queues existing `import_arxiv` with `source_article_revision_id`, `source_citation_id`, and `action_plan_id`. | `rtk uv run --project apps/api pytest apps/api/tests/test_citations.py apps/api/tests/test_research_citation_actions.py -q` |
| B-10 | Link jobs and task summaries to ActionPlans | `repositories.py`, `api/jobs.py`, `schemas.py` | B-05 and one gated adapter | Job detail exposes `action_plan_id`. Action status is visible from job detail. Article task summaries include gated action progress and error state. | `rtk uv run --project apps/api pytest apps/api/tests/test_jobs.py apps/api/tests/test_action_plan_progress.py -q` |
| B-11 | OpenAPI and generated client lock | `apps/api/src/bilin_api/openapi.py`, `apps/web/openapi.json`, `apps/web/src/api/generated/schema.ts` | B-04 | Generated types include ResearchSkill, ResearchPlan, ActionPlan, action step, action status, and permission types. Schema generation is deterministic. | `rtk make generate-api-client` then `rtk git diff --exit-code apps/web/openapi.json apps/web/src/api/generated/schema.ts` |

## External File Bridge Dispatch

This stream bridges backend, web, and macOS. It is a product boundary, not only a
UI feature. Reusing the existing `note_patches` table for Obsidian would blur
article-owned lecture notes with user-owned Markdown files, so it should be
avoided.

| ID | Package | Owner Files | Depends On | Acceptance | Verification |
| --- | --- | --- | --- | --- | --- |
| F-01 | Obsidian vault records | global migration, `schemas.py`, repository/service layer | B-02 | Store selected vaults with name, root path, status, default flag, detected app, optional macOS security bookmark, and timestamps. First setup requires explicit user choice or explicit confirmation of a proposed default. | Backend repository tests plus macOS config tests |
| F-02 | NoteBridge patch records | library migration, `schemas.py`, article store/service layer | F-01 | Store target vault, target note path, heading path, block anchor, callout type, tags, source payload, translation payload, patch Markdown, base and applied file hashes, status, conflict, and provenance. | `test_note_bridge_service.py` |
| F-03 | NoteBridge preview/accept/reject service | new `note_bridge_service.py`, low-level reuse of `obsidian_service.py` locking and atomic write | F-02 and B-05 | Preview does not write. Accept re-reads target file, checks hash, locks, upserts by anchor, writes atomically, and records applied hash. Reject keeps provenance and writes nothing. | Filesystem conflict tests |
| F-04 | WritingProject records | global migration, service layer, macOS WorkspaceKit mirror | F-01 | Store project root, project kind, main manuscript, bibliography files, detected files, status, security bookmark, and timestamps. | Backend and Swift temp-directory tests |
| F-05 | Writing patch records and service | library migration, new writing bridge service | F-04 and B-05 | Store source refs, target file, target anchor or section, patch kind, format, insert text, citation keys, bibliography intent, file hashes, conflict, status, and provenance. | Typst and TeX patch tests |

## Web Dispatch

Web work should begin after B-04 and B-11 produce stable OpenAPI types. The first
web implementation should expose plans and patches without bypassing backend
confirmation.

| ID | Package | Owner Files | Depends On | Acceptance | Verification |
| --- | --- | --- | --- | --- | --- |
| W-01 | API hooks for research and action plans | `apps/web/src/api/client.ts`, `hooks.ts`, generated schema | B-11 | Hooks can list skills, research plans, action plans, and approve or reject actions. | `rtk pnpm --filter @bilin/web typecheck` |
| W-02 | ActionPlanDrawer | new component beside `TaskDrawer.tsx`, `AppLayout.tsx`, i18n | W-01 | Drawer shows steps, target files, network calls, provider calls, skill permissions, payload hash, accept, reject, and inspect controls. | Vitest component tests |
| W-03 | Replace direct Obsidian save with prepare-patch | `ReaderPage.tsx`, toolbar actions, i18n | W-02 and F-03 | Save to Obsidian prepares a NoteBridge action or patch preview. It does not call a direct write route. | Existing Obsidian tests updated to assert pending preview |
| W-04 | ResearchPlan rail | `ReaderPage.tsx`, `ui.ts`, new rail component | W-02 | Rail shows topic or seed paper, candidate papers, related clusters, per-paper `ReadingOutline`, and pending action plans. | Render tests with mocked API |
| W-05 | Skill Registry settings | `SettingsPage.tsx`, API hooks, i18n | W-01 | Shows discovered, cached, installed, enabled, and disabled skills with source, digest, permissions, input/output shape, and enable flow. | Settings tests |
| W-06 | WritingDock rail | `ReaderPage.tsx`, `ui.ts`, new rail component | F-05 and W-02 | Rail shows linked Typst/TeX project, main file, bib files, candidate citations, and pending writing patches. | Render tests for preview and no-write state |

## macOS Dispatch

The macOS stream should create a `BilinWorkspaceKit` target before adding more
state to `ReaderWorkbenchSession`. That keeps file contracts testable without
SwiftUI, AppKit, SQLite, providers, or external tools.

| ID | Package | Owner Files | Depends On | Acceptance | Verification |
| --- | --- | --- | --- | --- | --- |
| M-01 | Add BilinWorkspaceKit | `apps/macos/Package.swift`, new `Sources/BilinWorkspaceKit/WorkspaceContracts.swift`, new tests | None | Define `ReadingOutline`, `NoteBridge`, `WritingProject`, `AgentActionPlan`, `ResearchSkill`, `SourceBlockProvenance`, and `PendingFilePatch` as `Codable`, `Hashable`, `Sendable`, Foundation-only contracts. | `rtk swift test --package-path apps/macos --filter BilinWorkspaceKitTests` |
| M-02 | Reader selection provenance snapshots | new `BilinReaderKit/ReaderSelectionSnapshot.swift`, reader tests | M-01 | Convert selected block, translation, article, revision, and library into `SourceBlockProvenance` using `articleRevisionId`, `blockUid`, and `contentHash`, never list index. | `rtk swift test --package-path apps/macos --filter ReaderSelectionSnapshotTests` |
| M-03 | Workspace path configuration | new `WorkspaceConfiguration.swift`, `WorkspaceConfigurationStore.swift` | M-01 | Persist selected Bilin library, Zotero library, Obsidian vault, and writing project path records, including optional security-scoped bookmark data. Corrupt config returns structured error without dropping known-good records. | `rtk swift test --package-path apps/macos --filter WorkspaceConfigurationStoreTests` |
| M-04 | Right work rail modes | `WorkbenchView.swift`, `BilinMacApp.swift`, new `RightWorkRailView.swift` | M-01, M-02 | Replace the generic inspector with Note Bridge, Research Plan, Writing Dock, Translation, Tasks, and Providers. Switching modes preserves selected article, block, translations, notes, and progress. | `rtk swift test --package-path apps/macos`; smoke `rtk swift run --package-path apps/macos BilinMac` |
| M-05 | Obsidian vault selection | new `ObsidianVault.swift`, `ObsidianVaultPanel.swift`, Note Bridge rail | M-03, M-04 | User chooses a vault. `.obsidian` is detected. Plain Markdown roots require explicit confirmation. Selection does not create or modify Markdown files. | `rtk swift test --package-path apps/macos --filter ObsidianVaultTests` |
| M-06 | NoteBridge patch preview | new `NoteBridgePatchBuilder.swift`, `NoteBridgeRailView.swift` | M-02, M-05 | Selected block creates a pending Markdown patch with callout, tags, source payload, translation payload, target note file, heading path, anchor, and provenance. Preview writes nothing. | `rtk swift test --package-path apps/macos --filter NoteBridgePatchBuilderTests` |
| M-07 | NoteBridge accept/reject writer | new `MarkdownPatchWriter.swift`, `NoteBridgeRailView.swift` | M-06 | Accept creates or updates the selected Markdown note, records provenance, and refuses file drift. Reject clears pending state and touches no external file or SQLite note patch. | `rtk swift test --package-path apps/macos --filter MarkdownPatchWriterTests` |
| M-08 | ResearchPlan rail and preflight | new `ResearchPlan.swift`, `ResearchPlanRailView.swift` | M-04 | Rail shows seed topic or article, candidates, evidence, and `ReadingOutline`. Any download, import, install, provider call, external tool, or file write becomes an `AgentActionPlan` first. | `rtk swift test --package-path apps/macos --filter ResearchPlanTests` |
| M-09 | Writing project linker | new `WritingProjectLinker.swift`, `WritingProjectPanel.swift` | M-03, M-04 | User chooses a project root. Linker detects `.typ`, `.tex`, and `.bib` files and records project kind, root, main file, bibliography, status, and bookmark data without editing files. | `rtk swift test --package-path apps/macos --filter WritingProjectLinkerTests` |
| M-10 | WritingDock patch preview | new `WritingPatchBuilder.swift`, `WritingDockRailView.swift` | M-02, M-09 | Selected definitions, claims, equations, citations, or TODOs become pending Typst or TeX insert patches with target section, preview text, bibliography intent, and source provenance. | `rtk swift test --package-path apps/macos --filter WritingPatchBuilderTests` |
| M-11 | WritingDock accept/reject writer | new `ManuscriptPatchWriter.swift`, `WritingDockRailView.swift` | M-10 | Accept writes only to the selected manuscript file, records provenance, and detects file drift. Reject writes nothing. Typst and TeX provenance comments are both supported. | `rtk swift test --package-path apps/macos --filter ManuscriptPatchWriterTests` |

## Research Skill Dispatch

Research skills should be introduced as an auditable registry before execution.
The first useful implementation is discovery, metadata, permission review, and
action-plan proposal. Execution can wait until the permission model has enough
tests to reject overreach.

| ID | Package | Acceptance |
| --- | --- | --- |
| S-01 | Local skill discovery | Scan `.agents/skills/*/SKILL.md` and `~/.codex/skills/*/SKILL.md`, store digest, source path, name, description, capability tags, and metadata-only status. Do not execute scripts. |
| S-02 | Remote skill discovery index | Fetch only a remote index. Downloading a candidate skill creates a `download_skill` ActionPlan. |
| S-03 | Skill cache and digest validation | Accepted downloads go to `BILIN_HOME/skill-cache/...`, are hashed, parsed, and registered as cached but disabled. |
| S-04 | Permission grant flow | Enabling a skill records granted permissions such as `network`, `provider_call`, `download_paper`, `import_library`, `write_library_bundle`, `write_obsidian`, `edit_manuscript`, and `run_external_tool`. |
| S-05 | Research Plan invocation | Enabled skills may propose searches, outlines, related-paper imports, and writing patches. Any side effect still becomes an ActionPlan. |

## Verification Matrix

| Area | Command | Proves | Manual Remainder |
| --- | --- | --- | --- |
| Docs | `rtk git diff --check` and `rtk rg -n "Obsidian|Typst|TeX|AgentActionPlan|NoteBridge|WritingProject" PRODUCT.md DESIGN.md docs apps` | Markdown is clean and the new contract is findable. | README and `AGENT_GUIDE.md` still need human review for older MVP framing. |
| Backend fast gate | `rtk make test` | Runs API and web unit tests through the Makefile. | Requires `uv` on PATH. If unavailable, use the venv directly. |
| Backend direct gate | `cd apps/api && rtk .venv/bin/pytest` | Covers migrations, imports, parser, notes, Obsidian, exports, translation, QA, CORS, and network safety with mocks and fixtures. | Real provider calls, live arXiv, live LaTeXML, and real vault behavior remain opt-in. |
| Backend lint/type | `cd apps/api && rtk .venv/bin/ruff check . && rtk .venv/bin/ruff format --check . && rtk .venv/bin/basedpyright` | Python style and typing. | Developer environment must keep venv current. |
| Golden acceptance | `rtk env BILIN_HOME=/tmp/bilin-home apps/api/.venv/bin/bilin acceptance golden fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance` | Creates a disposable library, imports a golden TeX fixture, materializes reader blocks, and exports artifacts. | Does not prove Typst/TeX manuscript insertion. |
| API client sync | `rtk make generate-api-client` then `rtk git diff --exit-code apps/web/openapi.json apps/web/src/api/generated/schema.ts` | FastAPI schema and generated TypeScript agree. | This writes generated files, so run in a branch or CI step that expects diff checking. |
| Web static/unit | `rtk pnpm --filter @bilin/web lint`; `rtk pnpm --filter @bilin/web typecheck`; `rtk pnpm --filter @bilin/web test:run`; `rtk pnpm --filter @bilin/web build`; `rtk pnpm --filter @bilin/web bundle:check` | Web reader, rendering fallbacks, drawers, provider settings, Obsidian actions, note patches, and exports under mocked APIs. | Live API, SSE, and downloads still need manual browser smoke. |
| Web e2e | `rtk pnpm --filter @bilin/web test:e2e` | Playwright layout, accessibility, long-page behavior, and mocked reader workflows. | Mocked API means it is not full product confidence. |
| macOS Swift | `rtk swift test --package-path apps/macos` | Swift fixture loading, SQLite reads, guarded note writes, Zotero metadata, arXiv extraction, fallback math, and RaTeX adapter tests. | Manual launch still required. Some local toolchains may fail before XCTest loads. |
| macOS smoke | `rtk swift run --package-path apps/macos BilinMac` | App opens and native flows can be inspected. | Manually verify Open Library, Open Zotero Library, note save, equation preview, and missing `render-svg` messaging. |
| Local tools | `rtk apps/api/.venv/bin/bilin doctor` or `rtk make doctor` | Reports LaTeXML, `latexmlpost`, pandoc, TeX, image, PDF, and credential-store capabilities. | `uv` must be available for Makefile doctor. Tool versions still need human interpretation. |

## Immediate Worker Assignment Order

Start with `B-01`, `B-02`, and `B-03` serially. These tasks define shared
schemas and state transitions, so parallel edits would mostly create merge
conflicts and inconsistent OpenAPI contracts.

In parallel with that serial backend stream, run `M-01`, `M-02`, and `M-03`.
Those are Foundation-only Swift contracts and local configuration work. They do
not depend on backend OpenAPI and should not touch web files.

After `B-04` and `B-11`, start `W-01` and `W-02`. After `B-05`, split the
side-effect gates across workers: one for notes, one for exports, one for
Obsidian, and one for citation imports. These workers must not change the shared
ActionPlan state machine except through narrow service methods.

After `F-01` through `F-03`, start `M-05`, `M-06`, and `M-07` for the macOS
NoteBridge vertical slice. After `F-04` and `F-05`, start the WritingDock
prototype on macOS and web. Until those tests pass, Typst and TeX writing should
remain labeled as prototype, not implemented product behavior.

## Stop Conditions

Stop and re-plan if any implementation path requires direct file writes before
an ActionPlan approval, stores external Markdown or manuscripts as Bilin-owned
documents, executes downloaded skills without permission records, uses block
list indexes as durable anchors, or makes Typst/TeX writing appear production
ready before file-drift and provenance tests exist.
