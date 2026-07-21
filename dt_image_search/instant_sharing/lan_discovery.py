from __future__ import annotations

import ipaddress
import psutil
import socket
import logging

_logger = logging.getLogger(__name__)

def get_lan_ip_addresses() -> list[str]:
    addrs: list[str] = []
    try:
        for lan_ip in _get_lan_ips():
            if _is_lan_address(lan_ip):
                _logger.info("LAN IP address discovered: %s", lan_ip)
                addrs.append(lan_ip)
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

def _get_lan_ips() -> list[str]:
    result = []

    for _, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family != socket.AF_INET:
                continue

            ip = addr.address

            try:
                ip_obj = ipaddress.ip_address(ip)

                if (
                    ip_obj.is_private
                    and not ip_obj.is_loopback
                ):
                    result.append(ip)

            except ValueError:
                pass

    return sorted(set(result))