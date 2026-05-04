# Ilios v0.1.0 Release Notes

Ilios v0.1.0 is the first GitHub-ready MVP release. It is a local-first paper reading system centered on arXiv TeX source packages, deterministic document structure, block-based translation, article-grounded question answering, editable lecture notes, and portable exports.

The product display names are 衔牍 in Simplified Chinese, Ilios in English and most other languages, and 理紐 in Japanese. Simplified Chinese and English are the core maintained languages. Japanese is the third README and is marked experimental. Korean, Spanish, French, and German README files are community contribution placeholders, while their interface hooks remain available as experimental community-friendly UI languages that may lag or fall back to English.

This release includes the React and TypeScript web app, the FastAPI backend, the SQLite migration layer, the Python worker, the `bilin` CLI, OpenAPI-generated frontend types, golden parser fixtures, localized README files, an agent-facing `AGENT_GUIDE.md`, Apache-2.0 licensing files, and a local release packaging script. The app can import arXiv papers, save PDFs, parse TeX through LaTeXML when installed, import local TeX archives and Markdown files, render real document blocks and assets in the reader, translate paragraphs and captions through OpenAI-compatible or Anthropic-compatible model profiles, preserve translation variants, review global translation memory before cross-paper reuse, manage article glossary terms, stream cited article-grounded answers, edit lecture-note patches, and export Markdown or bundle artifacts.

Generated Markdown exports and lecture notes include an invisible content notice watermark. It is stored as a Markdown HTML comment, so it does not affect normal reading layout, but it makes exported files self-describing when they contain third-party paper content, translations, captions, or notes.

The release intentionally keeps deployment local and lightweight. It does not include Docker, Redis, Celery, accounts, built-in sync, PDF LLM fallback parsing, neural embedding model downloads, Word export, EPUB export, polished PDF export, or a desktop shell. PDF files can be imported and stored in bundles, but they are not parsed, opened, OCR-processed, or translated in this MVP.

The recommended installation path is `pnpm install`, `cd apps/api && uv sync`, `make doctor`, and `make dev`. A deterministic no-network acceptance path is available with `uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance`.

The release archive can be produced with `./scripts/package-release.sh`. The generated archive excludes local application data, library folders, SQLite databases, virtual environments, node modules, caches, test artifacts, and build output.
