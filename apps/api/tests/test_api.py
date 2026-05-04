from __future__ import annotations

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
    assert jobs_response.status_code == 200
    assert jobs_response.json() == []


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
    assert export_payload["file_name"] == "source.md"
    assert export_payload["metadata"]["relative_path"] == "export/source.md"
    assert export_payload["metadata"]["bundle_path"]
    assert download_response.status_code == 200
    assert download_response.headers["content-disposition"].startswith("attachment")
    assert "source.md" in download_response.headers["content-disposition"]
    assert download_response.headers["content-type"].startswith("text/markdown")
    assert b"# Uploaded" in download_response.content
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
