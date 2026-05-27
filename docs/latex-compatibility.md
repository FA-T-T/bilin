# LaTeX Compatibility Table

Ilios keeps LaTeX-to-web compatibility rules in `shared/latex-compatibility.json`. This file is the first place to update when a paper exposes a KaTeX or LaTeXML dialect gap. The backend parser reads it before running LaTeXML and while normalizing math TeX. The frontend reader reads the same file before calling KaTeX, so old cached documents and newly parsed documents follow the same rule set.

The table is deliberately conservative. A rule belongs here only when it is semantic-preserving or display-preserving across papers. Font aliases such as `\vmathbb{1}` becoming `\mathbb{1}` are safe. Layout wrappers such as `\resizebox{...}{...}{x}` becoming `x` are acceptable because browser layout owns size. Paper-specific commands whose meaning depends on the source preamble should not be guessed in this global table.

Each command-group rule records the affected commands, argument count, replacement strategy, risk level, and reason. `template` rules render a replacement such as `\overset{#1}{#2}`. `unwrap` rules keep the first argument. `keep_arg` rules keep a specific argument, as in `\rotatebox{90}{x}` becoming `x`. Commands that also need LaTeXML help are mirrored in `latexml_preamble_commands`, which generates `\providecommand` shims in the temporary parser entry file without modifying the original source package.

Package-level parser policies live in `latexml_package_policies`. A package belongs there only when the failure mode is stable across papers and the fallback is conservative. The parser derives its disabled-package list from this registry, records matched policies in the parser profile, and stores them in the manifest as `latexml_compatibility_rules`. Do not add a package here just because one paper defines a local macro badly; reduce the failure to a fixture first.

Every parse failure should leave `logs/parser-diagnostics.json`. That file records the parser stage, generated entry path, first LaTeXML error, log excerpt, parser profile, and matched compatibility rules. Use `bilin parse diagnose <library> <revision_or_job_id>` to inspect an existing failure without rerunning LaTeXML. This command is intentionally read-only.

## Large Document Policy

Large TeX documents are treated as a conversion pipeline, not as one all-or-nothing command. The parser should preserve the most expensive successful artifact, resume from the failed stage, and degrade in ways the reader can understand.

The policy is based on three mature references. Engrafo uses LaTeXML as the conversion backend and runs the toolchain in Docker so conversions are isolated and reproducible: https://github.com/arxiv-vanity/engrafo. ar5iv serves arXiv articles converted with LaTeXML and treats conversion logs and fatal conversion states as first-class user-visible artifacts: https://github.com/dginev/ar5iv. LaTeXML documents `latexmlpost --split` and `--splitat=chapter|section|subsection|subsubsection` as the native way to split larger outputs into interlinked pages: https://math.nist.gov/~BMiller/LaTeXML/manual/usage/splitting/.

Bilin therefore follows this ladder for book-sized or otherwise slow papers:

1. Run `latexml` first and write `document/latexml.xml`.
2. For chapter-style sources, prefer split `latexmlpost` at `chapter`. For article-style sources, start with single-page `latexmlpost`.
3. If single-page `latexmlpost` times out, retry split `latexmlpost` at the preferred level.
4. If a retry already has `latexml.xml`, resume from `latexmlpost` instead of rerunning `latexml`.
5. If split `latexmlpost` still times out but `latexml.xml` exists, recover a structure-only HTML document from the XML and mark the manifest as degraded.

This recovery mode is intentionally conservative. It keeps headings, paragraphs, display equations, inline math text, lists, bibliography items, and simple figures/tables where they can be recognized from LaTeXML XML. It does not promise full cross-reference resolution, exact layout, or complete figure/table fidelity. User-facing UI should call this out as a recovered document, not a normal parse.

Every large-document parse must record enough manifest metadata for debugging and UI:

- `latexml_timeout_seconds` stores the timeout budget used for both `latexml` and `latexmlpost`.
- `latexml_split_level` stores the selected split level.
- `latexmlpost_mode` records `single`, `split`, `split_after_timeout`, `split_after_retry`, or `xml_fallback_after_split_timeout`.
- `parse_resume_from` records the resumed stage when a failed task is continued.
- `parse_fidelity` is `structure_only` when the final document came from XML recovery.
- `parse_recovery` describes the recovery stage, reason, and quality limitations.

The local LaTeX corpus lives under `fixtures/latex-corpus/`. It is for minimal, source-backed regressions such as old-style arXiv entry detection, `.bbl` fallback, `siunitx`, `tcolorbox`, `Qcircuit`, and caption/citation preservation. `bilin golden latex-corpus --fixture <path>` runs profile-only checks. Add `--live-latexml` only when you explicitly want to exercise the installed local LaTeXML toolchain.

When adding a new compatibility rule, first confirm that KaTeX or LaTeXML does not support the command natively, then add the smallest safe rule to `shared/latex-compatibility.json`. Add or extend a regression in `apps/api/tests/test_latexml_parser.py`, `apps/web/tests/render.test.tsx`, or the local LaTeX corpus depending on whether the problem is math rendering, parser preparation, or live parser execution. Then run the parser and reader checks. If a command is only safe for one paper because its definition is local, do not add it here; handle it later through source-aware macro extraction.

The current table is based on KaTeX's supported-function list, KaTeX's macro-extension behavior, the KaTeX unsupported-command wiki, and LaTeXML's customization model. The table is not a promise that every arbitrary LaTeX package is supported. It is a maintained compatibility layer for high-frequency, low-risk failures observed in arXiv papers and community reports.
