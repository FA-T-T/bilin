from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def bilin_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    home = tmp_path / "bilin-home"
    monkeypatch.setenv("BILIN_HOME", str(home))
    monkeypatch.setenv("BILIN_CREDENTIAL_STORE", "app_settings")
    monkeypatch.setenv("BILIN_ARXIV_API_INTERVAL_SECONDS", "0")
    monkeypatch.setenv("BILIN_ARXIV_REQUEST_INTERVAL_SECONDS", "0")
    return home
