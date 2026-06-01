import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import (
    CONNECTION_CONFIG_CHARACTERISTIC,
    DEVICE_NAME_CHARACTERISTIC,
    DEVICE_SIGNATURE_CHARACTERISTIC,
    CharacteristicAccessError,
    CharacteristicAccessMode,
    ConnectionConfig,
    DeviceNameAdvertisement,
    DeviceSignatureAdvertisement,
    InstantShareBleService,
)
from dt_image_search.instant_sharing.contracts import (
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)


def _connection_config_payload(**overrides):
    payload = {
        "session_id": str(uuid.uuid4()),
        "mobile_port": 8443,
        "mobile_ip_list": ["192.168.1.20", "fe80::10"],
        "correlation_id": str(uuid.uuid4()),
        "flow_id": "instant_share",
        "payload_class": "text",
        "target_intent": "clipboard_only",
        "trust_mode": "first_share",
    }
    payload.update(overrides)
    return payload


class TestInstantShareContracts(unittest.TestCase):
    def test_metadata_rejects_invalid_target_for_payload_class(self):
        metadata = InstantShareMetadata(
            payload_class=PayloadClass.TEXT,
            target_intent=TargetIntent.CLIPBOARD_OR_FILE,
            trust_mode=TrustMode.FIRST_SHARE,
        )

        with self.assertRaises(ValueError):
            metadata.validate()

    def test_connection_config_validates_mobile_ips_and_metadata(self):
        config = ConnectionConfig.from_dict(
            _connection_config_payload(
                payload_class="image",
                target_intent="clipboard_or_file",
                trust_mode="trusted_direct",
            )
        )

        self.assertEqual(config.mobile_port, 8443)
        self.assertEqual(config.mobile_ip_list, ("192.168.1.20", "fe80::10"))
        self.assertEqual(config.metadata.payload_class, PayloadClass.IMAGE)
        self.assertEqual(config.metadata.target_intent, TargetIntent.CLIPBOARD_OR_FILE)
        self.assertEqual(config.metadata.trust_mode, TrustMode.TRUSTED_DIRECT)

    def test_ble_service_enforces_characteristic_access_modes(self):
        received_connection_configs = []
        service = InstantShareBleService(
            device_name_provider=lambda: DeviceNameAdvertisement(device_name="Studio Mac", receiver_id="pc-001"),
            signature_provider=lambda: DeviceSignatureAdvertisement(
                signature="c2lnbmF0dXJl",
                signature_key_id="key-001",
                timestamp_ms=1710000000123,
            ),
            bootstrap_handler=received_connection_configs.append,
        )

        self.assertEqual(
            [characteristic.name for characteristic in service.list_characteristics()],
            [DEVICE_NAME_CHARACTERISTIC, DEVICE_SIGNATURE_CHARACTERISTIC, CONNECTION_CONFIG_CHARACTERISTIC],
        )
        self.assertEqual(
            [characteristic.access_mode for characteristic in service.list_characteristics()],
            [
                CharacteristicAccessMode.READ_ONLY,
                CharacteristicAccessMode.READ_ONLY,
                CharacteristicAccessMode.WRITE_ONLY,
            ],
        )
        self.assertEqual(service.read_characteristic(DEVICE_NAME_CHARACTERISTIC)["device_name"], "Studio Mac")
        self.assertEqual(service.read_characteristic(DEVICE_SIGNATURE_CHARACTERISTIC)["signature_key_id"], "key-001")

        with self.assertRaises(CharacteristicAccessError):
            service.read_characteristic(CONNECTION_CONFIG_CHARACTERISTIC)

        with self.assertRaises(CharacteristicAccessError):
            service.write_characteristic(DEVICE_NAME_CHARACTERISTIC, {})

        service.write_characteristic(CONNECTION_CONFIG_CHARACTERISTIC, _connection_config_payload())

        self.assertEqual(len(received_connection_configs), 1)
        self.assertEqual(received_connection_configs[0].metadata.payload_class, PayloadClass.TEXT)
        self.assertEqual(service.active_connection_config.session_id, received_connection_configs[0].session_id)


if __name__ == "__main__":
    unittest.main()