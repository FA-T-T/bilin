<h1 align="center">
  Ilios (lectura de papers asistida por LLM)<br>
  <sub><sub>衔牍 · 理紐</sub></sub>
</h1>

<p align="center">
  <em>Una herramienta multilingue para leer papers</em>
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

## Que es Ilios

Ilios es un espacio de lectura de papers **local-first y estructurado** para investigadores que necesitan entender papers en ingles a traves de varios idiomas.

Funciona de forma local y admite paquetes de codigo fuente de arXiv o archivos LaTeX locales.

Los papers, resultados de analisis, cache de traduccion, historiales de preguntas y notas se guardan en una carpeta local que eliges. **No requiere cuenta, no usa backend alojado y no sube archivos.**

El costo de traduccion es bajo. En una prueba, DeepSeek V4 Flash proceso 10 papers, 240 paginas en total, por aproximadamente 2 CNY.

## Funciones principales

##### **Multilingue**

El texto, las figuras y las formulas del paper que aparecen en las capturas pertenecen a sus autores o titulares de derechos. Aqui se usan solo para mostrar las funciones locales de lectura, traduccion, preguntas y renderizado estructurado de Ilios.

Ejemplo en chino:

<img src="./assets/image-20260522193937577.png" alt="Chinese translation example" style="zoom: 25%;" />

Ejemplo en frances:

<img src="./assets/image-20260522194355907.png" alt="French translation example" style="zoom:25%;" />

Ejemplo en japones:

<img src="./assets/image-20260522193846703.png" alt="Japanese translation example" style="zoom:25%;" />

Ejemplo en aleman:

<img src="./assets/image-20260522194717793.png" alt="German translation example" style="zoom:25%;" />

Ejemplo en coreano:

<img src="./assets/image-20260522194157385.png" alt="Korean translation example" style="zoom:25%;" />

##### Figuras

<img src="./assets/image-20260522194901555.png" alt="Figure rendering example" style="zoom: 25%;" />

##### Formulas

Renderizado con KaTeX.

<img src="./assets/image-20260522195038561.png" alt="Formula rendering example" style="zoom:25%;" />

##### Tablas

Renderizado como tablas HTML.

<img src="./assets/image-20260522195134674.png" alt="Table rendering example" style="zoom:25%;" />

##### Resaltado de frases al pasar el cursor

La segmentacion por frases facilita la comparacion bilingue.

![Sentence hover highlighting](./assets/image-20260522195506879.png)

##### Vista previa de citas

Las citas se analizan automaticamente. Ilios admite busqueda en Google Scholar y arXiv, importacion a la biblioteca con un clic y traduccion automatica.

<img src="./assets/image-20260522202145628.png" alt="Citation preview example" style="zoom: 33%;" />

##### Exportacion Markdown del original o la traduccion

Exporta el texto original o traducido como Markdown y usalo directamente como documento de base de conocimiento.

<img src="./assets/image-20260522202353196.png" alt="Markdown export example" style="zoom:25%;" />

##### Modo Kindle

El modo Kindle permite que los dispositivos e-ink de la red local lean desde el navegador con menor consumo de recursos. Elimina el desplazamiento y anade botones de cambio de pagina a la izquierda y a la derecha.

Se recomienda un dispositivo e-ink de 10 pulgadas o mas en orientacion horizontal.

![Kindle mode example](./assets/image-20260522202534656.png)

## Inicio rapido

### Usuarios de agentes (Codex, Claude, DeepSeek-TUI, OpenCode...)

Envia el enlace de esta pagina directamente a un agente y dile:

"https://github.com/FA-T-T/bilin Please help me deploy this service, install the required dependencies, and start the app."

El agente puede instalar dependencias, desplegar el proyecto e iniciar la aplicacion.

### Usuarios regulares

Ilios necesita Node.js, pnpm, Python 3.13 y uv. La aplicacion principal puede iniciarse sin una cadena TeX, pero el analisis real de LaTeX requiere `latexml` y `latexmlpost` en `PATH`. Se recomiendan ImageMagick `magick`, Ghostscript `gs` y `tectonic` o `pdflatex` para imagenes y PDF.

Preparacion en macOS + Homebrew:

```sh
brew install node pnpm uv latexml tectonic imagemagick ghostscript poppler
```

Iniciar desde codigo fuente:

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

En un entorno de desarrollo fijo, puedes usar el script de inicio rapido. Reutiliza virtual environments y `node_modules`, omite la deteccion del entorno y devuelve el estado si el stack ya esta ejecutandose.

```sh
./scripts/start-dev.sh
```

Despues del inicio, abre `http://127.0.0.1:5173`. La API usa por defecto `127.0.0.1:8000`, y el worker procesa importacion, analisis, traduccion, preguntas, notas y exportaciones. Tambien puedes ejecutar `make api`, `make worker` y `make web` por separado para depurar.

Sin LaTeXML, Ilios aun inicia y admite importacion Markdown, almacenamiento de PDF, configuracion de modelos, traduccion, notas, exportacion y pruebas con fixtures. Los trabajos de TeX fallan explicitamente con `missing_dependency:latexml` en vez de caer en un analisis regex inestable.

## Primer paper

Crea una library en la pagina inicial con un nombre y una ruta local. Una library es una carpeta autocontenida con `library.sqlite`, archivos fuente originales, PDF, TeX desempaquetado, `document.json` analizado, `source.md`, assets, logs, notas, exportaciones y manifests.

Dentro de la library, introduce un arXiv ID como `1706.03762`. Ilios descarga el source package y el PDF, crea un paquete de articulo autocontenido y encola tareas si el analisis esta activado. Los archivos TeX locales reutilizan la misma ruta de paquete. Markdown se importa de inmediato como documento con estructura debil, y los PDF se guardan como archivos fuente.

Cuando termina el analisis, selecciona el paper en la biblioteca y pulsa Read. El lector admite Study, Bilingual, Translation y Source. La barra izquierda cambia entre papers de la misma library. La barra derecha ofrece tareas, modelos, chat con el paper, traduccion, glosario, notas y exportacion. Al pasar el cursor por un parrafo puedes copiarlo, ver el source, retraducirlo o preguntar sobre ese parrafo. Las figuras y tablas se muestran directamente si hay assets; si faltan, se conservan captions y labels con placeholders estructurados.

## Configuracion de modelos

Abre Settings -> Models. En modo simple, pega una API key e Ilios obtiene la lista de modelos desde un endpoint compatible. El modo avanzado permite configurar profile label, base URL, concurrencia y limite de solicitudes por minuto. **Se recomienda usar el modo avanzado.**

Las provider keys no se guardan dentro de las carpetas library. En macOS se guardan por defecto en Keychain y la base global solo conserva una referencia `keychain:`. En otras plataformas, o con `BILIN_CREDENTIAL_STORE=app_settings`, se usa el fallback de desarrollo en SQLite. Para impedir la creacion de providers cuando Keychain no este disponible, define:

```sh
export BILIN_CREDENTIAL_STORE=keychain
```

## CLI

La CLI reutiliza la misma logica backend que la aplicacion web.

```sh
cd apps/api
uv run bilin library create /tmp/bilin-library --name Papers
uv run bilin import arxiv /tmp/bilin-library 1706.03762 --pdf --parse
uv run bilin jobs run-worker
```

El repositorio incluye golden fixtures para validar el pipeline del lector sin red ni cadena TeX completa.

```sh
cd apps/api
uv run bilin acceptance golden ../../fixtures/golden/minimal-paper --output-dir /tmp/bilin-acceptance
```

El comando devuelve `reader_route` y `library_id`. Inicia la aplicacion y abre la ruta en el navegador para revisar el articulo generado.

## Datos locales, seguridad y sincronizacion

Ilios usa un directorio global de datos de aplicacion para el estado SQLite, libraries registradas, configuracion de providers, trabajos, settings, note templates, translation memory y almacenamiento fallback de API keys cuando Keychain no esta disponible o esta desactivado. El directorio lo determina `platformdirs` y puede cambiarse en desarrollo con `BILIN_HOME`.

```sh
export BILIN_HOME=/tmp/bilin-home
cd apps/api
uv run bilin dev-info
```

Las carpetas library las elige el usuario y son autocontenidas, por lo que funcionan bien con herramientas externas como iCloud, OneDrive o Syncthing. Ilios no resuelve conflictos de sincronizacion. Cierra la aplicacion antes de sincronizar y recupera conflictos desde el historial de versiones de la herramienta de sync.

Los Markdown y apuntes exportados incluyen automaticamente una marca de agua invisible en comentario HTML. Indica que el archivo fue generado por Ilios y puede contener contenido de terceros. La marca no afecta la lectura normal.

## Desarrolladores

Ejecuta las comprobaciones backend desde `apps/api`.

```sh
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run pytest
```

Ejecuta las comprobaciones frontend desde la raiz del repositorio.

```sh
pnpm --filter @bilin/web lint
pnpm --filter @bilin/web typecheck
pnpm --filter @bilin/web test:run
pnpm --filter @bilin/web format:check
pnpm --filter @bilin/web build
pnpm --filter @bilin/web test:e2e
```

Las pruebas por defecto usan fixtures y mocks. No requieren red real ni una cadena TeX completa. Las pruebas reales de arXiv y LaTeXML son opt-in explicito.

## Licencia

El codigo fuente de Ilios, la documentacion propia del proyecto, las pruebas y los fixtures propios usan la licencia Apache-2.0. Consulta [LICENSE](LICENSE) y [NOTICE](NOTICE). Esta licencia cubre solo el proyecto Ilios, no los papers, PDF, paquetes TeX, figuras, captions, datasets, traducciones automaticas ni apuntes con material de terceros importados por el usuario. La redistribucion de exportaciones debe respetar la licencia del paper o asset original, el permiso del titular de derechos o las excepciones legales aplicables.

<p align="center">
  <br>
  <strong>衔牍</strong><br>
  Tomar luz prestada y traer el texto al escritorio.<br><br>
  <strong>理紐</strong><br>
  Quien ata el hilo del razonamiento y conecta tu pensamiento con el del autor.<br><br>
  <em>Si Ilios te ayuda a dormir antes despues de leer un paper, dale una Star para que mas investigadores nuevos lo encuentren.</em>
</p>
