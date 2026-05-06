<h1 align="center">
  衔牍<br>
  <sub><sub>Ilios · 理紐</sub></sub>
</h1>

<p align="center">
  <em>把英文论文拆开，先读懂，再回到原文深读。</em>
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

## 衔牍是什么？📚

你刚进入一个研究方向，导师给你一篇 30 页英文论文，让你下周组会汇报。你打开 PDF，发现 Introduction 就卡了半小时。你试过把论文丢给通用 AI，它给的总结很顺，但你不知道哪些细节被跳过了。
你也试过逐句翻译插件，整篇译完还是一头雾水，因为公式、图表、术语和章节逻辑没有真正被你理解。

第二语言是科研入门的巨大障碍, 在真正的进入研究之前, 你首先被匮乏的领域性知识打败了. 反复的在检索, 翻译, 碎片化理解之间周旋, 这有用, 但是太低效了.

然后你打开衔牍。它从 arXiv 或本地 LaTeX 源码包开始，把论文拆成章节、段落、公式、图和表。你可以先用母语消化每个段落，再随时回到英文原文校准术语。你可以针对当前段落提问，也可以把问答沉淀成组会讲义。论文、源码、PDF、翻译缓存、问答和笔记都保存在你选择的本地 library 文件夹里，不需要账号，也不需要上传到云端。

衔牍的目标不是替代英文原文，它是科研入门的第一层：先辅助你读懂研究本身，再把你带回英文原文。对母语不是英语的大学生、研究生和跨领域研究者来说，这条路径通常更快，也更稳。先用母语理解问题背景、方法动机和实验逻辑，再回头学习作者如何用英文表达这些概念，你同时在学习研究和学术英语。🌱


## 它解决什么问题？✨

| 你的痛点 | 衔牍的回应 |
| --- | --- |
| 理解英文论文效率低 | 以母语阅读 |
| 公式或图表不知道在讲什么 | 针对当前 block 提问，回答保存引用到的论文证据 |
| 下周要组会汇报 | 内置精读、组会、快速扫读和复现导向讲义模板 |
| 以后想整理到知识库 | 一键保存段落到 OneDrive 中的 Obsidian vault，也可以导出 Markdown、lecture notes 和完整 bundle |

## 衔牍已经能做什么？

它已经支持创建本地 library，导入 arXiv source package，导入本地 TeX archive，把 Markdown 导入为弱结构文档，把 PDF 作为源文件保存进 bundle，在本机安装 LaTeXML 时解析 TeX，保存结构化 document blocks 和 assets，构建确定性的本地 block embeddings，通过 OpenAI-compatible 或 Anthropic-compatible provider 翻译段落和 caption，保存多个 translation variants，审核并复用 translation memory，管理文章术语，使用 macOS Keychain 保存 provider key，在文章证据范围内流式问答，生成可编辑的讲义笔记 patch，编辑自定义笔记模板，一键把中英文段落摘录保存到 Obsidian，并导出 source、translated、bilingual、lecture-note 或完整 bundle artifact。

完整功能说明见 [docs/user-feature-guide.md](docs/user-feature-guide.md)。这份文档解释了 Reader 的 Study、Focus、Bilingual、Translation 和 Source 模式，也说明了颜色标记、Obsidian 联动、段落工具栏、术语、问答、讲义和导出的实际用法。

## 界面语言 🌍

衔牍提供简体中文、English、日本語、한국어、Español、Français 和 Deutsch 入口。第一次打开时，界面会跟随浏览器语言；之后可以在 Settings 的 Interface 页面随时切换。部分语言的文案仍可能回退到 English，但不会影响导入、阅读、翻译、问答和导出流程。
## 快速开始

衔牍需要 Node.js、pnpm、Python 3.13 和 uv。核心应用可以在没有 TeX 工具链的情况下启动，但真实 TeX 解析需要 `latexml` 和 `latexmlpost` 在 `PATH` 上。图像和资产转换建议安装 ImageMagick `magick`、Ghostscript `gs`，以及 `tectonic` 或 `pdflatex`。

macOS + Homebrew 可以这样准备环境。

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

从源码启动。

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

启动后打开 `http://127.0.0.1:5173`。API 默认在 `127.0.0.1:8000`，worker 会处理导入、解析、翻译、问答、笔记和导出任务。也可以分别运行 `make api`、`make worker` 和 `make web` 来调试。

如果没有 LaTeXML，衔牍仍能启动，Markdown 导入、PDF save-only 导入、provider 设置、翻译、笔记、导出和 fixture 测试仍然可用。TeX parse job 会明确失败为 `missing_dependency:latexml`，不会悄悄 fallback 到不稳定的正则解析。

## 第一篇论文

先在首页创建一个 library，填写名称和本地目录路径。一个 library 是可携带的文件夹，包含 `library.sqlite`、原始 source package、上传或下载的 PDF、解包后的 TeX、解析后的 `document.json`、生成的 `source.md`、assets、logs、lecture notes、exports 和 bundle manifests。

进入 library 后，可以输入 arXiv ID，例如 `1706.03762`。衔牍会下载 source package 和 PDF，创建自包含 article bundle，并在启用 parse 时排队解析任务。本地 TeX archive 复用同样的 bundle 路径。Markdown 会立即导入为弱结构 document。PDF 只保存为源文件。

解析完成后，从 article table 打开 reader。Reader 支持 Study、Focus、Bilingual、Translation 和 Source 视图。章节通过可折叠 Chapters 控件提供。段落 hover 后会显示复制、查看源 LaTeX、针对当前段落提问和重新翻译等操作。图和表在存在真实 asset 时显示 asset；缺失 asset 时保留 caption、label 和结构化 fallback，而不是假装已经渲染成功。

## 配置模型

进入 Settings 的 Models 页签。简单模式下粘贴 API key，衔牍会从 OpenAI-compatible 或 Anthropic-compatible endpoint 请求可用模型列表，让你按显示名称选择模型。高级模式下可以设置 profile label、base URL、并发数和每分钟请求数。普通用户不需要猜 provider 内部 model name。

Provider key 不会保存到 library 文件夹。macOS 上，衔牍默认把 key 存到 Keychain，全局数据库只保存 `keychain:` 引用。其他平台、CI，或显式设置 `BILIN_CREDENTIAL_STORE=app_settings` 时，会使用 SQLite 开发 fallback。如果你希望 Keychain 失败时直接阻止 provider 创建，可以设置：

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

复用和 Web app 相同的后端服务逻辑。

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

仓库包含 golden fixtures，因此新机器可以在没有公网 arXiv 访问、没有 LaTeXML 的情况下验证 reader pipeline。

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

这个命令会返回 `reader_route` 和 `library_id`。启动应用后，在浏览器中打开返回的 route 即可检查生成文章。

## 本地数据、安全和同步

衔牍使用全局应用数据目录保存 app-level SQLite state、registered libraries、provider profile metadata、jobs、settings、note templates、translation memory，以及 Keychain 不可用或被禁用时的 API-key fallback storage。这个目录由 `platformdirs` 决定，开发时可以用 `BILIN_HOME` 覆盖。

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library 目录由用户选择，并且设计成自包含文件夹。这使它适合被 iCloud、OneDrive 或 Syncthing 等外部文件夹同步工具同步。衔牍自己不解决同步冲突。移动或合并 synced library 前，请先关闭衔牍，并通过外部同步工具的 version history 恢复冲突。

导出的 Markdown 和生成的讲义会自动包含不可见 HTML 注释水印，说明该文件由衔牍生成、可能包含第三方论文内容或派生内容，并提醒只在原始许可或权利人允许时再分发。这个水印不会改变正常阅读排版。

## 未来计划

后续版本会把 PDF LLM fallback parsing、可选 neural embedding provider、Word/EPUB/精排 PDF 导出、桌面壳和更完整的安装形态作为扩展方向。PDF 当前已经能作为源文件进入 bundle；未来 PDF 能力会以可选解析链路接入，不改变 TeX 优先的主路径，也不会引入默认 OCR 或重型服务依赖。账号系统和内置同步不进入默认产品方向，衔牍会继续保持本地优先。

## 开发者检查

后端检查在 `apps/api` 中运行。

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

前端检查在仓库根目录运行。

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

默认测试使用 fixtures 和 mocks，不要求真实 arXiv 网络，也不要求完整 TeX 工具链。真实 arXiv 和真实 LaTeXML integration test 是显式 opt-in 的。

## 许可证

衔牍源代码、项目自有文档、测试和项目自有 fixtures 使用 Apache-2.0 许可证，见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。这个许可证只覆盖衔牍项目本身，不覆盖用户导入的论文、PDF、TeX 源码包、图表、caption、数据集、机器翻译稿或讲义中包含的第三方内容。导出物是否可以再分发，取决于原论文或素材的许可证、权利人授权或适用的法律例外。

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  凿壁借光，衔牍而来。将文献的逻辑与智慧，衔至你的案前。<br><br>
  <strong>理紐</strong><br>
  論理の紐を結ぶ者。あなたと著者の思考をつなぐ架け橋。<br><br>
  <em>如果衔牍帮你少熬一个读论文的夜晚，给项目一个 Star，会让更多科研新人找到这束光。</em>
</p>
