# Ilios / 衔牍 Design Contract

This document is the product and interaction contract for Ilios. It records the current accepted design, the default behavior, and the rules future refactors must preserve. It is not a roadmap and it is not human-facing marketing copy. User-facing pages must show useful controls and results, not implementation notes, naming policy, or maintainer reasoning.

## Product Purpose

Ilios is a local-first research paper reading and study environment for people who need to understand English research papers through a stronger native-language reading loop. The app should help users import a structured paper, read it as an article, translate missing parts, ask precise questions, create compact knowledge cards, save notes to Obsidian, and export useful files. It should not become a cloud account system, a generic PDF viewer, a heavy document management platform, or a tool that forces users to manage every block manually.

The primary path is TeX-first. arXiv source packages and local TeX archives are the canonical structured input. Markdown can be imported as weak structure. PDF can be saved into the bundle as source material, but PDF parsing, OCR, embedded PDF reading, and PDF translation are not part of the default MVP path. LaTeXML is the formal parser path for TeX. If a dependency is missing, the system should fail clearly and report the missing capability instead of silently producing low-quality structure.

The technical project identifier remains `bilin` for package names, CLI compatibility, and existing commands. The product names are `衔牍` in Chinese, `Ilios` in English and most other languages, and `理紐` in Japanese. This naming rule belongs in documentation and settings metadata, not in the main reader UI.

## Product Boundaries

Ilios stays local-first and lightweight. The default architecture uses React, TypeScript, FastAPI, SQLite, a Python worker, local files, and user-selected library folders. It must not introduce Docker, Redis, Celery, hosted accounts, default cloud sync, or required neural model downloads as normal startup dependencies. Optional external services are allowed only through explicit provider profiles or optional local tools surfaced by doctor.

Library folders are user-owned portable workspaces. A library contains source archives, PDFs, unpacked TeX, parsed documents, assets, logs, local SQLite state, exports, and notes. Provider API keys must not be stored inside library folders. On macOS, the preferred credential store is Keychain. SQLite credential fallback is only for development or platforms where OS storage is unavailable.

Generated Markdown, lecture notes, and exports may contain third-party paper content or derivative content. Exports must keep a concise provenance notice or invisible watermark that reminds users not to redistribute parsed paper content without permission. This notice must not disturb normal reading layout.

## Core Mental Model

The user thinks in libraries, papers, reading state, tasks, and notes. The app implementation thinks in article revisions, blocks, assets, translation variants, glossary terms, reader cards, jobs, and exports. The UI must bridge these models without exposing internal jargon unless it helps debugging.

A paper is shown as a readable article, not as a spreadsheet of blocks. Blocks are identity anchors for caching, translation, citations, notes, cards, and jumps, but visual layout should be continuous. Only strict bilingual mode should visibly depend on one source block matching one translation block. Source-only, translation-only, and study modes should read like a paper.

## Reader Modes

The supported reader modes are Study, Bilingual, Translation, and Source. Focus mode is deprecated and should not be reintroduced as a default mode. Pretext-style automatic text reflow is also deprecated because it made block alignment, translation expansion, and figure sizing harder to reason about.

Study is the default mode. It shows the original English article in one main column. Each paragraph can reveal its translation from a small inline control near the paragraph end. The default state should preserve article flow, not open every translation automatically. Bilingual mode shows source and translation in paired columns with the default source-to-translation ratio of 0.6 to 0.4. Translation mode shows only the target-language text in a single column. Source mode shows only the original source in a single column.

Figures, tables, equations, algorithms, titles, abstract headings, section headings, and similar environment or structure blocks are not ordinary bilingual paragraphs. They should remain centered or single-column by default. Captions may have translations, but formulas themselves are not translated. Tables may exceed the prose line width when necessary for readability.

## Reader Layout

The reader is a paper-first surface. The page background defaults to a neutral reading surface, with light mode based on `#cccccc` page background and `#000000` text, and dark mode based on `#333333` page background and `#ffffff` text. Derived surfaces may use subtle opacity, but body text contrast must remain strong. The reader should not look like a dashboard broken into cards.

The top command bar is for global reader actions. It should stay compact and avoid wrapping on ordinary laptop widths. Search belongs in the top bar. Mode switching belongs in the top bar. Translate, terms, notes, ask, export, and reading preferences should be grouped into a small reader-tools menu or compact panels, not spread as large persistent panels.

The chapter index belongs to the left side or bottom-left progress area. It must not permanently reduce the document line width. It can be overlayed, collapsed, or shown as a progress control. If term wiki is enabled, nonessential chrome such as chapter and mode overlays should collapse automatically so the paper remains stable.

Right and left side controls must not count against text line width. Source-side color marks sit at the top-left of the source paragraph region. Source-side paragraph actions sit outside the left edge of the paragraph. Translation-side marks sit outside the right edge of the translation paragraph. Card tags sit outside the paper body where possible and expand without covering the active paragraph.

## Reading Preferences

Reading preferences are product settings, not hidden constants. Users should be able to change line width, font scale, paragraph spacing, source-to-translation ratio, theme, target language, term wiki visibility, card visibility, toolbar density, and whether language switching automatically queues missing translation work. The default values should match the currently accepted reader defaults. Preferences should persist locally and apply across reader sessions.

Every optional feature that changes reading density should have an explicit on/off or intensity control. Term wiki, reader cards, sentence hover accent, automatic card extraction, native search, external evidence, glossary replacement, export inclusion of untranslated blocks, and background task notifications should be configurable. Defaults should favor low cognitive load: paper reading first, advanced panels collapsed, and no noisy inline explanations.

The canonical control surface is the Reading Preferences panel, shown both in Settings and inside the reader. Reader features that affect layout, hover UI, citations, image inspection, notices, glossary replacement, export fallback, or task-drawer auto-open must be backed by persisted local preferences rather than page-local hidden state. A feature may still have a contextual action button, but that button should update the same preference if it changes long-lived behavior.

## Batch Operations

A user with many papers must not have to open papers one by one to finish routine maintenance. Library-level batch operations are first-class product requirements. The library page should expose actions such as translate all untranslated blocks, translate selected papers, retry failed translations, parse selected unparsed papers, extract terms for selected papers, export selected papers, archive selected papers, and delete selected papers with confirmation.

The most urgent batch action is translating missing content. The library already knows each article's translation status, including translatable blocks, translated blocks, queued jobs, running jobs, and failures. The UI should turn this into a single action: queue translation for all untranslated or invalid blocks in the current library, using the selected provider, target language, glossary version, and rate limits. It should skip blocks that already have a valid current translation, avoid duplicate active jobs, and summarize how many papers, blocks, cached hits, existing jobs, and new jobs were affected.

Batch operations must be resumable and observable through the same job queue. They should not start hidden loops in the browser. If the user closes the tab, the worker should continue. If a provider is not configured, the batch action should explain the missing setting and link to Models. If many tasks are queued, the task drawer should show a compact summary by type and status first, with detailed rows loaded lazily.

## Translation

Translation is block-based and cache-based. Paragraphs, lists, figure captions, table captions, and algorithm captions are translatable. Formulas and raw mathematical expressions are not translated. Each translation job stores provider, model, target language, glossary version, context hash, content hash, validation status, usage metadata, and raw Markdown. Completed translations must survive restart.

The app has one active target-language context at a time. The library page, reader, glossary panel, term cards, export panel, and batch translation controls must all use that same active target language unless a panel explicitly states that it is overriding the default. Switching the active language changes the visible translation set and the article-level completion counters. If automatic language-switch translation is enabled, switching language queues only missing or invalid blocks for the current article with the selected provider. It must not overwrite existing variants, and it must not silently translate without a configured provider.

The system must never treat unchanged source text as a valid translation unless the block is translation-invariant, such as a short symbol-only or acronym-only block. If a model returns source text followed by translation, the source prefix should be removed before storage when that removal is safe. Invalid translation variants can remain in the database for audit, but the reader and translation status counters should only treat `ok` variants as usable.

Retranslation must create a new variant rather than overwriting the previous accepted result. Users can choose a default variant. Custom prompts are allowed at block level. Glossary changes should mark affected translations and offer batch retranslation without destroying older variants.

## Provider UX

Provider setup must not require ordinary users to know internal model IDs. User mode asks for protocol, endpoint preset when needed, and API key, then discovers available models through OpenAI-compatible or Anthropic-compatible APIs. The user selects from returned model names. Developer mode exposes base URL, custom profile labels, concurrency, rate limits, and advanced capability flags.

Provider capability controls should be honest. If a model supports streaming, answers can stream. If it supports native search, the user can enable external evidence. If it does not support native search, answers should be limited to the paper and local retrieval. The UI should not imply a feature is available when the selected provider cannot perform it.

## Terms, Glossary, And Reader Cards

Glossary and term wiki are separate systems. Glossary controls translation consistency. Term wiki and reader cards support concept understanding and note-taking. They can link visually, but they should not share database state or silently overwrite each other.

Term wiki extraction runs at article level and stores reusable cards in the library's shared card space. Cross-paper reuse is allowed only when the abbreviation exactly matches and the normalized full form exactly matches, with normalization limited to case, whitespace, hyphenation, and simple plural forms. A term with only an abbreviation should not be automatically shared.

Reader cards are anchored to relevant paragraphs. They are not global floating decorations. A paragraph may have multiple card tags, but only one card should expand at a time. Term cards default to compact tags on the left side of the paper. Question cards and answer cards can appear on the right side near the active paragraph. Expanded cards should prefer opening away from the paragraph text and should adapt to viewport edges so the full card remains visible.

Wikipedia and Wikidata are the preferred automatic source for term cards. If a stable wiki hit exists, the card should provide a concise native-language explanation and a wiki link. If no wiki hit exists, the user can ask the model to generate a card using native search when available, otherwise using only paper context. AI-generated cards should be concise, factual, editable, and clearly marked as AI-generated without pretending to have an external source link.

Card text should be paragraph-style, not long bullet lists. Cards are for quick understanding, not review scheduling. Card review, spaced repetition, and heavy knowledge graphs are outside the current product direction.

## Notes And Obsidian

Obsidian integration must reduce work rather than create another management task. Saving a paragraph should create or update one Markdown file per library in the configured vault, with one section per paper. The saved content should include source and translation together when translation exists. Re-saving the same block should update the existing block entry rather than creating duplicates.

Term wiki cards export to the library note under a `术语 Wiki` section. They should include term, abbreviation when relevant, native-language explanation, wiki link when available, or AI-generated marker when no link exists. They should not include paragraph full text, article provenance clutter, or hidden implementation metadata that Obsidian cannot parse cleanly.

Manual note cards and answer-derived cards should be editable and deletable. A concise model answer can become a knowledge card if the user chooses it. The default answer style for cards should be professional, precise, and compact.

## Question Answering

Questions can target the current block or the whole article. The answer system should prefer paper-grounded evidence. Internal evidence is represented by block references. External evidence is allowed only when the user enables native search and the selected provider supports it. External evidence metadata should be stored separately from paper evidence.

Answers should be useful to learners. They should be short enough to guide reading, not long generic lectures. A good answer says what the paragraph, formula, figure, or method means in context, what assumption matters, and what the user should check next. If the model cannot answer from the paper and native search is off, it should say so instead of inventing background claims.

## Import, Parse, And Assets

arXiv import should download the concrete source version and PDF into a self-contained bundle, then queue parse when requested. Local TeX archive import reuses the same bundle path. Markdown import creates weak document structure. PDF import saves the file and does not parse, OCR, translate, or open it by default.

Parser output must preserve stable block identity, source Markdown, source LaTeX where available, labels, captions, references, citations, assets, and manifest metadata. Compatibility fixes for common LaTeX and KaTeX gaps belong in the shared compatibility table, not in one-off frontend hacks. A parser bug discovered in one paper should become a fixture or regression whenever practical.

Images should be displayed when assets exist. Figures default to centered layout. Figure size should respect parsed metadata when available and otherwise infer narrow, single-column, double-column, or multi-panel intent conservatively. Multi-panel and side-by-side subfigures should preserve consistent panel ratios. Missing images should degrade to a structured fallback, not disappear silently.

Tables should render in an academic style. They may exceed prose width when necessary, but font size should remain close to body text. LaTeXML artifacts such as `toprule` must not appear as table data. Algorithms should preserve their original block structure and should not be translated as ordinary paragraphs.

## Library Management

The library page is the command center for many papers. Paper title click opens the reader. Archive hides or de-emphasizes an article without deleting cache. Delete requires confirmation and removes the article bundle and related cache. Translation status should be visible at article level, with clear labels for not started, translating, partial, translated, failed, and not required.

Libraries themselves should also support archive and delete. Archive keeps the library folder and cache. Delete requires strong confirmation because it can remove local data. If a library folder is externally synced, the app should avoid pretending it manages sync conflicts.

## Task Queue

Jobs are user-visible product state. The task drawer should remain responsive even with thousands of tasks. It should load summary counts first and detailed rows lazily. It should offer clear actions for pause, resume, cancel, retry failed, and clear completed or cancelled tasks. Clearing task history should not delete article data or exports unless the user explicitly asks for deletion elsewhere.

The worker owns long-running execution. UI code should enqueue work and observe progress, not perform large background loops. SSE can update summaries, but polling must remain a fallback. Job events should be compact enough that opening the task drawer does not freeze the app.

## Export

Exports must produce actual downloadable files through the browser. Supported default exports are source Markdown, translated Markdown, bilingual Markdown, lecture notes, and article bundle zip. Word, EPUB, polished PDF, and print-grade export are future work.

Export options should be explicit. Users can choose whether to include untranslated blocks, whether to use source fallback, target language, and bundle scope. Missing translations should be summarized with a useful action to queue the missing translation jobs rather than forcing the user to find them manually.

## Interface Copy

User-facing UI copy should describe actions, states, and outcomes. It should not expose design policy, language maintenance policy, technical naming history, or internal implementation tradeoffs. Product explanations belong in README or docs. Operational guidance belongs in AGENT_GUIDE or DESIGN. The reader itself should stay focused on reading.

Chinese and English are core maintained UI languages. Japanese is supported as an experimental language. Other community README files may exist as contribution entry points. UI translation contributions should start from `apps/web/src/locales/example.locale.json` and the notes in `apps/web/src/locales/README.md`, then be promoted into `apps/web/src/i18n.ts` after review. The UI may fall back to English for incomplete experimental translations, but this should not block core workflows.

## Refactor Rules

Future interaction refactors should start from user intent, not from existing component boundaries. If a user needs to do the same action across many papers or many blocks, the action belongs at library or article scope. If a feature can surprise users, it needs a setting, a preview, or an undo path. If a feature consumes provider credits, it must show scope before enqueueing. If a feature changes stored data, it must distinguish archive, delete, edit, regenerate, and export.

The default experience should remain simple: create or open a library, import papers, parse them, translate missing content in bulk, read in Study mode, open translations only when needed, ask concise questions, save useful content to Obsidian, and export files. Advanced controls should exist, but they should not become the first thing a new user has to understand.
