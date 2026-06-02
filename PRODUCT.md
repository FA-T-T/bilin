# Product

## Register

product

## Users

Ilios serves researchers who read English research papers across languages, keep many papers in local collections, and need translation, citation, notes, and export work to stay tied to the paper they are reading. The primary user is a technically capable researcher working on a desktop, laptop, tablet, or local network e-ink device. They value control over files, provider choice, and low operating cost more than hosted collaboration.

## Product Purpose

Ilios is a local-first paper reading workbench. It imports papers from arXiv sources or local LaTeX packages, parses structure, renders text, formulas, figures, tables, citations, translations, notes, cards, and exports, then keeps all artifacts in a user-selected local folder.

Success means a researcher can choose a paper, understand what has already been parsed or translated, continue reading without losing context, ask grounded questions, save concise study artifacts, and watch local or model-backed jobs without leaving the reading workflow. The product must not require accounts, hosted sync, Docker, Redis, Celery, or mandatory model downloads.

## Brand Personality

Quiet, scholarly, precise.

The interface should feel like a compact research desk: dense enough for real work, calm enough for long reading sessions, and explicit about local state. It should prefer expert confidence over decorative drama. The Chinese identity of 衔牍 should remain visible through the name and mark, but the UI should not rely on ornamental cultural styling.

## Anti-references

Do not make Ilios feel like a SaaS dashboard, a marketing landing page, a file manager with hidden reading actions, or a static mockup of a reference screen. Avoid account-first onboarding, cloud-sync language, decorative card grids, giant hero metrics, loud gradients, generic AI assistant chrome, and separate mental modes for reading versus translation.

The library must not become a nested document-management maze. The reader must not bury translation, provider state, tasks, notes, and paper-grounded questions behind unrelated navigation.

## Design Principles

1. Keep the paper selected, the current work visible, and the next useful action close to the reading surface.
2. Treat translation as part of reading, not a separate product area.
3. Preserve local-first trust: every provider, task, file, cache, note, and export should read as user-controlled local state.
4. Use density with discipline. Compact controls are acceptable when hierarchy, focus, and labels remain clear.
5. Make every interactive control real. A visible action must update local UI state, persist preference state, or call an existing API mutation.

## Accessibility & Inclusion

Target WCAG AA contrast for text and controls. Preserve keyboard focus, visible selection states, reduced-motion alternatives, and non-color-only status cues. The reading surface must remain stable while rails, tools, and task panels open. Text must fit at desktop, tablet, mobile, and e-ink-friendly widths.
