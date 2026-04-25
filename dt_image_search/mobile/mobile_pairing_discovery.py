from __future__ import annotations

import ipaddress
import socket
import psutil

PAIRING_ADVERTISED_HOST_LIMIT = 5
_EXCLUDED_ADDRESS_NETWORKS = (
    ipaddress.ip_network("198.18.0.0/15"),
)
_PREFERRED_INTERFACE_PREFIXES = ("en", "eth", "wlan", "wl")
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
    probe_host = _discover_advertised_host_via_udp_probe()
    if probe_host and _score_advertised_host_candidate("probe", probe_host) is not None:
        if probe_host in hosts:
            hosts.remove(probe_host)
        hosts.insert(0, probe_host)

    if hosts:
        return tuple(hosts[:limit])
    return ("127.0.0.1",)


def _discover_hosts_from_interfaces(*, limit: int) -> tuple[str, ...]:
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
    candidates: list[tuple[int, str, str]] = []

    for interface_name, addresses in interface_addresses.items():
        interface_stat = interface_stats.get(interface_name)
        if interface_stat is not None and getattr(interface_stat, "isup", False) is False:
            continue

        for address_info in addresses:
            if getattr(address_info, "family", None) != socket.AF_INET:
                continue

            address = getattr(address_info, "address", "")
            score = _score_advertised_host_candidate(interface_name, address)
            if score is None:
                continue
            candidates.append((score, interface_name, address))

    if not candidates or limit <= 0:
        return tuple()

    candidates.sort(key=lambda candidate: (-candidate[0], candidate[1], candidate[2]))
    hosts: list[str] = []
    seen_hosts: set[str] = set()
    for _, _, address in candidates:
        if address in seen_hosts:
            continue
        seen_hosts.add(address)
        hosts.append(address)
        if len(hosts) == limit:
            break

    return tuple(hosts)


def _discover_advertised_host_via_udp_probe() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe_socket:
            probe_socket.connect(("8.8.8.8", 80))
            advertised_host = probe_socket.getsockname()[0]
            if advertised_host:
                return advertised_host
    except OSError:
        pass
    return None


def _score_advertised_host_candidate(interface_name: str, address: str) -> int | None:
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
    if any(parsed_address in excluded_network for excluded_network in _EXCLUDED_ADDRESS_NETWORKS):
        return None
    if not parsed_address.is_private and not parsed_address.is_global:
        return None

    normalized_name = interface_name.lower()
    if normalized_name.startswith(_EXCLUDED_INTERFACE_PREFIXES):
        return None

    score = 0
    if parsed_address.is_private:
        score += 100
    else:
        score += 40

    if normalized_name.startswith(_PREFERRED_INTERFACE_PREFIXES):
        score += 20
    else:
        score += 5

    if normalized_name in {"en0", "en1", "eth0", "wlan0"}:
        score += 5

    return score
