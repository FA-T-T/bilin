# MVP Implementation Plan

## Objective

The first implementation must prove the end-to-end TeX reading loop. A user should be able to create a local library, import an arXiv paper, parse the source package into a structured document model, read semantic English Markdown beside a translated target-language view, run parallel cached translation jobs, ask questions grounded in the paper, and accept a lecture-note patch generated from a built-in template. Everything else exists only insofar as it protects that loop.

## Foundation

The repository should begin as a lightweight monorepo with `apps/web`, `apps/api`, `docs`, and `fixtures/golden`. The frontend uses Vite, React, TypeScript, Mantine, TanStack Query, Zustand, Tiptap in edit mode, Vitest, and Playwright. The backend uses Python, FastAPI, Pydantic, SQLite, Typer or Click, `uv`, and explicit SQL migrations. Root commands are wrapped in a `Makefile`.

This stage is complete when `make dev` can start the API and web app in development, `make test` can run fast checks, `make generate-api-client` can refresh TypeScript API types from FastAPI OpenAPI, and `make doctor` can report local toolchain capability without blocking startup.

## Backend Spine

The backend should first establish the global application database, library registration, library creation, per-library SQLite initialization, and migration execution. It should then define repositories and Pydantic schemas for libraries, article families, article revisions, article manifests, jobs, provider profiles, blocks, translations, glossary entries, chats, and notes. The schema does not need every future field, but it must include versioning fields and stable identity boundaries from the start.

The SQLite-backed job queue comes next. The worker process must be able to claim jobs transactionally, run them, update progress, retry transient failures, cancel active work where possible, and survive process restart. The FastAPI process exposes job creation and status APIs and emits progress through Server-Sent Events. Queue behavior is validated through real product jobs such as import, parse, translation, embedding, note generation, and export rather than a synthetic public endpoint.

## Import And Bundle Layout

The first real import path is arXiv ID import. The backend resolves the concrete latest version, downloads the source package, downloads the PDF by default, stores both in the article bundle, writes a manifest, and records the article family and revision in the library database. The PDF is saved for archival and external opening only; the reader does not embed it.

Uploaded TeX archives, PDFs, and Markdown files follow after arXiv import works. TeX archives enter the same source-package path as arXiv sources. Markdown imports become weak structured documents. PDFs are saved as source files and can later enter the LLM fallback path, but the MVP does not need a full PDF parser.

This stage is complete when an arXiv paper can be imported into a self-contained bundle with source archive, PDF, manifest, database row, and a visible library entry.

## Parser Vertical Slice

The parser should target a narrow but real golden set before broad arXiv coverage. The first parser route discovers the main TeX file, runs the selected converter path, normalizes headings and paragraphs, extracts equations, identifies figure and table environments, collects labels and citations where available, and emits a schema-versioned `document.json`. It then renders `source.md` from the document model.

Asset handling should first support copied raster images and common converted vector images. Controlled rendering for TikZ and PGFPlots should be added early because code-generated figures are part of the design, but it can be limited to the golden set at first. Tables can begin with conservative structure and original LaTeX fallback. Equations should store both original and normalized LaTeX and render in the frontend through KaTeX with fallback status.

This stage is complete when at least one golden arXiv source package produces a document model with sections, paragraphs, equations, figures, captions, labels, citations, and semantic Markdown, and when parser output can be regenerated deterministically.

## Reader Shell

The frontend should implement the library homepage, article open flow, structure navigation, bilingual soft-synchronized reading layout, single-column environment blocks, theme switching, and block hover toolbars. The source side shows semantic English Markdown. The translation side initially shows untranslated placeholders and job state. The reader supports bilingual, translation-first, and source-first modes, but only bilingual mode needs polish in the first pass.

Virtual scrolling and block identity must be designed before long documents are loaded. The reader scrolls and jumps by `block_uid`, not by DOM position. Hover operations can initially call stub actions, but the toolbar locations and action registry should be real.

This stage is complete when a parsed golden paper opens in the reader, navigation jumps to sections and blocks, formulas render, figures display, captions appear, and hover toolbars expose source-side, translation-side, and environment-block actions.

## Provider Profiles And Translation

The backend then implements OpenAI-compatible and Anthropic-compatible protocol adapters behind a unified `LLMClient`. User mode creates provider profiles from provider type, API key reference, base URL preset, and model selection. Developer mode can edit full provider profile fields. API keys are stored outside libraries in the operating system credential store, with a development fallback only for local development.

Translation jobs are generated from translatable paragraph and caption blocks. The job payload includes current block content, target language, glossary version, neighboring context, section context, and model routing. Translation runs in controlled parallel through the worker. Successful output is validated lightly, stored as a translation variant with Markdown and a lightweight AST, and rendered into the reader. Failed blocks become retryable.

This stage is complete when the user can configure a provider, select a model, translate a paper in the background, watch progress in the task drawer, reload the app without losing progress, and reopen the article without retranslating completed blocks.

## Glossary And Terminology

The initial glossary system should support global, library, and article scopes, but article scope can receive the first polished UI. Rule-based candidate extraction runs after parsing and proposes repeated terms, abbreviations, and technical noun phrases. LLM-generated translation suggestions can be added only after provider profiles are working. Candidates remain inactive until the user confirms them.

The reader exposes a glossary side panel. Changing a term updates render-layer terminology where safe and marks affected translations using recorded glossary versions and matched terms. Batch retranslation of affected blocks can reuse the translation queue.

This stage is complete when a user can confirm a candidate term, see it applied in rendered translations, change it, see affected blocks marked, and retranslate those blocks without overwriting previous variants.

## Question Answering

Article-grounded question answering should be built before external search. The backend indexes blocks in SQLite FTS5 and, when the local embedding model is available, in a local vector index. If embedding is not installed, FTS5 is sufficient for the first run. The question-answering prompt receives retrieved blocks, citations, paper metadata, current reading position, and relevant notes. The model response streams to the frontend and is saved only after completion.

The answer schema must include answer text, cited internal source references, uncertainty notes, and an optional note patch candidate. Native model search can be added as an explicit per-question switch once basic article-grounded answering works. When native search is enabled, the UI must separate current-paper evidence from external evidence and save returned external citation metadata.

This stage is complete when paragraph-level and whole-paper questions stream answers, cite internal `block_uid` references, save chat history, jump back to cited blocks, and refuse external claims unless the user enables native search with a compatible model.

## Lecture Notes

Lecture notes begin with built-in templates for deep reading, group meeting preparation, quick skimming, and reproduction-oriented reading. The first implementation can generate one patch from the deep-reading template. The patch references cited blocks and proposes additions to structured note sections. The user can accept, edit, or reject the patch. The accepted note writes to the database and refreshes `lecture-notes.md` in the article bundle.

Tiptap should be loaded only in note editing and translation variant editing modes. Markdown source editing can be available behind a tab, but the default path is a structured visual editor that preserves formulas and citations.

This stage is complete when a user can generate a default lecture-note patch from the current paper, inspect citations, accept or edit it, and see a durable Markdown note file updated in the article bundle.

## Export And Developer Workflow

The MVP export path should support source semantic Markdown, translated Markdown for a target language, bilingual Markdown, lecture-note Markdown, and the article bundle itself. PDF, Word, EPUB, and polished print export are later work.

The CLI should expose the same core capabilities as the UI for development and regression. It should create libraries, import arXiv papers, parse articles, run golden tests, export article bundles, and run `doctor`. It must reuse backend modules rather than duplicate behavior.

This stage is complete when the same golden paper can be imported and parsed from both the UI and CLI, and when generated files are readable outside the application.

## Testing Path

Testing starts with fast backend tests for migrations, repositories, hash generation, queue behavior, provider adapter mocks, glossary rendering, document schema validation, and API responses. Frontend tests cover action registries, layout state, API hooks, glossary replacement, and basic rendering logic. Playwright covers the real user path through library creation, import fixture, reader open, hover toolbar, mock translation, mock question answering, and note patch acceptance.

Golden tests use public arXiv fixtures and real tools only when dependencies are installed. They check structural facts rather than brittle snapshots. A passing golden test confirms that expected sections, paragraphs, equations, figures, tables, captions, references, assets, translation jobs, and Markdown outputs exist.

This stage is complete when ordinary CI can run fast tests without a heavy TeX installation, while a developer machine with the full toolchain can run golden regression tests and see meaningful parser diffs.

## MVP Acceptance

The MVP is accepted when a clean local machine can install frontend and backend dependencies, run `doctor`, create a library, import at least one public arXiv golden paper, parse it into `document.json`, open it in the reader, translate paragraph and caption blocks through a configured OpenAI-compatible or Anthropic-compatible model, cache translations across restart, ask cited questions about a paragraph and the whole paper, generate and accept a lecture-note patch, and export Markdown artifacts from the article bundle.

The MVP is not accepted if the system only displays uploaded files without a stable document model, if translations disappear after restart, if notes cannot cite source blocks, if parsing output cannot be regenerated, if API keys are stored in library directories, or if the core workflow requires Docker, Redis, Celery, cloud accounts, or built-in synchronization.
