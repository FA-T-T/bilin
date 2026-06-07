# Product

## Register

product

## Users

Ilios serves researchers who read technical papers, keep local notes, and turn reading into writing. The primary user already has a personal file workflow: Obsidian or Typora for Markdown notes, Typst or TeX for manuscripts, and local folders for papers, figures, experiments, citations, and drafts. They want the app to respect those files instead of replacing them with a private hosted workspace.

The user may begin from a topic, a seed paper, a Zotero library, an arXiv identifier, or a local TeX package. They are technically capable and willing to choose local paths, providers, and tools, but they do not want to spend their research time wiring together arXiv search, TeX parsing, translation, note capture, citation management, and manuscript drafting by hand. They value control, provenance, and low operating cost more than hosted collaboration or one-click automation.

## Product Purpose

Ilios is a macOS local-first research reading and writing workbench. It imports papers from arXiv, Zotero metadata, local TeX packages, Markdown files, or existing Bilin libraries; parses TeX into structured reading blocks; renders text, formulas, figures, tables, citations, translations, and notes; then connects those reading artifacts to the user's local Markdown, Typst, and TeX writing files.

The core experience runs from reading to notes to writing. A user should be able to open a paper, understand the paper through a reader-centered interface, generate a paper-specific reading outline, mark and save important blocks into Obsidian Markdown, and carry selected claims, citations, equations, and questions into a Typst or TeX manuscript project. Typora compatibility comes from opening the same Markdown files, not from a separate Typora-specific format.

Agent assistance is present throughout the workflow, but it is not the product's center. Agents help find candidate papers, propose a reading path, generate a per-paper mastery outline, explain difficult blocks, suggest related work, assemble notes, and propose next writing steps. They do not silently read on the user's behalf, overwrite notes, install research skills, download papers, import libraries, or edit Typst and TeX drafts without explicit user confirmation.

Success means a researcher can start from a topic or a paper, find related papers, read the chosen paper in a structured local reader, see what they need to master for that specific paper, save useful material into their Obsidian vault, and continue into a local writing project without losing citation, source-block, or provenance links. The product must not require accounts, hosted sync, Docker, Redis, Celery, mandatory model downloads, or surrendering the user's file system to a cloud service.

## Brand Personality

Quiet, scholarly, precise.

The interface should feel like a compact research desk that extends into a writing desk. It should be dense enough for real work, calm enough for long reading sessions, and explicit about local state. It should prefer expert confidence over decorative drama. The Chinese identity of 衔牍 should remain visible through the name and mark, but the UI should not rely on ornamental cultural styling.

The tone should treat the user as the researcher. Agent output should read as a proposal, outline, or patch that the user can inspect and accept. The product should never imply that a generated summary is equivalent to the user's understanding.

## Anti-references

Do not make Ilios feel like a SaaS dashboard, a marketing landing page, a generic file manager, a chat-first AI assistant, or a static mockup of a reference screen. Avoid account-first onboarding, cloud-sync language, decorative card grids, giant hero metrics, loud gradients, generic AI assistant chrome, and separate mental modes for reading, notes, and writing.

Do not make the library into a nested document-management maze. The reader must not bury translation, provider state, tasks, notes, writing links, research plans, and paper-grounded questions behind unrelated navigation. Do not turn Agent into a one-click autopilot that hides what was searched, downloaded, written, or changed. Do not automatically overwrite Obsidian, Typst, or TeX files.

## Design Principles

1. Keep the paper selected, the reading position stable, and the next useful note or writing action close to the reading surface.
2. Treat notes and writing as continuations of reading, not as exports after reading is finished.
3. Preserve local-first trust: every provider, task, file, cache, note, skill, action plan, and writing patch should read as user-controlled local state.
4. Use Agent as a research copilot. It may plan, suggest, search, explain, draft, and prepare patches, but user confirmation is required before downloads, imports, skill installation, file writes, or manuscript edits.
5. Make every paper-specific reading outline actionable. The outline should describe what the user needs to master in that paper, not produce a generic summary template.
6. Keep external file ownership clear. Obsidian Markdown is the first v1 note target, Typora opens the same Markdown files, and Typst or TeX projects remain linked local writing projects rather than private Bilin documents.

## Product Contracts

`ReadingOutline` represents the per-paper mastery outline. It is generated from one concrete article revision and should identify the definitions, assumptions, methods, equations, evidence, limitations, and follow-up questions the user needs to understand.

`NoteBridge` represents the path from a reader block to an external Markdown note. It stores the target vault, target file, block anchor, callout type, tags, source and translation payloads, pending patch state, and provenance.

`WritingProject` represents a linked Typst or TeX project. It stores the local project root, main manuscript file, bibliography or citation file, accepted insertions, pending writing patches, and source-block provenance.

`ResearchSkill` represents an installable and callable research capability. It records source, version, permissions, input and output shape, supported tasks, and whether it has been enabled by the user.

`AgentActionPlan` represents any Agent-proposed action that may write files, install skills, download papers, import a library, call external tools, or modify a manuscript. It must be visible and accepted before execution.

## Accessibility & Inclusion

Target WCAG AA contrast for text and controls. Preserve keyboard focus, visible selection states, reduced-motion alternatives, and non-color-only status cues. The reading surface must remain stable while rails, tools, note bridges, writing docks, and task panels open. Text must fit at desktop, tablet, mobile, and e-ink-friendly widths.

Research assistance must stay inspectable for users who cannot rely on visual scanning alone. Agent proposals, file patches, skill permissions, and citations need readable labels, keyboard navigation, and text alternatives. The product should support long sessions without forcing attention-grabbing animations or chat interruptions.
