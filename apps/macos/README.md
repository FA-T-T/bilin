# Bilin for macOS

This branch starts the native macOS app track for Bilin.

The chosen framework is SwiftUI, with AppKit/PDFKit bridges where native macOS APIs are
stronger than pure SwiftUI. The app should not begin as a WebView wrapper around the
current React frontend.

## Direction

- Build a native macOS reader shell.
- Read local Bilin libraries directly from the local store.
- Keep the current web app as a reference implementation, not as the runtime dependency.
- Use RaTeX as the leading candidate for native math rendering.
- Keep Python, Node, WebView, and HTTP-server dependencies out of the default app path.

## Initial Modules

- `BilinMacApp`: app lifecycle, windows, menus, commands, settings.
- `BilinReaderKit`: reader blocks, outline, citations, annotations, notes.
- `BilinStore`: local SQLite store and migrations.
- `BilinRenderKit`: math and rich content rendering.
- `BilinImportKit`: paper import and asset processing.
- `BilinLLMKit`: provider, translation, glossary, and reader-card workflows.

## Prototype Criteria

The first working prototype should open a local article fixture, render a native reader
layout, show equations through the selected math renderer, and persist simple notes in a
local store.
