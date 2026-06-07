---
name: "Ilios / 衔牍 Research Workbench"
description: "A compact local-first macOS workbench that connects paper reading, Obsidian Markdown notes, research planning, and Typst or TeX writing with confirmed Agent assistance."
colors:
  background-light: "#f5f5f2"
  background-dark: "#0f1213"
  elevated-light: "#ffffff"
  elevated-dark: "#171a1c"
  panel-light: "#ffffff"
  panel-dark: "#171a1c"
  panel-muted-light: "#f8f8f5"
  panel-muted-dark: "#1f2426"
  spine-light: "#ffffff"
  spine-dark: "#141719"
  border-light: "#deded8"
  border-dark: "#303638"
  border-strong-light: "#c6c6bd"
  border-strong-dark: "#434a4d"
  text-light: "#171717"
  text-dark: "#f2f2ed"
  muted-light: "#62615b"
  muted-dark: "#b7bbb8"
  faint-light: "#85837b"
  faint-dark: "#8d9490"
  accent-light: "#007a73"
  accent-dark: "#31d7c5"
  accent-strong-light: "#005f5a"
  accent-strong-dark: "#7beadc"
  coral-light: "#a84b2d"
  coral-dark: "#ff9e7f"
  amber-light: "#94610f"
  amber-dark: "#f4c15d"
  link-light: "#125f8f"
  link-dark: "#8bc9ff"
typography:
  display:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei UI", "Microsoft YaHei", sans-serif'
    fontSize: "clamp(1.72rem, 2.6vw, 2.8rem)"
    fontWeight: 680
    lineHeight: 1.04
    letterSpacing: "0"
  headline:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei UI", "Microsoft YaHei", sans-serif'
    fontSize: "clamp(1.22rem, 1.7vw, 1.56rem)"
    fontWeight: 680
    lineHeight: 1.2
    letterSpacing: "0"
  title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei UI", "Microsoft YaHei", sans-serif'
    fontSize: "1.1rem"
    fontWeight: 720
    lineHeight: 1.28
    letterSpacing: "0"
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei UI", "Microsoft YaHei", sans-serif'
    fontSize: "0.94rem"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "0"
  reader:
    fontFamily: '"Songti SC", "STSong", "Noto Serif CJK SC", "New York", Georgia, serif'
    fontSize: "16.32px"
    fontWeight: 400
    lineHeight: 1.58
    letterSpacing: "0"
  label:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", sans-serif'
    fontSize: "0.74rem"
    fontWeight: 650
    lineHeight: 1.25
    letterSpacing: "0"
rounded:
  xs: "4px"
  sm: "6px"
  md: "8px"
  mark: "10px"
  pill: "999px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "14px"
  xl: "22px"
  page-x: "clamp(12px, 2.5vw, 32px)"
  page-y: "clamp(18px, 2vw, 28px)"
components:
  button-primary:
    backgroundColor: "{colors.accent-light}"
    textColor: "{colors.background-light}"
    rounded: "{rounded.md}"
    height: "34px"
    padding: "0 12px"
  button-subtle:
    backgroundColor: "{colors.panel-light}"
    textColor: "{colors.muted-light}"
    rounded: "{rounded.md}"
    height: "34px"
    padding: "0 10px"
  input-default:
    backgroundColor: "{colors.elevated-light}"
    textColor: "{colors.text-light}"
    rounded: "{rounded.md}"
    height: "34px"
    padding: "0 12px"
  panel:
    backgroundColor: "{colors.panel-light}"
    textColor: "{colors.text-light}"
    rounded: "{rounded.md}"
    padding: "clamp(16px, 2vw, 22px)"
  rail-tile:
    backgroundColor: "{colors.panel-light}"
    textColor: "{colors.text-light}"
    rounded: "{rounded.md}"
    padding: "10px"
  chip-status:
    backgroundColor: "{colors.panel-muted-light}"
    textColor: "{colors.muted-light}"
    rounded: "{rounded.pill}"
    padding: "3px 8px"
---

# Design System: Ilios / 衔牍 Research Workbench

## 1. Overview

**Creative North Star: "From Reading Desk To Writing Desk"**

Ilios is a local-first macOS research workbench. The interface keeps the paper, reading position, Obsidian Markdown notes, research plan, and Typst or TeX writing project in one visible workspace. It should feel quiet, scholarly, precise, and file-aware. The user is doing research; Agent support is a tool beside the work, not a replacement for the work.

The system is product UI. It uses familiar macOS patterns, one-pixel borders, compact rails, stable reading surfaces, and subdued state color. The design is not a marketing surface and not a chat-first AI shell. It should not dramatize the product with hero sections, loud gradients, decorative card grids, or generic assistant chrome.

The accepted topology is a compact reading-to-writing shell: library and paper sources on the left, the reader canvas in the center, and a right-side work rail that can switch between Note Bridge, Research Plan, Writing Dock, tasks, provider state, translation, questions, and exports. The paper canvas remains the anchor. Notes and writing tools appear near the source block they came from.

**Key Characteristics:**

- Local-first state is explicit: libraries, files, jobs, providers, translations, notes, writing projects, skills, action plans, and exports read as user-controlled artifacts.
- The reader is the center. Rails and overlays may collapse, but the paper position must stay stable while notes, plans, and writing patches open.
- Obsidian Markdown is the first v1 note target. Typora opens the same Markdown files. Typst and TeX are linked writing projects, not hidden Bilin-owned documents.
- Agent proposals are inspectable. They appear as outlines, candidate lists, action plans, or patches with clear accept and reject paths.
- Every visible control should update local UI state, persist preference state, call an existing mutation, or prepare a confirmed action plan.

## 2. Colors

The palette remains a restrained dual-theme workbench: cool neutral surfaces, compact chrome, a teal reading accent, and small amber or coral semantic notes. The palette should not become a multi-color productivity dashboard just because research planning exists.

### Primary

- **Research Teal** (`#007a73` light, `#31d7c5` dark): Primary actions, selected rows, active reader mode, current block, progress, focus rings, accepted note links, and live local state. Use it sparingly. It should identify current work, not decorate the page.
- **Deep Teal** (`#005f5a` light, `#7beadc` dark): Strong accent text, selected labels, high-emphasis status copy, and confirmed local file links.

### Secondary

- **Local Coral** (`#a84b2d` light, `#ff9e7f` dark): Destructive, archival, conflict, or interruption-sensitive state. Use it for rejected patches, file conflicts, unsafe skill permissions, and failed write actions.
- **Citation Amber** (`#94610f` light, `#f4c15d` dark): Citation, bibliography, reading-outline checkpoints, glossary, warning, and scholarly reference cues.

### Tertiary

- **Reference Link Blue** (`#125f8f` light, `#8bc9ff` dark): Inline links, arXiv links, external evidence, writing project paths, Zotero references, and citation hover states.

### Neutral

- **Desk Background** (`#f5f5f2` light, `#0f1213` dark): App body and full-screen workbench background.
- **Paper Surface** (`#ffffff` light, `#171a1c` dark): Reader canvas, panels, task rows, form surfaces, and default containers.
- **Muted Panel** (`#f8f8f5` light, `#1f2426` dark): Secondary tool surfaces, pending patches, advanced options, skill discovery results, and low-priority form regions.
- **Workbench Spine** (`#ffffff` light, `#141719` dark): Header, rails, reader command center, and collapsed rail handles.
- **Ink** (`#171717` light, `#f2f2ed` dark): Primary text.
- **Desk Muted** (`#62615b` light, `#b7bbb8` dark): Secondary text, metadata labels, and inactive controls.
- **Desk Faint** (`#85837b` light, `#8d9490` dark): Table headers, timestamps, subtle counters, and tertiary labels.
- **Hairline Border** (`#deded8` light, `#303638` dark): Default structural border.
- **Strong Border** (`#c6c6bd` light, `#434a4d` dark): Empty-state dashed borders, selected structure, and file conflict boundaries.

### Named Rules

**The Functional Accent Rule.** Teal marks a current action, selected object, accepted local link, progress, focus, or live state. It is not background decoration.

**The Chrome Is Quiet Rule.** Rails, headers, drawers, command bars, note bridges, and writing docks use `--bilin-spine` or `--bilin-panel` with one-pixel borders. Do not add glass blur, gradient fills, or heavy shadows to chrome.

**The File State Rule.** File paths, vault links, manuscript links, pending patches, accepted patches, and conflicts need distinct labels and status cues. Do not rely on color alone.

**The Reader Token Rule.** Reader translation surfaces use `--bilin-reader-translation-*` tokens. Reader block highlights and swatches use `--bilin-reader-annotation-*` tokens. Note and writing patches may reuse those meanings but should not introduce raw hex values in component rules.

## 3. Typography

**Display Font:** system UI display stack with Chinese UI fallbacks.
**Body Font:** system UI text stack with `PingFang SC`, `Hiragino Sans GB`, `Noto Sans CJK SC`, and Microsoft YaHei fallbacks.
**Reader Font:** Songti and CJK serif stack for paper headings and long-form reader content.
**Label/Mono Font:** Mantine monospace or native monospaced system font only for note patches, file paths, TeX, Typst, code-like exports, and debug-adjacent text.

**Character:** The product UI uses one familiar sans family for controls, navigation, tables, file states, tasks, and Agent action plans. Serif appears only inside the paper canvas and study-card prose. Monospace appears where the content is literally file, code, TeX, Typst, or patch text.

### Hierarchy

- **Display** (680, `clamp(1.72rem, 2.6vw, 2.8rem)`, 1.04): Library and settings page titles. Keep letter spacing at `0`.
- **Headline** (680, `clamp(1.22rem, 1.7vw, 1.56rem)`, 1.2): Reader title blocks, article structural headings, research plan heads, and compact page section heads.
- **Title** (720, `1.1rem`, 1.28): Rail tiles, panel headings, task groups, selected-paper summaries, and writing project summaries.
- **Body** (400, `0.94rem`, 1.55): Product copy, table cells, messages, empty states, Agent proposals, and form descriptions.
- **Reader** (400, `16.32px`, about 1.58): Parsed paper body. Source and translation sizes may differ slightly through reader preferences.
- **Label** (650, `0.74rem`, 1.25): Table headers, metadata, compact rail labels, badges, tool captions, and skill permission labels. Use uppercase only for short technical markers.

### Named Rules

**The UI Sans Rule.** Do not use display or decorative fonts for labels, buttons, data, forms, tabs, task rows, skill rows, or settings.

**The Reader Exception Rule.** Serif typography belongs inside the paper canvas and study-card prose. It should not leak into global navigation, Agent panels, or product controls.

**The Writing Code Rule.** TeX, Typst, BibTeX, Markdown anchors, and patch previews use monospaced text only when the user is inspecting the literal file content.

**The Stable Scale Rule.** Product UI should prefer fixed rem sizes. Existing clamp titles are allowed for page titles and reader headings only.

## 4. Elevation

Ilios is flat by default. Depth comes from tonal layering, one-pixel borders, sticky placement, and collapsible rails. Shadows are reserved for transient overlays, citation popovers, term popovers, file conflict popovers, and the Kindle page frame. Resting panels, task rows, note bridges, writing docks, cards, rails, and command bars should have `box-shadow: none`.

### Shadow Vocabulary

- **Overlay Shadow** (`0 16px 40px var(--bilin-shadow)`): Term definitions and compact overlays that float over reading content.
- **Popover Shadow** (`0 18px 44px var(--bilin-shadow)`): Citation popovers, file conflict details, and dropdown-like evidence panels.
- **Kindle Page Shadow** (`inset 0 0 0 1px ... , 0 16px 42px ...`): E-ink-inspired page framing only.
- **Micro Tag Shadow** (`0 6px 14px light-dark(rgba(0,0,0,0.08), rgba(0,0,0,0.28))`): Reader card tags where small anchors need separation from paper text.

### Named Rules

**The Flat-At-Rest Rule.** Default panels, rails, rows, cards, note bridges, writing docks, and drawers do not cast shadows. Use border and background first.

**The Overlay Earns Shadow Rule.** A shadow means an element floats over content and may occlude reading. Do not use shadows as decoration.

## 5. Components

### Buttons

- **Shape:** 8px radius for normal actions, 999px only for compact badges or progress pills.
- **Primary:** Teal background, high-contrast text, compact 34px height in chrome and rail contexts.
- **Hover / Focus:** State changes use 160ms transitions. Focus adds teal-tinted border and a 3px soft ring.
- **Secondary / Ghost:** Subtle buttons use panel surfaces, muted text, and teal-soft active states. Icon-only actions use one icon family.
- **Agent Actions:** Agent proposals use explicit action buttons: Preview plan, Accept patch, Reject patch, Download paper, Install skill, Import paper, Insert into draft. Do not label them "OK" or "Run" when the action writes files.
- **Loading / Disabled:** Loading and disabled states must explain the missing dependency, permission, provider, vault, or writing project in nearby copy or status.

### Chips

- **Style:** Badges and status chips use light variants, pill radii, compact padding, and semantic colors only when status needs it.
- **State:** Selected chips use teal-soft background and strong text. Inactive chips stay muted.
- **File and Skill Chips:** Obsidian vault, Typst project, TeX project, skill source, and permission chips should remain quiet. Use labels and icons before saturated color.

### Cards / Containers

- **Corner Style:** 8px radius for repeated rows, task rows, rail tiles, modals, tool panels, note patches, skill rows, and writing patch rows. 0px radius for full-height shell regions and structural paper containers.
- **Background:** Use `--bilin-panel` for primary containers and `--bilin-panel-muted` for secondary tool regions.
- **Shadow Strategy:** No shadow at rest. Overlays follow the Elevation section.
- **Border:** 1px `--bilin-panel-border` by default. Use `--bilin-panel-border-strong` for dashed empty states, selected structure, or file conflict review.
- **Internal Padding:** 10 to 14px for rails and task rows, `clamp(16px, 2vw, 22px)` for page panels.

### Inputs / Fields

- **Style:** 8px radius, `--bilin-bg-elevated` background, 1px border, system sans, compact height.
- **Focus:** Border shifts toward teal and adds `0 0 0 3px var(--bilin-accent-soft)`.
- **Local Paths:** Vault paths, project roots, main TeX files, main Typst files, and bibliography paths should be selectable, copyable, and visibly local.
- **Error / Disabled:** Use semantic states with explicit recovery. Error text should not depend on red alone.

### Navigation

- **Top Navigation:** Library surfaces use a compact header with centered brand lockup, left language or mode switcher, and right utility controls.
- **Reader Navigation:** Reader routes remove the global header. The reader command center owns library return, reading mode, preferences, paper controls, note bridge state, research plan state, and writing project state.
- **Left Rails:** Left rails choose libraries, Zotero sources, arXiv candidates, local folders, or nearby papers. The left side answers what the user is reading.
- **Right Work Rail:** The right rail switches between Note Bridge, Research Plan, Writing Dock, Ask, Translate, Terms, Tasks, Providers, and Export. The right side answers what the user is doing with the reading.
- **Mobile / Narrow Width:** Collapse rails before shrinking the paper. Labels may hide behind icons only when tooltips and accessibility labels remain clear.

### Signature Component: Reader Canvas

The reader canvas is the stable center of the app. It renders structured blocks from TeX, Markdown, or imported bundles, with equations, figures, tables, citations, translations, paragraph markers, and source anchors. It should support Study, Focus, Bilingual, Translation, and Source modes without making notes or Agent panels cover the current reading position.

### Signature Component: Note Bridge

Note Bridge connects selected reader blocks to external Markdown notes. It shows the active Obsidian vault, current note file, heading path, block anchor, callout type, tags, source text, translation text, and pending patch state. Saving a block creates or updates a Markdown patch with provenance. Accepting the patch writes to the external file. Rejecting it leaves the source block untouched.

Typora compatibility comes from opening the same Markdown note file. Do not create a Typora-only note model.

### Signature Component: Research Plan

Research Plan is the planning surface for topic-to-reading and paper-to-related-work workflows. It shows the user's topic or seed paper, candidate papers, why each candidate matters, status of downloaded or parsed papers, related paper clusters, and the per-paper `ReadingOutline`. It should separate article-grounded evidence from external search results.

Research Plan may call enabled skills for arXiv search, literature review, related work, paper reading, experiment planning, and writing, but every skill invocation that downloads, installs, imports, or writes files must first appear as an `AgentActionPlan`.

### Signature Component: Writing Dock

Writing Dock connects reading artifacts to a local Typst or TeX project. It shows project root, main manuscript file, bibliography file, current section target, candidate citations, accepted snippets, and pending writing patches. It can prepare insertion patches for definitions, claims, related work notes, equations, citations, and TODOs. It must not silently rewrite a manuscript.

### Signature Component: Research Skill Registry

Research Skill Registry lists installed, discovered, and suggested research skills. It records source, version, permissions, input shape, output shape, and supported tasks. It may automatically discover and download candidate skills into an isolated cache, but enabling a skill and letting it write files or call external tools requires user confirmation. Skill rows should make permission and provenance more visible than branding.

### Signature Component: Action Plan Drawer

Action Plan Drawer is the confirmation surface for Agent work. It lists each proposed action, affected files, network calls, downloads, imports, skills, provider calls, and expected outputs. It has clear accept, reject, and inspect controls. It should be compact enough for routine use and explicit enough that a user can audit what will happen before it happens.

### Signature Component: Task Drawer And Rail

Tasks are product state. Task rows show queued, running, paused, completed, failed, and cancelled work with compact badges, clear messages, and explicit controls for pause, resume, cancel, retry, or clear. Clearing task history must never imply deleting papers, translations, notes, writing patches, skills, or exports.

## 6. External File Strategy

Obsidian Markdown is the first v1 note target. On first setup, the user should choose an Obsidian vault or confirm a proposed default. The app may index target files, create note files, and write accepted patches, but the Markdown file remains user-owned.

Typora is supported through the same Markdown file. The product should expose "Open in Typora" only when Typora is available or the user has configured it. It should not duplicate note storage for Typora.

Typst and TeX are linked writing projects. V1 should support choosing a project root, identifying the main manuscript file, identifying a bibliography file when present, and preparing insert patches. Full bidirectional synchronization and conflict-heavy live editing are out of scope for the first writing bridge.

Bilin stores indexes, anchors, patch records, task state, skill metadata, and provenance. It should not swallow external notes or manuscripts into a private database as the source of truth.

## 7. Do's and Don'ts

### Do:

- **Do** keep the selected paper, current block, current note target, and current writing target visible near the reading surface.
- **Do** use `--bilin-accent` for primary action, selection, accepted local links, progress, focus, and live state only.
- **Do** keep panels flat at rest with 1px borders and 8px radii.
- **Do** preserve local-first trust by naming providers, files, jobs, caches, notes, writing projects, skills, and exports as user-controlled local state.
- **Do** make Agent proposals inspectable as outlines, candidate lists, action plans, and patches.
- **Do** keep reading, note capture, research planning, and writing in one workspace.
- **Do** maintain WCAG AA contrast, visible focus, reduced-motion behavior, and non-color-only status cues.
- **Do** collapse rails before shrinking or destabilizing the paper canvas.

### Don't:

- **Don't** make Ilios feel like a SaaS dashboard, marketing landing page, generic file manager, chat-first AI assistant, or static mockup.
- **Don't** use account-first onboarding, cloud-sync language, or hosted-collaboration assumptions.
- **Don't** bury note bridge, writing project state, task state, provider state, skills, exports, or paper-grounded questions behind unrelated navigation.
- **Don't** split reading, notes, and writing into separate mental modes.
- **Don't** create decorative card grids, giant hero metrics, loud gradients, gradient text, glassmorphism, or generic AI assistant chrome.
- **Don't** turn Library into a nested document-management maze. It should remain paper-first and writing-aware.
- **Don't** use thick colored side stripes on cards, rows, callouts, or alerts. Structural dividers should be neutral and serve layout.
- **Don't** introduce decorative motion. Motion should communicate state and respect reduced-motion preferences.
- **Don't** invent new control vocabularies when native macOS controls, Mantine patterns, and existing CSS already define the interaction language.
- **Don't** let Agent write, download, install, import, or revise without a visible action plan and user acceptance.
