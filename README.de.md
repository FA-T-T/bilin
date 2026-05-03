# Bilin

Sprache: [简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | Deutsch

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## Warum Bilin? 📚✨

Bilin hat ein klares Ziel: Das Lesen wissenschaftlicher Arbeiten soll nicht länger bedeuten, sich allein durch ein englisches PDF zu kämpfen. Stattdessen wird daraus ein strukturierter Ablauf aus Lesen, Übersetzen, Fragen, Notizen und Wiederholung. Bilin ersetzt den englischen Originaltext nicht und macht aus dem Paper keine generische KI-Zusammenfassung. Die Struktur des Papers bleibt sichtbar: Abschnitte, Absätze, Gleichungen, Abbildungen, Tabellen, captions, Terminologie, Fragen und Vorlesungsnotizen.

Für Forschende bündelt Bilin viele verstreute Arbeitsschritte in einem lokalen Workflow. Sie können ein arXiv-Paper oder ein lokales TeX-Archiv importieren, absatzweises Markdown erzeugen, Blöcke übersetzen und zwischenspeichern, mehrere Übersetzungsvarianten behalten, Fachterminologie verwalten, Fragen zum aktuellen Block oder zum ganzen Paper stellen, Antworten in Notizen überführen und Markdown oder bundles exportieren. Papers, PDFs, TeX-Quellen, geparste Dokumente, Übersetzungs-Cache, Frageverlauf und Notizen bleiben im gewählten library-Ordner.

Für Forschende, deren Muttersprache nicht Englisch ist, ist der Nutzen besonders klar. Studierende, Promovierende und Neueinsteiger in ein Feld scheitern oft nicht an mangelnder Intelligenz, sondern daran, dass lange englische Sätze, dichte Fachbegriffe, Gleichungskontext und fachtypische Schreibweisen gleichzeitig auftreten. Wenn man zuerst in der eigenen Sprache Hintergrund, Motivation, zentrale Gleichungen, experimentelle Logik und Grenzen versteht, ist das meist effizienter, als von Anfang an jeden englischen Satz mühsam zu lesen. Danach wird die Rückkehr zum englischen Original zu einer Möglichkeit, Terminologie und akademisches Englisch an einer bereits verstandenen Idee zu lernen.

Bilin ist daher als erste Leseschicht für den Einstieg in Forschung gedacht. Es hilft, aus „Ich komme durch dieses Paper nicht durch“ ein „Ich weiß, welches Problem es untersucht, warum es wichtig ist, wie die Methode funktioniert und welche Stellen ich im englischen Original erneut lesen sollte“ zu machen. Ernsthaftes Lesen führt immer zurück zum englischen Text, zu Gleichungen, Abbildungen und Zitaten. Bilin macht diesen Weg weniger hart und hilft neuen Forschenden, schneller zur eigentlichen Forschung vorzudringen. 🌱

Bilin ist eine local-first Webanwendung zum Lesen, Übersetzen, Befragen, Annotieren und Exportieren akademischer Papers. Der Hauptpfad nutzt arXiv-TeX-Quellen, weil TeX die Struktur erhält, die ernsthafte Paper-Lektüre braucht: Abschnitte, Absätze, Gleichungen, Abbildungen, Tabellen, captions, labels, Zitate und source assets. Bilin läuft auf der eigenen Maschine mit React + TypeScript im Frontend, FastAPI im Backend, einer SQLite job queue und einem Python worker. Docker, Redis, Celery, Accounts, gehostetes Backend oder eingebaute Cloud-Synchronisierung sind nicht nötig.

Die aktuelle Version ist das v0.1.0 MVP. Sie kann lokale libraries erstellen, arXiv source packages importieren, lokale TeX-Archive importieren, Markdown als schwach strukturiertes Dokument importieren, PDFs als source artifacts speichern, TeX mit LaTeXML parsen, wenn die Toolchain installiert ist, strukturierte document blocks und assets speichern, deterministische lokale block embeddings bauen, Absätze und captions über OpenAI-compatible oder Anthropic-compatible providers übersetzen, translation variants behalten, translation memory prüfen und wiederverwenden, Artikelterminologie verwalten, provider keys im macOS Keychain speichern, paper-grounded Antworten streamen, editierbare lecture-note patches erstellen, custom note templates bearbeiten und Markdown oder bundles exportieren.

## Zukünftige Pläne

Künftige Versionen können PDF LLM fallback parsing, optionale neural embedding providers, Word/EPUB/ausgearbeitete PDF-Exports, eine Desktop-Shell und eine vollständigere Installationsform hinzufügen. PDFs können bereits als source artifacts im bundle gespeichert werden. Zukünftige PDF-Funktionen werden als optionaler Parsing-Pfad integriert, ohne den TeX-first-Hauptpfad zu ändern oder standardmäßig OCR oder schwere Service-Abhängigkeiten einzuführen. Accounts und eingebaute Synchronisierung sind nicht Teil der Standardrichtung. Bilin bleibt local-first und hält library-Ordner kompatibel mit externen Tools wie iCloud, OneDrive oder Syncthing.

## Repository-Struktur

`apps/api` enthält das FastAPI backend, CLI, SQLite migrations, arXiv- und Upload-Importe, LaTeXML parser path, provider profiles, translation jobs, deterministic local embeddings, glossary, question answering, lecture-note services, export services, worker und doctor command.

`apps/web` enthält das Vite + React + TypeScript frontend. Es nutzt Mantine, TanStack Query, Zustand, KaTeX, React Markdown und Playwright/Vitest.

`docs` enthält Design, MVP-Plan, local-safety notes und Entwicklerdokumentation. `fixtures/golden` enthält deterministic parser regression fixtures.

## Voraussetzungen

Bilin benötigt Node.js, pnpm, Python 3.13 und uv. Echtes TeX parsing erfordert `latexml` und `latexmlpost` im `PATH`. Für asset conversion helfen ImageMagick `magick`, Ghostscript `gs` sowie `tectonic` oder `pdflatex`.

Unter macOS mit Homebrew:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Unter Linux installieren Sie die entsprechenden Pakete über den Paketmanager der Distribution. Ohne LaTeXML funktionieren Markdown import, PDF save-only import, provider setup, Übersetzung, Notizen, export und fixture tests weiterhin. TeX parse jobs schlagen ausdrücklich mit `missing_dependency:latexml` fehl.

## Installation

Starten Sie im source directory oder im heruntergeladenen Projektordner.

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

Führen Sie vor der ersten Nutzung doctor aus.

```sh
make doctor
```

## Anwendung starten

API, worker und web gemeinsam starten:

```sh
make dev
```

Oder separat:

```sh
make api
make worker
make web
```

Öffnen Sie danach `http://127.0.0.1:5173`. Erstellen Sie eine library mit Namen und lokalem Ordner. Eine library ist ein portabler Ordner mit `library.sqlite`, source packages, PDFs, entpacktem TeX, `document.json`, `source.md`, assets, logs, lecture notes, exports und manifests.

## Erstes Paper

Nach dem Erstellen einer library nutzen Sie das Add article panel. Der normale Pfad ist eine arXiv ID wie `1706.03762`. Bilin lädt source package und PDF herunter, erstellt ein self-contained article bundle und stellt bei Bedarf einen parse job in die Warteschlange. Lokale TeX-Archive nutzen dieselbe bundle-Struktur wie arXiv sources. Markdown erzeugt sofort ein schwach strukturiertes Dokument. PDFs werden im aktuellen MVP nur gespeichert, nicht geparst, geöffnet, OCR-verarbeitet oder übersetzt.

Sobald ein document erzeugt wurde, öffnen Sie den reader über die article table. Reader unterstützt Study, Focus, Bilingual, Translation und Source view. Sections stehen über ein einklappbares Chapters control zur Verfügung. Paragraph blocks besitzen eine hover toolbar zum Kopieren, Prüfen des source LaTeX, Fragen zum aktuellen Block und erneuten Übersetzen.

## Provider einrichten

Öffnen Sie Settings und Models. Im simple mode fügen Sie eine API key ein, lassen Modelle von einem OpenAI-compatible oder Anthropic-compatible endpoint erkennen und wählen ein Modell per Anzeigenamen. Im advanced mode können Sie zusätzlich profile label, base URL, concurrency und requests per minute setzen.

Provider keys werden nicht in library-Ordnern gespeichert. Unter macOS nutzt Bilin standardmäßig Keychain und speichert in der globalen Datenbank nur eine `keychain:` reference. Um Keychain ohne fallback zu erzwingen:

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## Übersetzung und Translation Memory

Übersetzung läuft blockweise. Absätze und captions werden übersetzt; Gleichungen und strukturierte environment blocks behalten ihre source structure. Jede Übersetzung wird als variant gespeichert, sodass erneutes Übersetzen frühere Ergebnisse nicht überschreibt.

Validierte Übersetzungen gelangen zunächst als `pending` in die translation memory. Nur `approved` Einträge mit aktiviertem reuse werden in späteren Papers wiederverwendet.

## Fragen und Notizen

Reader kann Fragen zum ganzen Artikel oder zu einem ausgewählten Block beantworten. Bilin holt Evidenz aus lokalen Indizes, streamt die Antwort und speichert zitierte block refs. Wenn das gewählte model profile native search unterstützt, kann externe Suche aktiviert werden; sonst bleibt die Antwort auf den Artikelkontext beschränkt.

Lecture notes entstehen aus editierbaren patches. Es gibt Vorlagen für deep reading, group meeting, quick skim und reproduction-oriented reading. Akzeptierte Notizen werden als `lecture-notes.md` im article bundle gespeichert.

## CLI

Der CLI-Befehl ist `bilin` und wird aus `apps/api` mit `uv run` ausgeführt.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

Wenn die article revision id bekannt ist, können parsing, embeddings und export direkt laufen. Exportierte Markdown-Dateien und erzeugte lecture notes enthalten automatisch ein unsichtbares HTML-comment watermark. Es weist darauf hin, dass die Datei von Bilin erzeugt wurde, Drittinhalte oder abgeleitetes Material enthalten kann und nur weitergegeben werden sollte, wenn die ursprüngliche Lizenz oder der Rechteinhaber dies erlaubt.

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

## Lokale Daten und Synchronisierung

Bilin speichert app-level SQLite state, registered libraries, provider metadata, jobs, settings, note templates, translation memory und API-key fallback storage in einem globalen Datenverzeichnis, das `platformdirs` bestimmt. In der Entwicklung kann `BILIN_HOME` genutzt werden.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Libraries sind vom Nutzer gewählte, self-contained Ordner. Sie passen gut zu externen Synchronisierungstools wie iCloud, OneDrive oder Syncthing. Bilin löst Synchronisierungskonflikte nicht selbst.

## Entwicklerchecks

Backend:

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Frontend:

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

## Lizenz

Bilin source code, project-owned documentation, tests und project-owned fixtures stehen unter Apache-2.0. Siehe `LICENSE` und `NOTICE`. Diese Lizenz gilt nur für Bilin selbst. Sie gewährt keine Rechte an von Nutzern importierten Papers, PDFs, TeX source packages, Abbildungen, Tabellen, captions, datasets, maschinellen Übersetzungen oder lecture notes mit Drittinhalten.

## Fehlerbehebung

Wenn die API nicht erreichbar ist, prüfen Sie, ob `make api` läuft und `http://127.0.0.1:8000/health` JSON zurückgibt. Wenn TeX parsing mit `missing_dependency:latexml` fehlschlägt, installieren Sie LaTeXML und prüfen Sie mit `bilin doctor`, ob `latexml` und `latexmlpost` erkannt werden.
