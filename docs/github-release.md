# GitHub Release Guide

This guide describes how to turn the current Ilios checkout into a GitHub release. It assumes the repository is being published as source code plus optional release archives, not as a hosted service or desktop installer. The default repository README is Simplified Chinese for the primary audience, with the English version available as `README.en.md`. AI coding agents should read `AGENT_GUIDE.md` before installing, configuring, starting, or modifying the project.

## Release Scope

The v0.2.1 package is an MVP source release. It contains the React web app, FastAPI backend, CLI, worker, SQLite migrations, generated OpenAPI TypeScript schema, golden fixtures, documentation, Apache-2.0 `LICENSE` and `NOTICE` files, and release packaging script. It does not contain local application data, user libraries, API keys, SQLite databases, virtual environments, node modules, build output, Playwright test output, or machine caches.

## Preflight

Start from the repository root. Confirm that the generated OpenAPI client is current, then run the backend and frontend quality gates.

```sh
make generate-api-client
cd apps/api
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
cd ../..
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Run the deterministic acceptance path so the release can be validated without network access or LaTeXML.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
cd ../..
```

## Package

Create release archives from a clean staging copy. The script does not require a git repository; it packages the current working tree after excluding local-only artifacts.

```sh
./scripts/package-release.sh 0.2.1
```

The output is written to `release/`. The expected files are `bilin-v0.2.1-source.tar.gz`, `bilin-v0.2.1-source.zip`, and matching `.sha256` files.

Inspect the archive before uploading it. The archive root should be `bilin-v0.2.1-source/`, and it should not contain `.venv`, `node_modules`, `.bilin`, `papers`, `*.sqlite`, `dist`, `test-results`, `.DS_Store`, or `__pycache__`.

```sh
tar -tzf release/bilin-v0.2.1-source.tar.gz | head
tar -tzf release/bilin-v0.2.1-source.tar.gz | rg 'node_modules|\\.venv|\\.bilin|papers/|\\.sqlite|__pycache__|\\.DS_Store|test-results' || true
shasum -a 256 -c release/bilin-v0.2.1-source.tar.gz.sha256
shasum -a 256 -c release/bilin-v0.2.1-source.zip.sha256
```

## Publish

Create a GitHub repository, push the source tree, and tag the release. If the repository is meant to be open source, choose and add a `LICENSE` file before publishing. Without a license, GitHub users can view the code but do not receive open-source reuse rights.

```sh
git init
git add .
git commit -m "Release Ilios v0.2.1"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
git tag v0.2.1
git push origin v0.2.1
```

On GitHub, create a new release from tag `v0.2.1`. Use `RELEASE_NOTES.md` as the release body and upload the files from `release/` as release assets if you want explicit archives in addition to GitHub's automatic source archives.

## Post-Publish Check

Download the GitHub archive or release asset into a temporary directory and run the clean-machine path from `README.md`, or `README.en.md` if you prefer English. A valid release should install dependencies, run `make doctor`, run the golden acceptance command, start `make dev`, and open the generated reader route without relying on files outside the archive.
