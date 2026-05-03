# Bilin

Langue : [简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | Français | [Deutsch](README.de.md)

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## Pourquoi Bilin ? 📚✨

Bilin a un objectif simple : transformer la lecture d’un article scientifique, souvent vécue comme un combat solitaire avec un PDF en anglais, en un flux structuré de lecture, traduction, questions, prise de notes et révision. Bilin ne remplace pas le texte anglais original et ne réduit pas l’article à un résumé générique d’IA. Il conserve la structure du papier : sections, paragraphes, équations, figures, tableaux, captions, terminologie, questions et notes de cours.

Pour les chercheurs, Bilin rassemble des tâches dispersées dans un même flux local. Vous pouvez importer un article arXiv ou une archive TeX locale, obtenir du Markdown par paragraphes, traduire et mettre en cache les blocs, conserver plusieurs variantes de traduction, gérer les termes techniques, poser des questions sur le bloc courant ou sur tout l’article, transformer les réponses en notes de cours, puis exporter du Markdown ou des bundles. Les articles, PDFs, sources TeX, documents analysés, caches de traduction, historiques de questions et notes restent dans le dossier library que vous choisissez.

Pour les chercheurs dont l’anglais n’est pas la langue maternelle, l’intérêt est encore plus fort. Les étudiants, doctorants et personnes qui entrent dans un nouveau domaine ne sont souvent pas bloqués par un manque d’intelligence, mais par la combinaison de longues phrases anglaises, de termes spécialisés, du contexte des équations et des conventions d’écriture propres au domaine. Comprendre d’abord dans sa langue maternelle le contexte, la motivation, les équations clés, la logique expérimentale et les limites est souvent plus efficace que de lire l’anglais phrase par phrase dès le départ. Revenir ensuite au texte anglais permet de calibrer les termes et d’apprendre l’anglais académique sur une idée déjà comprise.

Bilin est donc conçu comme une première couche de lecture pour entrer dans la recherche. Il aide à passer de « je n’arrive pas à lire cet article » à « je comprends le problème, son importance, la méthode et les passages à revoir dans le texte anglais ». Une lecture sérieuse revient toujours au texte anglais, aux équations, aux figures et aux citations. Bilin rend ce chemin moins difficile et aide les nouveaux chercheurs à entrer plus vite dans le vrai sujet. 🌱

Bilin est une application web local-first pour lire, traduire, interroger, annoter et exporter des articles académiques. Le chemin principal utilise les sources TeX d’arXiv, car TeX préserve la structure nécessaire à une lecture sérieuse : sections, paragraphes, équations, figures, tableaux, captions, labels, citations et assets. Bilin fonctionne sur votre machine avec un frontend React + TypeScript, un backend FastAPI, une file de jobs SQLite et un worker Python. Il ne nécessite pas Docker, Redis, Celery, de comptes, de backend hébergé ni de synchronisation cloud intégrée.

La version actuelle est le MVP v0.1.0. Elle peut créer des libraries locales, importer des source packages arXiv, importer des archives TeX locales, transformer du Markdown en document faiblement structuré, sauvegarder des PDFs comme source artifacts, parser TeX avec LaTeXML lorsque la chaîne est installée, conserver des document blocks et assets structurés, construire des embeddings locaux déterministes, traduire paragraphes et captions avec des providers OpenAI-compatible ou Anthropic-compatible, conserver des translation variants, revoir et réutiliser la translation memory, gérer la terminologie d’un article, stocker les provider keys dans macOS Keychain, répondre avec des preuves issues de l’article, créer des patches éditables de lecture notes, gérer des templates de notes et exporter Markdown ou bundle.

## Feuille de route

Les prochaines versions pourront ajouter PDF LLM fallback parsing, providers optionnels d’embeddings neuronaux, export Word/EPUB/PDF soigné, shell de bureau et une forme d’installation plus complète. Les PDFs peuvent déjà être stockés comme source artifacts dans un bundle. Le support PDF futur sera un chemin optionnel qui ne modifie pas le flux TeX-first et n’introduit pas d’OCR ou de services lourds par défaut. Les comptes et la synchronisation intégrée ne font pas partie de la direction par défaut. Bilin restera local-first et gardera les dossiers library faciles à synchroniser avec iCloud, OneDrive ou Syncthing.

## Structure du dépôt

`apps/api` contient le backend FastAPI, le CLI, les migrations SQLite, les imports arXiv et fichiers locaux, le LaTeXML parser path, les provider profiles, translation jobs, deterministic local embeddings, glossary, question answering, lecture-note services, export services, worker et doctor command.

`apps/web` contient le frontend Vite + React + TypeScript. Il utilise Mantine, TanStack Query, Zustand, KaTeX, React Markdown et les tests Playwright/Vitest.

`docs` contient la conception, le plan MVP, les notes de sécurité locale et la documentation développeur. `fixtures/golden` contient des deterministic parser regression fixtures.

## Prérequis

Bilin nécessite Node.js, pnpm, Python 3.13 et uv. Le parsing TeX réel nécessite `latexml` et `latexmlpost` dans le `PATH`. La conversion d’assets peut utiliser ImageMagick `magick`, Ghostscript `gs`, ainsi que `tectonic` ou `pdflatex`.

Sur macOS avec Homebrew :

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Sous Linux, installez les paquets équivalents avec le gestionnaire de votre distribution. Sans LaTeXML, Markdown import, PDF save-only import, provider setup, traduction, notes, export et fixture tests restent disponibles. Les TeX parse jobs échouent clairement avec `missing_dependency:latexml`.

## Installation

Depuis le dossier source ou le projet téléchargé :

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

Lancez doctor avant de travailler.

```sh
make doctor
```

## Lancer l’application

Lancez API, worker et web ensemble :

```sh
make dev
```

Ou séparément :

```sh
make api
make worker
make web
```

Ouvrez `http://127.0.0.1:5173`. Créez une library avec un nom et un dossier local. Une library est un dossier portable contenant `library.sqlite`, source packages, PDFs, TeX décompressé, `document.json`, `source.md`, assets, logs, lecture notes, exports et manifests.

## Premier article

Après avoir créé une library, utilisez le panneau Add article. Le chemin habituel est un arXiv ID comme `1706.03762`. Bilin télécharge le source package et le PDF, crée un article bundle autonome et enfile un parse job si nécessaire. Les archives TeX locales utilisent la même structure de bundle. Markdown produit immédiatement un document faiblement structuré. Les PDFs sont seulement stockés dans ce MVP ; ils ne sont pas parsés, ouverts, OCRisés ni traduits.

Une fois le document produit, ouvrez le reader depuis la table d’articles. Reader supporte Study, Focus, Bilingual, Translation et Source view. Les sections sont disponibles dans un contrôle Chapters repliable. Les blocs de paragraphe ont une hover toolbar pour copier, inspecter le LaTeX source, poser une question sur le bloc courant et retraduire.

## Configuration des providers

Ouvrez Settings puis Models. En simple mode, collez une API key, découvrez les modèles depuis un endpoint OpenAI-compatible ou Anthropic-compatible et choisissez un modèle par son nom affiché. En advanced mode, vous pouvez aussi régler profile label, base URL, concurrency et requests per minute.

Les provider keys ne sont pas stockées dans les dossiers library. Sur macOS, Bilin utilise Keychain par défaut et ne garde qu’une référence `keychain:` dans la base globale. Pour forcer Keychain sans fallback :

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## Traduction et Translation Memory

La traduction se fait par blocs. Les paragraphes et captions sont traduits ; les équations et blocs structurés conservent la structure source. Chaque traduction est stockée comme variant, donc une retraduction n’écrase pas les versions précédentes.

Les traductions validées entrent dans la translation memory en état `pending`. Seules les entrées `approved` avec reuse activé sont réutilisées dans d’autres articles.

## Questions et notes

Reader permet de poser des questions sur tout l’article ou sur un bloc sélectionné. Bilin récupère des preuves dans les index locaux, diffuse la réponse et stocke les block refs cités. Si le model profile déclare native search, une recherche externe peut être activée ; sinon la réponse reste limitée au contexte de l’article.

Les lecture notes sont construites à partir de patches éditables. Des templates existent pour lecture approfondie, réunion de groupe, lecture rapide et reproduction. Les notes acceptées sont matérialisées dans `lecture-notes.md` dans l’article bundle.

## CLI

La commande CLI est `bilin`, exécutée via `uv run` depuis `apps/api`.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

Si vous connaissez l’article revision id, vous pouvez parser, créer des embeddings ou exporter directement. Les fichiers Markdown exportés et lecture notes générées incluent automatiquement un watermark invisible sous forme de commentaire HTML. Il indique que le fichier a été généré par Bilin, qu’il peut contenir du contenu tiers ou dérivé, et que la redistribution dépend de la licence originale ou de l’autorisation du titulaire des droits.

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

## Données locales et synchronisation

Bilin stocke app-level SQLite state, registered libraries, provider metadata, jobs, settings, note templates, translation memory et fallback storage de clés API dans un répertoire global choisi par `platformdirs`. En développement, vous pouvez utiliser `BILIN_HOME`.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Les libraries sont des dossiers autonomes choisis par l’utilisateur. Elles sont adaptées à des outils externes comme iCloud, OneDrive ou Syncthing. Bilin ne résout pas lui-même les conflits de synchronisation.

## Vérifications développeur

Backend :

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Frontend :

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

## Licence

Le code source de Bilin, la documentation propre au projet, les tests et les fixtures propres au projet sont sous Apache-2.0. Voir `LICENSE` et `NOTICE`. Cette licence ne couvre que Bilin lui-même. Elle ne donne aucun droit sur les articles, PDFs, sources TeX, figures, tableaux, captions, datasets, traductions automatiques ou notes contenant du contenu tiers importés par les utilisateurs.

## Dépannage

Si l’API ne répond pas, vérifiez que `make api` fonctionne et que `http://127.0.0.1:8000/health` renvoie du JSON. Si le parsing TeX échoue avec `missing_dependency:latexml`, installez LaTeXML et vérifiez que `bilin doctor` détecte `latexml` et `latexmlpost`.
