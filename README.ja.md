<h1 align="center">
  理紐 (LLM 支援論文読解)<br>
  <sub><sub>衔牍 · Ilios</sub></sub>
</h1>

<p align="center">
  <em>多言語論文読解ツール</em>
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

## 理紐とは

理紐は、英語論文を多言語で理解したい研究者のための **local-first で構造化された** 論文読解ワークスペースです。

完全にローカルで動作し、arXiv source package またはローカル LaTeX archive を扱えます。

論文、解析結果、翻訳 cache、Q&A 履歴、notes はすべてユーザーが指定した local folder に保存されます。**登録不要、hosted backend なし、file upload なし** です。

翻訳コストは低く抑えられます。DeepSeek V4 Flash で 10 本、合計 240 ページの論文を処理したテストでは、総費用は約 2 元でした。

## 主な機能

##### **多言語**

スクリーンショット内の論文本文、図表、数式は原著者または権利者に帰属します。ここでは理紐のローカル読解、翻訳、Q&A、構造化 rendering の表示例としてのみ使用しています。

中国語の例:

<img src="./assets/image-20260522193937577.png" alt="Chinese translation example" style="zoom: 25%;" />

フランス語の例:

<img src="./assets/image-20260522194355907.png" alt="French translation example" style="zoom:25%;" />

日本語の例:

<img src="./assets/image-20260522193846703.png" alt="Japanese translation example" style="zoom:25%;" />

ドイツ語の例:

<img src="./assets/image-20260522194717793.png" alt="German translation example" style="zoom:25%;" />

韓国語の例:

<img src="./assets/image-20260522194157385.png" alt="Korean translation example" style="zoom:25%;" />

##### 図

<img src="./assets/image-20260522194901555.png" alt="Figure rendering example" style="zoom: 25%;" />

##### 数式

KaTeX rendering。

<img src="./assets/image-20260522195038561.png" alt="Formula rendering example" style="zoom:25%;" />

##### 表

HTML table として再 rendering します。

<img src="./assets/image-20260522195134674.png" alt="Table rendering example" style="zoom:25%;" />

##### 文ホバー強調

文単位に分割することで、対訳比較がしやすくなります。

![Sentence hover highlighting](./assets/image-20260522195506879.png)

##### 引用プレビュー

引用を自動解析し、Google Scholar と arXiv 検索を利用できます。ワンクリックで文庫へ追加し、自動翻訳することもできます。

<img src="./assets/image-20260522202145628.png" alt="Citation preview example" style="zoom: 33%;" />

##### 原文または訳文の Markdown export

原文 Markdown または訳文 Markdown を export し、knowledge base document として直接利用できます。

<img src="./assets/image-20260522202353196.png" alt="Markdown export example" style="zoom:25%;" />

##### Kindle mode

Kindle mode は、同じ local network 上の e-ink device が browser から読むための軽量表示です。scrolling をなくし、左右に page-turn button を追加します。

10 inch 以上の e-ink device を横向きで使うことを推奨します。

![Kindle mode example](./assets/image-20260522202534656.png)

## Quick Start

### Agent users (Codex, Claude, DeepSeek-TUI, OpenCode...)

この page link を agent に直接送り、次のように依頼してください。

"https://github.com/FA-T-T/bilin Please help me deploy this service, install the required dependencies, and start the app."

agent は依存関係の install、deployment、application startup を自動で進められます。

### 一般ユーザー

理紐には Node.js、pnpm、Python 3.13、uv が必要です。core app は TeX toolchain なしでも起動できますが、実際の LaTeX parsing には `latexml` と `latexmlpost` が `PATH` 上に必要です。image と PDF 処理には ImageMagick `magick`、Ghostscript `gs`、`tectonic` または `pdflatex` を推奨します。

macOS + Homebrew 環境:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

source から起動:

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

固定された開発環境では quick start script を使えます。既存の virtual environment と `node_modules` を再利用し、環境検査を省略し、すでに起動済みなら status を返します。

```sh
./scripts/start-dev.sh
```

起動後 `http://127.0.0.1:5173` を開きます。API は標準で `127.0.0.1:8000`、worker は import、parsing、translation、Q&A、notes、export job を処理します。debug には `make api`、`make worker`、`make web` を個別に実行できます。

LaTeXML がない場合でも、理紐は Markdown import、PDF 保存、model configuration、translation、notes、export、fixture tests を利用できます。TeX parse job は `missing_dependency:latexml` として明示的に失敗し、不安定な regex parsing に暗黙 fallback しません。

## 最初の論文

home page で library を作成し、名前と local directory path を入力します。library は self-contained folder で、`library.sqlite`、original source archive、PDF、unpacked TeX、parsed `document.json`、`source.md`、assets、logs、notes、exports、manifests を含みます。

library に入ったら、`1706.03762` のような arXiv ID を入力します。理紐は source package と PDF を download し、self-contained article package を作成し、parsing が有効なら task を queue に入れます。local TeX archive も同じ package path を使います。Markdown は弱構造 document として即時 import され、PDF は source file として保存されます。

parsing 完了後、文庫で論文を選択し、Read をクリックして reader に入ります。reader は Study、Bilingual、Translation、Source の 4 view を提供します。left rail で同じ library 内の論文を切り替え、right rail から tasks、model setup、paper chat、translation、glossary、notes、export tool を開けます。paragraph hover action で copy、source inspection、retranslation、current paragraph question ができます。figure と table は asset があれば直接表示され、欠落している場合も caption と label を保った structured placeholder が表示されます。

## Model configuration

Settings -> Models を開きます。simple mode では API key を貼り付けると、互換 endpoint から model list を取得します。advanced mode では profile label、base URL、concurrency、requests-per-minute limit を設定できます。**advanced mode の利用を推奨します。**

provider key は library folder には保存されません。macOS では標準で Keychain に保存し、global database には `keychain:` reference だけを保存します。他の platform、または `BILIN_CREDENTIAL_STORE=app_settings` を設定した場合は SQLite development fallback を使います。Keychain が使えない場合に provider creation を拒否したいときは、次を設定します。

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

CLI は Web app と同じ backend logic を再利用します。

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

repository には golden fixtures が含まれており、network access や完全な TeX toolchain がなくても reader pipeline を検証できます。

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

command は `reader_route` と `library_id` を返します。app を起動し、browser で該当 route を開くと生成された article を確認できます。

## Local data, security, sync

理紐は global application data directory に app-level SQLite state、registered libraries、provider configuration、jobs、settings、note templates、translation memory、Keychain が使えないまたは無効な場合の API key fallback storage を保存します。この directory は `platformdirs` で決まり、development 時は `BILIN_HOME` で上書きできます。

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library directory は user-selected な self-contained folder で、iCloud、OneDrive、Syncthing などの外部 sync tool に向いています。理紐自体は sync conflict を処理しません。app を閉じてから sync し、conflict は sync tool の version history から復元してください。

export された Markdown と lecture notes には、理紐が生成した file であり third-party content を含み得ることを示す invisible HTML comment watermark が自動で入ります。watermark は通常の読解 layout には影響しません。

## Developers

backend checks は `apps/api` で実行します。

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

frontend checks は repository root で実行します。

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

default tests は fixtures と mocks を使い、real network や完全な TeX toolchain を要求しません。real arXiv と LaTeXML integration tests は明示的な opt-in です。

## License

理紐 / Ilios / 衔牍 の source code、project-owned documentation、tests、project-owned fixtures は Apache-2.0 で license されています。[LICENSE](LICENSE) と [NOTICE](NOTICE) を参照してください。この license は理紐 project 自体だけを対象とし、user-imported papers、PDFs、TeX source packages、figures、captions、datasets、machine translations、third-party material を含む lecture notes には適用されません。exports の再配布は、原論文または素材の license、rights-holder permission、または適用法上の例外に従う必要があります。

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  凿壁借光，衔牍而来。文献の論理と知恵を、あなたの机上へ届けます。<br><br>
  <strong>理紐</strong><br>
  論理の紐を結ぶ者。あなたと著者の思考をつなぐ架け橋。<br><br>
  <em>理紐が論文読解の夜を少し短くできたなら、Star を付けて、より多くの研究初心者がこの光を見つけられるようにしてください。</em>
</p>
