from __future__ import annotations

import io
import json
import tarfile
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

from bilin_api.article_store import (
    bundle_path_for_arxiv,
    read_article_document,
    sha256_text,
    upsert_arxiv_revision,
)
from bilin_api.latexml_parser import (
    build_parser_profile,
    find_main_tex,
    normalize_latexml_html,
    parse_article_revision,
    render_source_markdown,
)
from bilin_api.schemas import AssetRecord, DocumentBlock, Library, LibraryStatus


class GoldenRegressionFailure(AssertionError):
    def __init__(self, fixture_path: Path, failures: list[str]) -> None:
        self.fixture_path = fixture_path
        self.failures = failures
        super().__init__("\n".join(failures))


class GoldenRegressionResult(BaseModel):
    fixture: str
    fixture_path: str
    block_count: int
    asset_count: int
    block_types: list[str]
    block_uids: list[str]
    source_markdown_sha256: str
    summary: dict[str, Any] = Field(default_factory=dict)


class LatexCorpusResult(BaseModel):
    fixture: str
    fixture_path: str
    live_latexml: bool
    skipped_reason: str | None = None
    profile: dict[str, Any] = Field(default_factory=dict)
    summary: dict[str, Any] = Field(default_factory=dict)


def default_golden_fixture_path() -> Path:
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "fixtures" / "golden" / "minimal-paper"
        if candidate.exists():
            return candidate
    return Path("fixtures/golden/minimal-paper").resolve()


def default_latex_corpus_fixture_path() -> Path:
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "fixtures" / "latex-corpus" / "legacy-compatibility"
        if candidate.exists():
            return candidate
    return Path("fixtures/latex-corpus/legacy-compatibility").resolve()


def run_golden_fixture(fixture_path: Path | None = None) -> GoldenRegressionResult:
    fixture = (fixture_path or default_golden_fixture_path()).expanduser().resolve()
    expected = _load_expected(fixture)
    html_path = fixture / _string_value(expected.get("latexml_html"), "latexml.html")
    if not html_path.exists():
        msg = f"Missing LaTeXML HTML fixture: {html_path}"
        raise GoldenRegressionFailure(fixture, [msg])

    revision_id = _string_value(expected.get("revision_id"), "golden-revision")
    blocks, assets = normalize_latexml_html(html_path, revision_id)
    source_markdown = render_source_markdown(blocks)
    summary = stable_document_summary(blocks, assets, source_markdown)
    failures = _compare_expected(fixture, expected, summary, source_markdown)
    if failures:
        raise GoldenRegressionFailure(fixture, failures)
    return GoldenRegressionResult(
        fixture=fixture.name,
        fixture_path=str(fixture),
        block_count=len(blocks),
        asset_count=len(assets),
        block_types=[block.block_type for block in blocks],
        block_uids=[block.block_uid for block in blocks],
        source_markdown_sha256=str(summary["source_markdown_sha256"]),
        summary=summary,
    )


async def run_live_latexml_golden_fixture(
    fixture_path: Path | None = None,
) -> GoldenRegressionResult:
    fixture = (fixture_path or default_golden_fixture_path()).expanduser().resolve()
    expected = _load_expected(fixture)
    source_root = fixture / _string_value(expected.get("source_root"), "source")
    if not source_root.exists():
        msg = f"Missing golden source directory: {source_root}"
        raise GoldenRegressionFailure(fixture, [msg])

    with tempfile.TemporaryDirectory(prefix="bilin-golden-") as temp_dir:
        now = datetime.now(UTC)
        library = Library(
            id="golden-live-library",
            name="Golden Live",
            path=str(Path(temp_dir) / "library"),
            status=LibraryStatus.active,
            metadata={"golden_fixture": fixture.name},
            created_at=now,
            updated_at=now,
        )
        bundle_path = bundle_path_for_arxiv(library, "golden-minimal", "v1")
        original_dir = bundle_path / "original"
        original_dir.mkdir(parents=True, exist_ok=True)
        _write_source_tar(source_root, original_dir / "source.tar")
        _, revision = await upsert_arxiv_revision(
            library,
            bare_id="golden-minimal",
            version="v1",
            title=f"Golden fixture: {fixture.name}",
            bundle_path=bundle_path,
            metadata={"golden_fixture": fixture.name},
        )
        await parse_article_revision(library, revision.id)
        document = await read_article_document(library, revision.id)
        if document is None:
            msg = "Live LaTeXML golden parse did not produce a document."
            raise GoldenRegressionFailure(fixture, [msg])
        source_markdown_path = bundle_path / "document" / "source.md"
        source_markdown = source_markdown_path.read_text(encoding="utf-8")
        summary = stable_document_summary(document.blocks, document.assets, source_markdown)
        failures = _compare_expected(fixture, expected, summary, source_markdown)
        if failures:
            raise GoldenRegressionFailure(fixture, failures)
        return GoldenRegressionResult(
            fixture=fixture.name,
            fixture_path=str(fixture),
            block_count=len(document.blocks),
            asset_count=len(document.assets),
            block_types=[block.block_type for block in document.blocks],
            block_uids=[block.block_uid for block in document.blocks],
            source_markdown_sha256=str(summary["source_markdown_sha256"]),
            summary=summary,
        )


async def run_latex_corpus_fixture(
    fixture_path: Path | None = None,
    *,
    live_latexml: bool = False,
) -> LatexCorpusResult:
    fixture = (fixture_path or default_latex_corpus_fixture_path()).expanduser().resolve()
    expected = _load_expected(fixture)
    source_root = fixture / _string_value(expected.get("source_root"), "source")
    if not source_root.exists():
        msg = f"Missing LaTeX corpus source directory: {source_root}"
        raise GoldenRegressionFailure(fixture, [msg])
    main_tex = find_main_tex(source_root)
    profile = build_parser_profile(source_root, main_tex)
    if not live_latexml:
        return LatexCorpusResult(
            fixture=fixture.name,
            fixture_path=str(fixture),
            live_latexml=False,
            skipped_reason="live_latexml_not_requested",
            profile=profile.to_json(),
            summary={"profile_only": True},
        )

    with tempfile.TemporaryDirectory(prefix="bilin-latex-corpus-") as temp_dir:
        now = datetime.now(UTC)
        library = Library(
            id="latex-corpus-library",
            name="LaTeX Corpus",
            path=str(Path(temp_dir) / "library"),
            status=LibraryStatus.active,
            metadata={"latex_corpus_fixture": fixture.name},
            created_at=now,
            updated_at=now,
        )
        bare_id = _string_value(expected.get("arxiv_id"), f"corpus-{fixture.name}")
        version = _string_value(expected.get("version"), "v1")
        bundle_path = bundle_path_for_arxiv(library, bare_id, version)
        original_dir = bundle_path / "original"
        original_dir.mkdir(parents=True, exist_ok=True)
        _write_source_tar(source_root, original_dir / "source.tar")
        _, revision = await upsert_arxiv_revision(
            library,
            bare_id=bare_id,
            version=version,
            title=f"LaTeX corpus fixture: {fixture.name}",
            bundle_path=bundle_path,
            metadata={"latex_corpus_fixture": fixture.name},
        )
        await parse_article_revision(library, revision.id)
        document = await read_article_document(library, revision.id)
        if document is None:
            msg = "Live LaTeX corpus parse did not produce a document."
            raise GoldenRegressionFailure(fixture, [msg])
        source_markdown = (bundle_path / "document" / "source.md").read_text(encoding="utf-8")
        summary = stable_document_summary(document.blocks, document.assets, source_markdown)
        failures = _compare_latex_corpus_expected(expected, summary)
        if failures:
            raise GoldenRegressionFailure(fixture, failures)
        return LatexCorpusResult(
            fixture=fixture.name,
            fixture_path=str(fixture),
            live_latexml=True,
            profile=profile.to_json(),
            summary=latex_corpus_summary(summary),
        )


def stable_document_summary(
    blocks: list[DocumentBlock],
    assets: list[AssetRecord],
    source_markdown: str,
) -> dict[str, Any]:
    return {
        "block_count": len(blocks),
        "asset_count": len(assets),
        "block_types": [block.block_type for block in blocks],
        "block_uids": [block.block_uid for block in blocks],
        "duplicate_block_uids": duplicate_values([block.block_uid for block in blocks]),
        "source_markdown_sha256": sha256_text(source_markdown),
        "blocks": [
            {
                "block_uid": block.block_uid,
                "structural_path": block.structural_path,
                "block_type": block.block_type,
                "content_hash": block.content_hash,
                "source_markdown": block.source_markdown,
                "label": block.metadata.get("label"),
                "asset_id": block.metadata.get("asset_id"),
            }
            for block in blocks
        ],
        "assets": [
            {
                "asset_id": asset.asset_id,
                "kind": asset.kind,
                "caption": asset.caption,
                "label": asset.label,
                "source_path": asset.source_path,
                "web_path": asset.web_path,
            }
            for asset in assets
        ],
    }


def latex_corpus_summary(summary: dict[str, Any]) -> dict[str, Any]:
    block_types = [str(value) for value in summary.get("block_types", [])]
    assets = _summary_list(summary, "assets")
    return {
        "block_count": summary["block_count"],
        "asset_count": summary["asset_count"],
        "section_count": block_types.count("section"),
        "equation_count": block_types.count("equation"),
        "figure_count": block_types.count("figure"),
        "table_count": block_types.count("table"),
        "captions": [asset.get("caption") for asset in assets if asset.get("caption")],
    }


def _compare_latex_corpus_expected(
    expected: dict[str, Any],
    summary: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    corpus_summary = latex_corpus_summary(summary)
    minimums = expected.get("minimum_summary")
    if isinstance(minimums, dict):
        for key, minimum in minimums.items():
            actual = corpus_summary.get(str(key))
            if isinstance(minimum, int) and isinstance(actual, int) and actual < minimum:
                failures.append(f"{key}: expected at least {minimum!r}, got {actual!r}")
    required_caption_fragments = expected.get("required_caption_fragments")
    if isinstance(required_caption_fragments, list):
        caption_text = "\n".join(str(caption) for caption in corpus_summary["captions"])
        for fragment in required_caption_fragments:
            if isinstance(fragment, str) and fragment not in caption_text:
                failures.append(f"caption fragment not found: {fragment!r}")
    return failures


def _load_expected(fixture: Path) -> dict[str, Any]:
    expected_path = fixture / "expected.json"
    if not expected_path.exists():
        msg = f"Missing expected.json in golden fixture: {fixture}"
        raise GoldenRegressionFailure(fixture, [msg])
    payload = json.loads(expected_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        msg = f"expected.json must contain an object: {expected_path}"
        raise GoldenRegressionFailure(fixture, [msg])
    return payload


def _write_source_tar(source_root: Path, output_path: Path) -> None:
    files = sorted(path for path in source_root.rglob("*") if path.is_file())
    if not files:
        msg = f"Golden source directory contains no files: {source_root}"
        raise GoldenRegressionFailure(source_root, [msg])
    with tarfile.open(output_path, mode="w") as archive:
        for path in files:
            content = path.read_bytes()
            relative_name = path.relative_to(source_root).as_posix()
            info = tarfile.TarInfo(relative_name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))


def _compare_expected(
    fixture: Path,
    expected: dict[str, Any],
    summary: dict[str, Any],
    source_markdown: str,
) -> list[str]:
    failures: list[str] = []
    _compare_value(failures, "block_count", expected.get("block_count"), summary["block_count"])
    _compare_value(failures, "asset_count", expected.get("asset_count"), summary["asset_count"])
    _compare_list(failures, "block_types", expected.get("block_types"), summary["block_types"])
    _compare_list(failures, "block_uids", expected.get("block_uids"), summary["block_uids"])
    _compare_mapping(
        failures,
        "labels_by_block_uid",
        expected.get("labels_by_block_uid"),
        {
            str(block["block_uid"]): block["label"]
            for block in _summary_list(summary, "blocks")
            if block.get("label") is not None
        },
    )
    _compare_mapping(
        failures,
        "asset_captions_by_asset_id",
        expected.get("asset_captions_by_asset_id"),
        {str(asset["asset_id"]): asset["caption"] for asset in _summary_list(summary, "assets")},
    )
    _compare_no_duplicates(failures, "block_uids", summary["duplicate_block_uids"])
    _compare_source_markdown(failures, fixture, expected, source_markdown)
    return failures


def _compare_value(
    failures: list[str],
    name: str,
    expected: object,
    actual: object,
) -> None:
    if expected is not None and expected != actual:
        failures.append(f"{name}: expected {expected!r}, got {actual!r}")


def _compare_list(
    failures: list[str],
    name: str,
    expected: object,
    actual: object,
) -> None:
    if expected is not None and expected != actual:
        failures.append(f"{name}: expected {expected!r}, got {actual!r}")


def _compare_mapping(
    failures: list[str],
    name: str,
    expected: object,
    actual: dict[str, object],
) -> None:
    if expected is not None and expected != actual:
        failures.append(f"{name}: expected {expected!r}, got {actual!r}")


def _compare_no_duplicates(failures: list[str], name: str, duplicates: object) -> None:
    if isinstance(duplicates, list) and duplicates:
        failures.append(f"{name}: duplicate values are not allowed: {duplicates!r}")


def duplicate_values(values: list[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return sorted(duplicates)


def _compare_source_markdown(
    failures: list[str],
    fixture: Path,
    expected: dict[str, Any],
    source_markdown: str,
) -> None:
    expected_source_name = expected.get("expected_source_markdown")
    if expected_source_name is None:
        return
    expected_source_path = fixture / _string_value(expected_source_name, "")
    if not expected_source_path.exists():
        failures.append(f"expected_source_markdown file is missing: {expected_source_path}")
        return
    expected_source = expected_source_path.read_text(encoding="utf-8")
    if expected_source != source_markdown:
        failures.append(
            f"source_markdown: rendered Markdown does not match {expected_source_path.name}"
        )


def _summary_list(summary: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = summary.get(key)
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def _string_value(value: object, fallback: str) -> str:
    return value if isinstance(value, str) else fallback
