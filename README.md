# Bilin

语言：简体中文 | [English](README.en.md)

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

Bilin 是一个本地优先的论文阅读、翻译、问答、笔记和导出工具。它优先面向 arXiv TeX 源码包，而不是 PDF，因为 TeX 能保留严肃论文阅读真正需要的结构信息，包括章节、段落、公式、图、表、caption、label、引用和源文件资产。Bilin 运行在你自己的机器上，由 React + TypeScript 前端、FastAPI 后端、SQLite 后台任务队列和 Python worker 组成。它不需要 Docker、Redis、Celery、账号系统、托管后端或内置云同步。

当前仓库是 v0.1.0 MVP 发布版本。它已经可以创建本地 library，导入 arXiv source package，导入本地 TeX archive，把 Markdown 导入为弱结构文档，把 PDF 作为源文件保存进 bundle，在本机安装 LaTeXML 时解析 TeX，保存结构化 document blocks 和 assets，构建确定性的本地 block embeddings，通过 OpenAI-compatible 或 Anthropic-compatible provider 翻译段落和 caption，保存多个 translation variants，审核并复用 translation memory，管理文章术语，使用 macOS Keychain 保存 provider key，在文章证据范围内流式问答，生成可编辑的讲义笔记 patch，编辑自定义笔记模板，并导出 source、translated、bilingual、lecture-note 或完整 bundle artifact。

## 未来计划

后续版本会把 PDF LLM fallback parsing、可选神经 embedding provider、Word/EPUB/精排 PDF 导出、桌面壳和更完整的发布形态作为扩展方向。PDF 当前已经能作为源文件进入 bundle；未来的 PDF 能力会以可选解析链路接入，不改变 TeX 优先的主路径，也不会引入默认 OCR 或重型服务依赖。账号系统和内置同步不进入默认产品方向，Bilin 会继续保持本地优先，让 library 文件夹便于被 iCloud、OneDrive、Syncthing 等外部工具同步。

## 项目结构

`apps/api` 是后端。里面包含 FastAPI 服务、`bilin` CLI、SQLite migrations、arXiv 和本地上传导入、LaTeXML parser path、provider profiles、translation jobs、deterministic local embeddings、glossary services、question answering、lecture-note services、export services、worker 和 doctor command。

`apps/web` 是前端。它是 Vite + React + TypeScript 应用，使用 Mantine、TanStack Query、Zustand、KaTeX、React Markdown 和 Playwright/Vitest 测试链路。

`docs` 保存设计文档、MVP 执行队列、本地安全说明和 GitHub 发布流程。`fixtures/golden` 保存 deterministic parser regression fixtures，用于测试和无网络验收。

## 环境要求

Bilin 需要 Node.js、pnpm、Python 3.13 和 uv。前端使用 pnpm 10.32.1。后端使用 uv 创建和管理 Python 环境。核心应用可以在没有 TeX 工具链的情况下启动，但真实 TeX 解析需要 `latexml` 和 `latexmlpost` 都在 `PATH` 上。可选的图像和资产转换会用到 ImageMagick 的 `magick`、Ghostscript 的 `gs`，以及 `tectonic` 或 `pdflatex` 这类 TeX engine。

macOS + Homebrew 环境下，一个比较完整的开发安装方式如下。

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Linux 用户可以用发行版包管理器安装对应工具。如果没有 LaTeXML，Markdown 导入、PDF save-only 导入、provider 设置、翻译、笔记、导出和 fixture 测试仍然可以工作。TeX parse job 会明确失败为 `missing_dependency:latexml`，。

## 安装

从 fresh checkout 或 release archive 开始，在仓库根目录安装前端依赖，然后初始化后端环境。

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

第一次运行前先执行 doctor。它会报告应用数据目录、macOS Keychain 能力和本地文档工具状态。缺失可选工具不会阻止启动，只会让相关功能降级。

```sh
make doctor
```

## 启动应用

开发时可以用一个命令同时启动 API、worker 和 web。API 默认监听 `127.0.0.1:8000`，worker 在旁边处理后台任务，Vite web app 默认监听 `127.0.0.1:5173`。

```sh
make dev
```

也可以分别启动三个进程，方便调试。

```sh
make api
make worker
make web
```

启动后打开 `http://127.0.0.1:5173`。先创建一个 library，填入名称和本地目录路径。一个 library 是一个可携带的文件夹，包含 `library.sqlite`、原始 source package、上传或下载的 PDF、解包后的 TeX、解析后的 `document.json`、生成的 `source.md`、assets、logs、lecture notes、exports 和 bundle manifests。

## 第一篇论文

创建 library 后，从 Library 页面进入该 library，使用 Add article 面板添加论文。常规路径是输入 arXiv ID，例如 `1706.03762`。Bilin 会下载 source package 和 PDF，创建自包含 article bundle，并在启用 parse 时排队解析任务。本地 TeX archive 会复用和 arXiv source package 相同的 bundle 路径。Markdown 会立即导入成弱结构文档。PDF 只会被保存为源文件，不会在当前 MVP 中解析或翻译。

解析或导入生成 document 后，可以从 article table 打开 reader。Reader 支持 Study、Focus、Bilingual、Translation 和 Source 视图。章节以可折叠 Chapters 控件提供。段落 block 支持 hover 工具栏，可复制、查看源 LaTeX、针对当前段落提问和重新翻译。图和表会在存在真实 asset 时显示 asset，同时保留 caption、label 和结构化引用；缺失 asset 时保留结构化 fallback，而不是伪装成已经渲染成功。

## 配置模型 Provider

进入 Settings 的 Models 页签。简单模式下，粘贴 API key，Bilin 会向 OpenAI-compatible 或 Anthropic-compatible endpoint 请求可用模型列表，然后让用户按显示名称选择模型。高级模式下，还可以设置 profile label、base URL、并发数和每分钟请求数。Bilin 不要求普通用户手动猜测 provider 内部 model name。

Provider key 不会保存到 library 文件夹。macOS 上，Bilin 默认把 key 存到 Keychain，全局数据库里只保存 `keychain:` 引用。其他平台、CI，或显式设置 `BILIN_CREDENTIAL_STORE=app_settings` 时，会使用 SQLite 开发 fallback。如果你希望 Keychain 失败时直接阻止 provider 创建，而不是 fallback，可以设置下面的环境变量。

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## 翻译与 Translation Memory 审核

翻译任务按 block 执行。普通段落和 caption 会被翻译；公式和结构化环境 block 会保留源结构。每次翻译都会保存为 translation variant，因此重新翻译不会覆盖旧结果。每个 block 的默认 variant 会被持久化。

通过基础校验的翻译会进入应用级 translation memory，但默认状态是 `pending`，不会影响其他论文。进入 Settings 的 Translation memory 页签，可以按语言和审核状态查看条目。只有审核为 `approved` 且启用 reuse 的条目，才会在后续论文中被跨文章复用。你可以随时 disable 或 reject 某个 memory entry；这不会删除原文章里的本地 translation variant。

## 问答与讲义笔记

Reader 可以针对整篇文章或当前选中的 block 提问。Bilin 会从本地索引检索文章证据，流式生成答案，并保存 cited block references。如果选中的 model profile 声明支持 native search，用户可以启用外部模型原生检索；否则回答会限制在文章上下文内。

讲义笔记由可编辑 patch 构成。内置模板覆盖精读、组会、快速扫读和复现导向阅读。用户也可以在 Notes 面板保存自定义模板。模型生成的 proposed patch 可以先修改再接受。接受后的笔记会写入 article bundle 内的 `lecture-notes.md`。

## CLI 使用

CLI 命令名是 `bilin`。在 `apps/api` 目录中通过 `uv run` 调用，它复用和 web app 相同的后端服务逻辑。最小 CLI 路径是创建 library、导入论文、运行 worker 或直接 parse，然后导出结果。

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

如果已经知道 article revision id，可以直接 parse、构建本地 embedding 或导出。导出的 Markdown 和生成的讲义会自动包含不可见的 HTML 注释水印，说明该文件由 Bilin 生成、可能包含第三方论文内容或派生内容，并提醒只在原始许可或权利人允许时再分发。这个水印不会改变正常阅读排版。

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

Provider profile 也可以用 CLI 创建，但 Web Settings 页面更适合做模型发现。

```sh
uv run bilin provider create --name "OpenAI Compatible" --protocol openai-compatible --api-key "$OPENAI_API_KEY" --model gpt-5.5
```

## 无网络验收路径

仓库包含 golden fixtures，因此新机器可以在没有公网 arXiv 访问、没有 LaTeXML 的情况下验证 reader pipeline。下面的 acceptance 命令会创建一个一次性 library，导入 golden source，用保存好的 converter output 生成 reader-ready document，并导出 MVP artifact set。

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

命令会返回 `reader_route` 和 `library_id`。启动应用后，在浏览器中打开返回的 route 即可检查生成的文章。

## 本地数据与同步

Bilin 使用全局应用数据目录保存 app-level SQLite state、registered libraries、provider profile metadata、jobs、settings、note templates、translation memory，以及 Keychain 不可用或被禁用时的 API-key fallback storage。这个目录由 `platformdirs` 决定。开发时可以用 `BILIN_HOME` 覆盖。

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library 目录由用户选择，并且设计成一个自包含文件夹。这使它适合被 iCloud、OneDrive 或 Syncthing 这类外部文件夹同步工具同步。Bilin 自己不解决同步冲突。移动或合并 synced library 前，请先关闭 Bilin；如果两台机器同时编辑同一个 library，请通过外部同步工具的 version history 恢复冲突。

## 质量检查

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

## GitHub 发布打包

仓库提供 release packaging 脚本。它会从当前 working tree 构建干净源码 archive，排除本地数据、虚拟环境、node modules、缓存、测试输出、SQLite 数据库和构建产物。

```sh
./scripts/package-release.sh
```

脚本会在 `release/` 下生成 `bilin-v0.1.0-source.tar.gz`、`bilin-v0.1.0-source.zip` 和对应 SHA-256 文件。如果你希望 GitHub Release 附带显式 release assets，而不仅使用 GitHub 自动生成的 Source code archive，可以上传这些文件。

发布前应运行上面的质量检查，并在临时目录或新机器上检查 release archive。一个合格 release candidate 应该可以安装依赖、运行 `make doctor`、运行 golden acceptance、启动 `make dev`，并打开生成的 reader route，而不依赖任何被排除在 archive 外的本机文件。详细发布 checklist 在 `docs/github-release.md`，GitHub release body 可以使用 `RELEASE_NOTES.md`。

## 许可证

Bilin 源代码、项目自有文档、测试和项目自有 fixtures 使用 Apache-2.0 许可证，见 `LICENSE` 和 `NOTICE`。这个许可证只覆盖 Bilin 项目本身，不覆盖用户导入的论文、PDF、TeX 源码包、图表、caption、数据集、机器翻译稿或讲义中包含的第三方内容。导出物是否可以再分发，取决于原论文或素材的许可证、权利人授权或适用的法律例外。

## 常见问题

如果 API 无法访问，先确认 `make api` 正在运行，并检查 `http://127.0.0.1:8000/health` 是否返回 JSON。如果 web app 无法连接 API，确认 Vite 正在 `127.0.0.1:5173` 运行，并排除浏览器扩展阻止 localhost 请求的情况。

如果 TeX parse 失败并显示 `missing_dependency:latexml`，安装 LaTeXML，并确认 `bilin doctor` 中能看到 `latexml` 和 `latexmlpost`。Bilin 不会静默 fallback 到 regex parsing，因为稳定 block identity 依赖确定性的 parser output。

如果 provider model discovery 失败，检查 API key、protocol 和 base URL。OpenAI-compatible endpoint 通常需要在配置的 base URL 下暴露 `/models`。Anthropic-compatible endpoint 需要接受 Anthropic 的 model-listing protocol。

如果某段翻译不理想但总是再次出现，请检查该 block 的 translation variants 和 Settings 中的 Translation memory。文章内 variant 可以重新选择；全局 memory entry 可以 disable 或 reject，而不会删除原文章数据。
