# Bilin

Language: [简体中文](README.md) | English

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

Bilin is a local-first web application for reading, translating, questioning, annotating, and exporting academic papers. The primary path is arXiv TeX source, because TeX preserves the structure that a serious paper reader needs: sections, paragraphs, equations, figures, tables, captions, labels, citations, and source assets. Bilin runs on your own machine with a React and TypeScript frontend, a FastAPI backend, a SQLite job queue, and a Python worker. It does not require Docker, Redis, Celery, accounts, a hosted backend, or built-in cloud sync.

This repository is currently an MVP release. It can create local libraries, import arXiv source packages, import local TeX archives, import Markdown as weak structured documents, save PDFs as source artifacts, parse TeX through LaTeXML when the toolchain is installed, preserve document blocks and assets in SQLite, build deterministic local block embeddings, translate paragraph and caption blocks through OpenAI-compatible or Anthropic-compatible providers, keep translation variants, manage reviewed local translation memory, maintain article terminology, store provider keys in macOS Keychain when available, stream article-grounded answers with cited evidence, create editable lecture-note patches, edit custom note templates, and export source, translated, bilingual, lecture-note, or bundle artifacts.

## Future Plans

Future versions will extend Bilin with PDF LLM fallback parsing, optional neural embedding providers, Word/EPUB/polished PDF export, a desktop shell, and a more complete release shape. PDFs can already be stored as source artifacts in article bundles; future PDF support will be added as an optional parsing path without changing the TeX-first workflow or introducing default OCR or heavy service dependencies. Accounts and built-in sync are not part of the default product direction. Bilin will remain local-first and keep library folders easy to sync through external tools such as iCloud, OneDrive, and Syncthing.

## Repository Layout

The repository is a lightweight monorepo. `apps/api` contains the FastAPI backend, CLI, SQLite migrations, arXiv and upload import services, LaTeXML parser path, provider profiles, translation jobs, deterministic local embeddings, glossary services, question answering, lecture-note services, export services, worker, and doctor command. `apps/web` contains the Vite React TypeScript frontend. `docs` contains design, MVP, and local-safety notes. `fixtures/golden` contains deterministic parser regression fixtures used by tests and acceptance checks.

## Requirements

Bilin expects Node.js, pnpm, Python 3.13, and uv. The frontend package manager is pnpm 10.32.1. The backend uses uv to create and manage its Python environment. The core app can start without a TeX installation, but real TeX parsing requires both `latexml` and `latexmlpost` on `PATH`. Optional asset conversion benefits from ImageMagick `magick`, Ghostscript `gs`, and a TeX engine such as `tectonic` or `pdflatex`.

On macOS with Homebrew, a practical development setup looks like this.

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

On Linux, install equivalent packages through your distribution package manager. If LaTeXML is not available, Markdown import, PDF save-only import, provider setup, translation, notes, exports, and fixture tests still work. TeX parse jobs fail explicitly with `missing_dependency:latexml` until LaTeXML is installed.

## Installation

Start from a fresh checkout or release archive. Install frontend dependencies from the repository root, then initialize the backend environment.

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

Run doctor before starting real work. It reports the application data directory, macOS Keychain support, and local document tools. Missing optional tools are shown as degraded capabilities rather than startup blockers.

```sh
make doctor
```

## Running The App

For development, run all three local processes with one command. This starts FastAPI on `127.0.0.1:8000`, the worker process beside it, and Vite on `127.0.0.1:5173`.

```sh
make dev
```

The individual services can also be started separately when debugging.

```sh
make api
make worker
make web
```

Open `http://127.0.0.1:5173` in the browser. Create a library by choosing a name and local directory path. A library is a portable folder containing `library.sqlite`, original source packages, uploaded PDFs, unpacked TeX, parsed `document.json`, generated `source.md`, assets, logs, lecture notes, exports, and bundle manifests.

## First Paper Through The UI

After creating a library, open it from the Library page and use the Add article panel. The normal path is an arXiv ID such as `1706.03762`; Bilin downloads the source package and PDF, creates a self-contained article bundle, and queues a parse job when parsing is enabled. Local TeX archives use the same bundle path as arXiv source packages. Markdown imports generate a weak structured document immediately. PDF uploads are saved into the bundle but are not parsed, opened, OCR-processed, or translated in this MVP.

Open the reader from the article table once parsing or import has produced a document. The reader supports study, focus, bilingual, translation-only, and source-only views. Sections are available through a collapsible chapter control. Paragraph blocks expose hover actions for copying, inspecting source, asking about the current block, and retranslation. Figures and tables show real assets when available and preserve structured captions and references when assets are not generated.

## Provider Setup

Open Settings and choose Models. In simple mode, paste an API key, discover models from an OpenAI-compatible or Anthropic-compatible endpoint, and select a returned model by display name. In advanced mode, you can also set a profile label, base URL, concurrency, and requests per minute. Bilin does not ask users to guess raw model names when the provider supports model listing.

Provider keys are stored outside library directories. On macOS, Bilin stores keys in Keychain by default and keeps only a `keychain:` reference in the global application database. On other platforms, in CI, or when `BILIN_CREDENTIAL_STORE=app_settings` is set, Bilin uses the SQLite development fallback. If you want Keychain failures to stop provider creation instead of falling back, set `BILIN_CREDENTIAL_STORE=keychain`.

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## Translation And Memory Review

Translation jobs are block-based. Paragraph and caption blocks are translated; formulas and structural environment blocks are preserved as source structure. Translations are saved as variants, so retranslation does not overwrite earlier output. The selected default variant is persisted per block.

Validated translations enter app-level translation memory as pending entries. Pending entries do not affect later papers. Open Settings and choose Translation memory to review entries by language and status. Approving an entry with reuse enabled allows later papers with the same content hash, target language, and glossary version to reuse it. Disabling or rejecting an entry stops cross-paper reuse without deleting the original article-local translation variant.

## Question Answering And Notes

The reader can ask questions about the whole article or a selected block. Bilin retrieves article evidence from local indexes, streams the answer, and stores cited block references. If a selected model profile declares native search support, external model-native search can be enabled; otherwise answers are constrained to the article context.

Lecture notes are built from editable patches. Built-in templates cover deep reading, group meeting preparation, quick skim, and reproduction-oriented reading, and users can save custom templates from the Notes panel. Proposed patches can be edited before acceptance. Accepted notes are materialized into `lecture-notes.md` inside the article bundle.

## CLI Workflow

The CLI command is `bilin` and is available through `uv run` from `apps/api`. It reuses the same services as the web app. The cleanest CLI path is to create a library, import a paper, run the worker or parse directly, translate, and export.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

If you already know the article revision id, parsing and export can be run directly.

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

Provider profiles can also be created from the CLI, although the web Settings page is better for model discovery.

```sh
uv run bilin provider create --name "OpenAI Compatible" --protocol openai-compatible --api-key "$OPENAI_API_KEY" --model gpt-5.5
```

## Deterministic Smoke Path

The repository includes golden fixtures so a new machine can validate the reader pipeline without public arXiv network access or LaTeXML. The acceptance command creates a disposable library, imports the golden source, materializes a reader-ready document from saved converter output, and exports the MVP artifact set.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

The command returns a `reader_route` and a `library_id`. Start the app, then open the route in the browser to inspect the generated article.

## Local Data And Sync

Bilin uses a global application data directory for app-level SQLite state, registered libraries, provider profile metadata, jobs, settings, note templates, translation memory, and API-key fallback storage when Keychain is unavailable or disabled. The location is chosen by `platformdirs`. Development can override it with `BILIN_HOME`.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library directories are user-chosen and self-contained. This makes them suitable for external folder sync tools such as iCloud, OneDrive, or Syncthing. Bilin itself does not resolve sync conflicts. Close Bilin before moving or merging synced libraries, and recover conflicts through the external sync tool's version history.

## Quality Gate

Backend checks run from `apps/api`.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Frontend checks run from the repository root.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Default tests use fixtures and mocks. They do not require live arXiv access or a full TeX toolchain. Optional live arXiv and live LaTeXML integration tests are deliberately opt-in.

## GitHub Release Packaging

This repository includes a release packaging script. It builds a clean source archive from the current working tree while excluding local data, virtual environments, node modules, caches, test output, SQLite databases, and generated build directories.

```sh
./scripts/package-release.sh
```

The script writes release artifacts under `release/`, including `bilin-v0.1.0-source.tar.gz`, `bilin-v0.1.0-source.zip`, and matching SHA-256 checksum files. Upload those archives to a GitHub release if you want release assets in addition to GitHub's automatic source archives.

Before publishing, run the quality gate above and check the release archive on a fresh machine or temporary directory. A release candidate should be able to install dependencies, run `make doctor`, run the golden acceptance command, start `make dev`, and open the generated reader route without requiring any local files that were excluded from the archive. The detailed publishing checklist is in `docs/github-release.md`, and `RELEASE_NOTES.md` can be used as the GitHub release body.

## License

No open-source license file is included in this release package yet. If this repository will be published for public reuse rather than private distribution, choose a license and add `LICENSE` before creating the GitHub release. Without a license, GitHub users can view the code but do not receive open-source reuse rights.

## Troubleshooting

If the API is unreachable, confirm `make api` is running and that `http://127.0.0.1:8000/health` returns JSON. If the web app cannot reach the API, confirm Vite is running on `127.0.0.1:5173` and that no browser extension is blocking localhost requests.

If TeX parsing fails with `missing_dependency:latexml`, install LaTeXML and confirm both `latexml` and `latexmlpost` appear in `bilin doctor`. Bilin will not silently fall back to regex parsing because stable block identity depends on deterministic parser output.

If provider model discovery fails, verify the API key, protocol, and base URL. OpenAI-compatible endpoints normally expose `/models` under the configured base URL. Anthropic-compatible endpoints must accept the Anthropic model-listing protocol.

If a translation looks wrong but keeps reappearing, inspect the block's translation variants and the Settings translation memory page. Article-local variants can be reselected, and global memory entries can be disabled or rejected without deleting the original article data.
