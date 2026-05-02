from __future__ import annotations

import os
import platform
import shutil
import subprocess
from dataclasses import dataclass

SERVICE_NAME = "Bilin Provider API Keys"
APP_SETTINGS_REF_PREFIX = "app_settings:"
KEYCHAIN_REF_PREFIX = "keychain:"


class CredentialStoreError(RuntimeError):
    pass


@dataclass(frozen=True)
class CredentialWriteResult:
    key_ref: str
    backend: str
    fallback_reason: str | None = None


def provider_api_key_account(provider_id: str) -> str:
    return f"provider_api_key:{provider_id}"


def app_settings_provider_key_ref(provider_id: str) -> str:
    return f"{APP_SETTINGS_REF_PREFIX}{provider_api_key_account(provider_id)}"


def keychain_provider_key_ref(provider_id: str) -> str:
    return f"{KEYCHAIN_REF_PREFIX}{provider_api_key_account(provider_id)}"


def credential_store_mode() -> str:
    return os.getenv("BILIN_CREDENTIAL_STORE", "auto").strip().lower() or "auto"


def keychain_available() -> bool:
    mode = credential_store_mode()
    if mode in {"app_settings", "database", "db", "sqlite", "none"}:
        return False
    return platform.system() == "Darwin" and shutil.which("security") is not None


def keychain_status_message() -> tuple[bool, str | None, str]:
    mode = credential_store_mode()
    if mode in {"app_settings", "database", "db", "sqlite", "none"}:
        return (
            False,
            None,
            "Provider API keys are configured to use the SQLite development fallback.",
        )
    security_path = shutil.which("security")
    if platform.system() != "Darwin":
        return (
            False,
            security_path,
            "macOS Keychain is unavailable on this platform; provider API keys use the SQLite "
            "development fallback.",
        )
    if security_path is None:
        return (
            False,
            None,
            "macOS Keychain command `security` was not found; provider API keys use the SQLite "
            "development fallback.",
        )
    return (
        True,
        security_path,
        "macOS Keychain is available for provider API key storage.",
    )


def store_provider_api_key(provider_id: str, api_key: str) -> CredentialWriteResult:
    if not keychain_available():
        return CredentialWriteResult(
            key_ref=app_settings_provider_key_ref(provider_id),
            backend="app_settings",
        )
    try:
        _security(
            "add-generic-password",
            "-a",
            provider_api_key_account(provider_id),
            "-s",
            SERVICE_NAME,
            "-w",
            api_key,
            "-U",
        )
    except CredentialStoreError as exc:
        if credential_store_mode() == "keychain":
            raise
        return CredentialWriteResult(
            key_ref=app_settings_provider_key_ref(provider_id),
            backend="app_settings",
            fallback_reason=str(exc),
        )
    return CredentialWriteResult(
        key_ref=keychain_provider_key_ref(provider_id),
        backend="keychain",
    )


def read_provider_api_key_from_keychain(provider_id: str) -> str | None:
    try:
        completed = _security(
            "find-generic-password",
            "-a",
            provider_api_key_account(provider_id),
            "-s",
            SERVICE_NAME,
            "-w",
        )
    except CredentialStoreError:
        return None
    value = completed.stdout.strip()
    return value or None


def delete_provider_api_key_from_keychain(provider_id: str) -> None:
    try:
        _security(
            "delete-generic-password",
            "-a",
            provider_api_key_account(provider_id),
            "-s",
            SERVICE_NAME,
        )
    except CredentialStoreError:
        return


def _security(*args: str) -> subprocess.CompletedProcess[str]:
    security_path = shutil.which("security")
    if security_path is None:
        msg = "macOS security command is not available"
        raise CredentialStoreError(msg)
    try:
        completed = subprocess.run(
            (security_path, *args),
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        msg = f"macOS Keychain command failed: {exc}"
        raise CredentialStoreError(msg) from exc
    if completed.returncode != 0:
        stderr = completed.stderr.strip() or completed.stdout.strip() or "unknown error"
        msg = f"macOS Keychain command failed: {stderr}"
        raise CredentialStoreError(msg)
    return completed
