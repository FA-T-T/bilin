from __future__ import annotations

import socket

import pytest

from bilin_api.network_security import NetworkPolicyError, validate_provider_base_url


def test_provider_base_url_allows_localhost_in_local_mode(monkeypatch) -> None:
    monkeypatch.delenv("BILIN_API_TOKEN", raising=False)
    monkeypatch.delenv("BILIN_RESTRICT_PROVIDER_BASE_URLS", raising=False)

    assert validate_provider_base_url("http://127.0.0.1:11434/v1") == "http://127.0.0.1:11434/v1"


def test_provider_base_url_blocks_private_addresses_in_lan_mode(monkeypatch) -> None:
    monkeypatch.setenv("BILIN_API_TOKEN", "token")

    with pytest.raises(NetworkPolicyError):
        validate_provider_base_url("http://127.0.0.1:11434/v1")
    with pytest.raises(NetworkPolicyError):
        validate_provider_base_url("http://192.168.1.1/v1")


def test_provider_base_url_requires_http_url() -> None:
    with pytest.raises(NetworkPolicyError):
        validate_provider_base_url("file:///etc/passwd")


def test_provider_base_url_blocks_domains_resolving_private_in_lan_mode(monkeypatch) -> None:
    monkeypatch.setenv("BILIN_API_TOKEN", "token")

    def fake_getaddrinfo(*args, **kwargs):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("10.0.0.4", 443))]

    monkeypatch.setattr(socket, "getaddrinfo", fake_getaddrinfo)

    with pytest.raises(NetworkPolicyError):
        validate_provider_base_url("https://provider.example/v1")


def test_provider_base_url_allows_domains_resolving_public_in_lan_mode(monkeypatch) -> None:
    monkeypatch.setenv("BILIN_API_TOKEN", "token")

    def fake_getaddrinfo(*args, **kwargs):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))]

    monkeypatch.setattr(socket, "getaddrinfo", fake_getaddrinfo)

    assert (
        validate_provider_base_url("https://provider.example/v1") == "https://provider.example/v1"
    )
