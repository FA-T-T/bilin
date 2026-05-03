# Bilin

Idioma: [简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | Español | [Français](README.fr.md) | [Deutsch](README.de.md)

AI agents: Read [AGENT_GUIDE.md](AGENT_GUIDE.md) instead — structured for LLM consumption, not human browsing.

## ¿Por qué Bilin? 📚✨

Bilin tiene un propósito claro: convertir la lectura de artículos científicos, que a menudo se siente como pelearse a solas con un PDF en inglés, en un flujo estructurado de lectura, traducción, preguntas, notas y repaso. No reemplaza el original en inglés y no pretende convertir el artículo en un resumen genérico de IA. Mantiene visible la estructura del paper: secciones, párrafos, ecuaciones, figuras, tablas, captions, terminología, preguntas y notas de estudio.

Para investigadores, Bilin reúne tareas dispersas en un flujo local. Puedes importar un paper de arXiv o un archivo TeX local, obtener Markdown por párrafos, traducir y cachear bloques, conservar variantes de traducción, gestionar términos técnicos, preguntar sobre el bloque actual o sobre todo el artículo, convertir respuestas en notas de clase y exportar Markdown o bundles. Papers, PDFs, fuentes TeX, documentos parseados, caché de traducción, historial de preguntas y notas quedan dentro de la carpeta library que eliges.

Para quienes no tienen el inglés como lengua materna, el valor es aún más directo. Estudiantes universitarios, estudiantes de posgrado y personas que entran en un campo nuevo muchas veces no se bloquean por falta de capacidad, sino porque las frases largas en inglés, la terminología densa, el contexto de las ecuaciones y las convenciones de escritura del área aparecen al mismo tiempo. Entender primero en la lengua materna el contexto, la motivación, las ecuaciones clave, la lógica experimental y las limitaciones suele ser mucho más eficiente que leer desde el inicio cada frase en inglés. Luego volver al original permite calibrar términos y aprender inglés académico sobre una idea que ya tiene sentido.

Bilin está diseñado como la primera capa de lectura para entrar en investigación. Ayuda a transformar “no puedo terminar este paper” en “sé qué problema estudia, por qué importa, cómo funciona y qué partes debo revisar en el original inglés”. La lectura rigurosa siempre vuelve al texto inglés, las ecuaciones, las figuras y las citas. Bilin hace ese camino menos duro y ayuda a entrar antes en la investigación real. 🌱

Bilin es una aplicación web local-first para leer, traducir, preguntar, anotar y exportar artículos académicos. La ruta principal usa fuentes TeX de arXiv, porque TeX conserva la estructura necesaria para una lectura seria: secciones, párrafos, ecuaciones, figuras, tablas, captions, labels, citas y assets. Bilin corre en tu propia máquina con frontend React + TypeScript, backend FastAPI, cola de trabajos SQLite y worker Python. No requiere Docker, Redis, Celery, cuentas, backend alojado ni sincronización integrada en la nube.

La versión actual es el MVP v0.1.0. Puede crear libraries locales, importar paquetes fuente de arXiv, importar archivos TeX locales, convertir Markdown en documentos de estructura débil, guardar PDFs como artefactos fuente, parsear TeX con LaTeXML cuando está instalado, guardar document blocks y assets estructurados, construir embeddings locales deterministas, traducir párrafos y captions mediante providers OpenAI-compatible o Anthropic-compatible, conservar translation variants, revisar y reutilizar translation memory, gestionar glosarios de artículo, guardar provider keys en macOS Keychain, responder preguntas con evidencia del artículo, crear patches editables de lecture notes, editar plantillas de notas y exportar Markdown o bundles.

## Planes futuros

Versiones futuras añadirán PDF LLM fallback parsing, providers opcionales de neural embeddings, exportación a Word/EPUB/PDF pulido, una shell de escritorio y una forma de instalación más completa. Los PDFs ya pueden guardarse como source artifacts dentro del bundle; el soporte futuro para PDF será una ruta opcional que no cambia el flujo principal TeX-first ni introduce OCR o servicios pesados por defecto. Las cuentas y la sincronización integrada no son parte de la dirección por defecto. Bilin seguirá siendo local-first y mantendrá las libraries fáciles de sincronizar con herramientas externas como iCloud, OneDrive o Syncthing.

## Estructura del repositorio

`apps/api` contiene el backend FastAPI, CLI, SQLite migrations, importación de arXiv y archivos locales, LaTeXML parser path, provider profiles, translation jobs, deterministic local embeddings, glossary, question answering, lecture-note services, export services, worker y doctor command.

`apps/web` contiene el frontend Vite + React + TypeScript. Usa Mantine, TanStack Query, Zustand, KaTeX, React Markdown y pruebas Playwright/Vitest.

`docs` contiene diseño, plan MVP, notas de seguridad local y documentación para desarrolladores. `fixtures/golden` contiene deterministic parser regression fixtures.

## Requisitos

Bilin necesita Node.js, pnpm, Python 3.13 y uv. El parseo real de TeX requiere `latexml` y `latexmlpost` en `PATH`. Para conversión de assets ayudan ImageMagick `magick`, Ghostscript `gs` y un motor TeX como `tectonic` o `pdflatex`.

En macOS con Homebrew:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

En Linux, instala los paquetes equivalentes con el gestor de tu distribución. Sin LaTeXML, siguen funcionando Markdown import, PDF save-only import, provider setup, traducción, notas, export y fixture tests. Los TeX parse jobs fallan explícitamente con `missing_dependency:latexml`.

## Instalación

Comienza desde el directorio fuente o el proyecto descargado.

```sh
pnpm install
cd apps/api
uv sync
cd ../..
```

Ejecuta doctor antes de usar el sistema.

```sh
make doctor
```

## Ejecutar la aplicación

Inicia API, worker y web juntos:

```sh
make dev
```

También puedes ejecutarlos por separado:

```sh
make api
make worker
make web
```

Abre `http://127.0.0.1:5173`. Crea una library con un nombre y una carpeta local. Una library es una carpeta portable que contiene `library.sqlite`, source packages, PDFs, TeX desempaquetado, `document.json`, `source.md`, assets, logs, lecture notes, exports y manifests.

## Primer artículo

Después de crear una library, usa el panel Add article. La ruta normal es un arXiv ID como `1706.03762`. Bilin descarga el source package y el PDF, crea un article bundle autocontenido y encola un parse job si corresponde. Los archivos TeX locales usan la misma estructura de bundle que arXiv. Markdown genera inmediatamente un documento de estructura débil. PDF solo se guarda en este MVP; no se parsea, abre, procesa con OCR ni traduce.

Cuando se produce el document, puedes abrir el reader desde la tabla de artículos. Reader soporta Study, Focus, Bilingual, Translation y Source view. Las secciones aparecen en un control Chapters plegable. Los bloques de párrafo tienen hover toolbar para copiar, inspeccionar LaTeX fuente, preguntar por el bloque actual y retraducir.

## Configuración de providers

Abre Settings y luego Models. En simple mode, pega una API key, descubre modelos desde un endpoint OpenAI-compatible o Anthropic-compatible y selecciona un modelo por nombre visible. En advanced mode puedes configurar profile label, base URL, concurrency y requests per minute.

Las provider keys no se guardan dentro de la library. En macOS, Bilin usa Keychain por defecto y guarda solo una referencia `keychain:` en la base global. Para exigir Keychain sin fallback:

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## Traducción y Translation Memory

La traducción funciona por bloques. Párrafos y captions se traducen; ecuaciones y bloques estructurales mantienen la estructura fuente. Cada traducción se guarda como variant, así que retraducir no sobrescribe resultados previos.

Las traducciones validadas entran como `pending` en la translation memory. Solo las entradas `approved` con reuse habilitado se reutilizan en otros papers.

## Preguntas y notas

Reader permite preguntar sobre todo el artículo o sobre el bloque seleccionado. Bilin recupera evidencia desde índices locales, transmite la respuesta y guarda referencias a bloques citados. Si el model profile declara native search, puede habilitarse búsqueda externa; de lo contrario, la respuesta se limita al contexto del artículo.

Las lecture notes se construyen desde patches editables. Hay plantillas para lectura profunda, reunión de grupo, lectura rápida y reproducción. Las notas aceptadas se materializan en `lecture-notes.md` dentro del article bundle.

## CLI

El comando CLI es `bilin` y se ejecuta con `uv run` desde `apps/api`.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

Si conoces el article revision id, puedes parsear, generar embeddings o exportar directamente. Los Markdown exportados y lecture notes generadas incluyen automáticamente una marca de agua invisible como comentario HTML. Indica que Bilin generó el archivo, que puede contener contenido de terceros o material derivado, y que la redistribución depende de la licencia original o del permiso del titular de derechos.

```sh
uv run bilin parse article /tmp/bilin-library <article_revision_id>
uv run bilin embed article /tmp/bilin-library <article_revision_id>
uv run bilin export article /tmp/bilin-library <article_revision_id> --kind bilingual_markdown --target-language zh-CN
```

## Datos locales y sincronización

Bilin guarda app-level SQLite state, libraries registradas, provider metadata, jobs, settings, note templates, translation memory y fallback storage de API keys en un directorio global elegido por `platformdirs`. En desarrollo puedes usar `BILIN_HOME`.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Las libraries son carpetas autocontenidas elegidas por el usuario. Funcionan bien con herramientas externas como iCloud, OneDrive o Syncthing. Bilin no resuelve conflictos de sincronización.

## Checks para desarrolladores

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

## Licencia

El código fuente de Bilin, la documentación propia del proyecto, los tests y los fixtures propios están bajo Apache-2.0. Consulta `LICENSE` y `NOTICE`. Esta licencia cubre solo Bilin. No concede derechos sobre papers, PDFs, paquetes TeX, figuras, tablas, captions, datasets, traducciones automáticas o lecture notes con contenido de terceros importados por usuarios.

## Solución de problemas

Si la API no responde, confirma que `make api` está corriendo y que `http://127.0.0.1:8000/health` devuelve JSON. Si TeX parsing falla con `missing_dependency:latexml`, instala LaTeXML y confirma que `bilin doctor` detecta `latexml` y `latexmlpost`.
