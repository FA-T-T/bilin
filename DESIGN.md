# Ilios / 衔牍 Workbench Design

This document is the current design contract for Ilios. It replaces the older page-separated contract with a reference-image-driven workbench model. The implementation should feel like one local research desk rather than a collection of unrelated admin pages.

## Core Decision

Ilios remains a lightweight local-first paper system. It still uses React, TypeScript, FastAPI, SQLite, a local worker, local files, and optional user-configured model providers. It must not introduce accounts, sync, Docker, Redis, Celery, or required model downloads. The redesign changes information architecture and interaction density, not the technical boundary.

The reference screen establishes the accepted topology. A dark compact shell frames the app. The left side organizes libraries, sources, collections, tags, and storage. The center-left column lists papers with search, filtering, sort, import, translation state, and reading progress. The center surface is the article reader. The right side exposes tasks and local model/provider status. The user should always understand what paper is selected, what work is running, and what action is available next.

## Top Navigation

The home navigation is deliberately smaller than the reader navigation. On the Library surface, the product logo and Library entry are one control: clicking the 衔牍 mark returns to the article list. The old top-level Reading, Notes, and Study entries are removed because they describe work that now happens inside a selected paper. Settings, task status, and theme remain global utility controls.

When a paper is open, the home navigation disappears. The reader owns its own command band. Its left side shows the current library name, such as Papers, and returns to that library. Its center shows Ilios / 衔牍 · Research Paper Reader. Its right side contains only reading mode and reading preferences. Full-text search, task buttons, theme buttons, and reader-tool menus do not belong in this band.

Library must not behave like a nested document-management page. It displays article rows and lets the user filter, select, import, translate missing content, archive, or delete with confirmation. Opening a paper is a deliberate reader action, not the meaning of Library itself. If a row is clicked inside Library, the row becomes the selected row and exposes a compact action strip; it should not silently navigate away.

Read & Translate owns all reading modes, target language, provider choice, translation queueing, retranslation, glossary replacement, and reader preferences. Translation is not a separate mental mode. It is the work required to make the reader useful.

Notes & Study owns paper-grounded chat, quick paragraph questions, reader cards, term wiki, note patch generation, template editing, Obsidian export, and study artifacts. A note and a study card are the same learning loop: the user notices something, asks or edits, then saves a compact artifact.

## Library Interaction

Library is the fastest path for handling many papers. It should open with a selected active library when one exists. If no library exists, the same surface shows the create-library form and a calm empty state. The user should not have to go through a library index, then a library detail page, then an article page just to see papers.

The library list is article-first. Each row shows title, external id, source, parse status, translation status, translated block count, total blocks, asset count, reading progress, and updated time. Rows have hover and focus states. Selecting a row shows a compact preview with status, provenance, progress, and explicit actions such as Read, Translate missing, Archive, and Delete. Read is the only action that enters the reader.

Import stays lightweight. The primary import action is a button near the article list. It opens inline or modal controls for arXiv and local files. Advanced options are collapsed by default. Import and parse work must go through the task queue, not a hidden browser loop.

Batch translation stays visible but bounded. The user chooses provider and target language, sees how many papers and blocks are missing, then queues work. If no provider exists, the control explains the missing dependency and points to Settings. A queued batch opens the task rail only when the user has task notifications enabled.

## Reader And Translation

The reader follows the reference image but resolves the working layer more explicitly. It is a three-part mosaic, not a document with floating accessories. The left rail switches between papers in the same library. The center remains the paper canvas and is the only non-collapsible reading surface. The right rail contains task status, model/provider selection, and paper-grounded questioning. Every rail except the article canvas can collapse without changing the current reading position.

Reader and Translate are one workspace. Provider, target language, translate paper, retranslate block, glossary terms, and translation variants must be available without leaving the reader. Translation jobs target paragraphs, lists, and captions. Formulas are never translated as formulas. Existing valid translations are reused unless the user explicitly requests retranslation.

Reader controls must be dense but not noisy. Mode and preferences belong in the compact command band; work actions belong beside the paper. The paper body must stay stable while tools open. Tasks, provider selection, paper chat, translation, glossary, notes, and export appear as sibling tiles in the right rail. All right-rail tiles are collapsible, and only the question tile is expanded by default because asking the current paper is the most time-sensitive interaction while reading.

## Notes And Study

Notes and Study are one workspace because both are about turning reading into reusable understanding. The merged panel should include paper chat, current-block questions, reader cards, term wiki, lecture-note patch generation, template editing, and Obsidian export. The user should be able to ask a question, turn the answer into a card, edit the card, and export it without switching product areas.

Study artifacts must stay compact. Cards are paragraph-anchored and expandable, not a separate spaced-repetition product. Note patches are editable before acceptance. Obsidian export updates stable Markdown entries rather than creating duplicates. External evidence is allowed only when provider capability and user preference allow it.

## Task And Provider Rail

Tasks are visible product state. The right rail summarizes queued, running, paused, completed, and failed work, then shows recent task rows lazily. Pause, resume, cancel, retry, and clear actions must be explicit. Clearing task history must not delete papers, translations, notes, or exports.

Task scheduling reflects the actual resource boundary. Article preparation is first priority: arXiv source acquisition, TeX parsing, local embedding refresh, local export, and automatic reader-card extraction run in the local preparation lane. Model work is second priority: block translation and generated reader-card work run in the model lane. A translation batch with many queued blocks must never prevent a newly requested article parse from starting; at most, the currently running model call continues while the local lane parses the new article.

Provider status belongs near tasks because both define whether work can proceed. The rail may show configured local or API providers, current model labels, running state when known, and rate-limit hints. It should never imply that a missing provider is ready. Provider setup remains in Settings.

## Visual System

The accepted visual direction is a compact dark workbench with a subtle teal accent, crisp one-pixel borders, 8px-or-smaller radii, readable paper typography, and quiet density. Cards are for repeated rows, task rows, modal panels, and tool surfaces. Page sections should not become decorative floating cards. Text must fit inside controls at desktop and mobile widths.

The product mark is an abstract bundle of writing slips joined by a golden clasp. It represents 衔牍 as carrying structured text back to the reader's desk without relying on a literal Chinese character that would collapse at favicon size. The same SVG mark is used in the app header and browser favicon so the product identity stays consistent across Library, Reader, and Settings.

The library and reader should preserve the reference hierarchy. Navigation is top and compact. Library organization is left. Article rows are center-left. Reading is central and paper-like. Tasks and providers are right. The UI may collapse rails on smaller screens, but it must preserve the same workflow order: choose article, read or translate, study or note, observe tasks.

## Interaction Contract

Every visible control that looks interactive must update real local UI state or call an existing API mutation. Library search filters rows. Sort changes article order. Row selection changes selected state. Import controls submit jobs. Translate controls enqueue jobs. Reader mode changes layout. Right-rail tiles expand and collapse in place. Notes can be generated, edited, accepted, rejected, or exported. Task controls call pause, resume, cancel, or clear. Theme and reader preferences persist locally.

The design is complete only when the browser proves the main interactions are live. A static recreation of the reference image is not acceptable. The implementation should be light enough to start quickly, practical enough for a researcher with many papers, and direct enough that the next useful action is visible without explanation text.
