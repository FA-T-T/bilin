# 衔牍功能说明

这份文档说明当前版本的主要功能和读论文时的实际用法。它面向使用者，而不是开发者；如果你只想知道某个按钮、模式或颜色标记应该怎么用，可以直接跳到对应章节。

## 基本概念

衔牍把论文保存在你选择的本地 library 文件夹里。一个 library 可以理解为一个可携带的论文工作区，里面包含论文源码、PDF 原文件、解析结果、图片资产、翻译缓存、问答记录、笔记和导出文件。你可以把这个文件夹放在普通磁盘目录中，也可以交给 iCloud、OneDrive 或 Syncthing 这类外部同步工具处理；衔牍自身不提供账号系统，也不替你解决同步冲突。

一篇论文在衔牍里会成为一个 article bundle。bundle 保存原始 source package、解包后的 TeX、`document.json`、`source.md`、assets、logs、exports 和 manifest。Reader 页面展示的是解析后的结构化 block，而不是直接打开 PDF。段落、标题、公式、图、表和算法都会尽量保留自己的结构身份，这样翻译、问答、复制和导出才能围绕真实论文结构工作。

## 文库和导入

首页用于创建和进入 library。创建 library 时填写一个名称和本地目录路径即可。进入 library 后，可以通过 arXiv ID 导入论文，也可以上传本地文件。

arXiv 导入是推荐路径。你输入 `1706.03762` 这样的 ID 后，衔牍会下载 source package，按选项保存 PDF，并在启用解析时把 LaTeXML parse job 放入后台任务队列。本地 TeX archive 走同一条结构化解析路径。Markdown 文件会立即变成弱结构文档，适合保存笔记或非 arXiv 文稿。PDF 导入用于把 PDF 原文件放进 bundle 归档；当前 reader 的主路径仍然是 TeX 或 Markdown，PDF 不会被打开、OCR、翻译或嵌入阅读器。

导入、解析、翻译、embedding、笔记生成和导出都通过后台任务执行。右上角的任务抽屉会显示 queued、running、paused、succeeded、failed 和 cancelled 等状态，并提供 pause、resume 和 cancel 操作。长任务断开页面后仍然可以由 worker 继续处理。

## 模型设置

Settings 的 Models 页签用于连接模型 provider。简单模式下，你只需要选择 OpenAI-compatible 或 Anthropic-compatible，粘贴 API key，然后点击查找模型。衔牍会请求 provider 的模型列表，把可用模型按显示名称列出来，你点击一个模型后保存即可。高级模式用于自定义 profile label、base URL、并发数和每分钟请求数，适合本地网关、代理服务或自建兼容 API。

保存 provider 后，Reader 里的翻译、问答和笔记生成会使用该 provider。模型能力会影响功能效果。支持 streaming 的模型可以流式回答问题，支持 native search 的模型可以在问答中使用模型原生检索；不支持 native search 时，问答会限制在当前论文内容内。翻译质量也取决于模型、目标语言和领域术语覆盖。

Settings 的 Translation memory 页签用于审核可复用翻译。被批准并开启 reuse 的条目可以在后续翻译中复用；被禁用或拒绝的条目不会继续污染新的论文。这个页面适合把明显错误的翻译排除掉，也适合把高质量术语化表达固定下来。

Settings 的 Interface 页签用于切换界面语言。Settings 的 Local tools 页签会列出 `latexml`、`latexmlpost`、`tectonic`、`magick`、`gs` 和 `pdfinfo` 等本地工具的检测结果。缺少某个工具只会影响需要它的能力，不会阻止应用启动。

## Reader 页面总览

Reader 顶部显示文章标题、修订信息和视图模式切换。章节入口是可折叠的 Chapters 控件，展开后可以跳转到解析出的章节。Reader 工作区有 Translate、Terms、Ask、Notes 和 Export 几个页签，分别用于翻译、术语、问答、讲义笔记和导出。

正文由 block 组成，但普通阅读模式会尽量保持文章流畅感。标题、摘要和章节标题以单栏强调显示。段落按阅读模式决定是否对照展示。公式保持数学块渲染。图和表在存在真实 asset 或 LaTeXML HTML fragment 时会显示真实内容，缺失时保留 caption、label 和可查看源内容的结构化 fallback。

鼠标移入段落时，当前原文段落和对应译文会自动出现轻量背景强调；鼠标移开后恢复普通正文排版。这个强调只依赖当前段落的原文和译文内容，不调用模型，也不读取上下文。英文和中文各自按本段内容自动切句，分别循环使用低饱和背景色，不要求两边句子数量一致。句子强调使用独立色系，不占用黄色、蓝色、绿色、粉色和紫色这些手动段落标记。

## 阅读模式

| 模式        | 适合场景 | 页面行为                                                                                                                                                         |
| ----------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Study       | 默认精读 | 以原文为主阅读，段落末尾有一个小的译文展开按钮。需要看译文时在当前段落展开，不需要时保持正文连贯。非双语内容会启用图文混排，让图、表和附近段落更像论文排版。     |
| Focus       | 逐段专注 | 当前阅读段落自动展开译文，其他段落降低透明度。适合逐段推导、读公式附近解释或检查难段。当前段落由滚动位置和鼠标经过共同决定。                                     |
| Bilingual   | 严格对照 | 原文和译文左右对照，比例约为英文 0.6、译文 0.4。这个模式牺牲一点排版流动性，换取逐段对应关系，适合校对译文和术语一致性。图、表、公式等环境块保持居中或单栏展示。 |
| Translation | 译文通读 | 只显示目标语言译文。这个模式不再强制双栏，适合第一次快速理解文章逻辑。没有译文的 block 会显示待翻译状态。                                                        |
| Source      | 原文通读 | 只显示英文原文。这个模式不再强制双栏，适合翻译后回到原文复查表达、公式符号和引用。                                                                               |

Study 和 Focus 是更适合长时间阅读的模式。Bilingual 更适合对齐和校对。Translation 更适合快速扫读，Source 更适合回到英文原文深读。

## 颜色标记

段落左侧会在 hover 时出现竖向颜色标记。颜色用于把段落变成可整理的阅读笔记线索。标记会在当前浏览器中按 library 和 article 保存；如果你希望长期沉淀到知识库，建议使用右侧工具栏的 Save to Obsidian。衔牍会自动在 OneDrive 下的 Obsidian vault 中按当前 library 名称创建一个 Markdown 文件，并把同一篇论文的摘录追加到对应文章章节里。

| 颜色 | 界面名称      | 建议用途                                                   | Obsidian callout | 默认标签          |
| ---- | ------------- | ---------------------------------------------------------- | ---------------- | ----------------- |
| 无色 | Clear color   | 清除标记，或作为普通摘录                                   | `note`           | `#ilios/note`     |
| 黄色 | Key idea      | 核心贡献、关键定义、文章最值得记住的句子                   | `important`      | `#ilios/key-idea` |
| 蓝色 | Method        | 方法、模型结构、算法流程、证明步骤和实现细节               | `info`           | `#ilios/method`   |
| 绿色 | Evidence      | 实验结果、理论支撑、对比结论、图表给出的证据               | `success`        | `#ilios/evidence` |
| 粉色 | Question mark | 没读懂的假设、想问导师的问题、需要回查的符号或推导         | `question`       | `#ilios/question` |
| 紫色 | Review later  | 信息密度高、需要二刷、可能和自己课题相关但暂时不展开的段落 | `abstract`       | `#ilios/review`   |

一个实用流程是先用黄色标出论文主线，用蓝色标方法细节，用绿色标证据，再用粉色留下问题。读完后把每个标记段落通过 Save to Obsidian 保存。衔牍会把 source block、已存在的译文、颜色对应的 callout 类型、标签和 block anchor 一起写入 Markdown，便于后续做双向链接和组会讲义。

默认 Obsidian vault 会创建在 OneDrive 目录下的 `Obsidian/Ilios`。例如 macOS 上检测到 OneDrive 后，路径会类似 `~/Library/CloudStorage/OneDrive.../Obsidian/Ilios`。保存段落时，衔牍会根据当前 library 名称创建一个 Markdown 文件；同一个 library 的所有论文都写入同一个文件，每篇论文是一个二级章节，同一篇论文里重复保存同一个 block 会更新原摘录，而不是生成重复条目。

## 段落工具栏

段落右侧会在 hover 时出现竖向操作图标。原文侧工具包括 Copy source、Save to Obsidian、Ask about source 和 Show LaTeX。Copy source 复制原文 block。Save to Obsidian 把当前 block 的原文、译文和颜色语义追加到 Obsidian vault 中的 library 笔记。Ask about source 会把当前 block 设为问答上下文。Show LaTeX 会打开源内容检查窗口。

译文侧工具包括 Copy translation、Retranslate 和 Add note patch。Copy translation 复制当前译文。Retranslate 会打开一个自定义 prompt 输入框，让你针对当前段落重新翻译，例如要求保留某个术语、压缩表达或改成更适合组会讲解的中文。Add note patch 会把当前段落作为问答和笔记生成的上下文入口。

公式、图、表和算法这类环境块使用环境工具栏。Copy block 会复制整个环境块文本。Explain block 会把该环境块设为提问对象。Show source 会查看原始源内容或解析出来的结构信息。

## 翻译、术语和译文版本

Translate 页签用于把整篇文章排队翻译。翻译单位主要是段落和 caption，公式本身不会被翻译。任务会按 provider 的并发和速率设置执行，并根据 content hash、目标语言、模型和术语版本缓存结果。重新打开文章时，已有译文会从本地缓存读取，不需要重复调用模型。

Terms 页签用于管理文章术语。术语变更默认作用在显示层，尽量不覆盖模型原始输出。受术语影响的 block 会显示 glossary changed 标记。你可以批量重译受影响 block，也可以保留旧译文作为一个 translation variant。一个 block 存在多个译文版本时，Reader 会出现 translation variant 选择框，让你在不同译文之间切换。

翻译并不是一次性覆盖文件。衔牍会保留 variant、默认选择、provider、model、glossary version 和元数据。这样可以让你在“忠实原文”“更适合讲义”“术语统一”之间做选择，而不是被最后一次翻译永久覆盖。

## 问答和证据

Ask 页签用于围绕当前文章提问。你可以先在段落工具栏里选择某个 block，再提问当前段落；也可以清除 block 上下文，对整篇文章提问。回答会引用检索到的论文 block，并保存问题、答案、引用 block、provider、model 和 native search 状态。

如果 provider 支持 native search，你可以打开 Use model-native search，让模型检索外部资料。此时外部证据会和论文内部证据分开显示。若 provider 不支持 native search，衔牍会把回答限制在文章内容和本地检索结果里，避免模型把外部常识伪装成论文结论。

当前 MVP 默认用本地 FTS5 和已构建的 block 结构做文章内检索。Local embedding 已有确定性本地状态和任务入口，但神经 embedding provider 仍应被视为后续增强路径。

## 讲义笔记

Notes 页签用于从问答或模板生成 lecture-note patch。内置模板包括精读、组会、快速扫读和复现导向等常见阅读目标。生成结果不是直接覆盖最终讲义，而是先成为一个 patch。你可以编辑 patch 内容，再接受或拒绝。接受后的内容会合并到 `lecture-notes.md`。

这种 patch 流程适合科研阅读，因为第一次模型输出通常不是最终笔记。你可以先让模型给出结构，再人工补充自己的理解、疑问和复现实验计划，最后再持久化。

## 导出和下载

Export 页签可以生成完整文件，并通过浏览器下载。当前支持 Source Markdown、Translated Markdown、Bilingual Markdown、Lecture notes 和 Article bundle zip。导出成功后，浏览器会自动开始下载；如果浏览器拦截了自动下载，页面上仍然会保留 Download file 按钮。

Source Markdown 只包含原文结构。Translated Markdown 只包含目标语言译文，缺译文时可以按设置回填原文并标注 untranslated。Bilingual Markdown 同时包含 source 和 translation，适合校对或交给外部知识库。Lecture notes 导出已接受的讲义内容。Article bundle zip 会打包当前 article bundle 中的源码、解析结果、assets、manifest 和导出文件，适合归档或迁移。

导出的 Markdown 和讲义会包含不可见 HTML 注释水印，用来说明文件由衔牍生成，可能包含第三方论文内容或派生内容。这个水印不影响正常阅读，但能提醒你在公开分发前检查原论文许可证、作者版权和期刊政策。

## 图、表、公式和引用

公式使用 KaTeX 渲染。行内公式和展示公式会尽量保持数学排版，公式内容不会进入普通翻译输出。若 LaTeXML 把某些公式误包成 table 或 figure，Reader 会根据 HTML fragment 和 label 做纠正，尽量把它显示回 equation。

图和表会优先显示真实 asset。Reader 会根据 asset metadata 判断窄图、单栏图、双栏图和多面板图的尺寸，让图片更接近论文中的视觉比例。非双语模式会启用基于 Pretext 思路的图文混排，让图片附近的文字尽量自然填充。Bilingual 模式为了保持原译文对应关系，不会把多段文字自由流到图旁边。

表格会保留 LaTeXML HTML fragment 或结构化 fallback。复杂表格可以超出正文行宽，这是合理的，因为表格可读性通常比严格卡住行宽更重要。表格字体和字号会尽量接近正文，并保留公式渲染。

交叉引用会尽量链接到对应 block。点击文中的图、表、公式或章节引用时，Reader 会跳到解析出的目标。如果某个引用目标没有被解析出来，它仍会以普通文本显示，不会伪造不存在的链接。

文献引用编号会显示为可交互链接。鼠标移到 `[13]` 这类引用上时，Reader 会显示本地 bibliography 中解析出的文献题名、作者和年份，并提供三个直接动作：搜索 Google Scholar、搜索 arXiv、加入衔牍文献库。加入文献库会先用引用中的 arXiv ID 或题名检索 arXiv，找到后把最新版本加入当前文库；如果选择“加入并翻译”，系统会在解析完成后继续排队翻译任务。

## 推荐阅读流程

第一次读一篇论文时，可以先在 Library 中用 arXiv ID 导入并解析。解析完成后进入 Reader，用 Study 模式扫标题、摘要、章节和图表。遇到难段时打开 Focus 模式，让当前段落译文自动展开。读完一节后到 Ask 页签问这节解决了什么问题、关键假设是什么、公式在推导中起什么作用。把重要段落用颜色标记，再保存到 Obsidian 或生成 lecture-note patch。

如果要做组会汇报，可以在翻译完成后使用 Bilingual 模式校对关键段落，再在 Notes 中用组会模板生成讲义草稿。最后从 Export 下载 lecture notes 或 bilingual Markdown。如果要做复现，可以用蓝色标方法，用绿色标实验证据，用粉色标不确定的实现细节，再把这些 block 复制到自己的复现计划中。

衔牍最有价值的用法不是让你跳过英文原文，而是让你先理解论文逻辑，再回到英文原文确认术语、推导和表达。这样读得更快，也更不容易被流畅但空洞的总结带偏。
