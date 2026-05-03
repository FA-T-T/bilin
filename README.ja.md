# Bilin

言語：[简体中文](README.md) | [English](README.en.md) | 日本語 | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## なぜ Bilin が必要なのか？📚✨

Bilin の目的は明確です。英語の PDF を一人で無理に読み進める作業を、構造化された読解、翻訳、質問、ノート作成、復習のワークフローに変えることです。Bilin は英語原文を置き換えるためのものではありません。また、論文を雑な AI 要約に変えるものでもありません。章、段落、数式、図表、caption、専門用語、質問、講義ノートを原文構造に沿って扱えるようにします。

研究者にとっての利便性は、分散しがちな作業を一つのローカルな流れにまとめられる点にあります。arXiv 論文やローカル TeX アーカイブを取り込み、段落単位の Markdown に解析し、ブロックごとに翻訳とキャッシュを行い、翻訳バリアントを残し、専門用語を管理し、現在の段落や論文全体について質問し、その回答を講義ノートとして蓄積し、Markdown や bundle として書き出せます。論文、PDF、TeX ソース、解析結果、翻訳キャッシュ、質問履歴、ノートは、ユーザーが選んだ library フォルダに保存されます。

英語を母語としない研究初心者にとって、この価値はさらに大きくなります。学部生、大学院生、新しい分野に入ったばかりの研究者は、知能が足りないのではなく、英語の長い文、密度の高い専門用語、数式の文脈、分野特有の書き方に同時に止められることが多いです。まず母語で背景、動機、重要な数式、実験の論理、限界を理解し、その後で英語原文に戻って用語と表現を確認する方が、最初から英語を一文ずつ苦労して読むより効率的です。この流れは、研究理解と学術英語の学習を同時に進めます。

Bilin は、研究入門のための最初の読解レイヤーとして設計されています。「この論文を読み切れない」を、「この論文が何を解こうとしているのか、なぜ重要なのか、どのように解いているのか、どこを英語原文で読み直すべきか分かる」に変えるための道具です。真剣な読解は、最後には必ず英語原文、数式、図表、引用に戻ります。Bilin は、その道を少し歩きやすくします。🌱

Bilin は、論文の読解、翻訳、質問応答、注釈、エクスポートを支援する local-first な Web アプリケーションです。主な入力は arXiv の TeX ソースです。TeX は、章、段落、数式、図、表、caption、label、引用、ソース資産など、真面目な論文読解に必要な構造を保持できるからです。Bilin は React + TypeScript のフロントエンド、FastAPI バックエンド、SQLite ジョブキュー、Python worker で構成され、自分のマシン上で動作します。Docker、Redis、Celery、アカウントシステム、ホスト型バックエンド、組み込みクラウド同期は不要です。

現在のバージョンは v0.1.0 MVP です。ローカル library の作成、arXiv source package の取り込み、ローカル TeX アーカイブの取り込み、Markdown の弱構造ドキュメント化、PDF の bundle 保存、LaTeXML がある環境での TeX 解析、構造化された document blocks と assets の保存、決定的なローカル block embeddings、OpenAI-compatible または Anthropic-compatible provider による段落と caption の翻訳、translation variants、translation memory のレビューと再利用、論文用語管理、macOS Keychain での provider key 保存、論文根拠に基づくストリーミング質問応答、編集可能な講義ノート patch、カスタム note template、各種 Markdown や bundle の export に対応しています。

## 今後の計画

今後は PDF LLM fallback parsing、任意の neural embedding provider、Word/EPUB/整形済み PDF export、デスクトップシェル、より整ったインストール形態を拡張方向として扱います。PDF はすでに source artifact として bundle に保存できます。将来の PDF 機能は、TeX 優先の主経路を変えず、既定で OCR や重いサービス依存を導入しない任意の解析経路として追加されます。アカウントシステムと組み込み同期は既定の製品方向には入りません。Bilin は local-first を保ち、library フォルダを iCloud、OneDrive、Syncthing などの外部同期ツールで扱いやすくします。

## リポジトリ構成

`apps/api` は FastAPI バックエンド、CLI、SQLite migrations、arXiv とアップロード取り込み、LaTeXML parser path、provider profiles、translation jobs、deterministic local embeddings、glossary、question answering、lecture-note、export、worker、doctor command を含みます。

`apps/web` は Vite + React + TypeScript フロントエンドです。Mantine、TanStack Query、Zustand、KaTeX、React Markdown、Playwright/Vitest を使います。

`docs` には設計、MVP 計画、local-safety notes、開発者向け文書があります。`fixtures/golden` には deterministic parser regression fixtures があります。

## 必要環境

Bilin には Node.js、pnpm、Python 3.13、uv が必要です。TeX 解析には `latexml` と `latexmlpost` が `PATH` 上に必要です。画像や asset 変換では ImageMagick の `magick`、Ghostscript の `gs`、`tectonic` または `pdflatex` が役立ちます。

macOS + Homebrew では次のように準備できます。

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Linux ではディストリビューションのパッケージマネージャで対応するツールを入れてください。LaTeXML がなくても、Markdown import、PDF save-only import、provider 設定、翻訳、ノート、export、fixture tests は動きます。TeX parse job は `missing_dependency:latexml` として明確に失敗します。

## インストール

ソースディレクトリまたはダウンロードしたプロジェクトディレクトリから始めます。

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

最初に doctor を実行してください。

```sh
make doctor
```

## アプリの起動

API、worker、web をまとめて起動します。

```sh
make dev
```

個別に起動することもできます。

```sh
make api
make worker
make web
```

起動後、`http://127.0.0.1:5173` を開きます。library を作成し、名前とローカルフォルダを指定してください。library は `library.sqlite`、source package、PDF、展開済み TeX、`document.json`、`source.md`、assets、logs、lecture notes、exports、manifest を含む持ち運び可能なフォルダです。

## 最初の論文

library を作成したら、Library ページから Add article panel を使います。通常は `1706.03762` のような arXiv ID を入力します。Bilin は source package と PDF をダウンロードし、自己完結した article bundle を作り、必要なら parse job をキューに入れます。ローカル TeX archive は arXiv source package と同じ bundle 経路を使います。Markdown はすぐに弱構造ドキュメントになります。PDF は現在の MVP では保存のみで、解析、表示、OCR、翻訳は行いません。

document が生成されると、article table から reader を開けます。Reader には Study、Focus、Bilingual、Translation、Source view があります。章は折りたたみ可能な Chapters control で扱えます。段落 block には hover toolbar があり、コピー、source LaTeX の確認、現在段落への質問、再翻訳ができます。

## Provider 設定

Settings の Models を開きます。simple mode では API key を貼り付けると、OpenAI-compatible または Anthropic-compatible endpoint からモデル一覧を取得し、表示名で選べます。advanced mode では profile label、base URL、concurrency、requests per minute も設定できます。

provider key は library フォルダには保存されません。macOS では既定で Keychain に保存され、global application database には `keychain:` reference だけが残ります。Keychain fallback を止めたい場合は次を設定します。

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## 翻訳と Translation Memory

翻訳は block 単位で実行されます。段落と caption は翻訳され、数式と構造化 environment block は source structure として保持されます。翻訳は variant として保存されるため、再翻訳しても以前の結果は上書きされません。

検証済み翻訳は、最初は `pending` の translation memory として保存されます。Settings の Translation memory で確認し、`approved` かつ reuse 有効にしたものだけが後続の論文で再利用されます。

## 質問応答と講義ノート

Reader では論文全体または選択中 block について質問できます。Bilin はローカル index から論文根拠を取得し、回答を stream し、引用した block refs を保存します。選択した model profile が native search をサポートする場合だけ外部検索を有効にできます。

講義ノートは編集可能な patch から作られます。精読、グループミーティング、素早いスキム、再現性重視の built-in template があり、ユーザー独自の template も保存できます。accepted notes は article bundle 内の `lecture-notes.md` に保存されます。

## CLI

CLI command は `bilin` です。`apps/api` から `uv run` で実行します。

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

article revision id が分かっている場合は parse、embedding、export を直接実行できます。export された Markdown と生成された lecture notes には、Bilin が生成したこと、第三者の論文内容や派生内容を含む可能性があること、再配布は元のライセンスまたは権利者が許す場合に限ることを示す不可視 HTML comment watermark が自動で入ります。

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

## ローカルデータと同期

Bilin は app-level SQLite state、registered libraries、provider metadata、jobs、settings、note templates、translation memory、Keychain fallback storage を global application data directory に保存します。場所は `platformdirs` で決まり、開発時は `BILIN_HOME` で上書きできます。

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

library はユーザーが選ぶ自己完結フォルダです。iCloud、OneDrive、Syncthing などの外部同期ツールで同期しやすい構造です。Bilin 自体は同期衝突を解決しません。

## 開発者チェック

backend check は `apps/api` で実行します。

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

frontend check は repository root で実行します。

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

## ライセンス

Bilin の source code、project-owned documentation、tests、project-owned fixtures は Apache-2.0 でライセンスされています。`LICENSE` と `NOTICE` を参照してください。このライセンスは Bilin 自体にのみ適用され、ユーザーが取り込んだ論文、PDF、TeX source package、図表、caption、dataset、機械翻訳、第三者内容を含む lecture notes には権利を与えません。

## トラブルシューティング

API に接続できない場合は `make api` が動いていること、`http://127.0.0.1:8000/health` が JSON を返すことを確認してください。TeX parse が `missing_dependency:latexml` で失敗する場合は LaTeXML をインストールし、`bilin doctor` で `latexml` と `latexmlpost` が見えることを確認してください。
