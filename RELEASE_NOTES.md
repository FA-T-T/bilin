# Ilios v3.1.0 更新日志

Ilios v3.1.0 是一次围绕“研究工作台”重新组织的信息架构发布。v0.2.1 已经修复了真实 arXiv、旧式 TeX、LaTeXML、DeepSeek/OpenAI-compatible provider、任务队列和导出的稳定性问题；这个版本把这些能力重新放回更直接的用户路径里。目标很简单：文库负责处理很多论文，reader 负责读一篇论文，右侧工作块负责把翻译、提问、术语、笔记和导出接到同一个阅读动作上。

## Workbench 界面

首页导航被压缩为真正的全局入口。Logo 与文库入口合并，阅读、翻译、笔记和 study 不再作为顶层菜单存在，因为它们已经是论文阅读内部的工作。Settings、任务和主题仍保留为全局控制。

文库页从列表页变成 article-first 工作台。左侧组织本地文库和状态，主区域展示论文行、搜索、筛选、排序、阅读进度、翻译状态、导入和批量翻译。点击论文行只会选中并预览论文，显式点击 Read 才进入 reader，避免用户在批量管理论文时被页面跳转打断。

阅读页不再显示首页菜单。它有自己的阅读 command band：左侧显示当前文库名并返回文库，中间固定显示 `Ilios / 衔牍 · Research Paper Reader`，右侧只放阅读模式和阅读偏好。全文搜索、任务按钮、主题按钮和旧的 Reader tools 下拉从阅读顶部移除。

## Reader 与工具块

Reader 现在是三栏拼贴式结构。左侧可以在同文库文章之间切换，中间是唯一不可折叠的论文画布，右侧是同层工作区。任务、模型供应商、提问、翻译、术语、笔记和导出都作为右侧块展示；默认只有提问块展开，其余块默认折叠。这个默认值更符合实际阅读：读到问题时先问，只有需要时再展开翻译、术语、笔记或导出。

Reader 和 Translate 已经合并为一个工作空间。翻译整篇论文、语言切换自动补译、段落重新翻译、术语替换和翻译 variant 选择都在 reader 内完成，不需要离开论文。Note 和 Study 也合并为一个学习工作流：用户可以从提问、段落摘录、术语卡片和讲义 patch 进入同一套可编辑笔记路径。

新的 logo 已经接入应用 header 和 favicon。图形采用“书牍束与金色夹扣”的抽象标记，不依赖缩小后难以辨识的汉字形状。

## 文库、进度和 provider

后端增加 library rename API，文库名称可以直接在 UI 中修改。文章列表增加阅读进度数据，reader 会记录当前活跃 block 和阅读时间片段，文库页可以据此展示哪些论文正在读、读到哪里，以及按进度排序。

Provider 设置页增加 provider preset。OpenAI、Anthropic、DeepSeek、Gemini、Qwen DashScope、Kimi、Groq、OpenRouter 和 xAI 可以从预置入口开始配置；高级用户仍然可以直接编辑 protocol、base URL、并发和 rate limit。API 同步提供 `/providers/presets`，前端生成 schema 已更新。

## 解析与渲染继续加固

LaTeXML 解析兼容继续扩展，尤其是旧式 arXiv 源码和数学宏处理。Reader 渲染层继续减少大文档 DOM 压力，长论文采用渐进式 block 渲染，搜索入口从阅读顶部移除后仍保留阅读进度和章节跳转，避免工具栏挤占正文。

## 文档和设计契约

`DESIGN.md` 已更新为当前 workbench 设计契约，明确首页导航、文库工作台、reader command band、右侧工具块默认折叠、提问默认展开、Reader/Translate 合并、Note/Study 合并等行为。README 已同步到 v3.1.0，面向普通用户解释现在的文库、reader、provider 和本地数据路径；发布细节继续保留在 `docs/github-release.md` 和 `AGENT_GUIDE.md`。

## 质量验证

本版本发布前运行了前端 `typecheck`、`lint`、`prettier --check`、`build`、Vitest 56 个测试和 Playwright 2 个 e2e 测试。发布前还应运行后端 ruff、basedpyright、pytest、release archive 打包和 SHA-256 校验。

源码发布包可以通过 `./scripts/package-release.sh 3.1.0` 生成。v3.1.0 release assets 包含 `bilin-v3.1.0-source.tar.gz`、`bilin-v3.1.0-source.zip` 和对应的 SHA-256 校验文件。
