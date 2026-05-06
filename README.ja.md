<h1 align="center">
  理紐<br>
  <sub><sub>衔牍 · Ilios</sub></sub>
</h1>

<p align="center">
  <em>英語論文を、構造化された母語読解、対訳、質問、講義ノートへ変える local-first な研究支援アプリです。</em>
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

## 理紐とは？📚

この日本語 README は Experimental です。簡体中文 と English が core maintained であり、日本語の説明は更新が遅れる場合があります。

英語の長い論文を前にして、来週のゼミ発表までに内容を理解しなければならない。一般的な AI 要約は流暢でも、どの細部が省かれたのか分からない。逐語訳だけでは、数式、図表、専門用語、章構造がつながらない。理紐はこの最初の壁を低くするための道具です。

理紐は arXiv またはローカル LaTeX source package から、論文を章、段落、数式、図、表、caption、引用、翻訳、質問、講義ノートへ分解します。まず母語で研究の筋道を理解し、その後で英語原文に戻って用語と表現を確認できます。論文、source、PDF、翻訳 cache、質問履歴、notes はすべてユーザーが選んだ local library folder に保存されます。

目的は英語原文を置き換えることではありません。研究の入口でつまずかないようにし、最後には英語原文、数式、図表、引用へ戻れるようにすることです。🌱

中国語名は **衔牍**、英語名は **Ilios**、日本語名は **理紐** です。他の言語では当面 Ilios を使用します。

## 現在の MVP

v0.2.0 MVP は local library の作成、arXiv source package import、local TeX archive import、Markdown の弱構造 document import、PDF の source artifact 保存、LaTeXML による TeX parsing、structured document blocks と assets の保存、real figure/table rendering、OpenAI-compatible または Anthropic-compatible provider による paragraph/caption translation、parser update 後の translation variant preservation、translation memory review、article glossary、macOS Keychain provider key storage、article-grounded streaming Q&A、Obsidian への bilingual excerpt 保存、editable lecture-note patches、custom note templates、browser download による Markdown/bundle export を備えています。

理紐は local-first かつ lightweight です。Docker、Redis、Celery、account system、hosted backend、built-in cloud sync は使いません。PDF は import と保存ができますが、この MVP では parse、open、OCR、translate、reader embed は行いません。

## 多言語方針 🌍

主 README は简体中文、第二 README は English、第三 README はこの日本語版です。한국어、Español、Français、Deutsch の README は Community contribution placeholder として残しています。

UI には多言語 interface が用意されています。简体中文 と English は core language です。日本語、한국어、Español、Français、Deutsch は experimental/community language であり、一部 English に fallback する場合があります。初回起動時は browser language に従い、Settings でいつでも変更できます。

## Quick Start

Node.js、pnpm、Python 3.13、uv が必要です。実際の TeX parsing には `latexml` と `latexmlpost` が必要です。asset conversion には ImageMagick `magick`、Ghostscript `gs`、`tectonic` または `pdflatex` が役立ちます。

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

起動後 `http://127.0.0.1:5173` を開き、library を作成して arXiv ID、たとえば `1706.03762` を import します。technical CLI command は互換性のため `bilin` のままです。

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

LaTeXML がない場合でも app は起動しますが、TeX parse job は `missing_dependency:latexml` として明示的に失敗します。

## License

理紐 / Ilios / 衔牍 の source code、project-owned documentation、tests、project-owned fixtures は Apache-2.0 で license されています。[LICENSE](LICENSE) と [NOTICE](NOTICE) を参照してください。この license はユーザーが import した papers、PDFs、TeX packages、figures、tables、captions、datasets、translations、third-party material を含む lecture notes には権利を与えません。export された Markdown と notes には、再配布は元の license または rights holder が許す場合に限るという invisible HTML comment watermark が含まれます。
