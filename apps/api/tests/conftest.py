from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture()
def bilin_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    home = tmp_path / "bilin-home"
    monkeypatch.setenv("BILIN_HOME", str(home))
    monkeypatch.setenv("BILIN_CREDENTIAL_STORE", "app_settings")
    return home
