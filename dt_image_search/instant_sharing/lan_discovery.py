from __future__ import annotations

import socket
import logging

_logger = logging.getLogger(__name__)


def get_lan_ip_addresses() -> list[str]:
    addrs: list[str] = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM):
            ip = str(info[4][0])
            if _is_lan_address(ip):
                addrs.append(ip)
    except Exception as exc:
        _logger.warning("Failed to discover LAN IP addresses: %s", exc)
    if not addrs:
        _logger.info("No LAN IP addresses discovered, falling back to loopback")
        addrs = ["127.0.0.1"]
    return sorted(set(addrs))


def _is_lan_address(ip: str) -> bool:
    if ip.startswith("127."):
        return False
    if ip.startswith("169.254."):
        return False
    if ip == "0.0.0.0":
        return False
    return True
