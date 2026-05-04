from __future__ import annotations

import asyncio
from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from bilin_api.acceptance import run_golden_acceptance
from bilin_api.article_store import resolve_library
from bilin_api.branding import PRODUCT_NAME_EN
from bilin_api.doctor import build_doctor_report
from bilin_api.embedding_service import build_article_embeddings, queue_article_embedding
from bilin_api.export_service import export_article
from bilin_api.golden import (
    GoldenRegressionFailure,
    run_golden_fixture,
    run_live_latexml_golden_fixture,
)
from bilin_api.importer import import_arxiv, import_local_file
from bilin_api.latexml_parser import ParseFailure, parse_article_revision
from bilin_api.repositories import create_library, create_provider_profile, dev_info
from bilin_api.schemas import (
    ArticleExportKind,
    ArticleExportRequest,
    EmbedArticleRequest,
    ImportArxivRequest,
    ImportLocalKind,
    LibraryCreate,
    ProviderProfileCreate,
    ProviderProtocol,
    TranslationBatchRequest,
)
from bilin_api.translation_service import queue_article_translation
from bilin_api.worker import run_worker

app = typer.Typer(help=f"{PRODUCT_NAME_EN} local-first backend CLI.")
library_app = typer.Typer(help="Manage local libraries.")
jobs_app = typer.Typer(help="Run and inspect background jobs.")
import_app = typer.Typer(help="Import external paper sources.")
parse_app = typer.Typer(help="Parse imported article revisions.")
provider_app = typer.Typer(help="Manage LLM provider profiles.")
translate_app = typer.Typer(help="Queue translation jobs.")
export_app = typer.Typer(help="Export article artifacts.")
embed_app = typer.Typer(help="Build local article embeddings.")
golden_app = typer.Typer(help="Run golden parser regressions.")
acceptance_app = typer.Typer(help="Run end-to-end MVP acceptance flows.")
app.add_typer(library_app, name="library")
app.add_typer(jobs_app, name="jobs")
app.add_typer(import_app, name="import")
app.add_typer(parse_app, name="parse")
app.add_typer(provider_app, name="provider")
app.add_typer(translate_app, name="translate")
app.add_typer(export_app, name="export")
app.add_typer(embed_app, name="embed")
app.add_typer(golden_app, name="golden")
app.add_typer(acceptance_app, name="acceptance")
console = Console()
PROVIDER_PROTOCOL_OPTION = typer.Option(ProviderProtocol.openai_compatible, "--protocol")
EXPORT_KIND_OPTION = typer.Option(ArticleExportKind.bilingual_markdown, "--kind")
ACCEPTANCE_OUTPUT_DIR_OPTION = typer.Option(..., "--output-dir", "-o")
TARGET_LANGUAGE_OPTION = typer.Option("zh-CN", "--target-language")
GOLDEN_FIXTURE_ARGUMENT = typer.Argument(
    None,
    help="Golden fixture directory. Defaults to fixtures/golden/minimal-paper.",
)
IMPORT_LOCAL_KIND_OPTION = typer.Option(None, "--kind")
GOLDEN_LIVE_LATEXML_OPTION = typer.Option(
    False,
    "--live-latexml",
    help="Run the fixture source through the local LaTeXML parser before checking expectations.",
)


@app.command()
def doctor() -> None:
    """Check local document tool capabilities."""
    report = build_doctor_report()
    table = Table(title=f"{PRODUCT_NAME_EN} doctor ({report.bilin_home})")
    table.add_column("Tool")
    table.add_column("Status")
    table.add_column("Level")
    table.add_column("Path")
    table.add_column("Message")
    for capability in report.capabilities:
        table.add_row(
            capability.tool_name,
            capability.status.value,
            capability.level.value,
            capability.path or "-",
            capability.message,
        )
    console.print(table)


@app.command("dev-info")
def dev_info_command() -> None:
    """Print local development paths."""
    for key, value in dev_info().items():
        console.print(f"{key}: {value}")


@library_app.command("create")
def library_create(path: Path, name: str = typer.Option(..., "--name", "-n")) -> None:
    """Create a local library directory and register it globally."""
    library = asyncio.run(create_library(LibraryCreate(name=name, path=str(path))))
    console.print(f"Created library {library.name} at {library.path}")


@jobs_app.command("run-worker")
def jobs_run_worker() -> None:
    """Run the local background worker."""
    asyncio.run(run_worker())


@provider_app.command("create")
def provider_create_command(
    name: str = typer.Option(..., "--name", "-n"),
    protocol: ProviderProtocol = PROVIDER_PROTOCOL_OPTION,
    api_key: str | None = typer.Option(None, "--api-key"),
    model: str | None = typer.Option(None, "--model"),
    base_url: str | None = typer.Option(None, "--base-url"),
    max_concurrent_requests: int = typer.Option(1, "--max-concurrent-requests", min=1, max=32),
    requests_per_minute: int | None = typer.Option(None, "--requests-per-minute", min=1, max=6000),
) -> None:
    """Create an OpenAI-compatible or Anthropic-compatible provider profile."""

    async def _run() -> None:
        provider = await create_provider_profile(
            ProviderProfileCreate(
                name=name,
                protocol=protocol,
                api_key=api_key,
                default_model=model,
                base_url=base_url,
                max_concurrent_requests=max_concurrent_requests,
                requests_per_minute=requests_per_minute,
            )
        )
        console.print(provider.model_dump_json(indent=2))

    asyncio.run(_run())


@import_app.command("arxiv")
def import_arxiv_command(
    library_id_or_path: str,
    arxiv_id: str,
    version: str | None = typer.Option(None, "--version"),
    download_pdf: bool = typer.Option(True, "--pdf/--no-pdf"),
    parse_after_import: bool = typer.Option(True, "--parse/--no-parse"),
) -> None:
    """Import an arXiv source package into a local library."""

    async def _run() -> None:
        library = await resolve_library(library_id_or_path)
        result = await import_arxiv(
            library,
            ImportArxivRequest(
                arxiv_id=arxiv_id,
                version=version,
                download_pdf=download_pdf,
                parse_after_import=parse_after_import,
            ),
        )
        console.print(result.model_dump_json(indent=2))

    asyncio.run(_run())


@import_app.command("file")
def import_file_command(
    library_id_or_path: str,
    path: Path,
    kind: ImportLocalKind | None = IMPORT_LOCAL_KIND_OPTION,
    parse_after_import: bool = typer.Option(True, "--parse/--no-parse"),
) -> None:
    """Import a local TeX archive, Markdown file, or save-only PDF."""

    async def _run() -> None:
        library = await resolve_library(library_id_or_path)
        selected_kind = kind or infer_local_import_kind(path)
        result = await import_local_file(
            library,
            file_name=path.name,
            content=path.read_bytes(),
            kind=selected_kind,
            parse_after_import=parse_after_import,
        )
        console.print(result.model_dump_json(indent=2))

    asyncio.run(_run())


@translate_app.command("article")
def translate_article_command(
    library_id_or_path: str,
    article_revision_id: str,
    provider_id: str = typer.Option(..., "--provider"),
    target_language: str = TARGET_LANGUAGE_OPTION,
    model: str | None = typer.Option(None, "--model"),
    force: bool = typer.Option(False, "--force"),
) -> None:
    """Queue block translation jobs for an article revision."""

    async def _run() -> None:
        library = await resolve_library(library_id_or_path)
        result = await queue_article_translation(
            library,
            article_revision_id,
            TranslationBatchRequest(
                target_language=target_language,
                provider_profile_id=provider_id,
                model=model,
                force=force,
            ),
        )
        console.print(result.model_dump_json(indent=2))

    asyncio.run(_run())


@parse_app.command("article")
def parse_article_command(library_id_or_path: str, article_revision_id: str) -> None:
    """Parse an imported article revision with LaTeXML."""

    async def _run() -> None:
        library = await resolve_library(library_id_or_path)
        try:
            result = await parse_article_revision(library, article_revision_id)
        except ParseFailure as exc:
            console.print(f"[red]{exc.code}[/red]: {exc.message}")
            install_hint = exc.details.get("install_hint")
            doctor_command = exc.details.get("doctor_command")
            if isinstance(install_hint, str):
                console.print(install_hint)
            if isinstance(doctor_command, str):
                console.print(f"Run `{doctor_command}` to inspect local parser tools.")
            raise typer.Exit(code=1) from exc
        console.print_json(data=result)

    asyncio.run(_run())


@export_app.command("article")
def export_article_command(
    library_id_or_path: str,
    article_revision_id: str,
    kind: ArticleExportKind = EXPORT_KIND_OPTION,
    target_language: str = TARGET_LANGUAGE_OPTION,
    include_untranslated: bool = typer.Option(True, "--include-untranslated/--skip-untranslated"),
) -> None:
    """Export readable Markdown artifacts or a bundle zip for an article revision."""

    async def _run() -> None:
        library = await resolve_library(library_id_or_path)
        result = await export_article(
            library,
            article_revision_id,
            ArticleExportRequest(
                kind=kind,
                target_language=target_language,
                include_untranslated=include_untranslated,
            ),
        )
        console.print_json(data=result.model_dump(mode="json"))

    asyncio.run(_run())


@embed_app.command("article")
def embed_article_command(
    library_id_or_path: str,
    article_revision_id: str,
    provider: str = typer.Option("local-hash", "--provider"),
    model: str = typer.Option("hashing-64-v1", "--model"),
    force: bool = typer.Option(False, "--force"),
    background: bool = typer.Option(False, "--background"),
) -> None:
    """Build deterministic local embeddings for article blocks."""

    async def _run() -> None:
        library = await resolve_library(library_id_or_path)
        request = EmbedArticleRequest(provider=provider, model=model, force=force)
        if background:
            job = await queue_article_embedding(library, article_revision_id, request)
            console.print_json(data=job.model_dump(mode="json"))
            return
        result = await build_article_embeddings(library, article_revision_id, request)
        console.print_json(data=result.model_dump(mode="json"))

    asyncio.run(_run())


@golden_app.command("run")
def golden_run_command(
    fixture_path: Path | None = GOLDEN_FIXTURE_ARGUMENT,
    live_latexml: bool = GOLDEN_LIVE_LATEXML_OPTION,
) -> None:
    """Run deterministic parser assertions for a golden fixture."""
    try:
        if live_latexml:
            result = asyncio.run(run_live_latexml_golden_fixture(fixture_path))
        else:
            result = run_golden_fixture(fixture_path)
    except GoldenRegressionFailure as exc:
        console.print(f"[red]Golden regression failed:[/red] {exc.fixture_path}")
        for failure in exc.failures:
            console.print(f"- {failure}")
        raise typer.Exit(code=1) from exc
    console.print_json(data=result.model_dump(mode="json"))


@acceptance_app.command("golden")
def acceptance_golden_command(
    fixture_path: Path | None = GOLDEN_FIXTURE_ARGUMENT,
    output_dir: Path = ACCEPTANCE_OUTPUT_DIR_OPTION,
    live_latexml: bool = GOLDEN_LIVE_LATEXML_OPTION,
    target_language: str = TARGET_LANGUAGE_OPTION,
) -> None:
    """Create a disposable library from a golden fixture and export MVP artifacts."""
    try:
        result = asyncio.run(
            run_golden_acceptance(
                output_dir,
                fixture_path,
                live_latexml=live_latexml,
                target_language=target_language,
            )
        )
    except (GoldenRegressionFailure, ParseFailure, ValueError) as exc:
        console.print(f"[red]Acceptance failed:[/red] {exc}")
        raise typer.Exit(code=1) from exc
    console.print_json(data=result.model_dump(mode="json"))


def infer_local_import_kind(path: Path) -> ImportLocalKind:
    name = path.name.lower()
    if name.endswith((".zip", ".tar", ".tar.gz", ".tgz", ".gz")):
        return ImportLocalKind.tex_archive
    if name.endswith((".md", ".markdown")):
        return ImportLocalKind.markdown
    if name.endswith(".pdf"):
        return ImportLocalKind.pdf
    msg = "Could not infer import kind. Use --kind tex_archive, markdown, or pdf."
    raise typer.BadParameter(msg)


if __name__ == "__main__":
    app()
