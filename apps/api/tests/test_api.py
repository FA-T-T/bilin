from __future__ import annotations

import io
import zipfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import bilin_api.api.providers as providers_api
from bilin_api.article_store import (
    empty_manifest,
    make_asset,
    make_block,
    replace_document,
    upsert_arxiv_revision,
)
from bilin_api.main import app
from bilin_api.repositories import create_library, record_translation_memory_entry
from bilin_api.schemas import (
    LibraryCreate,
    ProviderModelInfo,
    ProviderProtocol,
    TranslationMemoryReviewStatus,
)


def test_health_endpoint(bilin_home: Path) -> None:
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_library_and_jobs_api(bilin_home: Path, tmp_path: Path) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(tmp_path / "local-library")},
        )
        assert library_response.status_code == 201
        jobs_response = client.get("/jobs")
        summary_response = client.get("/jobs/summary")
    assert jobs_response.status_code == 200
    assert jobs_response.json() == []
    assert summary_response.status_code == 200
    assert summary_response.json()["total"] == 0


def test_jobs_api_can_clear_background_tasks(bilin_home: Path) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(Path(bilin_home) / "clear-jobs-library")},
        )
        library_id = library_response.json()["id"]
        create_response = client.post(
            f"/libraries/{library_id}/imports/arxiv",
            json={"arxiv_id": "2401.00001", "parse_after_import": False},
        )
        clear_response = client.delete("/jobs")
        jobs_response = client.get("/jobs")

    assert create_response.status_code == 201
    assert clear_response.status_code == 200
    assert clear_response.json()["cleared"] == 1
    assert jobs_response.json() == []


def test_library_archive_and_delete_api_manage_cache(bilin_home: Path, tmp_path: Path) -> None:
    library_path = tmp_path / "deletable-library"
    with TestClient(app) as client:
        create_response = client.post(
            "/libraries",
            json={"name": "Deletable", "path": str(library_path)},
        )
        library_id = create_response.json()["id"]
        archive_response = client.post(f"/libraries/{library_id}/archive")
        delete_response = client.delete(f"/libraries/{library_id}")
        missing_response = client.get(f"/libraries/{library_id}")

    assert create_response.status_code == 201
    assert archive_response.status_code == 200
    assert archive_response.json()["status"] == "archived"
    assert delete_response.status_code == 200
    assert delete_response.json()["deleted_cache"] is True
    assert not library_path.exists()
    assert missing_response.status_code == 404


def test_library_update_api_renames_library(bilin_home: Path, tmp_path: Path) -> None:
    with TestClient(app) as client:
        create_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(tmp_path / "local-library")},
        )
        library_id = create_response.json()["id"]
        update_response = client.put(f"/libraries/{library_id}", json={"name": "Reading List"})
        get_response = client.get(f"/libraries/{library_id}")

    assert create_response.status_code == 201
    assert update_response.status_code == 200
    assert update_response.json()["name"] == "Reading List"
    assert update_response.json()["path"] == str(tmp_path / "local-library")
    assert get_response.json()["name"] == "Reading List"


def test_arxiv_import_api_enqueues_background_job(bilin_home: Path, tmp_path: Path) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(tmp_path / "local-library")},
        )
        library_id = library_response.json()["id"]
        response = client.post(
            f"/libraries/{library_id}/imports/arxiv",
            json={"arxiv_id": "2401.00001", "parse_after_import": False},
        )

    assert response.status_code == 201
    payload = response.json()
    assert payload["type"] == "import_arxiv"
    assert payload["payload"]["library_id"] == library_id
    assert payload["payload"]["arxiv_id"] == "2401.00001"


def test_arxiv_import_api_rejects_ambiguous_old_style_bare_id(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Papers", "path": str(tmp_path / "library")},
        )
        response = client.post(
            f"/libraries/{library_response.json()['id']}/imports/arxiv",
            json={"arxiv_id": "9407022", "parse_after_import": False},
        )

    assert response.status_code == 400
    assert "archive prefix" in response.json()["detail"]
    assert "cond-mat/9407022" in response.json()["detail"]


def test_arxiv_import_api_normalizes_old_style_archive_alias(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Papers", "path": str(tmp_path / "library")},
        )
        response = client.post(
            f"/libraries/{library_response.json()['id']}/imports/arxiv",
            json={"arxiv_id": "condmat/9407022", "parse_after_import": False},
        )

    assert response.status_code == 201
    payload = response.json()
    assert payload["payload"]["arxiv_id"] == "cond-mat/9407022"


def test_local_markdown_import_api_writes_article(bilin_home: Path, tmp_path: Path) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(tmp_path / "local-library")},
        )
        library_id = library_response.json()["id"]
        response = client.post(
            f"/libraries/{library_id}/imports/file"
            "?kind=markdown&file_name=note.md&parse_after_import=true",
            content=b"# Uploaded\n\nA local markdown article.",
            headers={"Content-Type": "text/markdown"},
        )
        payload = response.json()
        articles_response = client.get(f"/libraries/{library_id}/articles")
        status_response = client.get(
            f"/libraries/{library_id}/articles/{payload['article_revision_id']}/embeddings/status"
        )

    assert response.status_code == 201
    assert payload["source_kind"] == "markdown"
    assert payload["parse_job_id"] is None
    assert articles_response.status_code == 200
    assert articles_response.json()[0]["block_count"] == 2
    assert status_response.status_code == 200
    assert status_response.json()["embedded_blocks"] == 2


def test_article_archive_and_delete_api_manage_cache(bilin_home: Path, tmp_path: Path) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(tmp_path / "local-library")},
        )
        library_id = library_response.json()["id"]
        import_response = client.post(
            f"/libraries/{library_id}/imports/file"
            "?kind=markdown&file_name=note.md&parse_after_import=true",
            content=b"# Uploaded\n\nA local markdown article.",
            headers={"Content-Type": "text/markdown"},
        )
        revision_id = import_response.json()["article_revision_id"]
        bundle_path = Path(import_response.json()["bundle_path"])
        archive_response = client.post(f"/libraries/{library_id}/articles/{revision_id}/archive")
        delete_response = client.delete(f"/libraries/{library_id}/articles/{revision_id}")
        articles_response = client.get(f"/libraries/{library_id}/articles")

    assert archive_response.status_code == 200
    assert archive_response.json()["article_revision"]["status"] == "archived"
    assert delete_response.status_code == 200
    assert delete_response.json()["deleted_cache"] is True
    assert not bundle_path.exists()
    assert articles_response.json() == []


@pytest.mark.asyncio
async def test_reading_progress_api_merges_time_and_feeds_article_list(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(LibraryCreate(name="Reading", path=str(tmp_path / "library")))
    bundle_path = Path(library.path) / "articles" / "arxiv" / "2401.00001" / "v1"
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Reading Progress API",
        bundle_path=bundle_path,
        metadata={},
    )
    manifest = empty_manifest(revision)
    blocks = [
        make_block(revision.id, "sec-0001", "00001", "section", "Introduction"),
        make_block(revision.id, "p-0001", "00002", "paragraph", "First paragraph."),
        make_block(revision.id, "p-0002", "00003", "paragraph", "Second paragraph."),
    ]
    await replace_document(library, revision, manifest, blocks, [], source_md="")

    with TestClient(app) as client:
        first_response = client.put(
            f"/libraries/{library.id}/articles/{revision.id}/reading-progress",
            json={
                "active_block_uid": "p-0001",
                "block_seconds": {"sec-0001": 10, "p-0001": 20, "missing": 99},
            },
        )
        second_response = client.put(
            f"/libraries/{library.id}/articles/{revision.id}/reading-progress",
            json={"active_block_uid": "p-0002", "block_seconds": {"p-0001": 5}},
        )
        progress_response = client.get(
            f"/libraries/{library.id}/articles/{revision.id}/reading-progress"
        )
        articles_response = client.get(f"/libraries/{library.id}/articles")

    assert first_response.status_code == 200
    assert first_response.json()["segments"] == [10, 20, 0]
    assert second_response.status_code == 200
    assert second_response.json()["active_block_uid"] == "p-0002"
    assert second_response.json()["active_segment_index"] == 2
    assert second_response.json()["segments"] == [10, 25, 0]
    assert second_response.json()["total_seconds"] == 35
    assert progress_response.json()["segments"] == [10, 25, 0]
    assert articles_response.json()[0]["reading_progress"]["segments"] == [10, 25, 0]


def test_export_api_returns_metadata_and_queues_job(bilin_home: Path, tmp_path: Path) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Local", "path": str(tmp_path / "local-library")},
        )
        library_id = library_response.json()["id"]
        import_response = client.post(
            f"/libraries/{library_id}/imports/file"
            "?kind=markdown&file_name=note.md&parse_after_import=true",
            content=b"# Uploaded\n\nA local markdown article.",
            headers={"Content-Type": "text/markdown"},
        )
        revision_id = import_response.json()["article_revision_id"]
        export_response = client.post(
            f"/libraries/{library_id}/articles/{revision_id}/exports",
            json={"kind": "source_markdown"},
        )
        export_payload = export_response.json()
        download_response = client.get(
            f"/libraries/{library_id}/articles/{revision_id}/exports/{export_payload['file_name']}",
        )
        job_response = client.post(
            f"/libraries/{library_id}/articles/{revision_id}/exports/jobs",
            json={"kind": "bundle_zip"},
        )

    assert export_response.status_code == 200
    assert export_payload["file_name"] == "note-source.zip"
    assert export_payload["metadata"]["relative_path"] == "export/note-source.zip"
    assert export_payload["metadata"]["bundle_path"]
    assert download_response.status_code == 200
    assert download_response.headers["content-disposition"].startswith("attachment")
    assert "note-source.zip" in download_response.headers["content-disposition"]
    assert download_response.headers["content-type"].startswith("application/zip")
    with zipfile.ZipFile(io.BytesIO(download_response.content)) as archive:
        markdown_name = next(name for name in archive.namelist() if name.endswith(".md"))
        assert "# Uploaded" in archive.read(markdown_name).decode("utf-8")
    assert job_response.status_code == 201
    job_payload = job_response.json()
    assert job_payload["type"] == "export_article"
    assert job_payload["payload"]["article_revision_id"] == revision_id
    assert job_payload["payload"]["request"]["kind"] == "bundle_zip"


@pytest.mark.asyncio
async def test_asset_file_endpoint_serves_secondary_figure_files(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(LibraryCreate(name="Assets", path=str(tmp_path / "library")))
    bundle_path = Path(library.path) / "articles" / "arxiv" / "2401.00001" / "v1"
    assets_dir = bundle_path / "assets"
    assets_dir.mkdir(parents=True)
    primary_path = assets_dir / "fig-0001.png"
    secondary_path = assets_dir / "fig-0001-2.png"
    primary_path.write_bytes(b"primary")
    secondary_path.write_bytes(b"secondary")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Asset API",
        bundle_path=bundle_path,
        metadata={},
    )
    manifest = empty_manifest(revision)
    block = make_block(
        revision.id,
        block_uid="fig-0001",
        structural_path="00001",
        block_type="figure",
        source_markdown="**Figure 1.** A paired figure.",
        metadata={"asset_id": "fig-0001", "label": "fig:paired"},
    )
    asset = make_asset(
        revision.id,
        asset_id="fig-0001",
        kind="figure",
        caption="A paired figure.",
        label="fig:paired",
        web_path=str(primary_path),
        metadata={
            "asset_files": [
                {
                    "index": 1,
                    "original_reference": "figures/left.png",
                    "web_path": str(primary_path),
                },
                {
                    "index": 2,
                    "original_reference": "figures/right.png",
                    "web_path": str(secondary_path),
                },
            ]
        },
    )
    await replace_document(library, revision, manifest, [block], [asset], source_md="")

    with TestClient(app) as client:
        response = client.get(
            f"/libraries/{library.id}/articles/{revision.id}/assets/fig-0001/files/2"
        )

    assert response.status_code == 200
    assert response.content == b"secondary"


def test_provider_profile_api_does_not_echo_api_key(bilin_home: Path) -> None:
    with TestClient(app) as client:
        response = client.post(
            "/providers",
            json={
                "name": "Mock Provider",
                "protocol": "openai-compatible",
                "api_key": "secret-value",
                "default_model": "mock-model",
            },
        )
        providers_response = client.get("/providers")

    assert response.status_code == 201
    provider = response.json()
    assert provider["key_ref"]
    assert "secret-value" not in response.text
    assert providers_response.status_code == 200
    assert providers_response.json()[0]["name"] == "Mock Provider"


def test_provider_model_discovery_does_not_save_api_key(
    bilin_home: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_list_provider_models(
        protocol: ProviderProtocol,
        api_key: str,
        base_url: str | None = None,
    ) -> list[ProviderModelInfo]:
        assert protocol == ProviderProtocol.openai_compatible
        assert api_key == "secret-value"
        assert base_url == "https://api.example.com/v1"
        return [
            ProviderModelInfo(
                id="text-embedding-3-large",
                display_name="Embedding Model",
                capabilities={"chat": False, "translation": False, "streaming": True},
            ),
            ProviderModelInfo(id="model-a", display_name="Model A", capabilities={"chat": True}),
        ]

    monkeypatch.setattr(providers_api, "list_provider_models", fake_list_provider_models)

    with TestClient(app) as client:
        response = client.post(
            "/providers/discover-models",
            json={
                "protocol": "openai-compatible",
                "api_key": "secret-value",
                "base_url": "https://api.example.com/v1",
            },
        )
        providers_response = client.get("/providers")

    assert response.status_code == 200
    payload = response.json()
    assert payload["default_model"] == "model-a"
    assert payload["capabilities"]["chat_model_count"] == 1
    assert payload["models"][0]["display_name"] == "Embedding Model"
    assert "secret-value" not in response.text
    assert providers_response.json() == []


def test_provider_presets_api_returns_editable_endpoint_defaults(bilin_home: Path) -> None:
    with TestClient(app) as client:
        response = client.get("/providers/presets")

    assert response.status_code == 200
    presets = {item["id"]: item for item in response.json()}
    assert presets["openai"]["base_url"] == "https://api.openai.com/v1"
    assert presets["anthropic"]["protocol"] == "anthropic-compatible"
    assert presets["deepseek"]["base_url"] == "https://api.deepseek.com"
    assert (
        presets["gemini"]["base_url"] == "https://generativelanguage.googleapis.com/v1beta/openai/"
    )
    assert presets["qwen-dashscope-cn"]["base_url"] == (
        "https://dashscope.aliyuncs.com/compatible-mode/v1"
    )
    assert presets["qwen-dashscope-us"]["base_url"] == (
        "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
    )
    assert presets["qwen-dashscope-intl"]["base_url"] == (
        "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    )
    assert presets["kimi-cn"]["base_url"] == "https://api.moonshot.cn/v1"
    assert presets["kimi-global"]["base_url"] == "https://api.moonshot.ai/v1"


@pytest.mark.asyncio
async def test_translation_memory_review_api(bilin_home: Path) -> None:
    entry = await record_translation_memory_entry(
        source_hash="hash-review",
        source_markdown="A source paragraph.",
        target_language="zh-CN",
        raw_markdown="待审核译文。",
        provider_profile_id=None,
        model=None,
        validation_status="ok",
        glossary_version="glossary:none",
    )

    with TestClient(app) as client:
        list_response = client.get("/translation-memory?review_status=pending")
        patch_response = client.patch(
            f"/translation-memory/{entry.id}",
            json={"review_status": "approved", "reuse_enabled": True},
        )
        approved_response = client.get(
            "/translation-memory?review_status=approved&reuse_enabled=true"
        )

    assert list_response.status_code == 200
    assert list_response.json()["entries"][0]["id"] == entry.id
    assert patch_response.status_code == 200
    assert patch_response.json()["review_status"] == TranslationMemoryReviewStatus.approved
    assert patch_response.json()["reuse_enabled"] is True
    assert approved_response.status_code == 200
    assert approved_response.json()["entries"][0]["id"] == entry.id
