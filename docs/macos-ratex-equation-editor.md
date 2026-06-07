# macOS RaTeX Equation Editor

This slice recreates the core workflow of an online equation editor inside the native
macOS app, but keeps rendering local through `BilinRenderKit` instead of calling the
CodeCogs remote image service.

## Implemented Slice

- LaTeX input surface.
- Symbol and template insertion panels.
- RaTeX-backed renderer boundary via `RatexMathRenderer` and `RatexSVGCLIAdapter`.
- Local `render-svg --stdout` integration through `RATEX_RENDER_SVG_PATH` or PATH lookup.
- Native SVG preview through a JavaScript-disabled `WKWebView` wrapper.
- Rendered template previews for structure, Greek, operator, and matrix snippets.
- Shared in-memory and on-disk SVG cache for repeated editor opens.
- Inline and block mode.
- Output controls for font size, color, and inline/block mode.
- Export targets for LaTeX, HTML, URL, URL-encoded, XML, pre, Doxygen, WordPress,
  phpBB, and Tiny Wiki style strings in the render kit boundary.
- Copy LaTeX, copy SVG, and save SVG in the macOS editor surface.
- Reader integration: selected equation blocks open the editor with their current LaTeX.
- Lightweight diagnostics for brace and environment mismatches.
- Lightweight command suggestions from the template catalog.

## Boundary

The editor does not use the CodeCogs remote render endpoint. The generated URL export
uses a local `ratex://render` shape as an internal handoff format.

`RatexMathRenderer` is the rendering boundary. On macOS it currently calls the RaTeX
`render-svg` CLI because the published Swift package is iOS-oriented. The app discovers
the executable through `RATEX_RENDER_SVG_PATH`, PATH, common Homebrew paths, or
`~/.cargo/bin/render-svg`. When the CLI is missing, the editor still provides LaTeX
editing, diagnostics, and an explicit unavailable state rather than pretending to render.
Successful SVG renders are cached by renderer path, LaTeX, mode, size, and color under
the user's caches directory, so reopening the editor for the same equation or template
does not restart the RaTeX CLI. Failure states are not cached.

The macOS surface intentionally keeps the primary workflow narrow: edit LaTeX, inspect
the RaTeX preview, then copy or save SVG. Multi-target export string generation remains
available in `BilinRenderKit` for future integrations, but it is not shown as a primary
control because the current local renderer only guarantees SVG output.

## Next Work

- Bundle the RaTeX CLI in the app distribution, or replace the CLI adapter with a native
  macOS FFI/SPM adapter once RaTeX publishes one.
- Add an advanced export drawer only after PNG/PDF/HTML targets are backed by real local
  renderers or explicit integration handoff paths.
- Add persistent formula-block editing after `LibraryStore` grows a block-update API.
- Add richer syntax highlighting once the editor moves from `TextEditor` to a dedicated
  attributed text surface.
