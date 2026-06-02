---
name: "Ilios / 衔牍 Workbench"
description: "A compact local-first research reading workbench for papers, translation, notes, tasks, and exports."
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

# Design System: Ilios / 衔牍 Workbench

## 1. Overview

**Creative North Star: "The Compact Research Desk"**

Ilios is a local-first research desk. The interface keeps papers, translation, study artifacts, provider state, and background work in one visible workbench. It should feel quiet, scholarly, and precise, with enough density for researchers who read many papers and enough restraint for long sessions.

The system is a product UI. It uses familiar controls, one-pixel borders, compact rails, stable reading surfaces, and subdued state color. The design is not a marketing surface. It should not dramatize the product with hero sections, loud gradients, decorative card grids, or generic AI assistant chrome.

The accepted topology is a compact shell: library organization on the left, article rows or paper canvas in the center, and task, provider, translation, question, note, and export controls near the reading surface. Translation is part of reading. Notes and study cards are part of the same learning loop.

**Key Characteristics:**

- Local-first state is explicit: libraries, files, jobs, providers, translations, notes, and exports read as user-controlled artifacts.
- The reader is the anchor. Rails and overlays may collapse, but the paper position must stay stable.
- Density is allowed when hierarchy and labels remain clear.
- Accent color is rare and functional. It marks action, selection, progress, focus, and state.
- Every visible control should update local UI state, persist preferences, or call an existing API mutation.

## 2. Colors

The palette is a restrained dual-theme workbench: cool neutral surfaces, dark compact chrome, a teal reading accent, and small amber or coral semantic notes.

### Primary

- **Research Teal** (`#007a73` light, `#31d7c5` dark): Primary actions, selected rows, progress bars, focus rings, active tabs, and reader annotations. Use it sparingly. It should identify current work, not decorate the page.
- **Deep Teal** (`#005f5a` light, `#7beadc` dark): Strong accent text, compact page eyebrows, selected labels, and high-emphasis status copy.

### Secondary

- **Local Coral** (`#a84b2d` light, `#ff9e7f` dark): Destructive, archival, or interruption-sensitive state. It should appear as a semantic cue, not as a brand color.
- **Citation Amber** (`#94610f` light, `#f4c15d` dark): Citation, glossary, warning, and scholarly reference cues.

### Tertiary

- **Reference Link Blue** (`#125f8f` light, `#8bc9ff` dark): Inline links, article-title hover states, xrefs, and externally grounded citations.

### Neutral

- **Desk Background** (`#f5f5f2` light, `#0f1213` dark): App body and full-screen workbench background.
- **Paper Surface** (`#ffffff` light, `#171a1c` dark): Panels, cards, task rows, form surfaces, and default containers.
- **Muted Panel** (`#f8f8f5` light, `#1f2426` dark): Secondary tool surfaces, empty states, batch-action strips, advanced options, and low-priority form regions.
- **Workbench Spine** (`#ffffff` light, `#141719` dark): Header, rails, reader command center, and collapsed rail handles.
- **Ink** (`#171717` light, `#f2f2ed` dark): Primary text.
- **Desk Muted** (`#62615b` light, `#b7bbb8` dark): Secondary text, meta labels, and inactive controls.
- **Desk Faint** (`#85837b` light, `#8d9490` dark): Table headers, timestamps, subtle counters, and tertiary labels.
- **Hairline Border** (`#deded8` light, `#303638` dark): Default structural border.
- **Strong Border** (`#c6c6bd` light, `#434a4d` dark): Empty-state dashed borders, higher-contrast dividers, and selected boundaries.

### Named Rules

**The Functional Accent Rule.** Teal marks a current action, selected object, progress, focus, or live state. It is not background decoration.

**The Chrome Is Quiet Rule.** Rails, headers, drawers, and command bars use `--bilin-spine` and 1px borders. Do not add glass blur, gradient fills, or heavy shadows to chrome.

**The Two-Surface Rule.** Most product surfaces alternate between `--bilin-panel` and `--bilin-panel-muted`. Introduce new neutral layers only when a real hierarchy problem appears.

**The Reader Token Rule.** Reader translation surfaces use `--bilin-reader-translation-*` tokens. Reader block highlights and swatches use `--bilin-reader-annotation-*` tokens. Do not put raw hex or `rgba()` annotation colors in component rules.

## 3. Typography

**Display Font:** system UI display stack with Chinese UI fallbacks.
**Body Font:** system UI text stack with `PingFang SC`, `Hiragino Sans GB`, `Noto Sans CJK SC`, and Microsoft YaHei fallbacks.
**Reader Font:** Songti and CJK serif stack for paper headings and long-form reader content.
**Label/Mono Font:** Mantine monospace only for note patches, code-like exports, and debug-adjacent text.

**Character:** The product UI uses one familiar sans family for controls, navigation, tables, and state. Serif appears only inside the reading surface, where paper rhythm matters more than interface density.

### Hierarchy

- **Display** (680, `clamp(1.72rem, 2.6vw, 2.8rem)`, 1.04): Library and settings page titles. Keep letter spacing at `0`.
- **Headline** (680, `clamp(1.22rem, 1.7vw, 1.56rem)`, 1.2): Reader title blocks, article structural headings, and compact page section heads.
- **Title** (720, `1.1rem`, 1.28): Rail tiles, panel headings, task groups, and selected-paper summaries.
- **Body** (400, `0.94rem`, 1.55): Product copy, table cells, messages, empty states, and form descriptions.
- **Reader** (400, `16.32px`, about 1.58): Parsed paper body. Source and translation sizes may differ slightly through reader preferences.
- **Label** (650, `0.74rem`, 1.25): Table headers, metadata, compact rail labels, badges, and tool captions. Use uppercase only for short section kickers or technical markers.

### Named Rules

**The UI Sans Rule.** Do not use display or decorative fonts for labels, buttons, data, forms, tabs, task rows, or settings.

**The Reader Exception Rule.** Serif typography belongs inside the paper canvas and study-card prose. It should not leak into global navigation or product controls.

**The Stable Scale Rule.** Product UI should prefer fixed rem sizes. Existing clamp titles are allowed for page titles and reader headings only.

## 4. Elevation

Ilios is flat by default. Depth comes from tonal layering, 1px borders, sticky placement, and collapsible rails. Shadows are reserved for transient overlays, citation or term popovers, and the Kindle page frame. Resting panels, task rows, cards, rails, and command bars should have `box-shadow: none`.

### Shadow Vocabulary

- **Overlay Shadow** (`0 16px 40px var(--bilin-shadow)`): Term definitions and compact overlays that float over reading content.
- **Popover Shadow** (`0 18px 44px var(--bilin-shadow)`): Citation popovers and dropdown-like evidence panels.
- **Kindle Page Shadow** (`inset 0 0 0 1px ... , 0 16px 42px ...`): E-ink-inspired page framing only.
- **Micro Tag Shadow** (`0 6px 14px light-dark(rgba(0,0,0,0.08), rgba(0,0,0,0.28))`): Reader card tags where small anchors need separation from paper text.

### Named Rules

**The Flat-At-Rest Rule.** Default panels, rails, rows, cards, and drawers do not cast shadows. Use border and background first.

**The Overlay Earns Shadow Rule.** A shadow means an element floats over content and may occlude reading. Do not use shadows as decoration.

## 5. Components

### Buttons

- **Shape:** 8px radius for normal actions, 999px only for compact badges or progress pills.
- **Primary:** Teal background, high-contrast text, compact 34px height in chrome and rail contexts.
- **Hover / Focus:** State changes use 160ms transitions. Focus adds teal-tinted border and a 3px soft ring.
- **Secondary / Ghost:** Subtle buttons use panel surfaces, muted text, and teal-soft active states. Icon-only actions use Mantine `ActionIcon` with lucide icons.
- **Loading / Disabled:** Use Mantine loading and disabled states. Disabled actions must still explain missing dependencies in nearby copy or status.

### Chips

- **Style:** Badges and status chips use light variants, pill radii, compact padding, and semantic colors only when status needs it.
- **State:** Selected chips use teal-soft background and strong text. Inactive chips stay muted.

### Cards / Containers

- **Corner Style:** 8px radius for repeated rows, task rows, rail tiles, modals, and tool panels. 0px radius for full-height shell regions and structural paper containers.
- **Background:** Use `--bilin-panel` for primary containers and `--bilin-panel-muted` for secondary tool regions.
- **Shadow Strategy:** No shadow at rest. Overlays follow the Elevation section.
- **Border:** 1px `--bilin-panel-border` by default. Use `--bilin-panel-border-strong` for dashed empty states or selected structure.
- **Internal Padding:** 10 to 14px for rails and task rows, `clamp(16px, 2vw, 22px)` for page panels.

### Inputs / Fields

- **Style:** 8px radius, `--bilin-bg-elevated` background, 1px border, system sans, compact height.
- **Focus:** Border shifts toward teal and adds `0 0 0 3px var(--bilin-accent-soft)`.
- **Error / Disabled:** Use Mantine semantic states. Error text should be explicit and should not depend on red alone.

### Navigation

- **Top Navigation:** Library surface uses a 58px compact header with centered brand lockup, left language switcher, and right utility controls.
- **Reader Navigation:** Reader routes remove the global header. The reader command center owns library return, mode, preferences, and paper controls.
- **Rails:** Left rails choose libraries, sources, or nearby papers. Right rails expose tasks, providers, questions, translations, notes, and exports. Rails collapse structurally without moving the paper.
- **Mobile:** At narrow widths, command zones wrap, labels may hide behind icons, and the reader keeps the paper as the stable center.

### Signature Component: Reader Mosaic

The reader is a three-part mosaic: article rail, paper canvas, and study or task rail. The paper canvas is the only non-collapsible reading surface. Translation, glossary terms, paper-grounded questions, reader cards, notes, and exports live near the paper rather than in separate product areas.

### Signature Component: Task Drawer And Rail

Tasks are product state. Task rows show queued, running, paused, completed, and failed work with compact badges, clear messages, and explicit controls for pause, resume, cancel, retry, or clear. Clearing task history must never imply deleting papers, translations, notes, or exports.

## 6. Do's and Don'ts

### Do:

- **Do** keep the selected paper, current work, and next useful action visible near the reading surface.
- **Do** use `--bilin-accent` for primary action, selection, progress, focus, and live state only.
- **Do** keep panels flat at rest with 1px borders and 8px radii.
- **Do** preserve local-first trust by naming providers, files, jobs, caches, notes, and exports as local user-controlled state.
- **Do** keep reading and translation in one workspace. Translation is part of reading, not a separate product area.
- **Do** maintain WCAG AA contrast, visible focus, reduced-motion behavior, and non-color-only status cues.
- **Do** collapse rails before shrinking or destabilizing the paper canvas.

### Don't:

- **Don't** make Ilios feel like a SaaS dashboard, marketing landing page, generic file manager, or static mockup.
- **Don't** use account-first onboarding, cloud-sync language, or hosted-collaboration assumptions.
- **Don't** bury translation, provider state, tasks, notes, exports, or paper-grounded questions behind unrelated navigation.
- **Don't** split reading and translation into separate mental modes.
- **Don't** create decorative card grids, giant hero metrics, loud gradients, gradient text, glassmorphism, or generic AI assistant chrome.
- **Don't** turn Library into a nested document-management maze. It should remain article-first.
- **Don't** use thick colored side stripes on cards, rows, callouts, or alerts. Structural dividers should be neutral and serve layout.
- **Don't** introduce decorative motion. Motion should communicate state and respect reduced-motion preferences.
- **Don't** invent new control vocabularies when Mantine and existing CSS already define the interaction language.
