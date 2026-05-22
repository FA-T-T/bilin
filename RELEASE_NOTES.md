# Ilios v0.3.4

本版本继续把阅读器从原型状态推向可复用的研究工具。重点是修复多语言翻译状态、Attention Is All You Need 这类 LaTeXML 文献列表解析、Markdown 导出稳定性、Kindle 分页体验，以及同步多语言 README。

## 主要变化

- 多语言翻译状态按目标语言区分，简体中文下完成的块不会在切换到日文、韩文、法文、德文或其他目标语言时误显示为已翻译。
- Library 文章列表改为第一次点击选中、第二次点击进入阅读，减少误触进入阅读器。
- LaTeXML bibliography list 现在会生成结构化参考文献块，正文 citation alias 能关联到 bibliography metadata，Attention Is All You Need 这类论文的引文预览不再缺失。
- 引文跳转查询优先使用标题、DOI、arXiv ID 和更完整的 bibliography metadata，避免只拿作者年份片段去搜 Google Scholar 或 arXiv。
- Markdown 导出继续补强标题去重、独立公式块、KaTeX 兼容命令替换、图片插入和 HTML 表格转 Markdown 表格。
- Kindle 模式去掉上一页上下文尾巴，改为更接近电子书的上下翻页体验，并保留字体大小调节。
- 顶部 HTML / Kindle 入口居中显示图标和文字，首页入口放到最左侧，文库入口紧随其后。
- 简体中文 README 改为截图驱动的功能展示，并同步更新 English、日本語、한국어、Español、Français、Deutsch README；新增截图资产随 release package 一起发布。

## 验证

- `git diff --check`
- `apps/api/.venv/bin/python -m pytest -q apps/api/tests/test_export.py apps/api/tests/test_translation.py apps/api/tests/test_latexml_parser.py apps/api/tests/test_citations.py apps/api/tests/test_docs.py`，101 passed
- `pnpm --filter @bilin/web test:run -- render.test.tsx`，70 passed
- 文档图片引用检查：12 张 README 图片均存在于 `assets/`
