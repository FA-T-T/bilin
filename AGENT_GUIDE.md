# Ilios Agent Guide

This file is for AI coding agents. It is optimized for installation, configuration, startup, verification, and safe project maintenance. Human-facing product documentation lives in `README.md`, `README.en.md`, and the localized README files.

## Mission

Ilios is a local-first paper reading and study application. The main path is TeX-first arXiv or local TeX archive import, LaTeXML parsing, structured document blocks, provider-backed translation, article-grounded question answering, lecture-note editing, and local export. Preserve this direction when modifying the project.

Do not introduce Docker, Redis, Celery, accounts, hosted backend requirements, or built-in sync as default dependencies. Do not treat PDF parsing, OCR, Word export, EPUB export, polished PDF export, or neural embedding downloads as currently required startup features. Those are future or optional paths.

Before changing product behavior, reader layout, batch operations, feature toggles, or user-facing interaction logic, read `DESIGN.md`. It is the canonical contract for defaults, deprecated modes, batch-operation expectations, and what must stay configurable.

For UI copy and community translation work, read `apps/web/src/locales/README.md` and use `apps/web/src/locales/example.locale.json` as the contribution shape. Runtime dictionaries currently live in `apps/web/src/i18n.ts`, so reviewed locale updates must still be promoted there.

## Repository Facts

Use this block as the first-pass mental model before running commands.

```yaml
project_name: Ilios
product_names:
  zh-CN: 衔牍
  en: Ilios
  ja: 理紐
  default_international: Ilios
language_policy:
  core: [zh-CN, en]
  experimental_docs: [ja]
  community_readme_placeholders: [ko, es, fr, de]
  experimental_ui: [ja, ko, es, fr, de]
technical_project_id: bilin
repo_root: /Users/taotao/Documents/DAC2026presentation/bilin
frontend:
  package: "@bilin/web"
  path: apps/web
  framework: Vite + React + TypeScript
  default_port: 5173
backend:
  package: bilin_api
  path: apps/api
  framework: FastAPI + Typer + SQLite
  default_port: 8000
cli:
  command: bilin
  invocation_from_repo: cd apps/api && uv run bilin
worker:
  invocation_from_repo: make worker
data:
  app_home: platformdirs, override with BILIN_HOME
  library_home: user-selected folder, not inside generated caches
release:
  script: ./scripts/package-release.sh
```

## Non-Negotiable Local Rules

Keep runtime data out of the repository. Do not commit or package `.venv/`, `node_modules/`, `dist/`, `test-results/`, `coverage/`, `.bilin/`, `papers/`, `libraries/`, `local-data/`, SQLite databases, or local API keys. The packaging script already excludes these paths; keep that contract intact.

Do not store provider API keys in source files, README examples with real values, fixtures, or generated artifacts. On macOS the application should prefer Keychain. For CI or local fallback, use the documented credential-store environment variable instead of hardcoding secrets.

Generated Markdown exports and lecture notes must keep the invisible Ilios content notice watermark. It is an HTML comment, so it should not affect normal rendered reading layout. Do not remove it when changing export code.

Do not edit generated frontend API types by hand. When backend schemas or routes change, run `make generate-api-client`, then edit hooks and UI code outside `apps/web/src/api/generated`.

Use `rg` for code search. Use `apply_patch` for manual edits. Do not revert unrelated user changes.

## Install From A Fresh Checkout

Start at the repository root.

```sh
cd /Users/taotao/Documents/DAC2026presentation/bilin
```

Install system tools. On macOS with Homebrew, this is the expected broad setup.

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

The core app can start without the full TeX toolchain, but real TeX parsing needs `latexml` and `latexmlpost`. If they are missing, parse jobs must fail clearly with `missing_dependency:latexml`; do not add a silent regex fallback.

Install JavaScript and Python dependencies.

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

Run doctor after dependency installation.

```sh
make doctor
```

If `make doctor` fails because `uv`, `pnpm`, or Python is missing, fix the system installation first. If optional document tools are missing, keep startup working and let doctor report degraded capability.

## Configure Runtime State

Use `BILIN_HOME` when an agent needs isolated app state, repeatable tests, or a disposable local run.

```sh
export BILIN_HOME=/tmp/bilin-home
```

For provider key storage, use the default macOS Keychain path when available. Use SQLite fallback only for development or CI.

```sh
export BILIN_CREDENTIAL_STORE=keychain
# or, for CI/dev fallback only:
export BILIN_CREDENTIAL_STORE=app_settings
```

Create libraries outside the repository unless a test explicitly uses a temporary path. A library is intended to be a portable folder containing `library.sqlite`, source archives, PDFs, unpacked TeX, parsed documents, assets, logs, notes, exports, and manifests.

```sh
mkdir -p /tmp/bilin-library
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
cd ../..
```

Provider profiles are usually configured through the Settings page because the UI can discover models from OpenAI-compatible or Anthropic-compatible endpoints. If a CLI profile is needed for automation, pass the key through the environment.

```sh
cd apps/api
uv run bilin provider create \
  --name "OpenAI Compatible" \
  --protocol openai-compatible \
  --api-key "$OPENAI_API_KEY" \
  --model gpt-5.5
cd ../..
```

## Start The Application

The normal development startup command launches API, worker, and web together.

```sh
make dev
```

On this fixed local checkout, prefer the fast starter because the environment is already prepared and `uv` may not be on the shell PATH.

```sh
./scripts/start-dev.sh
./scripts/start-dev.sh status
./scripts/start-dev.sh stop
```

This is a long-running command. If the agent environment needs separate controllable processes, start each service in its own terminal session.

```sh
make api
make worker
make web
```

Expected endpoints after startup are:

```text
API health: http://127.0.0.1:8000/health
Web app:    http://127.0.0.1:5173
```

Use these checks when diagnosing startup.

```sh
curl -s http://127.0.0.1:8000/health
curl -I http://127.0.0.1:5173
```

If a port is occupied, either stop the existing process or run the service manually on another port. Do not change default ports in documentation unless the application defaults actually change.

## Deterministic Smoke Path

Use the golden acceptance path when you need to verify a clean checkout without live arXiv network access or LaTeXML.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
cd ../..
```

The command should create a temporary library and return a reader route. Start the app with `make dev`, then open the returned route in the browser.

For live arXiv import, use a real library path and expect network and LaTeXML requirements if parsing is enabled.

```sh
cd apps/api
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
cd ../..
```

## Quality Gates

Run backend checks from `apps/api`.

```sh
cd apps/api
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
cd ../..
```

Run frontend checks from the repository root.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
```

Run Playwright smoke tests only when the environment supports browser execution and the task requires UI path validation.

```sh
pnpm --filter @bilin/web test:e2e
```

If backend API contracts changed, regenerate the frontend client before running frontend type checks.

```sh
make generate-api-client
```

## Release Packaging

Create source archives with the release script.

```sh
./scripts/package-release.sh
```

Verify checksums and inspect that forbidden local artifacts were excluded.

```sh
shasum -a 256 -c release/bilin-v3.1.0-source.tar.gz.sha256
shasum -a 256 -c release/bilin-v3.1.0-source.zip.sha256
tar -tzf release/bilin-v3.1.0-source.tar.gz | rg 'node_modules|\.venv|\.bilin|papers/|libraries/|\.sqlite|__pycache__|\.DS_Store|test-results' || true
```

The final archive should include `README.md`, `README.en.md`, localized README files such as `README.ja.md`, `README.ko.md`, `README.es.md`, `README.fr.md`, and `README.de.md`, `AGENT_GUIDE.md`, `LICENSE`, `NOTICE`, `RELEASE_NOTES.md`, `docs/`, `fixtures/`, `apps/`, root package files, and release scripts.

## Common Failures

If `uv run` cannot find dependencies, run `cd apps/api && uv sync`. If `pnpm --filter @bilin/web` fails because packages are missing, run `pnpm install` from the repository root.

If TeX parsing fails with `missing_dependency:latexml`, install LaTeXML and confirm `latexml` and `latexmlpost` appear in `make doctor`. Do not patch parser behavior to hide this failure.

If model discovery fails, check protocol, base URL, and API key. OpenAI-compatible providers should expose a model-list endpoint under the configured base URL. Anthropic-compatible providers should follow Anthropic-style model listing. The UI should let users select discovered model names instead of asking them to guess raw identifiers.

If the web app cannot reach the API, verify that FastAPI is running on `127.0.0.1:8000`, then check browser console errors and CORS or proxy assumptions. The default local development path should not require a hosted backend.

If tests unexpectedly touch real network or real TeX tools, mark that path as optional integration behavior. Default tests should remain fixture-based and deterministic.

## Safe Change Workflow

Before editing, search the relevant module and existing tests. Keep changes scoped to the feature or bug. After editing backend routes or schemas, regenerate OpenAPI client and fix TypeScript compile errors. After changing startup, packaging, or documentation, rerun `tests/test_docs.py` and `./scripts/package-release.sh` if release artifacts are expected to stay current.

When the user asks to run the service, prefer `make dev` unless separate terminal control is needed. When the user asks to package for GitHub, update human README files and this agent guide if startup, install, or configuration behavior changed.
