# Bilin Local Safety

This document defines the MVP operating contract for local setup, data placement, dependency failures, job controls, and external folder sync. Bilin stays local-first and lightweight. It does not add Docker, Redis, Celery, accounts, or built-in sync for MVP.

## Clean Setup Path

Start from a fresh checkout with Node, pnpm, Python 3.13, and uv available.

```sh
pnpm install
cd apps/api && uv sync && cd ../..
make doctor
make dev
```

The API runs on `127.0.0.1:8000`, the frontend runs on `127.0.0.1:5173`, and the worker runs in the same `make dev` group. The first manual path is to open the web app, create a library, import an arXiv ID or local file, wait for jobs in the task drawer, and open the reader route from the library table.

Use the deterministic golden acceptance path when a new machine should be checked without network access or LaTeXML.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

The command creates a disposable library, imports the golden TeX source package, materializes a reader-ready document from fixture HTML, and exports the MVP artifact set. Use `--live-latexml` only after `bilin doctor` confirms both `latexml` and `latexmlpost`.

## Dependency Failure Contract

LaTeXML is the only official MVP TeX parser path. If either `latexml` or `latexmlpost` is missing, parse jobs fail with `missing_dependency:latexml`. This is intentional. Bilin must not silently fall back to regex parsing or low-quality conversion.

The failure appears in four places. The worker job stores a structured error with `code`, `message`, and `details`. The article revision moves to `parse_failed`, and `manifest.json` stores the same parse error. The bundle writes `logs/parse-error.json`. The CLI prints the error and suggests `bilin doctor`. The web task drawer displays the failed job error so users do not need to inspect SQLite manually.

Optional tools degrade rather than block startup. `magick` and `gs` affect EPS or PDF asset conversion. `tectonic` and `pdflatex` affect future controlled rendering paths for code-generated figures. `pdfinfo` affects future PDF metadata diagnostics. Existing raster assets, Markdown imports, PDF save-only imports, provider settings, translation jobs, notes, and exports still work when optional tools are absent.

## Job Control Semantics

The SQLite job queue supports `queued`, `running`, `paused`, `succeeded`, `failed`, and `cancelled`.

`import_arxiv` jobs can be cancelled before a worker claims them. Once running, they may finish the current HTTP and file-write step before cancellation is observed.

`parse_article` jobs can be cancelled before execution. Once LaTeXML is running, MVP cancellation does not kill the external process; cancellation is best-effort until process supervision is added.

`translate_block` jobs retry transient provider failures up to the configured attempt count. They honor queued cancellation, and running cancellation becomes reliable only between provider calls.

`export_article` jobs are short file-writing tasks. They can be cancelled before execution; once running, they normally finish quickly and write deterministic output into the article bundle. Queue regression tests use export jobs rather than a synthetic endpoint, so the tested path is also a product path.

Pause prevents queued work from being claimed and resumes a paused queued job, but it is not a hard preemption mechanism for already running external work.

## Data Directories

The global app directory is chosen by `platformdirs`. Set `BILIN_HOME` during development or tests to make this path explicit.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api && uv run bilin dev-info
```

The global app directory contains app-level SQLite state, registered libraries, provider profile metadata, jobs, settings, note templates, and API-key fallback storage when Keychain is unavailable or explicitly disabled. Do not put this directory inside a synced folder unless you accept normal SQLite sync risks.

Each library directory is chosen by the user. A library is meant to be portable as one folder. It contains `library.sqlite`, `articles/`, original source packages, downloaded or uploaded PDFs, unpacked TeX, `manifest.json`, `document/document.json`, `document/source.md`, `assets/`, `logs/`, `export/`, and generated `lecture-notes.md`.

External folder sync tools such as iCloud, OneDrive, or Syncthing should sync the whole library directory, not individual files inside a bundle. Close Bilin before moving or merging synced libraries. If two machines edit the same library simultaneously, Bilin does not resolve conflicts; keep the newer whole library folder or recover from the external sync tool's version history.

## Ignored Local Artifacts

The repository ignores virtual environments, node modules, build output, browser test output, local SQLite databases, generated library folders, local paper bundles, and temporary local data directories. Source fixtures under `fixtures/golden` remain tracked because they are deterministic test inputs, not user data.
