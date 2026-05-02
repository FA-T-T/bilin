# Bilin v0.1.0 Release Notes

Bilin v0.1.0 is the first GitHub-ready MVP release. It is a local-first paper reading system centered on arXiv TeX source packages, deterministic document structure, block-based translation, article-grounded question answering, editable lecture notes, and portable exports.

This release includes the React and TypeScript web app, the FastAPI backend, the SQLite migration layer, the Python worker, the `bilin` CLI, OpenAPI-generated frontend types, golden parser fixtures, a Simplified Chinese default README, an English `README.en.md`, an agent-facing `AGENT_GUIDE.md`, and a local release packaging script. The app can import arXiv papers, save PDFs, parse TeX through LaTeXML when installed, import local TeX archives and Markdown files, render real document blocks and assets in the reader, translate paragraphs and captions through OpenAI-compatible or Anthropic-compatible model profiles, preserve translation variants, review global translation memory before cross-paper reuse, manage article glossary terms, stream cited article-grounded answers, edit lecture-note patches, and export Markdown or bundle artifacts.

The release intentionally keeps deployment local and lightweight. It does not include Docker, Redis, Celery, accounts, built-in sync, PDF LLM fallback parsing, neural embedding model downloads, Word export, EPUB export, polished PDF export, or a desktop shell. PDF files can be imported and stored in bundles, but they are not parsed, opened, OCR-processed, or translated in this MVP.

The recommended installation path is `pnpm install`, `cd apps/api && uv sync`, `make doctor`, and `make dev`. A deterministic no-network acceptance path is available with `uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance`.

The release archive can be produced with `./scripts/package-release.sh`. The generated archive excludes local application data, library folders, SQLite databases, virtual environments, node modules, caches, test artifacts, and build output.
