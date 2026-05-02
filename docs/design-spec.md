# Local Paper Reading System Design Specification

## Purpose

This project is a local-first web application for reading, translating, questioning, and studying academic papers. The primary input is the arXiv TeX source package, because TeX preserves the semantic structure that a serious reading system needs: sections, paragraphs, equations, figures, tables, labels, citations, theorem-like environments, algorithms, and bibliography entries. PDF is supported as an archived source file and as a weak fallback input through capable LLMs, but PDF is not the canonical path for structured reading.

The system is not a SaaS product in its first form. It has no account system, no built-in cloud sync, no remote user identity, and no central backend. It runs as a local web service with a React and TypeScript frontend, a Python FastAPI backend, and a separately managed local worker process. The browser connects to `localhost`. A future desktop shell can wrap the same local service, but the first implementation should not spend design effort on a Tauri or Electron shell.

## Product Boundary

The canonical mode is TeX mode. In this mode the user imports an arXiv ID or uploads a TeX `zip` or `tar.gz` package. The backend builds a deterministic document model, renders semantic Markdown for reading, extracts or renders assets, creates paragraph-level translation jobs, caches translated blocks, supports paragraph-level operations, and lets the user ask questions grounded in the paper.

PDF mode is an LLM-assisted fallback mode. A PDF can be saved in the library, and a recommended capable model may attempt to parse or summarize it, but this mode does not promise strict paragraph alignment or TeX-level structure. The interface must label PDF-derived structure as model-generated fallback structure. The main product claim remains high-quality TeX-based reading and translation.

Markdown input is a weak structured input. The system can import a Markdown file, split it into headings and paragraphs, and then provide translation, question answering, and lecture-note generation. It cannot infer TeX-level equation labels, figure references, or bibliography structure unless that information is already present.

Other file types are attachments in the first version. They may be saved in an article bundle, but they are not first-class parsing targets.

## Local Data Boundary

A library is a real local directory, not just a UI label. Each library is self-contained enough to be backed up, moved, or synchronized by an external file-sync tool such as iCloud, OneDrive, Dropbox, or Syncthing. The application itself does not implement synchronization or conflict resolution.

Each library owns a `library.sqlite` database and a directory tree of article bundles. The global application database only stores library registrations, recently opened libraries, non-sensitive provider profile metadata, global settings, and cross-library translation memory. API keys never enter a library directory. They are stored in the operating system credential store, such as macOS Keychain, and the library only stores key references.

Each arXiv paper is represented as a paper family plus concrete revisions. The family is keyed by the bare arXiv ID, while each imported version is stored as a concrete revision such as `2401.12345v2`. The UI may show the latest revision as the default entry, but translations, notes, questions, and parsed documents attach to a concrete revision. This prevents silent drift when arXiv papers change.

Each article revision is an article bundle. A representative path is `libraries/<library-name>/articles/arxiv/2401.12345/v2/`. The bundle contains the source archive, the saved PDF when available, the unpacked controlled source copy, the document model, rendered semantic Markdown, translations, notes, assets, indexes, logs, and a manifest. Uploaded non-arXiv documents use a stable upload ID instead of an arXiv path.

The manifest records the article identity, source fingerprints, parser version, document schema version, toolchain versions, asset inventory, generated files, and which artifacts are primary assets versus rebuildable caches. Original sources, user notes, question history, lecture notes, glossary entries, and accepted translations are primary assets. Document models, rendered Markdown, rendered images, table HTML, formula render fallbacks, and indexes are rebuildable but should still be saved by default so that synced libraries open quickly on another device.

## Document Model

The document model is the single source of truth for structured reading. Markdown is a rendering and export format, not the canonical internal format. Each `document.json` has a strict `schema_version`, `generator_version`, `source_fingerprint`, `created_at`, and `toolchain` field. Unknown or experimental fields live under an explicit `extras` object rather than drifting into the core schema.

Every block has a version-stable `block_uid`, a human-readable structural path, a `block_type`, parent section information, source location when available, normalized content, original source fragments when available, and content hashes. The `block_uid` is stable within one article revision. It combines article revision identity, structural path, and block type. Cross-version reuse relies on `content_hash` and neighboring context, not on assuming structural paths remain identical.

Paragraphs are the normal translation unit. The system should not split ordinary paragraphs into sentence-level jobs unless a paragraph exceeds model or UI thresholds. Long paragraphs can be split into sub-blocks under the same parent paragraph, preserving the parent identity and reading flow.

Equations are first-class objects. Inline and display equations store original LaTeX, normalized LaTeX, labels, numbers, block ownership, render status, and fallback render assets if needed. Formula content is not translated. The frontend defaults to KaTeX for speed, falls back locally to MathJax for difficult expressions, and falls back again to backend-rendered images when browser math rendering cannot handle the expression.

Figures, tables, algorithms, theorem-like environments, definitions, lemmas, proofs, assumptions, remarks, and bibliography entries are not ordinary paragraphs. They are typed environment blocks. Captions are translatable. Code blocks are not translated. Algorithm captions and natural-language comments may be translated, but pseudocode structure, variables, function names, formulas, and line numbers are preserved. Bibliography entries are structured and clickable but not translated by default.

## Parsing Pipeline

The parsing pipeline is deterministic by default. LLMs must not participate in normal structure generation, because document identity, translation caches, regression tests, and note citations depend on reproducible block structure. LLMs may assist in three places: explicit parse-failure repair, PDF fallback parsing, and optional explanation of complex environment blocks.

The main TeX route is a staged pipeline. It unpacks and sanitizes the archive, discovers the main source file, normalizes macros and paths where possible, runs a primary converter, normalizes converter output into the document model, extracts references and bibliography, processes assets, validates the document, and emits semantic Markdown. The preferred main converter path is `LaTeXML -> HTML/XML -> normalized document model -> Markdown render`, while `pandoc` remains a fallback interface. Business logic must not bind itself directly to one converter output format.

The parser supports internal fixer plugins. Fixers are registered into named stages such as source discovery, macro preprocessing, converter repair, environment normalization, asset resolution, TikZ or PGFPlots rendering, table normalization, and validation. A fixer declares applicability, priority, input shape, and output shape. This prevents the parser from becoming a pile of template-specific conditional logic.

Parse failures first go through deterministic repair. If the user explicitly chooses LLM repair, the system can ask a model to explain the error or propose a patch. That patch must be recorded in the article logs and manifest. The system must not silently let a model rewrite source and continue as if the result were deterministic.

Uploaded archives and arXiv source packages are treated as untrusted input. The first version does not use Docker or containers, because the product must remain lightweight. Instead, parsing runs in a separate restricted worker process with temporary work directories, path traversal protection, file size limits, command whitelists, timeouts, disabled shell escape, cleaned environment variables, and explicit cleanup of temporary files.

## Asset Pipeline

Figure handling is not limited to copying image files from a source package. Some papers generate figures from code-like LaTeX constructs such as TikZ, PGFPlots, PSTricks, or standalone subdocuments. The asset pipeline first resolves existing raster or vector files, then converts browser-hostile formats such as EPS or PDF into web assets when possible, and then attempts controlled rendering for code-generated figures when supported by the local toolchain.

Each asset receives a stable asset ID. The document model stores the asset ID, original source reference, caption, label, source position, generated render status, and any errors. Frontend blocks display the web asset, not arbitrary paths from inside the source package.

The first version does not perform OCR. Search and question answering for figures are based on caption, label, nearby text, explicit references from the paper, and optional user-triggered model explanations. A vision-capable model can be used to explain a figure on demand, but that explanation is stored as a note or asset explanation, not as original document text.

Tables are structured environment blocks. Simple tables can render as Markdown or HTML tables. Complex tables preserve a table model with cells, spans, caption, label, original LaTeX, and conservative HTML rendering. If the structure cannot be safely normalized, the UI still offers original LaTeX and an explanation action.

## Translation

Translation is block-based, cached, resumable, and parallel. Each translatable paragraph or caption becomes a persistent job in a SQLite-backed queue. The job includes the target language, provider profile, model, glossary version, `content_hash`, `context_hash`, retry count, status, error fields, and output metadata. Jobs run in a background worker process, not in the FastAPI request lifecycle.

Translation jobs are parallelized under provider-specific concurrency and rate limits. User mode exposes simple low, medium, and high concurrency settings. Developer mode exposes provider-level maximum concurrency, request limits, token limits where known, and retry policy. The system does not estimate costs in the MVP. If an API returns usage metadata, it is saved in the LLM call log but not surfaced as a pricing promise.

The translation input uses the current block as the only output target. It may include the paper title, abstract, section title, active glossary, neighboring one or two blocks, and an optional section summary as read-only context. The prompt must instruct the model to translate only the current block. Formula blocks, figures, tables, algorithms, and references can appear as context but are not translated as paragraph output.

The cache has two layers. The `content_hash` identifies normalized block content after ignoring irrelevant whitespace, formatting noise, and non-semantic TeX differences. The `context_hash` includes target language, glossary version, model settings, section context, and nearby context. A full cache hit can be reused directly. A content-only hit can be offered as a candidate or lightly validated.

Each article owns an article-local translation cache. A separate global translation memory can store confirmed reusable translations across libraries and papers. Lookup first checks the article-local cache, then global memory. Promotion to global memory requires either validation or user confirmation.

Translation variants are never overwritten casually. A retranslation creates a new variant, and the user may set it as the default. Interactive retranslation and question answering support streaming draft output, but only completed and validated output is committed as an official translation variant or chat message.

Translation output stores both raw Markdown and a lightweight parsed AST. Markdown remains human-readable and exportable. The AST supports validation, glossary rendering, reference links, formula protection, and diffing. If AST parsing fails, the raw Markdown still displays with a validation warning.

## Glossary System

Terminology is a versioned system, not a global find-and-replace. There are global, library-level, and article-level glossaries. Rendering uses an active glossary composed by priority, with article terms overriding library terms and library terms overriding global terms. Glossary version participates in translation context hashing.

A glossary entry contains the source term, target term candidates, language direction, domain, phrase type, case sensitivity, inflection policy, whether formulas are protected, and whether English should be preserved. The UI must support switching terminology presets and previewing affected blocks.

Terminology extraction starts with deterministic rules. The system can identify title and abstract noun phrases, repeated multi-word terms, `term (ACR)` abbreviation patterns, capitalized method names, hyphenated technical phrases, and domain-specific repeated expressions. An LLM may suggest translations and classifications, but candidates must be confirmed by the user before entering the active glossary.

Glossary changes do not automatically force retranslation. By default, they affect the render layer. The system preserves model output and applies the active glossary at display time where safe. If a glossary change affects syntax, long phrases, or meaning, the user can batch-retranslate affected blocks. Translation variants record the glossary version and matched terms used at generation time, so affected blocks can be marked when terminology changes.

## LLM Providers

The system supports two protocol families in the first version: OpenAI-compatible APIs and Anthropic-compatible APIs. Provider presets can configure common services, but business logic must talk to a unified `LLMClient` abstraction. Provider-specific differences in request shape, streaming, errors, model listing, structured output, and native search are hidden behind protocol adapters.

The model configuration UI has two modes. User mode shows provider selection, API key entry, model detection, and a simple default model choice. Developer mode exposes the full provider profile, including base URL, protocol, model capability tags, context length, streaming support, PDF support, vision support, structured-output support, native-search support, concurrency limits, retry policy, and manual model overrides.

Model capabilities are detected where possible, filled from presets where known, and manually overridable in developer mode. API key storage is application-level secure storage. Libraries store only non-sensitive provider profile references.

Per-task model routing is supported. Translation, PDF fallback parsing, paragraph question answering, full-paper question answering, lecture-note generation, validation, glossary suggestion, and embedding may use different models. User mode may set one default model for convenience, while developer mode exposes task-specific routing.

## Search And Question Answering

The default question-answering mode is article-grounded. The system retrieves relevant blocks from the current article and passes those blocks, their neighbors, the paper title, abstract, section structure, current reading position, and relevant notes to the model. The answer must cite source blocks, equations, figures, tables, or bibliography entries. Unsupported models without native search are restricted to the article context.

Local retrieval is hybrid. SQLite FTS5 handles exact terms, abbreviations, symbols, author-defined phrases, references, and equation numbers. Local multilingual embedding handles semantic queries. Embedding is local by default and should not depend on an external API. If local embedding is not available, the system falls back to FTS5.

Native model search is the first version's external evidence path. The application does not build its own external literature search engine in the MVP. If the user enables native search for a question and the chosen model supports it, the answer may cite external sources. The application must still record external citation metadata returned by the model, including title, URL, DOI or arXiv ID when available, retrieval time, model name, and raw citation snippet.

External search is off by default. The user explicitly enables it per question or conversation. Answers that use it must separate what the current paper says from what external sources add. Lecture notes likewise separate the main paper reading domain from an external supplement domain.

Figures and tables enter question answering through structured text by default. Tables contribute extracted cells and captions when available. Figures contribute captions, labels, nearby text, and references. Vision-capable models can receive an image asset only when the user asks to explain a figure with a suitable model.

## Lecture Notes

The note system has two layers. The first layer is the raw question history, including prompt, answer, cited blocks, model, provider, time, whether native search was enabled, and any external evidence metadata. The second layer is an editable structured lecture note.

Lecture notes are not automatically overwritten. Model output creates a note patch with proposed additions or edits, cited `block_id` references, and evidence type. The user can accept, edit, reject, or merge the patch. This preserves long-term notes as user assets rather than ephemeral chat summaries.

The system includes built-in templates for deep reading, group meeting preparation, quick skimming, and reproduction-oriented reading. Users can create custom general templates. A template defines the question set, output sections, citation requirements, and depth. The default lecture note can cover background, why the problem matters, assumptions, method, key equations, experiments, conclusions, limitations, reproducibility details, and follow-up questions.

Main-paper notes and external supplement notes remain separate evidence domains. External sources can enrich background and related-work understanding, but they must not be merged into the paper's own claims without labeling.

## Frontend Experience

The frontend is a React and TypeScript application built with Vite. Mantine is the UI foundation. The application uses TanStack Query for server state and Zustand for UI state. The API client is generated from FastAPI OpenAPI output.

The library homepage is a paper database view, not a file explorer. It shows paper title, authors, year, arXiv ID and version, source type, tags, reading state, parse state, translation state, note state, and recently opened time. The MVP supports tags and reading states. Collections or reading paths can be added later.

The reading page has a collapsible structure navigation sidebar, a central reading area, and optional side panels for glossary, chat, notes, and task progress. The default reading mode is bilingual soft synchronization. The left side shows English semantic Markdown. The right side shows the target-language translation. Blocks align at the top, but the layout uses virtual scrolling and current block synchronization rather than a rigid table layout. Figures, tables, formulas, algorithms, and other environment blocks can render as single-column blocks.

The reader also supports translation-first and source-first modes. The target language is multi-language by design, while the default optimized case is English to Simplified Chinese. The UI must warn users that translation quality for each language depends on the selected model, glossary, and domain coverage.

Hover toolbars are block-specific and normally hidden. Source-side operations focus on source understanding, source copying, source LaTeX inspection, citation navigation, and asking about the original block. Translation-side operations focus on copying translations, retranslating, custom prompt actions, variant selection, glossary effects, and adding note patches. Environment blocks have operations such as copy, explain, show source LaTeX, translate caption, and add to notes.

Custom prompts can be saved as prompt actions. A prompt action declares its input scope, output type, whether it is batch-safe, and whether it can appear in hover toolbars or the command palette. Batch-safe actions can run over selected blocks, a section, or affected translation blocks through the job queue.

The application supports light mode, dark mode, and system theme. It includes a command palette and a small set of high-frequency shortcuts for search, view switching, translation, retranslation, chat, note insertion, glossary switching, and task access.

The reader does not embed PDF as a third pane in the MVP. The arXiv PDF is saved by default into the article bundle for archival and manual external opening, and this behavior can be disabled in settings.

## Jobs And Runtime

The backend uses FastAPI for API requests and SSE event streams. Long-running work runs in a separate local worker process managed by the application. The worker handles parsing, asset rendering, translation, embedding, export, and lecture-note generation.

The job queue is SQLite-backed. It does not require Redis, Celery, Docker, or any external service. Jobs are claimed transactionally, can be paused, resumed, retried, cancelled, or marked failed, and survive process restarts. Job cancellation attempts to stop actual external processes and API streams where possible. LaTeX and conversion processes receive termination signals, temporary files are cleaned, and stubborn processes are killed after timeout.

Task progress is pushed to the frontend with Server-Sent Events. TanStack Query polling acts as a consistency fallback when events are missed or the connection restarts. A global task drawer shows active parsing, translation, embedding, export, and note-generation jobs. A later full task page can expose deeper history and logs.

Error handling is type-aware. Transient network errors, rate limits, and temporary provider failures can retry with backoff. Authentication failures, missing models, context overflows, repeated validation failures, parse failures, and missing files stop and surface suggested actions. A failed block does not block the entire article; the article becomes partially failed and supports retrying failed blocks.

## Dependencies And Tooling

The application body remains lightweight. Heavy document tools are managed external dependencies, not bundled wholesale. A `doctor` command and settings page detect tools such as LaTeXML, Pandoc, Tectonic or a LaTeX engine, Poppler, ImageMagick, Ghostscript, and related converters. Capabilities are reported as required, recommended, or optional. First launch does not block on missing tools, but parsing actions explain which capabilities are unavailable.

The project uses a lightweight monorepo. The web app lives under `apps/web`. The backend lives under `apps/api`. Generated API types or clients live under the web app or a shared package. Documentation lives under `docs`. Golden fixtures live under `fixtures/golden`.

The frontend package manager is `pnpm`. The Python backend uses `uv`. Root development commands are exposed through a `Makefile`. The backend CLI is implemented with Python Typer or Click and reuses backend core modules. It supports dependency diagnosis, library creation, arXiv import, article parsing, golden tests, and export.

SQLite schema changes use explicit SQL migrations from the first version. The global database and each library database have their own migration state. Backend models use Pydantic schemas and repositories over SQLite rather than a heavy ORM.

## Testing And Quality

The first version uses golden regression tests for the parser and reading pipeline. A public golden set should include representative papers from physics, computer science, quantum information, and communications, with examples covering formulas, figures, tables, algorithms, bibliography, custom macros, and code-rendered figures. The golden set is public and replaceable by project-local private samples.

Backend tests are split into fast mock tests and optional real-toolchain golden tests. Fast tests mock external LLM and document tools and verify repositories, queue behavior, hashing, schemas, glossary rendering, provider adapters, and API behavior. Golden tests run real tools only when dependencies are installed and can be skipped on machines without the full toolchain.

Frontend tests use Vitest for small logic units and Playwright for smoke and end-to-end paths. The key browser tests cover library creation, fixture import, reader opening, bilingual view, hover toolbar, view switching, mock translation, mock question answering, note patch creation, and task progress display.

The project configures TypeScript strict mode, ESLint, Prettier, Ruff, and Pyright or basedpyright from the start. Continuous integration is lightweight. It runs formatting, linting, type checks, generated API schema checks, and fast tests. Full TeX golden tests are local or manually triggered until the dependency story is mature.

## MVP Definition

The MVP is a true vertical slice, not a shallow mock. It creates a library, imports one arXiv ID, downloads the concrete source package and PDF by default, builds a deterministic document model, extracts or renders basic assets, displays semantic English Markdown, translates paragraphs and captions in the background, caches translation variants, supports paragraph hover actions, supports article-grounded question answering, and generates a lecture-note patch from a built-in template.

The MVP intentionally postpones embedded PDF reading, internal cloud sync, account systems, custom external search engines, OCR, EPUB or DOCX parsing, Word/PDF export, full multi-paper comparison, and a public plugin marketplace. These are not rejected features. They are excluded because the first version must prove the TeX-to-study workflow before expanding outward.
