# Golden Fixtures

This directory stores deterministic parser regression fixtures. Default tests
consume saved converter output so they do not need network access or a local TeX
toolchain. Optional integration tests may still run LaTeXML against source files
when the dependency is installed.

`minimal-paper` is the first fixture. It covers sections, paragraphs, display
equations, figure captions, table captions, labels, asset placeholders, and
rendered source Markdown.

`public-arxiv-2408.13687` is a reduced public arXiv fixture based on the
CC-BY-licensed arXiv record for `arXiv:2408.13687`. It is not a full vendored
source package; it is an attributed, compact source and saved LaTeXML-style HTML
pair that exercises real paper features such as multiple sections, stable unique
paragraph IDs, a display equation, a figure asset, a table caption, labels, and a
citation placeholder.
