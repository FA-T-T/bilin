# Ilios v0.2.0 更新日志

Ilios v0.2.0 是面向真实阅读体验的第二个源码发布版本。这个版本继续保持本地优先、轻量部署和无账号系统的边界，但把 MVP 从“能跑通论文链路”推进到“可以较舒服地精读真实论文”。重点变化集中在 reader 排版、LaTeXML 解析稳定性、图片和表格显示、引用交互、Obsidian 摘录、导出下载、翻译缓存一致性和前端性能。

## 主要变化

- Reader 现在以文章阅读为中心，而不是以块状表格为中心。默认背景和文字颜色改为更适合长时间阅读的高对比方案，标题字号更克制，正文更紧凑，双语模式默认保持英文和译文约 6:4 的阅读比例。
- 章节导航改为可收起的章节索引，阅读模式和阅读偏好收进更窄的右侧控制栏。阅读偏好支持行宽、字号、段距、图像大小和双语比例等设置，减少对正文区域的占用。
- Reader 增加渐进虚拟化、懒加载段落工具栏、Markdown/KaTeX 轻量缓存和内置全文查找，降低长文档滚动时的 DOM 数量和按钮数量，缓解卡顿。
- 段落工具重新布局。英文段落的颜色标记和操作按钮不再挤占正文行宽，译文区域也避免把操作图标叠到文字上。复制、复制到 Obsidian、查看源 LaTeX、针对段落提问、重新翻译和颜色标记仍保留。
- 颜色标记和 Obsidian 摘录流程更完整。保存段落到 Obsidian 时会按当前文库写入对应 Markdown 文件，同一篇文章自动作为章节追加，中英文内容一起保存。
- 引用悬浮预览改为阅读辅助入口。用户可以查看引用信息，直接搜索 Google Scholar、搜索 arXiv，或把感兴趣的引用加入当前衔牍文库；加入并翻译保持为显式操作。
- 导出流程改为浏览器下载完整文件。Markdown 和 bundle 导出完成后，前端会通过浏览器下载结果，而不是只显示后台路径。

## 解析与文档结构

- LaTeXML parser 修复了多种真实论文解析问题，包括行内公式 Markdown 化、引用链接多余中括号、公式被误判为表格、表格 caption 前缀错误、缺失图片引用、EPS/PDF/PNG 资产拷贝和多子图布局 metadata。
- 图片显示改为默认居中，并根据 LaTeXML 提供的宽度、图片尺寸和多子图结构推断单栏、双栏和多面板布局。并排子图会保留一致比例；表格字体和字号保持接近正文，并允许表格超过正文行宽以保留信息密度。
- `\paragraph` / LaTeXML 的 paragraph heading 解析回到独立结构块策略。`Encoder:` 和 `Decoder:` 会作为 section 出现，后续正文段落保持独立，以兼容已有段落翻译缓存和旧阅读对应。
- 交叉引用、图表标签、bibliography placeholder 和 asset metadata 更稳定，reader 可以把正文中的图、表、公式和引用链接到对应结构块。

## 翻译、缓存与问答

- Provider 设置改为从 OpenAI-compatible 或 Anthropic-compatible API 自动解析可用模型，用户选择模型即可，不需要猜 provider 的内部模型名。
- 翻译缓存现在在重解析后优先保持稳定 `block_uid` 对应；如果 block 确实移动，则再用内容哈希迁移译文。这样可以避免中文错位，同时减少因为公式或引文格式规范化造成的不必要重翻。
- 术语、翻译记忆和段落级重新翻译入口继续保留。失败块可以重试，用户可在段落操作里加入自定义 prompt。
- 问答入口支持当前段落和整篇文章两种场景。启用模型原生检索时可以搜索新文献；不启用时回答限制在当前文章证据内。

## 本地集成与安全边界

- 增加 Obsidian 联动文档和用户功能说明文档，解释颜色标记、阅读模式、段落操作、摘录到 Obsidian、问答、讲义和导出工作流。
- 后端测试默认强制进入临时 `BILIN_HOME`，避免测试文库注册到用户真实应用数据库。真实用户文库仍然保存在用户选择的 library 文件夹中，便于通过 OneDrive、iCloud、Syncthing 等外部工具同步。
- 版权和内容边界保持透明。导出 Markdown 和讲义继续写入不可见 HTML comment 水印，提醒用户第三方论文、图表、译文和笔记的再分发必须遵守原始授权。

## 安装和发布

推荐安装路径仍然是 `pnpm install`、`cd apps/api && uv sync`、`make doctor` 和 `make dev`。真实 TeX 解析需要 `latexml` 和 `latexmlpost`；图片转换建议安装 ImageMagick、Ghostscript、Poppler 和 Tectonic。缺少 LaTeXML 时，TeX parse job 会明确失败并给出 dependency 信息，而不是静默降级。

本版本仍然不提供 Docker、Redis、Celery、账号系统、内置同步、桌面壳、PDF LLM fallback parsing、Word 导出、EPUB 导出或精排 PDF 导出。PDF 可以导入和保存，但在当前 MVP 中不会被解析、打开、OCR、翻译或嵌入 reader。

源码发布包可以通过 `./scripts/package-release.sh` 生成。v0.2.0 release assets 包含 `bilin-v0.2.0-source.tar.gz`、`bilin-v0.2.0-source.zip` 和对应的 SHA-256 校验文件。
