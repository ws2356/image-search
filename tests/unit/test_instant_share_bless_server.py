"""Unit tests for the bless-backed BLE GATT server.

These tests focus on the read/write callback encoding and the lifecycle
scaffolding without requiring real Bluetooth hardware. Hardware-dependent
behavior (actual advertising, OS-level permissions) is covered by manual
end-to-end tests.
"""

from __future__ import annotations

import json
import os
import sys
import threading
import unittest
import uuid
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.instant_sharing.ble import (
    CONNECTION_CONFIG_CHARACTERISTIC,
    CONNECTION_CONFIG_CHARACTERISTIC_UUID,
    DEVICE_NAME_CHARACTERISTIC,
    DEVICE_NAME_CHARACTERISTIC_UUID,
    DEVICE_SIGNATURE_CHARACTERISTIC,
    DEVICE_SIGNATURE_CHARACTERISTIC_UUID,
    DeviceNameAdvertisement,
    DeviceSignatureAdvertisement,
    InstantShareBleDaemon,
    InstantShareBleService,
    InstantShareBlessServer,
)
from dt_image_search.instant_sharing.contracts import (
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)


class _FakeCharacteristic:
    def __init__(self, uuid: str) -> None:
        self.uuid = uuid


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


def _make_service():
    bootstrapped: list = []

    def bootstrap_handler(config) -> None:
        bootstrapped.append(config)

    service = InstantShareBleService(
        device_name_provider=lambda: DeviceNameAdvertisement(
            device_name="Studio Mac", receiver_id="pc-001"
        ),
        signature_provider=lambda: DeviceSignatureAdvertisement(
            signature="c2lnbmF0dXJl",
            signature_key_id="key-001",
            timestamp_ms=1710000000123,
        ),
        bootstrap_handler=bootstrap_handler,
    )
    return service, bootstrapped


class TestInstantShareBlessServerCallbacks(unittest.TestCase):
    def test_read_device_name_returns_json_payload(self):
        service, _ = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        result = server._on_read_request(_FakeCharacteristic(DEVICE_NAME_CHARACTERISTIC_UUID))

        decoded = json.loads(bytes(result).decode("utf-8"))
        self.assertEqual(decoded["device_name"], "Studio Mac")
        self.assertEqual(decoded["receiver_id"], "pc-001")

    def test_read_device_signature_returns_json_payload(self):
        service, _ = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        result = server._on_read_request(_FakeCharacteristic(DEVICE_SIGNATURE_CHARACTERISTIC_UUID))

        decoded = json.loads(bytes(result).decode("utf-8"))
        self.assertEqual(decoded["signature"], "c2lnbmF0dXJl")
        self.assertEqual(decoded["signature_key_id"], "key-001")
        self.assertEqual(decoded["timestamp_ms"], 1710000000123)

    def test_read_unknown_characteristic_raises(self):
        service, _ = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        with self.assertRaises(KeyError):
            server._on_read_request(_FakeCharacteristic("00000000-0000-0000-0000-000000000000"))

    def test_write_connection_config_bytes_forwards_to_bootstrap(self):
        service, bootstrapped = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        payload = _connection_config_payload()
        server._on_write_request(
            _FakeCharacteristic(CONNECTION_CONFIG_CHARACTERISTIC_UUID),
            json.dumps(payload).encode("utf-8"),
        )

        self.assertEqual(len(bootstrapped), 1)
        self.assertEqual(bootstrapped[0].session_id, payload["session_id"])
        self.assertEqual(service.active_connection_config.session_id, payload["session_id"])

    def test_write_connection_config_str_forwards_to_bootstrap(self):
        service, bootstrapped = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        payload = _connection_config_payload()
        server._on_write_request(
            _FakeCharacteristic(CONNECTION_CONFIG_CHARACTERISTIC_UUID),
            json.dumps(payload),
        )

        self.assertEqual(len(bootstrapped), 1)
        self.assertEqual(bootstrapped[0].correlation_id, payload["correlation_id"])

    def test_write_non_json_payload_raises(self):
        service, bootstrapped = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        with self.assertRaises(ValueError):
            server._on_write_request(
                _FakeCharacteristic(CONNECTION_CONFIG_CHARACTERISTIC_UUID),
                json.dumps(["not", "an", "object"]).encode("utf-8"),
            )

        self.assertEqual(bootstrapped, [])

    def test_write_wrong_uuid_raises(self):
        service, _ = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        with self.assertRaises(ValueError):
            server._on_write_request(
                _FakeCharacteristic(DEVICE_NAME_CHARACTERISTIC_UUID),
                b"{}",
            )


class TestInstantShareBlessServerLifecycle(unittest.TestCase):
    def test_uuid_constants_match_design(self):
        self.assertEqual(DEVICE_NAME_CHARACTERISTIC, "DeviceName")
        self.assertEqual(DEVICE_SIGNATURE_CHARACTERISTIC, "DeviceSignature")
        self.assertEqual(CONNECTION_CONFIG_CHARACTERISTIC, "ConnectionConfig")
        self.assertTrue(uuid.UUID(DEVICE_NAME_CHARACTERISTIC_UUID))
        self.assertTrue(uuid.UUID(DEVICE_SIGNATURE_CHARACTERISTIC_UUID))
        self.assertTrue(uuid.UUID(CONNECTION_CONFIG_CHARACTERISTIC_UUID))

    def test_start_returns_false_when_bluetooth_unavailable(self):
        service, _ = _make_service()
        server = InstantShareBlessServer(ble_service=service)

        with patch(
            "dt_image_search.instant_sharing.ble.BlessServer",
            side_effect=RuntimeError("bluetooth not available"),
        ):
            self.assertFalse(server.start(timeout_seconds=0.5))
            self.assertIsNotNone(server.last_error)
        self.assertFalse(server.is_advertising)
        server.stop(timeout_seconds=0.1)

    def test_daemon_uses_ble_server_when_provided(self):
        service, _ = _make_service()
        ble_server = InstantShareBlessServer(ble_service=service)
        heartbeat = threading.Event()
        daemon = InstantShareBleDaemon(
            ble_service=service,
            is_enabled=lambda: True,
            heartbeat=heartbeat.set,
            poll_interval_seconds=0.01,
            ble_server=ble_server,
        )

        with patch.object(ble_server, "start", return_value=True) as mock_start:
            with patch.object(ble_server, "stop") as mock_stop:
                self.assertTrue(daemon.start())
                self.assertTrue(heartbeat.wait(timeout=1.0))
                daemon.stop()
                mock_start.assert_called_once()
                mock_stop.assert_called_once()

    def test_daemon_falls_back_to_heartbeat_without_ble_server(self):
        service, _ = _make_service()
        heartbeat = threading.Event()
        daemon = InstantShareBleDaemon(
            ble_service=service,
            is_enabled=lambda: True,
            heartbeat=heartbeat.set,
            poll_interval_seconds=0.01,
        )

        self.assertTrue(daemon.start())
        self.assertTrue(heartbeat.wait(timeout=1.0))
        daemon.stop()

    def test_daemon_stop_also_stops_ble_server(self):
        service, _ = _make_service()
        ble_server = InstantShareBlessServer(ble_service=service)
        heartbeat = threading.Event()
        daemon = InstantShareBleDaemon(
            ble_service=service,
            is_enabled=lambda: True,
            heartbeat=heartbeat.set,
            poll_interval_seconds=0.01,
            ble_server=ble_server,
        )

        with patch.object(ble_server, "start", return_value=True):
            with patch.object(ble_server, "stop") as mock_stop:
                daemon.start()
                heartbeat.wait(timeout=1.0)
                daemon.stop()
                mock_stop.assert_called_once()


if __name__ == "__main__":
    unittest.main()
