from __future__ import annotations

import os
from pathlib import Path

from platformdirs import user_data_dir
from pydantic import BaseModel, Field


class AppSettings(BaseModel):
    app_name: str = "Bilin"
    bilin_home: Path = Field(default_factory=lambda: default_bilin_home())
    api_host: str = "127.0.0.1"
    api_port: int = 8000

    @property
    def global_db_path(self) -> Path:
        return self.bilin_home / "bilin.sqlite"


def default_bilin_home() -> Path:
    override = os.getenv("BILIN_HOME")
    if override:
        return Path(override).expanduser().resolve()
    return Path(user_data_dir("Bilin", "Bilin")).expanduser().resolve()


def get_settings() -> AppSettings:
    return AppSettings()
