# macOS App Framework Decision

Status: accepted for the `feature/macos-app` branch.

## Decision

Build Bilin for macOS as a native SwiftUI app, with AppKit and PDFKit bridges where
SwiftUI is not the strongest surface.

Do not start with Electron. Do not use Tauri as the primary product architecture. Tauri
can remain a short-lived compatibility prototype if we need to reuse the current React
reader during migration.

## Why SwiftUI

Bilin's macOS app should not be a desktop wrapper around the web app. The point of this
branch is to remove dependency pressure from React, WebView, local HTTP, Python runtime
packaging, and DOM-based math rendering where native macOS has better primitives.

SwiftUI is the best fit for the product we want:

- Native macOS menus, commands, keyboard handling, sidebars, inspectors, sheets, and
  document-window behavior.
- Direct integration with AppKit when SwiftUI needs a lower-level escape hatch.
- PDFKit support for PDF reading, text selection, annotations, and document navigation.
- Cleaner accessibility and text interaction than Canvas/WebView-first rendering.
- A natural path to use RaTeX through Rust FFI or pre-rendered SVG/PDF output instead of
  WASM-to-Canvas in a browser.

## Why Not Tauri

Tauri is a good Rust-backed WebView shell. It is a reasonable way to ship the existing
React app quickly, and it is substantially lighter than Electron. That is not the core
goal here.

For this branch, Tauri keeps the main reader UI in a web rendering model. It preserves
many of the same dependencies we are trying to unwind: CSS layout, WebView behavior,
browser font loading, DOM assumptions, and frontend test complexity.

## Why Not Electron

Electron embeds Chromium and Node.js. That is useful when the product is fundamentally a
web app that needs desktop distribution. It is the wrong default for a macOS-only reader
whose goal is native performance, smaller runtime surface, better file integration, and
less dependency coupling.

## Target Architecture

The macOS app should evolve into these layers:

- `BilinMacApp`: SwiftUI app target, window lifecycle, menus, commands, settings.
- `BilinReaderKit`: reader state, outline, blocks, citations, notes, annotations.
- `BilinStore`: local SQLite-backed library store with explicit migrations.
- `BilinRenderKit`: math and rich content rendering; RaTeX is the preferred native math
  candidate, with KaTeX retained only as a compatibility reference during migration.
- `BilinImportKit`: arXiv, TeX bundle, LaTeXML-derived, and asset import workflows.
- `BilinLLMKit`: provider configuration, translation jobs, glossary, reader cards.

## Migration Plan

1. Start with a native library shell: sidebar, article list, reader pane, settings.
2. Read the existing local Bilin library database/schema rather than starting with a
   local FastAPI server.
3. Port the reader block model into Swift structs and keep JSON fixtures shared with the
   web tests.
4. Add native math rendering as a feature flag: first display equations, then inline
   formulas, then table math.
5. Move import and translation workflows behind protocol-based services so Python,
   Rust, and Swift implementations can be swapped during migration.

## First Prototype Boundary

The first prototype should prove three things:

- A native SwiftUI reader shell can render article block fixtures without the web app.
- The local store can open an existing Bilin library without running the API server.
- RaTeX can render representative paper formulas with acceptable baseline alignment,
  copy fallback, and accessibility text.
