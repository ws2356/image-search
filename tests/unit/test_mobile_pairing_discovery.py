import os
import socket
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.mobile_pairing_discovery import (
    _select_advertised_hosts_from_netif_data,
    discover_advertised_hosts,
)


class TestMobilePairingDiscovery(unittest.TestCase):
    def test_select_advertised_hosts_prefers_private_lan_interfaces_over_tunnels(self):
        interface_addresses = {
            "lo0": [SimpleNamespace(family=socket.AF_INET, address="127.0.0.1")],
            "en0": [SimpleNamespace(family=socket.AF_INET, address="192.168.50.17")],
            "en7": [SimpleNamespace(family=socket.AF_INET, address="169.254.22.94")],
            "utun7": [SimpleNamespace(family=socket.AF_INET, address="198.18.0.1")],
            "en5": [SimpleNamespace(family=socket.AF_INET, address="10.0.0.22")],
        }
        interface_stats = {
            interface_name: SimpleNamespace(isup=True) for interface_name in interface_addresses
        }

        self.assertEqual(
            _select_advertised_hosts_from_netif_data(
                interface_addresses=interface_addresses,
                interface_stats=interface_stats,
            ),
            ("192.168.50.17", "10.0.0.22"),
        )

    def test_select_advertised_hosts_ignores_interfaces_that_are_down(self):
        interface_addresses = {
            "en0": [SimpleNamespace(family=socket.AF_INET, address="192.168.50.17")],
            "en5": [SimpleNamespace(family=socket.AF_INET, address="192.168.50.18")],
        }
        interface_stats = {
            "en0": SimpleNamespace(isup=False),
            "en5": SimpleNamespace(isup=True),
        }

        self.assertEqual(
            _select_advertised_hosts_from_netif_data(
                interface_addresses=interface_addresses,
                interface_stats=interface_stats,
            ),
            ("192.168.50.18",),
        )

    def test_discover_advertised_hosts_limits_results_and_prioritizes_probe_host(self):
        with patch(
            "dt_image_search.mobile.mobile_pairing_discovery._discover_hosts_from_interfaces",
            return_value=(
                "192.168.50.17",
                "10.0.0.22",
                "172.16.0.8",
                "192.168.1.9",
                "10.10.10.10",
                "192.168.100.2",
            ),
        ), patch(
            "dt_image_search.mobile.mobile_pairing_discovery._discover_advertised_host_via_udp_probe",
            return_value="172.16.0.8",
        ):
            self.assertEqual(
                discover_advertised_hosts(),
                ("172.16.0.8", "192.168.50.17", "10.0.0.22", "192.168.1.9", "10.10.10.10"),
            )

    def test_discover_advertised_hosts_excludes_benchmark_probe_host(self):
        with patch(
            "dt_image_search.mobile.mobile_pairing_discovery._discover_hosts_from_interfaces",
            return_value=("192.168.50.17", "10.0.0.22"),
        ), patch(
            "dt_image_search.mobile.mobile_pairing_discovery._discover_advertised_host_via_udp_probe",
            return_value="198.18.0.1",
        ):
            self.assertEqual(
                discover_advertised_hosts(),
                ("192.168.50.17", "10.0.0.22"),
            )


if __name__ == "__main__":
    unittest.main()
