from pathlib import Path
import unittest
from xml.etree import ElementTree


class TestAppxManifest(unittest.TestCase):
    @staticmethod
    def _load_manifest():
        manifest_path = (
            Path(__file__).resolve().parents[2]
            / "dt_image_search"
            / "resources"
            / "AppxManifest.xml"
        )
        manifest_tree = ElementTree.parse(manifest_path)
        namespaces = {
            "appx": "http://schemas.microsoft.com/appx/manifest/foundation/windows10",
            "desktop2": "http://schemas.microsoft.com/appx/manifest/desktop/windows10/2",
        }
        return manifest_tree, namespaces

    def test_manifest_declares_private_network_client_server_capability(self):
        manifest_tree, namespace = self._load_manifest()

        capabilities = {
            capability.attrib["Name"]
            for capability in manifest_tree.findall(".//appx:Capabilities/appx:Capability", namespace)
        }

        self.assertIn("privateNetworkClientServer", capabilities)

    def test_manifest_declares_firewall_rule_for_pairing_listener(self):
        manifest_tree, namespace = self._load_manifest()
        firewall_extension = manifest_tree.find(
            ".//appx:Applications/appx:Application/appx:Extensions/"
            "desktop2:Extension[@Category='windows.firewallRules']",
            namespace,
        )
        self.assertIsNotNone(firewall_extension)

        firewall_rules = firewall_extension.find("desktop2:FirewallRules", namespace)
        self.assertIsNotNone(firewall_rules)
        self.assertEqual(
            firewall_rules.attrib.get("Executable"),
            "DTImageSearch\\DTImageSearch.exe",
        )

        firewall_rule = firewall_rules.find(
            "desktop2:Rule[@Direction='in'][@IPProtocol='TCP'][@Profile='all']",
            namespace,
        )
        self.assertIsNotNone(firewall_rule)


if __name__ == "__main__":
    unittest.main()
