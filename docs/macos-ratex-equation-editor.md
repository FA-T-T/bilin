# macOS RaTeX Equation Editor

This slice recreates the core workflow of an online equation editor inside the native
macOS app, but keeps rendering local through `BilinRenderKit` instead of calling the
CodeCogs remote image service.

## Implemented Slice

- LaTeX input surface.
- Symbol and template insertion panels.
- RaTeX-backed renderer boundary via `RatexMathRenderer`.
- Inline and block mode.
- Output controls for image format, font size, DPI, and color.
- Export targets for LaTeX, HTML, URL, URL-encoded, XML, pre, Doxygen, WordPress,
  phpBB, and Tiny Wiki style strings.
- Copy LaTeX, copy export, and save export.
- Lightweight diagnostics for brace and environment mismatches.
- Lightweight command suggestions from the template catalog.

## Boundary

The editor does not use the CodeCogs remote render endpoint. The generated URL export
uses a local `ratex://render` shape as an internal handoff format until the app has a
bundled RaTeX renderer/export service.

`RatexMathRenderer` is the rendering boundary. When the native RaTeX SVG adapter is not
bundled, the editor still provides LaTeX editing, export strings, diagnostics, and a raw
fallback preview.

## Next Work

- Bundle a real RaTeX Swift/Rust adapter or CLI renderer.
- Convert RaTeX SVG output into a native preview image.
- Add actual SVG/PNG/PDF save paths.
- Add richer syntax highlighting once the editor moves from `TextEditor` to a dedicated
  attributed text surface.
