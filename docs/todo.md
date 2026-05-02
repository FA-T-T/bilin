# Bilin MVP Todo

This document is the execution queue for closing the Bilin MVP. It does not
replace `docs/mvp-plan.md`; the MVP plan describes product intent, while this
file tracks the remaining engineering work in implementation order.

## Current Baseline

Bilin already has the lightweight monorepo foundation, arXiv import, a LaTeXML
parser vertical slice, provider-backed block translation, article-level
glossary, FTS5-backed article question answering, lecture-note patch generation,
and Markdown or bundle export. The remaining work below only tracks gaps that
still block a credible MVP acceptance path.

The MVP remains local-first and lightweight. Do not add accounts, Docker, Redis,
Celery, built-in sync, or an embedded PDF reader while closing this queue.

## Quality Gate

Every implementation stage must finish with the relevant checks below. A stage
cannot be considered complete if it only passes manual testing.

Backend checks:

```sh
cd apps/api
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Frontend checks:

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Golden and live LaTeXML tests must stay optional. Default tests should use
fixtures, mocks, and structural assertions so CI does not require network access
or a full TeX toolchain. Developer machines with LaTeXML installed may run the
integration markers explicitly.

## 1. Golden Regression

- [x] Target: make parser behavior reproducible before broadening feature work.
- [x] Add a real public TeX fixture under `fixtures/golden`.
- [x] Add structural assertions for sections, paragraphs, equations,
      figure/table captions, labels, asset placeholders, and source Markdown.
- [x] Add deterministic `document.json` checks that avoid brittle full snapshots.
- [x] Add an optional live LaTeXML integration path that is skipped unless the
      local toolchain is installed and explicitly requested.
- [x] Add or expose a CLI golden command that runs the same service code as the
      API and worker.
- [x] Completion standard: one golden paper can be regenerated into stable
      `document.json` and `source.md`, and parser diffs are meaningful.
- [x] Required tests: at least one backend golden fixture test and one CLI or
      service-level regression test.

Progress: `fixtures/golden/minimal-paper` and
`fixtures/golden/public-arxiv-2408.13687` now provide deterministic fixture
paths for the current normalizer. The public arXiv fixture is an attributed,
reduced CC-BY fixture based on the arXiv record for `arXiv:2408.13687`, not a
vendored multi-megabyte source package. It exercises multiple sections, globally
unique paragraph IDs, a display equation, figure and table captions, labels, an
asset reference, citation placeholder preservation, exact source Markdown, and
CLI golden execution. Adding it exposed and fixed a real normalizer defect where
paragraph IDs restarted after each section. `bilin golden run --live-latexml`
and the optional `integration_latexml` test still run fixture source through the
real parser when `latexml` and `latexmlpost` are installed.

## 2. Upload Imports

- [x] Target: support local file import without changing the arXiv-first design.
- [x] Add TeX archive import for `zip`, `tar`, and `tar.gz`, reusing the same
      source-package bundle layout as arXiv imports.
- [x] Add Markdown import as a weak structured document path that splits
      headings and paragraphs into stable blocks.
- [x] Add PDF save-only import. The PDF enters the article bundle but is not
      parsed, opened, OCRed, translated, or treated as canonical structure.
- [x] Add library-page UI for local file import beside arXiv ID import.
- [x] Completion standard: the library page can create an article revision from
      both an arXiv ID and a local file, and each revision has a self-contained
      bundle and database row.
- [x] Required tests: backend import tests for TeX archive, Markdown, and PDF
      save-only behavior; frontend test for the file-import form path.

Progress: raw file upload import is implemented without multipart dependencies.
TeX archives queue parse jobs, Markdown imports create weak structured blocks
immediately, and PDF imports are saved as source artifacts only.

## 3. Parser Asset Hardening

- [ ] Target: make parsed environment blocks useful instead of only structural.
- [x] Copy existing raster assets into the article bundle and expose them through
      the existing asset endpoint.
- [x] Add lightweight conversion entry points for common web-hostile assets such
      as EPS and PDF, gated by doctor-detected optional tools.
- [x] Add a minimal controlled-render path for TikZ or PGFPlots in the golden
      set; if rendering is unavailable, keep a structured fallback instead of
      failing the whole parse.
- [x] Improve table fallback records so table captions and original source are
      preserved even when full table normalization is not ready.
- [x] Preserve equation metadata, citation placeholders, and reference
      placeholders in document blocks.
- [x] Completion standard: reader shows real assets when available and a clear
      structured fallback when assets cannot be generated.
- [x] Required tests: parser fixture tests for copied assets, fallback assets,
      equation metadata, and table/caption preservation.

Progress: LaTeXML image references are resolved from local converter/source
paths, copied into the article bundle assets directory when a bundle is present,
and surfaced through existing asset records and reader image rendering. EPS and
PDF assets attempt optional `magick` plus `gs` conversion to PNG and degrade to
structured fallback metadata when tools are missing or conversion fails. Equations
now preserve TeX/display metadata, paragraphs preserve link references, and
environment blocks keep HTML fallback fragments. Code-generated figure hints such
as TikZ, PGFPlots, and PSTricks are marked for controlled rendering without
blocking parse when render tools are unavailable.

## 4. Reader Hardening

- [x] Target: make real parsed articles the primary reading path, not the mock
      reader.
- [x] Add virtualized long-document rendering keyed by `block_uid`.
- [x] Implement robust soft synchronization between source and translation
      columns without rigid table layout.
- [x] Add a real article Playwright path that opens a parsed fixture or mocked
      API article through `/articles/:articleId?libraryId=...`.
- [x] Turn hover toolbar actions into a small registry covering copy, inspect
      source LaTeX, retranslate, ask current block, and environment operations.
- [x] Add source-side and translation-side action separation for paragraphs and
      environment blocks.
- [x] Completion standard: a parsed article can be opened, navigated, read, and
      acted on smoothly without relying on `/articles/mock`.
- [x] Required tests: frontend render tests for toolbar actions and a Playwright
      smoke path for a real article route.

Progress: block hover actions now run through a registry instead of label-based
conditionals. Source, translation, and environment panes dispatch separate
actions for copy, current-block chat selection, source inspection, and
retranslation. The reader has a source inspector modal and clipboard-backed copy
actions, with frontend render coverage for a real article block. Playwright now
opens a mocked parsed article through the real `/articles/:articleId?libraryId=...`
route and checks rendered source, translation, and source inspection. The
reader also tracks the active block across source, translation, and structure
navigation so the two panes are visually synchronized at the block level.
`ReaderBlockList` now wraps every `block_uid` in a browser-native virtual shell
using `content-visibility`, and IntersectionObserver updates the active block
from scroll visibility. Reader Hardening is closed for MVP purposes; deeper
editor-like synchronized scrolling can move later if real papers expose a
specific defect.

## 5. Translation And Provider Hardening

- [x] Target: make translation reliable across restart, failure, and terminology
      changes.
- [x] Add provider-level concurrency and rate-limit settings to the stored
      provider profile and worker execution path.
- [x] Add retry handling for transient provider failures and clear terminal
      errors for authentication, missing model, and context overflow.
- [x] Add lightweight translation Markdown validation and store validation
      status without discarding raw model output.
- [x] Add translation variant selection in the reader.
- [x] Add custom prompt retranslation for selected blocks.
- [x] Add a minimal local translation memory interface while keeping article
      cache as the first lookup source.
- [x] Keep API keys outside library folders. macOS uses Keychain by default,
      while CI and explicit development runs can still use the SQLite fallback.
- [x] Completion standard: completed translations survive restart, failed blocks
      can be retried, glossary-triggered retranslations create new variants, and
      old variants are not overwritten.
- [x] Required tests: backend worker/provider mock tests for retry and variant
      creation; frontend tests for variant selection and custom retranslation.

Progress: provider profiles now carry explicit `max_concurrent_requests` and
optional `requests_per_minute` fields, with a global migration, CLI options,
developer-mode settings controls, and generated OpenAPI types. Translation jobs
run through provider-scoped in-process semaphores and rate-limit gates before
calling the LLM provider. Worker execution now requeues transient provider
errors up to the job's `max_attempts` while leaving configuration/data failures
terminal. Translation variants now preserve raw model output and store a
lightweight `validation_status` such as `ok`, `empty`, or
`unbalanced_code_fence`.

Reader translation panes now expose per-block variant selection when multiple
variants exist, and selecting a variant persists it as the default instead of
only changing local UI state. Block retranslation opens a focused prompt dialog,
passes the custom prompt into the queued job, and always uses `force` so a
retranslation creates a new variant rather than silently reusing the old cache.
The global application database now has a minimal `translation_memory` table and
lookup API. Translation execution checks the article-local exact cache first,
then validated translation memory entries with the same content hash, target
language, and glossary version, and only then calls the provider. Validated
non-custom translations are recorded into local translation memory. API keys
remain outside library folders; macOS stores them in Keychain by default and
legacy SQLite fallback keys are promoted on first use when Keychain is available.

## 6. QA Evidence Hardening

- [x] Target: make article answers auditable and distinguish local evidence from
      external model-native search.
- [x] Stream question-answer responses to the frontend and save the final answer
      only after completion.
- [x] Separate current-paper evidence from external native-search evidence in
      schema, storage, and UI.
- [x] Save returned external citation metadata when native search is enabled,
      including title, URL, DOI or arXiv ID when available, retrieval time, model
      name, and raw citation snippet.
- [x] Add a current-block question path that can propose a note patch candidate.
- [x] Keep local embedding after MVP. FTS5 remains the default local retrieval
      path for this queue.
- [x] Completion standard: answers stream, cite internal `block_uid` references,
      preserve external citation metadata when enabled, and restrict external
      claims when native search is disabled or unsupported.
- [x] Required tests: backend tests for streaming completion, evidence storage,
      and native-search capability gating; frontend tests for evidence display.

Progress: question answering now has a streaming SSE endpoint that emits
current-paper evidence first, streams answer deltas, and persists the user and
assistant messages only after answer completion. `RetrievedBlock` now carries a
`current_paper` evidence type, while model-native external citations are stored
as structured `ExternalCitation` records with title, URL, DOI or arXiv ID,
retrieval time, model name, raw snippet, and provider metadata. The reader shows
current-paper evidence separately from external evidence and continues to
disable native search for providers that do not advertise support. Assistant
answers can be turned into proposed note patches from the chat panel, preserving
block citations and external references in patch metadata. This MVP stage kept
FTS5 and block-neighborhood retrieval as the default local evidence path; the
post-MVP backlog now has a first local embedding vertical slice.

## 7. Lecture Notes Editing

- [x] Target: let users edit learning notes instead of only accepting or
      rejecting generated patches.
- [x] Add a note editing mode using Tiptap or a Markdown editor, keeping Markdown
      as the durable saved artifact.
- [x] Add custom note template management for user-defined general templates.
- [x] Allow patch editing before accept.
- [x] Define and implement accepted-note section merge behavior so repeated
      patches update `lecture-notes.md` predictably.
- [x] Completion standard: users can generate a patch, edit it, accept it, and
      reopen a durable `lecture-notes.md` that preserves citations.
- [x] Required tests: backend tests for note merge behavior and frontend tests
      for edit-before-accept.

Progress: note patches now have an edit-before-accept flow in the reader using
a Markdown textarea and editable title field. Proposed patches can be saved as
drafts or accepted with the edited Markdown through the same update endpoint,
and accepted patches regenerate `lecture-notes.md` with deterministic
`bilin-note-patch` markers, stable section ordering, preserved source
references, and a stored notes path. Built-in templates remain fixed, while
user-defined custom templates are stored in the global app database, exposed by
the notes template API, selectable in the reader, and usable by the same note
generation service. Backend tests cover custom templates, edit-before-accept,
and deterministic note-file markers; frontend render tests cover creating a
custom template, editing patch Markdown, and accepting the edited patch.

## 8. Export And CLI Acceptance

- [x] Target: prove that UI and CLI operate on the same portable article bundle.
- [x] Optionally route export through the background job system for consistent
      task progress and cancellation semantics.
- [x] Add a CLI acceptance command or documented script for golden import,
      parse, reader-ready artifact generation, and export.
- [x] Keep MVP export limited to source Markdown, translated Markdown, bilingual
      Markdown, lecture-note Markdown, and bundle zip.
- [x] Put PDF, Word, EPUB, and polished print export in Backlog, not in MVP.
- [x] Completion standard: the same golden paper can be imported, parsed, and
      exported from both UI and CLI, with readable files outside the app.
- [x] Required tests: CLI/service tests for import-parse-export flow and API
      tests for export result metadata.

Progress: export remains available as a synchronous reader/API action, and the
same request can now also be queued as an `export_article` background job for
worker-driven progress and task history. Export results include stable metadata
for the bundle path, manifest path, export directory, and bundle-relative output
path, and manifest export entries preserve the same metadata. The CLI now has
`bilin acceptance golden`, which creates a disposable library from a golden TeX
fixture, imports the source archive, materializes a reader-ready document from
fixture LaTeXML HTML by default, optionally runs live LaTeXML, and exports the
MVP artifact set: source Markdown, translated Markdown, bilingual Markdown,
lecture-note Markdown, and bundle zip. Backend coverage now checks direct
exports, worker export jobs, API export metadata, and the CLI acceptance path.

## 9. Install And Local Safety

- [x] Target: make a clean local setup predictable and safe.
- [x] Verify the clean-machine path documented in `README.md`: install
      dependencies, run doctor, create a library, import, parse, open reader.
- [x] Improve doctor suggestions for missing LaTeXML and optional asset tools.
- [x] Make LaTeXML missing-dependency parse failures explicit in UI, API, CLI,
      and logs.
- [x] Document job pause and cancel semantics for import jobs, parse jobs,
      translation jobs, embedding jobs, and exports.
- [x] Confirm `.gitignore` excludes generated caches, local databases, bundles,
      node modules, virtual environments, and build output.
- [x] Document `BILIN_HOME`, library directory portability, and which files are
      safe to sync with external tools such as iCloud or OneDrive.
- [x] Completion standard: a new machine can follow the documented path to reach
      reader-open state without Docker, Redis, Celery, accounts, or built-in
      sync.
- [x] Required tests: setup smoke documentation check where practical, plus API
      or CLI tests for missing dependency messages and local path behavior.

Progress: README now describes the clean-machine path, deterministic golden
acceptance command, real LaTeXML parser dependency, `BILIN_HOME`, local data
layout, and quality gates without implying Docker, Redis, Celery, accounts, or
built-in sync. `docs/local-safety.md` records the operational contract for
dependency failures, worker pause/cancel semantics, global app data, portable
library folders, and external sync boundaries. Doctor output now distinguishes
LaTeXML parser blockers from optional asset/PDF helpers, and missing LaTeXML
parse failures include a doctor command and install hint. Parse failures write
structured `logs/parse-error.json`, persist the same error in `manifest.json`,
surface through worker job errors, print guidance in the CLI, and render in the
web task drawer. `.gitignore` now covers local SQLite databases, generated
library and paper bundles, local data directories, virtual environments, node
modules, builds, and test artifacts. Backend tests cover the documentation
contract, gitignore contract, doctor messages, parse failure logs, CLI guidance,
and worker job error shape; frontend tests cover task drawer error rendering.

## Backlog After MVP

- [x] Local embedding and hybrid vector retrieval vertical slice.
- [ ] LLM-assisted PDF fallback parsing.
- [x] OS credential-store integration such as macOS Keychain.
- [ ] Global and library-level glossary scopes.
- [x] Global translation memory promotion and review.
- [ ] Optional neural local embedding provider with model download and doctor
      gating.
- [ ] Word, EPUB, PDF, and polished print export.
- [ ] Rich command palette and high-frequency keyboard shortcuts.
- [ ] Model usage and cost metadata display.
- [ ] Desktop shell packaging.
- [ ] External sync conflict detection and repair guidance.

Progress: the first post-MVP backlog slice adds a SQLite `block_embeddings`
table, deterministic local hash embeddings, `embed_article` worker jobs,
`bilin embed article`, embedding status/build/job API endpoints, generated
frontend types, and QA retrieval mode selection. `auto` question answering now
uses hybrid FTS5 plus vector retrieval when current embeddings exist, and falls
back to FTS5 when they do not. This is intentionally a lightweight local
interface, not yet a neural semantic model; a neural provider remains a separate
optional backlog item so the default project stays small and offline-friendly.
