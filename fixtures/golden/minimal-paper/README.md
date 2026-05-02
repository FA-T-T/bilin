# Minimal Golden Paper

This fixture is a deterministic parser regression case. It is intentionally
small enough to run in ordinary tests without LaTeXML while still exercising the
document shapes Bilin must preserve: section headings, paragraphs, display
equations, figure captions, table captions, labels, assets, and source Markdown.

`latexml.html` is the converter output consumed by the default regression test.
`source/main.tex` records the TeX shape this fixture represents and can be used
by optional LaTeXML integration work later.

Run the saved-output regression with:

```sh
cd apps/api
.venv/bin/bilin golden run ../../fixtures/golden/minimal-paper
```

On a machine with `latexml` and `latexmlpost` installed, run the live converter
path with:

```sh
cd apps/api
.venv/bin/bilin golden run ../../fixtures/golden/minimal-paper --live-latexml
```
