from __future__ import annotations

from pathlib import Path


def test_clean_machine_docs_cover_local_safety_contract() -> None:
    repo_root = Path(__file__).resolve().parents[3]
    readme = (repo_root / "README.md").read_text(encoding="utf-8")
    local_safety = (repo_root / "docs" / "local-safety.md").read_text(encoding="utf-8")
    license_text = (repo_root / "LICENSE").read_text(encoding="utf-8")

    assert "make doctor" in readme
    assert "make dev" in readme
    assert "bilin acceptance golden" in readme
    assert "missing_dependency:latexml" in readme
    assert "BILIN_HOME" in readme
    assert "Docker, Redis, Celery, accounts, or built-in sync" in local_safety
    assert "logs/parse-error.json" in local_safety
    assert "Job Control Semantics" in local_safety
    assert "iCloud, OneDrive, or Syncthing" in local_safety
    assert "Apache License" in license_text
    assert "Apache-2.0" in readme


def test_readme_language_switch_covers_localized_readmes() -> None:
    repo_root = Path(__file__).resolve().parents[3]
    readmes = {
        "README.md": "简体中文",
        "README.en.md": "English",
        "README.ja.md": "日本語",
        "README.ko.md": "한국어",
        "README.es.md": "Español",
        "README.fr.md": "Français",
        "README.de.md": "Deutsch",
    }

    for filename, language_label in readmes.items():
        content = (repo_root / filename).read_text(encoding="utf-8")
        assert language_label in content
        assert "AGENT_GUIDE.md" in content
        for linked_file in readmes:
            if linked_file != filename:
                assert linked_file in content


def test_gitignore_excludes_local_runtime_artifacts() -> None:
    repo_root = Path(__file__).resolve().parents[3]
    gitignore = (repo_root / ".gitignore").read_text(encoding="utf-8")

    for pattern in (
        ".venv/",
        "node_modules/",
        "dist/",
        "test-results/",
        "*.sqlite",
        "*.sqlite-wal",
        "libraries/",
        "papers/",
        "local-data/",
        ".bilin/",
    ):
        assert pattern in gitignore
