<h1 align="center">
  Ilios (LLM-gestuetztes Lesen von Papers)<br>
  <sub><sub>衔牍 · 理紐</sub></sub>
</h1>

<p align="center">
  <em>Ein mehrsprachiges Werkzeug zum Lesen wissenschaftlicher Papers</em>
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

## Was ist Ilios?

Ilios ist ein **local-first, strukturiertes** Paper-Reading-Workspace fuer Forschende, die englische Papers ueber mehrere Sprachen hinweg verstehen muessen.

Es laeuft lokal und unterstuetzt arXiv source packages oder lokale LaTeX archives.

Papers, Parse-Ergebnisse, translation cache, Q&A records und notes bleiben in einem lokalen Ordner, den du auswaehlst. **Kein Konto, kein hosted backend und kein file upload sind notwendig.**

Die Uebersetzungskosten sind niedrig. In einem Test hat DeepSeek V4 Flash 10 Papers mit insgesamt 240 Seiten fuer etwa 2 CNY verarbeitet.

## Hauptfunktionen

##### **Mehrsprachig**

Der Paper-Text, die Abbildungen und Formeln in den Screenshots gehoeren den urspruenglichen Autorinnen, Autoren oder Rechteinhabern. Sie werden hier nur verwendet, um Ilios' lokales Lesen, Uebersetzen, Q&A und structured rendering zu zeigen.

Chinesisches Beispiel:

<img src="./assets/image-20260522193937577.png" alt="Chinese translation example" style="zoom: 25%;" />

Franzoesisches Beispiel:

<img src="./assets/image-20260522194355907.png" alt="French translation example" style="zoom:25%;" />

Japanisches Beispiel:

<img src="./assets/image-20260522193846703.png" alt="Japanese translation example" style="zoom:25%;" />

Deutsches Beispiel:

<img src="./assets/image-20260522194717793.png" alt="German translation example" style="zoom:25%;" />

Koreanisches Beispiel:

<img src="./assets/image-20260522194157385.png" alt="Korean translation example" style="zoom:25%;" />

##### Abbildungen

<img src="./assets/image-20260522194901555.png" alt="Figure rendering example" style="zoom: 25%;" />

##### Formeln

KaTeX rendering.

<img src="./assets/image-20260522195038561.png" alt="Formula rendering example" style="zoom:25%;" />

##### Tabellen

Rendering als HTML tables.

<img src="./assets/image-20260522195134674.png" alt="Table rendering example" style="zoom:25%;" />

##### Satz-Hervorhebung beim Hover

Satzsegmentierung erleichtert den bilingualen Vergleich.

![Sentence hover highlighting](./assets/image-20260522195506879.png)

##### Zitationsvorschau

Zitationen werden automatisch geparst. Ilios unterstuetzt Google Scholar und arXiv search, one-click library import und automatische Uebersetzung.

<img src="./assets/image-20260522202145628.png" alt="Citation preview example" style="zoom: 33%;" />

##### Markdown-Export fuer Original oder Uebersetzung

Exportiere Originaltext oder Uebersetzung als Markdown und nutze es direkt als knowledge-base document.

<img src="./assets/image-20260522202353196.png" alt="Markdown export example" style="zoom:25%;" />

##### Kindle mode

Kindle mode laesst e-ink devices im lokalen Netzwerk ueber den Browser mit geringerem Ressourcenverbrauch lesen. Scrolling wird entfernt, links und rechts werden page-turn buttons hinzugefuegt.

Empfohlen wird ein e-ink device ab 10 inch im Landscape-Modus.

![Kindle mode example](./assets/image-20260522202534656.png)

## Schnellstart

### Agent users (Codex, Claude, DeepSeek-TUI, OpenCode...)

Sende diesen page link direkt an einen agent und sage:

"https://github.com/FA-T-T/bilin Please help me deploy this service, install the required dependencies, and start the app."

Der agent kann dependencies installieren, das Projekt deployen und die application starten.

### Normale Nutzer

Ilios benoetigt Node.js, pnpm, Python 3.13 und uv. Die core app kann ohne TeX toolchain starten, aber echtes LaTeX parsing braucht `latexml` und `latexmlpost` im `PATH`. Fuer image und PDF handling werden ImageMagick `magick`, Ghostscript `gs` und `tectonic` oder `pdflatex` empfohlen.

macOS + Homebrew vorbereiten:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Aus dem source starten:

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

In einer festen Entwicklungsumgebung kannst du das quick-start script nutzen. Es verwendet bestehende virtual environments und `node_modules`, ueberspringt environment probing und gibt sofort den status zurueck, wenn der stack bereits laeuft.

```sh
./scripts/start-dev.sh
```

Nach dem Start oeffne `http://127.0.0.1:5173`. Die API laeuft standardmaessig auf `127.0.0.1:8000`, und der worker verarbeitet import, parsing, translation, Q&A, notes und export jobs. Fuer debugging kannst du auch `make api`, `make worker` und `make web` getrennt ausfuehren.

Ohne LaTeXML startet Ilios trotzdem und unterstuetzt Markdown import, PDF storage, model configuration, translation, notes, export und fixture tests. TeX parse jobs schlagen explizit mit `missing_dependency:latexml` fehl, statt still auf instabiles regex parsing zurueckzufallen.

## Erstes Paper

Erstelle auf der home page eine library mit Namen und lokalem directory path. Eine library ist ein self-contained folder mit `library.sqlite`, original source archives, PDFs, unpacked TeX, parsed `document.json`, `source.md`, assets, logs, notes, exports und manifests.

Gib in der library eine arXiv ID wie `1706.03762` ein. Ilios laedt source package und PDF herunter, erstellt ein self-contained article package und reiht parsing tasks ein, wenn parsing aktiv ist. Lokale TeX archives verwenden denselben package path. Markdown wird sofort als weak structured document importiert, PDFs werden als source files gespeichert.

Nach dem Parsing waehle das Paper in der Bibliothek und klicke Read. Der Reader unterstuetzt Study, Bilingual, Translation und Source. Die linke rail wechselt zwischen Papers derselben library. Die rechte rail bietet tasks, model setup, paper chat, translation, glossary, notes und export tools. Paragraph hover actions koennen kopieren, source inspizieren, erneut uebersetzen oder eine Frage zum aktuellen paragraph stellen. Figures und tables werden direkt angezeigt, wenn assets vorhanden sind; fehlende assets behalten captions und labels mit structured placeholders.

## Model configuration

Oeffne Settings -> Models. Im simple mode fuegst du eine API key ein, und Ilios laedt die model list von einem compatible endpoint. Im advanced mode kannst du profile label, base URL, concurrency und requests-per-minute limit setzen. **Advanced mode wird empfohlen.**

Provider keys werden nicht in library folders gespeichert. Auf macOS werden keys standardmaessig in Keychain gespeichert, und die globale database enthaelt nur eine `keychain:` reference. Andere Plattformen oder `BILIN_CREDENTIAL_STORE=app_settings` verwenden den SQLite development fallback. Wenn provider creation blockiert werden soll, falls Keychain nicht verfuegbar ist, setze:

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

Die CLI verwendet dieselbe backend logic wie die Web app.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

Das Repository enthaelt golden fixtures, mit denen sich die reader pipeline ohne network access oder vollstaendige TeX toolchain validieren laesst.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

Der command gibt `reader_route` und `library_id` zurueck. Starte die app und oeffne die route im Browser, um den erzeugten article zu pruefen.

## Lokale Daten, Sicherheit und Sync

Ilios verwendet ein globales application data directory fuer app-level SQLite state, registered libraries, provider configuration, jobs, settings, note templates, translation memory und fallback API-key storage, wenn Keychain nicht verfuegbar oder deaktiviert ist. Das directory wird durch `platformdirs` bestimmt und kann in development mit `BILIN_HOME` ueberschrieben werden.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library directories werden vom Nutzer gewaehlt und sind self-contained folders, geeignet fuer externe sync tools wie iCloud, OneDrive oder Syncthing. Ilios behandelt sync conflicts nicht selbst. Schliesse die app vor dem Sync und stelle Konflikte ueber die version history des sync tools wieder her.

Exportierte Markdown files und lecture notes enthalten automatisch ein unsichtbares HTML comment watermark. Es erklaert, dass die Datei von Ilios erzeugt wurde und third-party content enthalten kann. Das watermark beeinflusst das normale reading layout nicht.

## Developers

Backend checks laufen in `apps/api`.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Frontend checks laufen vom repository root.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Default tests verwenden fixtures und mocks. Sie brauchen kein echtes network und keine vollstaendige TeX toolchain. Echte arXiv- und LaTeXML-integration tests sind explicit opt-in.

## Lizenz

Ilios source code, project-owned documentation, tests und project-owned fixtures stehen unter Apache-2.0. Siehe [LICENSE](LICENSE) und [NOTICE](NOTICE). Diese Lizenz deckt nur das Ilios project selbst ab. Sie deckt keine user-imported papers, PDFs, TeX source packages, figures, captions, datasets, machine translations oder lecture notes mit third-party material ab. Redistribution von exports muss der Lizenz des Originalpapers oder assets, der rights-holder permission oder geltenden legal exceptions folgen.

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  Geliehenes Licht, das den Text auf deinen Schreibtisch bringt.<br><br>
  <strong>理紐</strong><br>
  Wer den Faden der Logik bindet und dein Denken mit dem des Autors verbindet.<br><br>
  <em>Wenn Ilios dir eine schlaflose Paper-Nacht erspart, gib dem Projekt einen Star, damit mehr neue Forschende dieses Licht finden.</em>
</p>
