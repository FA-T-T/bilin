from __future__ import annotations

import ipaddress
import os
import socket
from urllib.parse import urlparse


class NetworkPolicyError(ValueError):
    pass


def lan_security_enabled() -> bool:
    return (
        bool(os.getenv("BILIN_API_TOKEN")) or os.getenv("BILIN_RESTRICT_PROVIDER_BASE_URLS") == "1"
    )


def validate_provider_base_url(base_url: str) -> str:
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc or not parsed.hostname:
        raise NetworkPolicyError("Provider base URL must be an absolute http(s) URL.")

    hostname = parsed.hostname.lower().rstrip(".")
    if hostname in {"localhost", "localhost.localdomain"} or hostname.endswith(".localhost"):
        if lan_security_enabled():
            raise NetworkPolicyError("Local provider base URLs are disabled in LAN-secured mode.")
        return base_url

    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        if lan_security_enabled():
            _validate_resolved_hostname(hostname, parsed.port or _default_port(parsed.scheme))
        return base_url

    if lan_security_enabled() and _is_restricted_address(address):
        raise NetworkPolicyError(
            "Private or local provider base URLs are disabled in LAN-secured mode."
        )
    return base_url


def _default_port(scheme: str) -> int:
    return 443 if scheme == "https" else 80


def _validate_resolved_hostname(hostname: str, port: int) -> None:
    try:
        records = socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise NetworkPolicyError(
            "Provider hostname must resolve before it can be used in LAN-secured mode."
        ) from exc

    for record in records:
        sockaddr = record[4]
        if not sockaddr:
            continue
        try:
            address = ipaddress.ip_address(sockaddr[0])
        except ValueError:
            continue
        if _is_restricted_address(address):
            raise NetworkPolicyError(
                "Provider hostnames resolving to private or local addresses are "
                "disabled in LAN-secured mode."
            )


def _is_restricted_address(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    return (
        address.is_loopback
        or address.is_private
        or address.is_link_local
        or address.is_multicast
        or address.is_unspecified
        or address.is_reserved
    )
