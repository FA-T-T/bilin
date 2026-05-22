<h1 align="center">
  Ilios (lecture d'articles assistee par LLM)<br>
  <sub><sub>衔牍 · 理紐</sub></sub>
</h1>

<p align="center">
  <em>Un outil multilingue pour lire les articles scientifiques</em>
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

## Qu'est-ce qu'Ilios

Ilios est un espace de lecture **local-first et structure** pour les chercheurs qui doivent comprendre des articles en anglais a travers plusieurs langues.

Il fonctionne localement et prend en charge les paquets sources arXiv ou les archives LaTeX locales.

Les articles, resultats d'analyse, caches de traduction, historiques de questions et notes restent dans le dossier local que vous choisissez. **Aucun compte, aucun backend heberge et aucun upload de fichier ne sont requis.**

Le cout de traduction est faible. Dans un test, DeepSeek V4 Flash a traite 10 articles, 240 pages au total, pour environ 2 CNY.

## Fonctionnalites principales

##### **Multilingue**

Le texte, les figures et les formules visibles dans les captures appartiennent aux auteurs ou ayants droit originaux. Ils sont utilises ici uniquement pour montrer les fonctions locales de lecture, traduction, Q&A et rendu structure d'Ilios.

Exemple chinois:

<img src="./assets/image-20260522193937577.png" alt="Chinese translation example" style="zoom: 25%;" />

Exemple francais:

<img src="./assets/image-20260522194355907.png" alt="French translation example" style="zoom:25%;" />

Exemple japonais:

<img src="./assets/image-20260522193846703.png" alt="Japanese translation example" style="zoom:25%;" />

Exemple allemand:

<img src="./assets/image-20260522194717793.png" alt="German translation example" style="zoom:25%;" />

Exemple coreen:

<img src="./assets/image-20260522194157385.png" alt="Korean translation example" style="zoom:25%;" />

##### Figures

<img src="./assets/image-20260522194901555.png" alt="Figure rendering example" style="zoom: 25%;" />

##### Formules

Rendu KaTeX.

<img src="./assets/image-20260522195038561.png" alt="Formula rendering example" style="zoom:25%;" />

##### Tableaux

Rendu sous forme de tableaux HTML.

<img src="./assets/image-20260522195134674.png" alt="Table rendering example" style="zoom:25%;" />

##### Mise en evidence des phrases au survol

La segmentation en phrases facilite la comparaison bilingue.

![Sentence hover highlighting](./assets/image-20260522195506879.png)

##### Apercu des citations

Les citations sont analysees automatiquement. Ilios prend en charge la recherche Google Scholar et arXiv, l'import en bibliotheque en un clic et la traduction automatique.

<img src="./assets/image-20260522202145628.png" alt="Citation preview example" style="zoom: 33%;" />

##### Export Markdown de l'original ou de la traduction

Exportez le texte original ou traduit en Markdown et utilisez-le directement comme document de base de connaissances.

<img src="./assets/image-20260522202353196.png" alt="Markdown export example" style="zoom:25%;" />

##### Mode Kindle

Le mode Kindle permet aux appareils e-ink du reseau local de lire depuis le navigateur avec une consommation reduite. Il supprime le scroll et ajoute des boutons de changement de page a gauche et a droite.

Un appareil e-ink de 10 pouces ou plus en orientation paysage est recommande.

![Kindle mode example](./assets/image-20260522202534656.png)

## Demarrage rapide

### Utilisateurs d'agents (Codex, Claude, DeepSeek-TUI, OpenCode...)

Envoyez le lien de cette page directement a un agent et dites:

"https://github.com/FA-T-T/bilin Please help me deploy this service, install the required dependencies, and start the app."

L'agent peut installer les dependances, deployer le projet et lancer l'application.

### Utilisateurs classiques

Ilios requiert Node.js, pnpm, Python 3.13 et uv. L'application principale peut demarrer sans chaine TeX, mais l'analyse LaTeX reelle necessite `latexml` et `latexmlpost` dans le `PATH`. ImageMagick `magick`, Ghostscript `gs` et `tectonic` ou `pdflatex` sont recommandes pour les images et PDF.

Preparation macOS + Homebrew:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Demarrer depuis les sources:

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

Dans un environnement de developpement fixe, vous pouvez utiliser le script de demarrage rapide. Il reutilise les virtual environments et `node_modules`, evite la detection de l'environnement et retourne directement l'etat si la stack tourne deja.

```sh
./scripts/start-dev.sh
```

Apres le demarrage, ouvrez `http://127.0.0.1:5173`. L'API utilise par defaut `127.0.0.1:8000`, et le worker gere import, parsing, traduction, Q&A, notes et exports. Vous pouvez aussi lancer `make api`, `make worker` et `make web` separement pour deboguer.

Sans LaTeXML, Ilios demarre toujours et prend en charge l'import Markdown, le stockage PDF, la configuration des modeles, la traduction, les notes, l'export et les tests fixtures. Les jobs TeX echouent explicitement avec `missing_dependency:latexml` au lieu de retomber silencieusement sur un parsing regex instable.

## Premier article

Sur la page d'accueil, creez une library avec un nom et un chemin de dossier local. Une library est un dossier autonome contenant `library.sqlite`, les sources originales, les PDF, le TeX decompresse, le `document.json` parse, `source.md`, assets, logs, notes, exports et manifests.

Dans la library, saisissez un arXiv ID comme `1706.03762`. Ilios telecharge le source package et le PDF, cree un article package autonome et met les taches en queue si le parsing est active. Les archives TeX locales reutilisent le meme package path. Markdown est importe immediatement comme document faiblement structure, et les PDF sont conserves comme fichiers source.

Une fois le parsing termine, selectionnez l'article dans la bibliotheque et cliquez sur Read. Le lecteur prend en charge Study, Bilingual, Translation et Source. La barre gauche change d'article dans la meme library. La barre droite donne acces aux taches, modeles, chat sur l'article, traduction, glossaire, notes et exports. Au survol d'un paragraphe, vous pouvez copier, inspecter la source, retraduire ou poser une question sur ce paragraphe. Les figures et tableaux s'affichent directement lorsque les assets existent; sinon Ilios conserve captions et labels avec des placeholders structures.

## Configuration des modeles

Ouvrez Settings -> Models. En mode simple, collez une API key et Ilios recupere la liste des modeles depuis un endpoint compatible. Le mode avance permet de definir le profile label, base URL, la concurrence et la limite de requetes par minute. **Le mode avance est recommande.**

Les provider keys ne sont pas stockees dans les dossiers library. Sur macOS, elles sont stockees par defaut dans Keychain et la base globale ne conserve qu'une reference `keychain:`. Sur les autres plateformes, ou avec `BILIN_CREDENTIAL_STORE=app_settings`, Ilios utilise le fallback SQLite de developpement. Pour bloquer la creation de provider si Keychain est indisponible, definissez:

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

La CLI reutilise la meme logique backend que l'application web.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

Le depot inclut des golden fixtures pour valider le pipeline du lecteur sans reseau ni chaine TeX complete.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

La commande retourne `reader_route` et `library_id`. Lancez l'application et ouvrez la route dans le navigateur pour verifier l'article genere.

## Donnees locales, securite et synchronisation

Ilios utilise un repertoire global de donnees applicatives pour l'etat SQLite, les libraries enregistrees, la configuration des providers, les jobs, settings, note templates, translation memory et le stockage fallback des API keys lorsque Keychain est indisponible ou desactive. Ce repertoire est determine par `platformdirs` et peut etre remplace en developpement avec `BILIN_HOME`.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Les dossiers library sont choisis par l'utilisateur et autonomes, donc adaptes a des outils externes comme iCloud, OneDrive ou Syncthing. Ilios ne resout pas les conflits de synchronisation. Fermez l'application avant de synchroniser et recuperez les conflits avec l'historique de versions de l'outil de sync.

Les Markdown et notes exportes incluent automatiquement un watermark invisible en commentaire HTML. Il indique que le fichier a ete genere par Ilios et peut contenir du contenu tiers. Le watermark n'affecte pas la lecture normale.

## Developpeurs

Executez les checks backend dans `apps/api`.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Executez les checks frontend depuis la racine du depot.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Les tests par defaut utilisent fixtures et mocks. Ils ne demandent ni reseau reel ni chaine TeX complete. Les tests reels arXiv et LaTeXML sont opt-in explicites.

## Licence

Le code source d'Ilios, la documentation propre au projet, les tests et les fixtures propres au projet sont sous licence Apache-2.0. Voir [LICENSE](LICENSE) et [NOTICE](NOTICE). Cette licence couvre seulement le projet Ilios lui-meme. Elle ne couvre pas les articles, PDF, paquets sources TeX, figures, captions, datasets, traductions automatiques ou notes contenant du contenu tiers importes par l'utilisateur. La redistribution des exports doit respecter la licence de l'article ou de l'asset original, l'autorisation de l'ayant droit ou les exceptions legales applicables.

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  Emprunter une lumiere et porter le texte jusqu'a votre bureau.<br><br>
  <strong>理紐</strong><br>
  Celui qui noue le fil du raisonnement et relie votre pensee a celle de l'auteur.<br><br>
  <em>Si Ilios vous evite une nuit blanche sur un article, donnez une Star au projet pour aider d'autres jeunes chercheurs a le trouver.</em>
</p>
