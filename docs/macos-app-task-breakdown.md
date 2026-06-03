# macOS App Task Breakdown

本文档把 native macOS app 的启动工作拆成可执行的 milestones 和工作包。范围限定在 `feature/macos-app` 分支的 macOS 原生路线：SwiftUI 作为主框架，AppKit/PDFKit 作为必要桥接，现有 web/API 实现作为行为参考，不作为默认运行时依赖。

## 范围假设

- 不以 Electron、Tauri、WebView shell 作为主产品架构。
- 不把本地 FastAPI 服务作为 macOS app 的默认依赖。
- 第一版直接读取本地 Bilin library 和 article bundle，并保留与现有 SQLite schema、fixture、manifest、`document.json` 的兼容性。
- 第一版优先证明 reader shell、SQLite store、block model、数学渲染、简单笔记和 provider 配置的垂直切片。
- Python、Rust、RaTeX、LaTeXML 等外部路径都必须通过协议或 adapter 隔离，避免锁死 SwiftUI 主体。

## Milestones

| Milestone | 目标 | 交付物 | 验收标准 |
| --- | --- | --- | --- |
| Milestone 0: 工程骨架与决策冻结 | 建立 macOS 原生工程的最小可构建边界，并冻结模块职责。 | Xcode/SPM 工程结构；`BilinMacApp` app target；五个 library modules 的 target 边界；基础 CI 或本地 build 命令；module dependency graph；开发文档入口。 | clean checkout 可在 macOS 上构建 app shell；所有 module 可独立编译；模块之间不存在反向依赖；不需要启动 web/API 服务；README 写明本地运行命令和最低 macOS/Xcode 版本。 |
| Milestone 1: 本地 library store 读取 | 让 app 能发现、打开、校验现有 Bilin library。 | `BilinStore` SQLite 连接层；schema version 检查；migration 状态读取；library registry；article list query；只读兼容测试；错误分类。 | 用户选择 library 目录后，app 能列出 article families/revisions；不修改未知 schema；SQLite 连接失败、schema 过旧、WAL/lock 冲突都有明确错误；fixture library 的查询结果与 API 端参考结果一致。 |
| Milestone 2: Native reader vertical slice | 用 SwiftUI 打开 article fixture，渲染结构化 blocks。 | `BilinReaderKit` block model；`document.json` decoder；reader route/state；outline；block list；source/translation 双栏布局；基础 hover/selection 状态；阅读位置保存。 | 打开 golden paper 后可看到标题、章节、段落、公式占位、figure/table caption；outline jump 基于 `block_uid`；滚动后关闭再打开能恢复位置；reader 不依赖 DOM 或 HTTP 服务。 |
| Milestone 3: Native rendering and notes | 建立 rich content 渲染与最小笔记写入能力。 | `BilinRenderKit` math renderer adapter；RaTeX feasibility path；KaTeX/reference fallback fixture；inline/block equation baseline 测试；image asset loader；`BilinReaderKit` note model；`BilinStore` note write/read。 | representative equations 能显示并保留 accessibility/copy fallback；图片和 caption 从 article bundle 加载；用户可对 block 写入一条简单 note；note 持久化到 SQLite 或 bundle 约定位置；reader 性能在长文档上没有明显卡顿。 |
| Milestone 4: Import compatibility slice | 支持第一版本地导入路径，并保持与现有 bundle layout 兼容。 | `BilinImportKit` import service protocol；本地 TeX archive import；本地 `document.json`/fixture import；arXiv import 规划 adapter；manifest writer/reader；asset copy policy；import job 状态模型。 | 用户可导入一个本地 fixture 或 TeX bundle 并生成可打开的 article entry；不会破坏现有 bundle 文件；缺少 LaTeXML/RaTeX/外部工具时返回结构化错误；import 后 reader 可直接打开结果。 |
| Milestone 5: Provider and translation jobs | 接入 provider 配置与第一版 translation job，不要求完整 QA。 | `BilinLLMKit` provider profile；Keychain API key storage；OpenAI-compatible adapter；Anthropic-compatible adapter 规划；translation job queue abstraction；block translation request builder；progress state；retry/cancel 语义。 | 用户可配置 provider 并通过 Keychain 保存 key；选择若干 paragraph blocks 后能启动 mock 或真实 translation job；完成结果写回 store 并在 reader 显示；重启后已完成 translation 不丢失；失败 block 可重试。 |
| Milestone 6: MVP hardening and release candidate | 把原型收敛为可手测的 macOS MVP。 | app settings；menus/commands；diagnostics panel；权限说明；error reporting；golden regression tests；performance pass；packaging/notarization checklist；manual acceptance script。 | clean macOS 机器可安装、打开 library、导入 fixture、阅读、渲染公式、保存 note、配置 provider、运行 translation；关键路径有测试或手测脚本覆盖；安全权限和数据目录行为可解释；无必须依赖 web/API 服务的用户路径。 |

## 当前进展

- 已建立 `apps/macos` SwiftPM 工程、SwiftUI 三栏 reader skeleton、fixture reader、`BilinReaderKit` block model、`BilinRenderKit` math renderer protocol 与 fallback renderer。
- 已实现 `BilinStore` 的 SQLite-backed per-library store，可打开现有 `library.sqlite`，读取 article list、revision、ordered blocks、`zh-CN` translation variants 和 note patches。
- `Open Library...` 已接入 macOS `NSOpenPanel`，可选择 library 目录或 `library.sqlite` 文件，并把结果刷新到 reader surface 与 inspector。
- 已实现 schema/version guard，读取 `schema_migrations` 并要求当前 library migration set 兼容；note write path 仅在 schema current 且无未知 future migration 时写入 `note_patches`。
- 已读取 `reading_progress`，并用 `active_block_uid` 作为 reader 初始选中 block。没有 progress row 时返回基于 ordered blocks 的空进度。
- 当前 Windows 环境没有 Swift toolchain，SwiftPM build/test 仍需在 macOS 上执行。已用 Python 对真实 portable `library.sqlite` 验证核心 SQL 字段和 join 方向。

## 模块第一版任务

### BilinMacApp

- 建立 app lifecycle：`App` entry、main window、library selection、reader window state、settings scene。
- 实现 native navigation：sidebar、article list、reader pane、task/inspector rail 的布局壳。
- 接入 macOS commands：open library、import、search、reader mode、toggle inspector、settings。
- 定义 app-level dependency injection，把 store、reader、render、import、LLM service 以 protocol 注入。
- 建立错误展示规则：non-blocking banner、blocking sheet、diagnostics detail。
- 交付第一版 app settings：library path、theme、reader preference、provider entry point。

### BilinStore

- 建立 SQLite 连接管理，明确 readonly/readwrite mode、WAL、busy timeout、foreign key pragma。
- 读取 global app state 与 per-library SQLite 的边界；第一版至少支持打开 per-library `library.sqlite`。
- 实现 schema version、migration history、compatibility guard。
- 实现 article list、article revision、manifest path、document path、translation、note、reading progress 的 repository。
- 建立 store error taxonomy：missing file、unsupported schema、locked database、corrupt database、permission denied、migration required。
- 建立测试 fixture：最小 library、golden library、schema mismatch、locked DB。

### BilinReaderKit

- 定义 Swift block model：section、paragraph、equation、figure、table、caption、citation、translation、note anchor。
- 实现 `document.json` decoder，保留 schema version 和 unknown fields 的兼容策略。
- 建立 reader state：opened article、current `block_uid`、outline selection、view mode、translation visibility、hover/selection。
- 实现 outline 和 jump by `block_uid`，避免依赖列表 index 或视图位置。
- 定义 annotation/note/translation action registry，先接 mock action，再接 store/LLM。
- 建立 reader preference：font scale、source/translation layout、theme、reduced motion。

### BilinRenderKit

- 定义 render input/output：LaTeX source、display mode、baseline metrics、accessibility text、copy fallback、error state。
- 调研并接入 RaTeX 的第一版 adapter；若需要 Rust FFI，先固定 ABI、resource path、build artifact 约定。
- 建立 fallback renderer：无法渲染时显示原始 LaTeX、错误状态和可复制文本。
- 支持 image asset loading：相对 article bundle path、安全路径校验、missing asset state。
- 建立 equation fixture suite：inline、display、aligned、matrix、citation-adjacent、table math。
- 做 reader 性能预算：渲染缓存、lazy rendering、可见区域优先。

### BilinImportKit

- 定义 import service protocol：source type、destination library、progress callback、cancellation token、result manifest。
- 第一版支持本地 fixture/article bundle import；第二步支持 TeX archive import。
- 复用现有 bundle layout：source archive、PDF、manifest、document/document.json、document/source.md、assets、logs、export。
- 建立 manifest validation 和 write policy，避免覆盖未知字段。
- 把 LaTeXML、arXiv download、TeX extraction 放进 adapter 层；缺少依赖时返回 structured error。
- 建立 import job 与 store 的边界：job state 可持久化，但外部工具执行不阻塞 UI 主线程。

### BilinLLMKit

- 定义 provider profile：provider type、base URL、model、capabilities、rate limit、credential reference。
- 使用 Keychain 存储 API key；开发 fallback 必须显式启用，且不能写入 library bundle。
- 实现 OpenAI-compatible adapter；Anthropic-compatible adapter 可先完成协议和 mock。
- 定义 translation request builder：block content、target language、glossary version、neighbor context、section context。
- 建立 job abstraction：queued、running、paused、succeeded、failed、cancelled；支持 retry 和 cancellation boundary。
- 第一版 reader card/QA 只保留接口，不进入 Milestone 5 的验收范围。

## 并行与串行关系

### 必须串行

1. Milestone 0 必须先完成。后续所有模块依赖 target 边界、dependency direction 和 build command。
2. `BilinStore` 的 SQLite compatibility guard 必须早于真实 write path。没有 schema/version guard，不应写 note、translation 或 import result。
3. `BilinReaderKit` 的 block model 必须早于 native reader UI polish。UI 不应先绑定临时 dictionary 或未版本化 JSON。
4. `BilinRenderKit` 的 renderer protocol 必须早于 RaTeX 深度集成。先固定 input/output，再选择 FFI 或 pre-render artifact。
5. Provider credential storage 必须早于真实 provider call。没有 Keychain path，不应引入真实 API key 输入。
6. Import write policy 必须早于 arXiv/live import。先证明本地 fixture 和 bundle 兼容，再接网络和外部工具。

### 可以并行

- `BilinMacApp` shell 和 `BilinStore` readonly repository 可并行，只需要约定 view model input。
- `BilinReaderKit` block model 和 `BilinRenderKit` renderer protocol 可并行，交汇点是 equation block render input。
- `BilinImportKit` 的 protocol/job model 可与 `BilinStore` repository 并行，但真正写库必须等 store guard 完成。
- `BilinLLMKit` provider profile/mock adapter 可与 reader vertical slice 并行，真实 translation 写回等 store write path 完成。
- 视觉 shell、commands、settings 可以与数据层并行，前提是通过 mock services 驱动。
- 测试 fixture、golden acceptance、diagnostics 文案可以从 Day 1 开始并行准备。

## 第一周开发计划

### Day 1: 工程边界与构建

- 建立或确认 macOS app target 和五个 library modules。
- 固定 dependency graph：`BilinMacApp -> Reader/Store/Render/Import/LLM`，feature modules 不依赖 app target。
- 加入最小 app shell：library sidebar、empty article list、empty reader pane。
- 建立本地 build/check 命令，并记录 Xcode/macOS 版本要求。
- 输出 Milestone 0 的 build acceptance checklist。

### Day 2: Store readonly vertical slice

- 实现 SQLite connection wrapper 和 schema/version read。
- 读取 per-library article list 与 article revision metadata。
- 接入 open library flow，失败时显示 structured error。
- 增加 fixture 或手测 library 路径，验证不启动 API 服务也能列出文章。
- 写第一组 store tests：missing DB、unsupported schema、valid minimal DB。

### Day 3: Document model and reader shell

- 实现 `document.json` decoder 和 block identity model。
- 从 article revision 找到 manifest/document path。
- 在 reader pane 渲染 section、paragraph、equation placeholder、figure/table placeholder。
- 实现 outline jump by `block_uid`。
- 保存并恢复 reading progress 的内存版；持久化等 Day 4 store write path。

### Day 4: Render adapter and first write path

- 定义 math renderer protocol 和 fallback renderer。
- 接入 RaTeX spike 或建立可替换 adapter stub，跑 equation fixtures。
- 实现 note 或 reading progress 的最小 SQLite write path，并受 schema guard 保护。
- 增加 image asset path 校验和 missing asset state。
- 做一次长文档滚动手测，记录性能瓶颈。

### Day 5: Import/LLM protocols and integration demo

- 定义 import service protocol，接本地 fixture/bundle import mock 或最小实现。
- 定义 provider profile、credential reference、translation job protocol。
- 接 mock translation，使 reader 能显示 translation state 和 completed result。
- 汇总第一周 demo path：open library -> open article -> render blocks -> render/fallback math -> save note/progress -> mock translate。
- 更新风险登记和下一周 backlog，明确哪些任务进入 Milestone 2/3，哪些延后到 Milestone 4/5。

## 风险清单

| 风险 | 影响 | 早期信号 | 缓解策略 | Owner module |
| --- | --- | --- | --- | --- |
| SQLite 兼容 | 现有 web/API library 不能被 native app 安全读取或写入。 | schema version 不一致；WAL/lock 冲突；migration 表缺失；字段语义在 API 端隐式维护。 | 先做 readonly compatibility；写路径全部受 schema guard 保护；为每个 write path 增加 fixture test；未知 schema 只读或拒绝写入。 | BilinStore |
| RaTeX | 公式 baseline、字体、accessibility、copy fallback 或打包路径不稳定。 | inline math 垂直错位；display equation 截断；Rust/Swift FFI build 失败；notarization 找不到资源。 | 先定义 renderer protocol；建立 equation fixture；RaTeX 作为 adapter 接入；保留 raw LaTeX fallback；在 Milestone 3 前完成打包 spike。 | BilinRenderKit |
| SwiftUI reader 性能 | 长文档滚动、双栏同步、公式 lazy render 造成卡顿。 | 打开 golden paper 首屏慢；滚动掉帧；state 更新触发全列表刷新；公式重复渲染。 | 使用 block identity、lazy containers、render cache、visible-range 优先；避免把全局 reader state 注入每个 block；早期建立长文档性能手测。 | BilinReaderKit / BilinRenderKit |
| LLM/provider | provider schema、rate limit、streaming、失败重试和 credential storage 复杂度高。 | key 存储位置不清；OpenAI-compatible provider 差异；失败 block 无法恢复；重启丢 progress。 | Provider profile 和 credential reference 分离；Keychain 优先；mock adapter 先覆盖 job semantics；真实调用前固定 retry/cancel/progress schema。 | BilinLLMKit / BilinStore |
| 安全权限 | macOS sandbox、file access、Keychain、network permission 影响 library 和 provider 访问。 | 用户选择目录后重启失去访问；Keychain item 读写失败；network call 被权限或 ATS 阻断。 | 早期决定 sandbox 策略；使用 security-scoped bookmark；Keychain error 可诊断；provider base URL 做 allow/validation；权限失败显示可操作说明。 | BilinMacApp / BilinStore / BilinLLMKit |
| 测试环境 | macOS-only、RaTeX、SQLite、external tools 和 golden fixtures 难以在 CI 中稳定复现。 | CI 无法运行 macOS job；本地测试依赖工具链；snapshot 脆弱；fixture 生成不确定。 | 分层测试：pure Swift unit、SQLite fixture、renderer fixture、manual golden；heavy toolchain 只进入 optional regression；结构化断言替代像素级脆弱 snapshot。 | All modules |

## 第一版验收路径

第一版可接受的 demo 不是完整产品。它必须证明 native app 的核心路径成立：

1. 打开本地 Bilin library。
2. 列出 article revisions。
3. 打开一个 golden article。
4. 渲染 native reader blocks。
5. 对公式使用 RaTeX 或明确 fallback。
6. 保存 reading progress 或 note。
7. 通过 mock provider 写入一条 translation。
8. 重启后仍能读取已保存状态。

如果这条路径需要启动 web app、FastAPI server、临时 HTTP server、手工复制数据库字段，或者把 API key 写入 library bundle，则第一版不通过。
