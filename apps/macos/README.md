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

## Current Prototype

This package is intentionally small:

- `BilinMacApp` renders a three-column SwiftUI workbench from a bundled fixture.
- `BilinReaderKit` defines the first native reader models and fixture loader.
- `BilinStore` exposes the store protocol, an in-memory fixture store, and a
  SQLite-backed local library store for existing `library.sqlite` databases.
- `BilinRenderKit` defines the math renderer protocol, a fallback renderer, and the
  future RaTeX adapter boundary.

Use `Open Library...` to choose either a Bilin library directory or its `library.sqlite`
file. The prototype loads article rows, ordered document blocks, existing `zh-CN`
translation variants, reading progress, and local note patches from SQLite. New notes
are written to the existing `note_patches` table only after the library schema guard
confirms the expected migration set.

Open `apps/macos/Package.swift` in Xcode on macOS, then run the `BilinMac` executable
product. Command-line validation on a Mac:

```bash
cd apps/macos
swift test
swift run BilinMac
```

The current Windows workspace does not include a Swift toolchain, so Swift compilation
must be validated on macOS.
