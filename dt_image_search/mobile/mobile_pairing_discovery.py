from __future__ import annotations

import ipaddress
import socket

PAIRING_ADVERTISED_HOST_LIMIT = 5
_EXCLUDED_INTERFACE_PREFIXES = (
    "lo",
    "utun",
    "tun",
    "tap",
    "ppp",
    "bridge",
    "awdl",
    "llw",
    "gif",
    "stf",
    "docker",
    "br-",
    "vboxnet",
    "vmnet",
    "tailscale",
    "wg",
    "zt",
)


def discover_advertised_hosts(*, limit: int = PAIRING_ADVERTISED_HOST_LIMIT) -> tuple[str, ...]:
    if limit <= 0:
        return tuple()

    # Keep several LAN candidates so phones can retry across multi-network desktops.
    hosts = list(_discover_hosts_from_interfaces(limit=limit))
    if hosts:
        return tuple(hosts[:limit])
    return ("127.0.0.1",)


def _discover_hosts_from_interfaces(*, limit: int) -> tuple[str, ...]:
    try:
        import psutil
    except ImportError:
        return tuple()

    return _select_advertised_hosts_from_netif_data(
        interface_addresses=psutil.net_if_addrs(),
        interface_stats=psutil.net_if_stats(),
        limit=limit,
    )


def _select_advertised_hosts_from_netif_data(
    *,
    interface_addresses: dict[str, list[object]],
    interface_stats: dict[str, object],
    limit: int = PAIRING_ADVERTISED_HOST_LIMIT,
) -> tuple[str, ...]:
    address_set = set()

    for interface_name, addresses in interface_addresses.items():
        interface_stat = interface_stats.get(interface_name)
        if interface_stat is not None and getattr(interface_stat, "isup", False) is False:
            continue

        for address_info in addresses:
            if getattr(address_info, "family", None) != socket.AF_INET:
                continue

            address = getattr(address_info, "address", "")
            if not _is_valid_local_ip(interface_name, address):
                continue
            address_set.add(address)

    return tuple(list(address_set)[:limit])

def _is_valid_local_ip(interface_name: str, address: str) -> bool | None:
    try:
        parsed_address = ipaddress.ip_address(address)
    except ValueError:
        return None

    if parsed_address.version != 4:
        return None
    if parsed_address.is_loopback or parsed_address.is_link_local or parsed_address.is_multicast or parsed_address.is_unspecified:
        return None
    if parsed_address.is_reserved:
        return None
    if not parsed_address.is_private and not parsed_address.is_global:
        return None

    normalized_name = interface_name.lower()
    if normalized_name.startswith(_EXCLUDED_INTERFACE_PREFIXES):
        return None

    return True
