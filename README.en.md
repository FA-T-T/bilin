<h1 align="center">
  Ilios<br>
  <sub><sub>衔牍 · 理紐</sub></sub>
</h1>

<p align="center">
  <em>A local-first research-paper reader that turns English papers into structured, bilingual study material.</em>
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

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## What Is Ilios? 📚

You are facing a dense thirty-page English paper. Your advisor expects a group-meeting presentation next week. A generic AI summary sounds fluent but hides what it skipped. A sentence-by-sentence translation still leaves the formula context, figures, terminology, and section logic disconnected.

Ilios starts from arXiv or local LaTeX source packages and turns the paper into sections, paragraphs, equations, figures, tables, captions, references, translations, questions, and lecture notes. You can read first in your native language, then return to the English original to calibrate terminology and phrasing. Your papers, sources, PDFs, translations, Q&A history, and notes remain in a local library folder that you choose.

The point is not to replace the English paper. The point is to make the first pass humane for students, graduate researchers, and cross-field readers whose native language is not English. Once the research logic is clear in your own language, the English original becomes something you can learn from instead of something that blocks entry. 🌱

The Chinese name is **衔牍**. The English name is **Ilios**. The Japanese name is **理紐**. Other languages currently use the English name.

## Why It Helps ✨

| Pain point | Ilios response |
| --- | --- |
| An English paper feels like a wall | Read by section, paragraph, equation, figure, and table instead of a flattened summary |
| Translation loses structure | Source, translation, captions, terms, and context stay aligned to document blocks |
| A formula or figure is unclear | Ask about the current block and keep cited paper evidence |
| A presentation is due soon | Generate editable lecture-note patches from reading templates |
| Cloud upload is unacceptable | Local-first FastAPI + React + SQLite, with no accounts or built-in sync |
| You use Obsidian or Notion | Export Markdown, lecture notes, and complete bundles |

## Current MVP

Ilios v0.1.0 can create local libraries, import arXiv source packages, import local TeX archives, import Markdown as weak structured documents, save PDFs as source artifacts, parse TeX with LaTeXML when installed, store structured document blocks and assets, build deterministic local block embeddings, translate paragraph and caption blocks through OpenAI-compatible or Anthropic-compatible providers, preserve translation variants, review translation memory, manage article glossary terms, store provider keys in macOS Keychain when available, stream article-grounded Q&A, create editable lecture-note patches, edit custom note templates, and export source, translated, bilingual, lecture-note, or full bundle artifacts.

The project remains local and lightweight. It does not use Docker, Redis, Celery, accounts, a hosted backend, or built-in cloud sync. PDFs can be imported and saved, but this MVP does not parse, open, OCR, translate, or embed PDFs in the reader.

## Multilingual Policy 🌍

Simplified Chinese and English are core maintained languages. Japanese is the third README and is marked Experimental. Korean, Spanish, French, and German README files are intentionally kept as Community contribution entry points until maintainers can keep them accurate.

The web interface already keeps multilingual hooks. Simplified Chinese and English should stay accurate with every release. Japanese, Korean, Spanish, French, and German are experimental or community-friendly UI languages and may fall back to English. Interface language follows the browser on first launch and can be changed in Settings.

## Quick Start

Ilios expects Node.js, pnpm, Python 3.13, and uv. Real TeX parsing requires `latexml` and `latexmlpost` on `PATH`. Asset conversion benefits from ImageMagick `magick`, Ghostscript `gs`, and a TeX engine such as `tectonic` or `pdflatex`.

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
git clone https://github.com/FA-T-T/bilin.git
cd bilin
pnpm install
cd apps/api
uv sync
cd ../..
make doctor
make dev
```

Open `http://127.0.0.1:5173`, create a library, then import an arXiv ID such as `1706.03762`. The technical CLI command remains `bilin` for compatibility:

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

If LaTeXML is missing, the app still starts, but TeX parse jobs fail explicitly with `missing_dependency:latexml`.

## License And Content Boundary

Ilios source code, project-owned documentation, tests, and project-owned fixtures are licensed under Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The license does not grant rights to user-imported papers, PDFs, TeX packages, figures, tables, captions, datasets, translations, or lecture notes containing third-party material. Exported Markdown and notes include an invisible HTML comment watermark reminding users to redistribute only when the original license or rights holder permits it.

For full installation, provider setup, local data placement, CLI usage, troubleshooting, and developer checks, use the Chinese main README first or contribute improvements to this English version.
