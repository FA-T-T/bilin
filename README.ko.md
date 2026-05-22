<h1 align="center">
  Ilios (LLM 보조 논문 읽기)<br>
  <sub><sub>衔牍 · 理紐</sub></sub>
</h1>

<p align="center">
  <em>다국어 논문 읽기 도구</em>
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

## Ilios란 무엇인가

Ilios는 영어 논문을 여러 언어로 이해해야 하는 연구자를 위한 **local-first, structured** 논문 읽기 워크스페이스입니다.

완전히 로컬에서 동작하며 arXiv source package 또는 로컬 LaTeX archive를 지원합니다.

논문, 파싱 결과, 번역 cache, Q&A 기록, note는 사용자가 지정한 local folder에 저장됩니다. **계정이 필요 없고, hosted backend가 없으며, 파일을 업로드하지 않습니다.**

번역 비용도 낮습니다. DeepSeek V4 Flash로 10편, 총 240쪽의 논문을 처리한 테스트에서 전체 비용은 약 2 CNY였습니다.

## 주요 기능

##### **다국어**

스크린샷에 보이는 논문 본문, 그림, 수식은 원저자 또는 권리자에게 속합니다. 여기서는 Ilios의 로컬 읽기, 번역, Q&A, structured rendering 기능을 보여 주기 위해서만 사용합니다.

중국어 예시:

<img src="./assets/image-20260522193937577.png" alt="Chinese translation example" style="zoom: 25%;" />

프랑스어 예시:

<img src="./assets/image-20260522194355907.png" alt="French translation example" style="zoom:25%;" />

일본어 예시:

<img src="./assets/image-20260522193846703.png" alt="Japanese translation example" style="zoom:25%;" />

독일어 예시:

<img src="./assets/image-20260522194717793.png" alt="German translation example" style="zoom:25%;" />

한국어 예시:

<img src="./assets/image-20260522194157385.png" alt="Korean translation example" style="zoom:25%;" />

##### 그림

<img src="./assets/image-20260522194901555.png" alt="Figure rendering example" style="zoom: 25%;" />

##### 수식

KaTeX rendering.

<img src="./assets/image-20260522195038561.png" alt="Formula rendering example" style="zoom:25%;" />

##### 표

HTML table로 다시 rendering합니다.

<img src="./assets/image-20260522195134674.png" alt="Table rendering example" style="zoom:25%;" />

##### 문장 hover 강조

문장 단위로 나누어 bilingual 비교를 쉽게 합니다.

![Sentence hover highlighting](./assets/image-20260522195506879.png)

##### 인용 미리보기

인용을 자동으로 파싱하며 Google Scholar와 arXiv 검색을 지원합니다. 한 번의 클릭으로 문고에 추가하고 자동 번역할 수도 있습니다.

<img src="./assets/image-20260522202145628.png" alt="Citation preview example" style="zoom: 33%;" />

##### 원문 또는 번역문의 Markdown export

원문 Markdown 또는 번역문 Markdown을 export하여 knowledge base document로 바로 사용할 수 있습니다.

<img src="./assets/image-20260522202353196.png" alt="Markdown export example" style="zoom:25%;" />

##### Kindle mode

Kindle mode는 같은 local network에 있는 e-ink device가 browser로 읽을 수 있게 만든 저자원 모드입니다. scrolling을 없애고 좌우에 page-turn button을 둡니다.

10 inch 이상의 e-ink device를 landscape 방향으로 사용하는 것을 권장합니다.

![Kindle mode example](./assets/image-20260522202534656.png)

## Quick Start

### Agent users (Codex, Claude, DeepSeek-TUI, OpenCode...)

이 page link를 agent에게 직접 보내고 다음과 같이 말하세요.

"https://github.com/FA-T-T/bilin Please help me deploy this service, install the required dependencies, and start the app."

agent가 dependency install, deployment, application startup을 진행할 수 있습니다.

### 일반 사용자

Ilios에는 Node.js, pnpm, Python 3.13, uv가 필요합니다. core app은 TeX toolchain 없이도 시작할 수 있지만 실제 LaTeX parsing에는 `PATH`의 `latexml`과 `latexmlpost`가 필요합니다. image와 PDF 처리를 위해 ImageMagick `magick`, Ghostscript `gs`, `tectonic` 또는 `pdflatex`를 권장합니다.

macOS + Homebrew 환경 준비:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

source에서 시작:

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

고정된 개발 환경에서는 quick-start script를 사용할 수 있습니다. 기존 virtual environment와 `node_modules`를 재사용하고, 환경 탐색을 건너뛰며, 이미 실행 중이면 status를 바로 반환합니다.

```sh
./scripts/start-dev.sh
```

시작 후 `http://127.0.0.1:5173`을 여세요. API는 기본적으로 `127.0.0.1:8000`에서 실행되고, worker는 import, parsing, translation, Q&A, notes, export job을 처리합니다. debugging에는 `make api`, `make worker`, `make web`을 따로 실행할 수 있습니다.

LaTeXML이 없어도 Ilios는 Markdown import, PDF 저장, model configuration, translation, notes, export, fixture tests를 지원합니다. TeX parse job은 불안정한 regex parsing으로 조용히 fallback하지 않고 `missing_dependency:latexml`로 명시적으로 실패합니다.

## 첫 논문

home page에서 library를 만들고 이름과 local directory path를 입력합니다. library는 self-contained folder이며 `library.sqlite`, original source archive, PDF, unpacked TeX, parsed `document.json`, `source.md`, assets, logs, notes, exports, manifests를 포함합니다.

library 안에서 `1706.03762` 같은 arXiv ID를 입력합니다. Ilios는 source package와 PDF를 download하고, self-contained article package를 만들며, parsing이 켜져 있으면 task를 queue에 넣습니다. local TeX archive도 같은 package path를 재사용합니다. Markdown은 weak structured document로 즉시 import되고, PDF는 source file로 저장됩니다.

parsing이 끝나면 문고에서 논문을 선택하고 Read를 눌러 reader로 들어갑니다. reader는 Study, Bilingual, Translation, Source 네 가지 view를 지원합니다. left rail은 같은 library 안의 논문을 전환합니다. right rail은 tasks, model setup, paper chat, translation, glossary, notes, export tools를 제공합니다. paragraph hover action으로 copy, source inspection, retranslation, current paragraph question을 실행할 수 있습니다. figure와 table은 asset이 있으면 직접 표시되고, 없으면 caption과 label을 유지한 structured placeholder로 표시됩니다.

## Model configuration

Settings -> Models를 여세요. simple mode에서는 API key를 붙여 넣으면 compatible endpoint에서 model list를 가져옵니다. advanced mode에서는 profile label, base URL, concurrency, requests-per-minute limit를 설정할 수 있습니다. **advanced mode를 권장합니다.**

provider key는 library folder에 저장되지 않습니다. macOS에서는 기본적으로 Keychain에 저장하고 global database에는 `keychain:` reference만 남깁니다. 다른 platform이나 `BILIN_CREDENTIAL_STORE=app_settings`를 설정한 경우 SQLite development fallback을 사용합니다. Keychain을 사용할 수 없을 때 provider creation을 막고 싶다면 다음을 설정하세요.

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

CLI는 Web app과 같은 backend logic을 재사용합니다.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

repository에는 network access나 완전한 TeX toolchain 없이 reader pipeline을 검증할 수 있는 golden fixtures가 포함되어 있습니다.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

command는 `reader_route`와 `library_id`를 반환합니다. app을 시작한 뒤 browser에서 해당 route를 열면 생성된 article을 확인할 수 있습니다.

## Local data, security, sync

Ilios는 app-level SQLite state, registered libraries, provider configuration, jobs, settings, note templates, translation memory, Keychain을 사용할 수 없거나 끈 경우의 API key fallback storage를 global application data directory에 저장합니다. 이 directory는 `platformdirs`로 결정되며 개발 중에는 `BILIN_HOME`으로 override할 수 있습니다.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Library directory는 사용자가 선택하는 self-contained folder이며 iCloud, OneDrive, Syncthing 같은 external sync tool에 적합합니다. Ilios는 sync conflict를 직접 처리하지 않습니다. app을 닫은 뒤 sync하고, conflict는 sync tool의 version history로 복구하세요.

export된 Markdown과 lecture notes에는 Ilios가 생성한 file이며 third-party content를 포함할 수 있다는 invisible HTML comment watermark가 자동으로 들어갑니다. watermark는 일반 reading layout에 영향을 주지 않습니다.

## Developers

backend checks는 `apps/api`에서 실행합니다.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

frontend checks는 repository root에서 실행합니다.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

default tests는 fixtures와 mocks를 사용하며 real network나 완전한 TeX toolchain을 요구하지 않습니다. real arXiv와 LaTeXML integration tests는 명시적으로 opt-in해야 합니다.

## License

Ilios source code, project-owned documentation, tests, project-owned fixtures는 Apache-2.0 license를 따릅니다. [LICENSE](LICENSE)와 [NOTICE](NOTICE)를 확인하세요. 이 license는 Ilios project 자체만 다루며 user-imported papers, PDFs, TeX source packages, figures, captions, datasets, machine translations, third-party material이 들어간 lecture notes에는 적용되지 않습니다. export물을 재배포하려면 원논문 또는 asset license, rights-holder permission, 또는 적용 가능한 legal exception을 따라야 합니다.

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  빛을 빌려 글을 책상 앞으로 가져옵니다.<br><br>
  <strong>理紐</strong><br>
  논리의 끈을 묶는 사람. 당신의 생각과 저자의 생각을 잇는 다리입니다.<br><br>
  <em>Ilios가 논문 읽는 밤을 하나 줄여 주었다면, Star를 눌러 더 많은 새 연구자가 이 도구를 찾을 수 있게 해 주세요.</em>
</p>
