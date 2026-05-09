from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import time
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ArxivSample:
    arxiv_id: str
    label: str


SAMPLES: tuple[ArxivSample, ...] = (
    ArxivSample("1706.03762", "Transformer / NLP conference template"),
    ArxivSample("1512.03385", "ResNet / CVPR-style template"),
    ArxivSample("1810.04805", "BERT / ACL-style template"),
    ArxivSample("1502.03167", "BatchNorm / compact ML template"),
    ArxivSample("1207.0580", "Dropout / older ML template"),
    ArxivSample("2006.11239", "Diffusion models / ML template"),
    ArxivSample("2103.00020", "CLIP / multimodal ML template"),
    ArxivSample("1606.00915", "DeepLab / dense CV template"),
    ArxivSample("quant-ph/9705052", "Quantum error correction / older arXiv id"),
    ArxivSample("2205.14135", "FlashAttention / algorithm-heavy ML template"),
)


RAW_ARTIFACT_PATTERNS = (
    re.compile(r"\\(?:toprule|midrule|bottomrule|cmidrule)\b"),
    re.compile(r"\\cite[a-zA-Z*]*\b"),
    re.compile(r"ltx_ERROR", re.IGNORECASE),
    re.compile(r"\\begin\{(?:itemize|enumerate|algorithm|tabular)\}"),
)
UNLINKED_URL_RE = re.compile(r"https?://[^\s<>)\]]+")
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(https?://[^)\s]+\)")


async def main() -> int:
    args = parse_args()
    run_dir = args.run_dir.expanduser().resolve()
    home_dir = run_dir / "home"
    library_dir = run_dir / "library"
    os.environ["BILIN_HOME"] = str(home_dir)

    from bilin_api.article_store import list_assets, list_blocks
    from bilin_api.importer import import_arxiv
    from bilin_api.latexml_parser import ParseFailure, parse_article_revision
    from bilin_api.repositories import create_library
    from bilin_api.schemas import ImportArxivRequest, LibraryCreate

    run_dir.mkdir(parents=True, exist_ok=True)
    library = await create_library(LibraryCreate(name="Ilios stability run", path=str(library_dir)))
    samples = SAMPLES[: args.limit]
    report: dict[str, Any] = {
        "created_at": datetime.now(UTC).isoformat(),
        "bilin_home": str(home_dir),
        "library_id": library.id,
        "library_path": library.path,
        "samples": [],
    }

    for index, sample in enumerate(samples, start=1):
        started = time.monotonic()
        print(f"[{index}/{len(samples)}] importing {sample.arxiv_id} - {sample.label}", flush=True)
        sample_report: dict[str, Any] = {
            "arxiv_id": sample.arxiv_id,
            "label": sample.label,
            "status": "started",
            "warnings": [],
        }
        try:
            imported = await import_arxiv(
                library,
                ImportArxivRequest(
                    arxiv_id=sample.arxiv_id,
                    download_pdf=False,
                    parse_after_import=False,
                ),
            )
            sample_report["revision_id"] = imported.article_revision_id
            sample_report["bundle_path"] = imported.bundle_path
            print(f"[{index}/{len(samples)}] parsing {sample.arxiv_id}", flush=True)
            result = await parse_article_revision(library, imported.article_revision_id)
            blocks = await list_blocks(library, imported.article_revision_id)
            assets = await list_assets(library, imported.article_revision_id)
            sample_report.update(
                {
                    "status": "parsed",
                    "result": result,
                    "block_counts": dict(Counter(block.block_type for block in blocks)),
                    "asset_counts": dict(Counter(asset.kind for asset in assets)),
                    "warnings": inspect_document(blocks, assets, Path(imported.bundle_path)),
                }
            )
        except ParseFailure as exc:
            sample_report.update(
                {
                    "status": "parse_failed",
                    "error": {
                        "code": exc.code,
                        "message": exc.message,
                        "details": exc.details,
                    },
                }
            )
        except Exception as exc:
            sample_report.update(
                {
                    "status": "failed",
                    "error": {"type": type(exc).__name__, "message": str(exc)},
                }
            )
        finally:
            sample_report["elapsed_seconds"] = round(time.monotonic() - started, 2)
            report["samples"].append(sample_report)
            warning_count = len(sample_report.get("warnings", []))
            print(
                f"[{index}/{len(samples)}] {sample.arxiv_id} -> "
                f"{sample_report['status']} with {warning_count} warnings",
                flush=True,
            )
            if index < len(samples) and args.delay > 0:
                await asyncio.sleep(args.delay)

    summary = Counter(sample["status"] for sample in report["samples"])
    report["summary"] = dict(summary)
    report["total_warnings"] = sum(len(sample.get("warnings", [])) for sample in report["samples"])
    report_path = run_dir / "report.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"report: {report_path}", flush=True)
    return 0 if summary.get("parsed", 0) == len(samples) else 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Import and parse a diverse arXiv sample set in an isolated local Bilin home. "
            "This does not run the worker, so it does not trigger translation or term jobs."
        )
    )
    parser.add_argument(
        "--run-dir",
        type=Path,
        default=Path("tmp/arxiv-stability") / datetime.now(UTC).strftime("%Y%m%d-%H%M%S"),
    )
    parser.add_argument("--limit", type=int, default=len(SAMPLES))
    parser.add_argument(
        "--delay",
        type=float,
        default=3.0,
        help="Seconds to wait between arXiv samples to avoid hammering the public API.",
    )
    return parser.parse_args()


def inspect_document(blocks: list[Any], assets: list[Any], bundle_path: Path) -> list[dict[str, Any]]:
    warnings: list[dict[str, Any]] = []
    block_counts = Counter(block.block_type for block in blocks)
    if block_counts.get("paragraph", 0) == 0:
        warnings.append({"kind": "missing_paragraphs", "message": "No paragraph blocks produced."})
    if block_counts.get("section", 0) == 0:
        warnings.append({"kind": "missing_sections", "message": "No section blocks produced."})

    html_text = read_text(bundle_path / "document" / "latexml.html")
    if "ltx_itemize" in html_text or "ltx_enumerate" in html_text:
        if block_counts.get("list", 0) == 0:
            warnings.append(
                {
                    "kind": "list_not_materialized",
                    "message": "LaTeXML HTML contains list classes but no list blocks.",
                }
            )
    if re.search(r"algorithm\s+\d+", html_text, flags=re.IGNORECASE):
        if block_counts.get("algorithm", 0) == 0:
            warnings.append(
                {
                    "kind": "algorithm_not_materialized",
                    "message": "HTML appears to contain an algorithm but no algorithm block.",
                }
            )

    for block in blocks:
        text = block.source_markdown
        for pattern in RAW_ARTIFACT_PATTERNS:
            if pattern.search(text):
                warnings.append(
                    {
                        "kind": "raw_latex_artifact",
                        "block_uid": block.block_uid,
                        "block_type": block.block_type,
                        "pattern": pattern.pattern,
                        "excerpt": excerpt(text),
                    }
                )
        protected_text = MARKDOWN_LINK_RE.sub("", text)
        for match in UNLINKED_URL_RE.finditer(protected_text):
            url = match.group(0).rstrip(".,;:")
            if url:
                warnings.append(
                    {
                        "kind": "unlinked_url",
                        "block_uid": block.block_uid,
                        "block_type": block.block_type,
                        "url": url,
                        "excerpt": excerpt(text),
                    }
                )
                break
        if block.block_type == "table":
            fragment = str(block.metadata.get("html_fragment") or "")
            if "<table" not in fragment.lower():
                warnings.append(
                    {
                        "kind": "table_without_table_html",
                        "block_uid": block.block_uid,
                        "excerpt": excerpt(text),
                    }
                )
            if re.search(r"\\(?:toprule|midrule|bottomrule|cmidrule)\b", fragment):
                warnings.append(
                    {
                        "kind": "booktabs_leaked_into_table_html",
                        "block_uid": block.block_uid,
                        "excerpt": excerpt(fragment),
                    }
                )

    for asset in assets:
        if asset.kind == "figure" and not asset.web_path:
            resolution = str(asset.metadata.get("asset_resolution") or "")
            fragment = str(asset.metadata.get("html_fragment") or "")
            has_renderable_fragment = bool(re.search(r"<(?:svg|table)\b", fragment, re.I))
            if (
                resolution not in {"requires_controlled_render", "missing_dependency"}
                and not has_renderable_fragment
            ):
                warnings.append(
                    {
                        "kind": "figure_without_web_asset",
                        "asset_id": asset.asset_id,
                        "resolution": resolution or None,
                        "caption": asset.caption,
                    }
                )
        if asset.kind == "table":
            fragment = str(asset.metadata.get("html_fragment") or "")
            if "<table" not in fragment.lower():
                warnings.append(
                    {
                        "kind": "table_asset_without_table_html",
                        "asset_id": asset.asset_id,
                        "caption": asset.caption,
                    }
                )
    return warnings


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def excerpt(value: str, limit: int = 220) -> str:
    normalized = " ".join(value.split())
    if len(normalized) <= limit:
        return normalized
    return normalized[: limit - 1] + "…"


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
