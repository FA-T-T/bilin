<h1 align="center">
  Ilios (LLM-assisted paper reading)<br>
  <sub><sub>衔牍 · 理紐</sub></sub>
</h1>

<p align="center">
  <em>A multilingual paper-reading tool</em>
</p>

<p align="center">
  <a href="README.md">简体中文 · Core</a> ·
  <a href="README.en.md">English · Core</a> ·
  <a href="README.ja.md">日本語 · Experimental</a> ·
  <a href="README.ko.md">한국어 · Community</a> ·
  <a href="README.es.md">Español · Community</a> ·
  <a href="README.fr.md">Français · Community</a> ·
  <a href="README.de.md">Deutsch · Community</a>
</p>

<p align="center">
  <a href="https://github.com/FA-T-T/bilin/releases"><img src="https://img.shields.io/github/v/release/FA-T-T/bilin?include_prereleases" alt="release"></a>
  <a href="https://github.com/FA-T-T/bilin/blob/main/LICENSE"><img src="https://img.shields.io/github/license/FA-T-T/bilin" alt="license"></a>
  <a href="https://github.com/FA-T-T/bilin/stargazers"><img src="https://img.shields.io/github/stars/FA-T-T/bilin?style=social" alt="stars"></a>
</p>

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## What Is Ilios?

Ilios is a **local-first, structured** paper-reading workspace for researchers who need to understand English papers across languages.

It runs locally and supports arXiv source packages or local LaTeX archives.

Papers, parsed documents, translation cache, Q&A records, and notes stay in a local folder you choose. **No account, no hosted backend, and no file upload are required.**

Translation cost is low. In one test, DeepSeek V4 Flash translated 10 papers, 240 pages in total, for about 2 CNY.

## Main Features

##### **Multilingual Reading**

The paper text, figures, and formulas shown in the screenshots belong to the original authors or rights holders. They are used here only to demonstrate Ilios's local reading, translation, Q&A, and structured rendering features.

Chinese example:

<img src="./assets/image-20260522193937577.png" alt="Chinese translation example" style="zoom: 25%;" />

French example:

<img src="./assets/image-20260522194355907.png" alt="French translation example" style="zoom:25%;" />

Japanese example:

<img src="./assets/image-20260522193846703.png" alt="Japanese translation example" style="zoom:25%;" />

German example:

<img src="./assets/image-20260522194717793.png" alt="German translation example" style="zoom:25%;" />

Korean example:

<img src="./assets/image-20260522194157385.png" alt="Korean translation example" style="zoom:25%;" />

##### Figures

<img src="./assets/image-20260522194901555.png" alt="Figure rendering example" style="zoom: 25%;" />

##### Formulas

KaTeX rendering.

<img src="./assets/image-20260522195038561.png" alt="Formula rendering example" style="zoom:25%;" />

##### Tables

Rendered as HTML tables.

<img src="./assets/image-20260522195134674.png" alt="Table rendering example" style="zoom:25%;" />

##### Sentence Hover Highlighting

Sentence segmentation makes bilingual comparison easier.

![Sentence hover highlighting](./assets/image-20260522195506879.png)

##### Citation Preview

Citations are parsed automatically. Ilios supports Google Scholar and arXiv search, one-click library import, and automatic translation.

<img src="./assets/image-20260522202145628.png" alt="Citation preview example" style="zoom: 33%;" />

##### Markdown Export For Source Or Translation

Export the original text or translated text as Markdown and use it directly as a knowledge-base document.

<img src="./assets/image-20260522202353196.png" alt="Markdown export example" style="zoom:25%;" />

##### Kindle Mode

Kindle mode lets e-ink devices on the local network read through a browser with lower resource usage. It removes scrolling and adds page-turn buttons on the left and right sides.

A 10-inch or larger e-ink device in landscape orientation is recommended.

![Kindle mode example](./assets/image-20260522202534656.png)

## Quick Start

### Agent Users (Codex, Claude, DeepSeek-TUI, OpenCode...)

Send this page link directly to an agent and say:

"https://github.com/FA-T-T/bilin Please help me deploy this service, install the required dependencies, and start the app."

The agent can install dependencies, deploy the project, and start the application.

### Regular Users

Ilios expects Node.js, pnpm, Python 3.13, and uv. The core app can start without a TeX toolchain, but real LaTeX parsing requires `latexml` and `latexmlpost` on `PATH`. ImageMagick `magick`, Ghostscript `gs`, and `tectonic` or `pdflatex` are recommended for image and PDF handling.

Prepare a macOS + Homebrew environment:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Start from source:

```sh
git clone https://github.com/FA-T-T/bilin.git
cd bilin
pnpm install
cd apps/api
uv sync
cd ../..
make doctor
make dev
```

In a fixed development environment, you can use the quick-start script. It reuses existing virtual environments and `node_modules`, skips environment probing, and returns status immediately if the stack is already running.

```sh
./scripts/start-dev.sh
```

After startup, open `http://127.0.0.1:5173`. The API defaults to `127.0.0.1:8000`, and the worker handles import, parsing, translation, Q&A, notes, and export jobs. You can also run `make api`, `make worker`, and `make web` separately for debugging.

Without LaTeXML, Ilios still starts and supports Markdown import, PDF storage, model configuration, translation, notes, export, and fixture tests. TeX parse jobs fail explicitly with `missing_dependency:latexml` instead of silently falling back to unstable regex parsing.

## First Paper

Create a library on the home page by entering a name and a local directory path. A library is a self-contained folder containing `library.sqlite`, original source archives, PDFs, unpacked TeX, parsed `document.json`, `source.md`, assets, logs, notes, exports, and manifests.

Inside the library, enter an arXiv ID such as `1706.03762`. Ilios downloads the source package and PDF, creates a self-contained article package, and queues parse tasks when parsing is enabled. Local TeX archives reuse the same package path. Markdown imports immediately as weakly structured documents, and PDFs are stored as source files.

After parsing, select the paper in the library and click Read. The reader supports Study, Bilingual, Translation, and Source views. The left rail switches between papers in the same library. The right rail provides tasks, model setup, paper chat, translation, glossary, notes, and export tools. Paragraph hover actions can copy, inspect source, retranslate, or ask about the current paragraph. Figures and tables render directly when assets are available; missing assets keep captions and labels with structured placeholders.

## Model Configuration

Open Settings -> Models. In simple mode, paste an API key and Ilios pulls the model list from a compatible endpoint. Advanced mode lets you configure the profile label, base URL, concurrency, and requests-per-minute limit. **Advanced mode is recommended.**

Provider keys are not stored inside library folders. On macOS, keys are stored in Keychain by default and the global database stores only a `keychain:` reference. Other platforms, or `BILIN_CREDENTIAL_STORE=app_settings`, use the SQLite development fallback. To block provider creation when Keychain is unavailable, set:

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

The CLI reuses the same backend logic as the web app.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

The repository includes golden fixtures for validating the reader pipeline without network access or a full TeX toolchain.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

The command returns `reader_route` and `library_id`. Start the app and open the route in a browser to inspect the generated article.

## Local Data, Security, And Sync

Ilios uses a global application data directory for app-level SQLite state, registered libraries, provider configuration, jobs, settings, note templates, translation memory, and fallback API-key storage when Keychain is disabled or unavailable. The directory is chosen by `platformdirs` and can be overridden during development with `BILIN_HOME`.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library directories are user-selected, self-contained folders suitable for external sync tools such as iCloud, OneDrive, or Syncthing. Ilios does not resolve sync conflicts. Close the app before syncing and recover conflicts through the sync tool's version history.

Exported Markdown and lecture notes automatically include an invisible HTML comment watermark explaining that the file was generated by Ilios and may contain third-party content. The watermark does not affect normal reading layout.

## Developers

Run backend checks from `apps/api`.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Run frontend checks from the repository root.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Default tests use fixtures and mocks. They do not require live network access or a complete TeX toolchain. Real arXiv and LaTeXML integration tests are explicit opt-in tests.

## License

Ilios source code, project-owned documentation, tests, and project-owned fixtures are licensed under Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). This license covers only the Ilios project itself. It does not cover user-imported papers, PDFs, TeX source packages, figures, captions, datasets, machine translations, or lecture notes containing third-party material. Redistribution of exports must follow the original paper or asset license, rights-holder permission, or applicable legal exceptions.

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  Borrow light through the wall; carry the text to the desk.<br><br>
  <strong>理紐</strong><br>
  One who ties the thread of reasoning, bridging your thought and the author's.<br><br>
  <em>If Ilios helps you spend one less sleepless night on a paper, give the project a Star so more new researchers can find it.</em>
</p>
