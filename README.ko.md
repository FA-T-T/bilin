# Bilin

언어: [简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | 한국어 | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## 왜 Bilin이 필요한가요? 📚✨

Bilin의 목적은 분명합니다. 영어 PDF를 혼자 버티며 읽는 일을, 구조화된 읽기, 번역, 질문, 노트 작성, 복습 흐름으로 바꾸는 것입니다. Bilin은 영어 원문을 대체하지 않습니다. 논문을 대충 요약하는 AI 레이어도 아닙니다. 논문의 장, 단락, 수식, 그림, 표, caption, 전문 용어, 질문, 강의 노트를 원문 구조에 맞춰 읽을 수 있게 합니다.

연구자에게 Bilin이 주는 편의는 흩어진 작업을 하나의 로컬 워크플로로 묶는 데 있습니다. arXiv 논문이나 로컬 TeX 아카이브를 가져오고, 단락 단위 Markdown으로 파싱하고, 블록별 번역과 캐시를 만들고, 여러 번역 버전을 보존하고, 전문 용어를 관리하고, 현재 단락이나 논문 전체에 질문하고, 답변을 강의 노트로 축적하고, Markdown이나 bundle로 내보낼 수 있습니다. 논문, PDF, TeX 소스, 파싱 결과, 번역 캐시, 질문 기록, 노트는 사용자가 선택한 library 폴더에 남습니다.

영어가 모국어가 아닌 연구 입문자에게 이 가치는 더 큽니다. 학부생, 대학원생, 새로운 분야에 들어온 연구자는 지능이 부족해서 막히는 것이 아니라, 긴 영어 문장, 밀도 높은 전문 용어, 수식의 맥락, 분야 특유의 글쓰기 방식에 동시에 막히는 경우가 많습니다. 먼저 모국어로 배경, 동기, 핵심 수식, 실험 논리, 한계를 이해한 뒤 영어 원문으로 돌아가 용어와 표현을 확인하면, 처음부터 영어를 한 문장씩 억지로 읽는 것보다 훨씬 효율적입니다. 이 과정은 연구 이해와 학술 영어 학습을 동시에 돕습니다.

Bilin은 연구 입문을 위한 첫 번째 읽기 레이어입니다. “이 논문을 못 읽겠다”를 “무슨 문제를 다루는지, 왜 중요한지, 어떤 방법을 쓰는지, 어떤 부분을 영어 원문으로 다시 봐야 하는지 알겠다”로 바꾸는 도구입니다. 진지한 읽기는 결국 영어 원문, 수식, 그림, 표, 인용으로 돌아가야 합니다. Bilin은 그 길을 조금 덜 고통스럽게 만듭니다. 🌱

Bilin은 논문 읽기, 번역, 질문, 주석, 내보내기를 위한 local-first 웹 애플리케이션입니다. 주요 입력은 arXiv TeX 소스입니다. TeX는 장, 단락, 수식, 그림, 표, caption, label, 인용, 소스 asset처럼 진지한 논문 읽기에 필요한 구조를 보존하기 때문입니다. Bilin은 React + TypeScript 프론트엔드, FastAPI 백엔드, SQLite job queue, Python worker로 구성되며 사용자의 컴퓨터에서 동작합니다. Docker, Redis, Celery, 계정 시스템, 호스팅 백엔드, 내장 클라우드 동기화는 필요하지 않습니다.

현재 버전은 v0.1.0 MVP입니다. 로컬 library 생성, arXiv source package 가져오기, 로컬 TeX archive 가져오기, Markdown 약한 구조화, PDF를 bundle에 저장, LaTeXML이 설치된 환경에서 TeX 파싱, 구조화된 document blocks와 assets 저장, deterministic local block embeddings, OpenAI-compatible 또는 Anthropic-compatible provider를 통한 단락과 caption 번역, translation variants, translation memory 검토와 재사용, 논문 용어 관리, macOS Keychain에 provider key 저장, 논문 근거 기반 스트리밍 질문 응답, 편집 가능한 강의 노트 patch, custom note template, Markdown과 bundle export를 지원합니다.

## 앞으로의 계획

앞으로 PDF LLM fallback parsing, 선택적 neural embedding provider, Word/EPUB/정리된 PDF export, desktop shell, 더 완성된 설치 형태를 확장 방향으로 둡니다. PDF는 이미 source artifact로 bundle에 저장할 수 있습니다. 미래의 PDF 기능은 TeX-first 경로를 바꾸지 않는 선택적 파싱 경로로 추가되며, 기본 OCR이나 무거운 서비스 의존성을 도입하지 않습니다. 계정 시스템과 내장 동기화는 기본 제품 방향에 포함하지 않습니다. Bilin은 local-first를 유지하고 library 폴더를 iCloud, OneDrive, Syncthing 같은 외부 동기화 도구와 잘 맞게 둡니다.

## 저장소 구조

`apps/api`는 FastAPI backend, CLI, SQLite migrations, arXiv와 업로드 import, LaTeXML parser path, provider profiles, translation jobs, deterministic local embeddings, glossary, question answering, lecture-note, export, worker, doctor command를 포함합니다.

`apps/web`은 Vite + React + TypeScript frontend입니다. Mantine, TanStack Query, Zustand, KaTeX, React Markdown, Playwright/Vitest를 사용합니다.

`docs`에는 설계 문서, MVP 실행 계획, local-safety notes, 개발자 문서가 있습니다. `fixtures/golden`에는 deterministic parser regression fixtures가 있습니다.

## 요구 사항

Bilin에는 Node.js, pnpm, Python 3.13, uv가 필요합니다. 실제 TeX 파싱에는 `latexml`과 `latexmlpost`가 `PATH`에 있어야 합니다. asset 변환에는 ImageMagick `magick`, Ghostscript `gs`, `tectonic` 또는 `pdflatex`가 도움이 됩니다.

macOS + Homebrew에서는 다음처럼 설치할 수 있습니다.

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Linux에서는 배포판 패키지 관리자로 대응 도구를 설치하세요. LaTeXML이 없어도 Markdown import, PDF save-only import, provider 설정, 번역, 노트, export, fixture tests는 동작합니다. TeX parse job은 `missing_dependency:latexml`로 명확하게 실패합니다.

## 설치

소스 디렉터리 또는 다운로드한 프로젝트 디렉터리에서 시작합니다.

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

처음에는 doctor를 실행하세요.

```sh
make doctor
```

## 앱 실행

API, worker, web을 함께 실행합니다.

```sh
make dev
```

개별 실행도 가능합니다.

```sh
make api
make worker
make web
```

실행 후 `http://127.0.0.1:5173`을 엽니다. library를 만들고 이름과 로컬 폴더를 지정하세요. library는 `library.sqlite`, source package, PDF, unpacked TeX, `document.json`, `source.md`, assets, logs, lecture notes, exports, manifest를 담는 이동 가능한 폴더입니다.

## 첫 논문

library를 만든 뒤 Library 페이지에서 Add article panel을 사용합니다. 일반적인 경로는 `1706.03762` 같은 arXiv ID입니다. Bilin은 source package와 PDF를 다운로드하고, self-contained article bundle을 만들고, 필요하면 parse job을 큐에 넣습니다. 로컬 TeX archive는 arXiv source package와 같은 bundle 경로를 사용합니다. Markdown은 즉시 약한 구조 문서가 됩니다. PDF는 현재 MVP에서 저장만 하며, 파싱, 열기, OCR, 번역은 하지 않습니다.

document가 생성되면 article table에서 reader를 열 수 있습니다. Reader는 Study, Focus, Bilingual, Translation, Source view를 지원합니다. section은 접을 수 있는 Chapters control로 제공됩니다. 단락 block에는 hover toolbar가 있어 복사, source LaTeX 확인, 현재 단락 질문, 재번역을 할 수 있습니다.

## Provider 설정

Settings에서 Models를 엽니다. simple mode에서는 API key를 붙여 넣으면 OpenAI-compatible 또는 Anthropic-compatible endpoint에서 모델 목록을 가져오고 표시 이름으로 선택할 수 있습니다. advanced mode에서는 profile label, base URL, concurrency, requests per minute도 설정할 수 있습니다.

provider key는 library 폴더에 저장되지 않습니다. macOS에서는 기본적으로 Keychain에 저장하고 global application database에는 `keychain:` reference만 남깁니다. Keychain 실패 시 fallback을 막고 싶다면 다음을 설정합니다.

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## 번역과 Translation Memory

번역은 block 단위로 실행됩니다. 단락과 caption은 번역되고, 수식과 구조화된 environment block은 source structure로 보존됩니다. 번역은 variant로 저장되므로 재번역해도 이전 결과를 덮어쓰지 않습니다.

검증된 번역은 처음에는 `pending` translation memory로 들어갑니다. Settings의 Translation memory에서 검토하고, `approved`이며 reuse가 활성화된 항목만 이후 논문에서 재사용됩니다.

## 질문 응답과 강의 노트

Reader에서는 논문 전체나 선택한 block에 대해 질문할 수 있습니다. Bilin은 로컬 index에서 논문 근거를 찾고, 답변을 스트리밍하며, 인용한 block refs를 저장합니다. 선택한 model profile이 native search를 지원할 때만 외부 검색을 사용할 수 있습니다.

강의 노트는 편집 가능한 patch로 만들어집니다. 정독, 그룹 미팅, 빠른 훑어보기, 재현 중심 읽기 템플릿이 기본 제공되며, 사용자 템플릿도 저장할 수 있습니다. accepted notes는 article bundle 안의 `lecture-notes.md`에 저장됩니다.

## CLI

CLI command는 `bilin`입니다. `apps/api`에서 `uv run`으로 실행합니다.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

article revision id를 알고 있다면 parse, embedding, export를 직접 실행할 수 있습니다. export된 Markdown과 생성된 lecture notes에는 Bilin이 생성했다는 점, 제3자 논문 내용이나 파생 내용을 포함할 수 있다는 점, 원 라이선스나 권리자가 허용할 때만 재배포해야 한다는 점을 담은 보이지 않는 HTML comment watermark가 자동으로 들어갑니다.

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

## 로컬 데이터와 동기화

Bilin은 app-level SQLite state, registered libraries, provider metadata, jobs, settings, note templates, translation memory, Keychain fallback storage를 global application data directory에 저장합니다. 위치는 `platformdirs`가 정하며 개발 중에는 `BILIN_HOME`으로 바꿀 수 있습니다.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

library는 사용자가 선택하는 self-contained 폴더입니다. iCloud, OneDrive, Syncthing 같은 외부 동기화 도구와 함께 쓰기 쉽습니다. Bilin 자체는 동기화 충돌을 해결하지 않습니다.

## 개발자 검사

backend check는 `apps/api`에서 실행합니다.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

frontend check는 repository root에서 실행합니다.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

## 라이선스

Bilin의 source code, project-owned documentation, tests, project-owned fixtures는 Apache-2.0으로 라이선스됩니다. `LICENSE`와 `NOTICE`를 보세요. 이 라이선스는 Bilin 자체에만 적용되며, 사용자가 가져온 논문, PDF, TeX source package, 그림, 표, caption, dataset, 기계 번역, 제3자 내용을 포함한 lecture notes에 대한 권리를 부여하지 않습니다.

## 문제 해결

API에 연결할 수 없으면 `make api`가 실행 중인지, `http://127.0.0.1:8000/health`가 JSON을 반환하는지 확인하세요. TeX parse가 `missing_dependency:latexml`로 실패하면 LaTeXML을 설치하고 `bilin doctor`에서 `latexml`과 `latexmlpost`가 보이는지 확인하세요.
