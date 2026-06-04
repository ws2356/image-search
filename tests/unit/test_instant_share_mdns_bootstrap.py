from __future__ import annotations

import threading
from unittest.mock import Mock, patch

import pytest

from dt_image_search.instant_sharing.mdns import (
    INSTANT_SHARE_MDNS_SERVICE_TYPE,
    INSTANT_SHARE_MDNS_PORT,
    BootstrapRequest,
    ConnectionConfig,
    DeviceNameAdvertisement,
    DeviceSignatureAdvertisement,
    InstantShareBleDaemon,
    InstantShareBleService,
    InstantShareMDNSAdvertiser,
)
from dt_image_search.instant_sharing.contracts import (
    InstantShareMetadata,
    PayloadClass,
    TargetIntent,
    TrustMode,
)



def _default_metadata(**kwargs) -> InstantShareMetadata:
    defaults = {
        "flow_id": "instant_share",
        "payload_class": PayloadClass.TEXT,
        "target_intent": TargetIntent.CLIPBOARD_ONLY,
        "trust_mode": TrustMode.FIRST_SHARE,
    }
    defaults.update(kwargs)
    return InstantShareMetadata(**defaults)




class TestDeviceSignatureAdvertisement:
    def test_validate_ok(self) -> None:
        adv = DeviceSignatureAdvertisement(signature="sig", signature_key_id="k1", timestamp_ms=1000)
        adv.validate()

    def test_validate_empty_signature(self) -> None:
        adv = DeviceSignatureAdvertisement(signature="  ", signature_key_id="k1", timestamp_ms=1000)
        with pytest.raises(ValueError, match="signature must not be empty"):
            adv.validate()

    def test_validate_empty_key_id(self) -> None:
        adv = DeviceSignatureAdvertisement(signature="sig", signature_key_id="  ", timestamp_ms=1000)
        with pytest.raises(ValueError, match="signature_key_id must not be empty"):
            adv.validate()

    def test_validate_nonpositive_timestamp(self) -> None:
        adv = DeviceSignatureAdvertisement(signature="sig", signature_key_id="k1", timestamp_ms=-1)
        with pytest.raises(ValueError, match="timestamp_ms must be positive"):
            adv.validate()

    def test_as_dict(self) -> None:
        adv = DeviceSignatureAdvertisement(signature="sig", signature_key_id="k1", timestamp_ms=1000)
        d = adv.as_dict()
        assert d == {"signature": "sig", "signature_key_id": "k1", "timestamp_ms": 1000}


class TestConnectionConfig:
    def test_from_dict_valid(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 8080,
            "mobile_ip_list": ["192.168.1.5"],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
        config = ConnectionConfig.from_dict(raw)
        assert config.session_id == raw["session_id"]
        assert config.mobile_port == 8080
        assert config.mobile_ip_list == ("192.168.1.5",)
        assert config.correlation_id == raw["correlation_id"]
        assert config.metadata.payload_class == PayloadClass.TEXT

    def test_from_dict_invalid_port(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 0,
            "mobile_ip_list": ["192.168.1.5"],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
        with pytest.raises(ValueError, match="mobile_port"):
            ConnectionConfig.from_dict(raw)

    def test_from_dict_empty_ip_list(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 8080,
            "mobile_ip_list": [],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "text",
            "target_intent": "clipboard_only",
            "trust_mode": "first_share",
        }
        with pytest.raises(ValueError, match="mobile_ip_list"):
            ConnectionConfig.from_dict(raw)


class TestBootstrapRequest:
    def test_from_dict_valid(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 8080,
            "mobile_ip_list": ["192.168.1.5"],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "text",
            "target_intent": "clipboard_only",
        }
        req = BootstrapRequest.from_dict(raw)
        assert req.session_id == raw["session_id"]
        assert req.mobile_port == 8080
        assert req.mobile_ip_list == ("192.168.1.5",)
        assert req.payload_class == "text"
        assert req.target_intent == "clipboard_only"

    def test_from_dict_invalid_payload_class(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 8080,
            "mobile_ip_list": ["192.168.1.5"],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "video",
            "target_intent": "clipboard_only",
        }
        with pytest.raises(ValueError, match="payload_class"):
            BootstrapRequest.from_dict(raw)

    def test_from_dict_invalid_target_intent(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 8080,
            "mobile_ip_list": ["192.168.1.5"],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "text",
            "target_intent": "file_only",
        }
        with pytest.raises(ValueError, match="target_intent"):
            BootstrapRequest.from_dict(raw)

    def test_from_dict_invalid_ip(self) -> None:
        raw = {
            "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "mobile_port": 8080,
            "mobile_ip_list": ["not-an-ip"],
            "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567891",
            "payload_class": "text",
            "target_intent": "clipboard_only",
        }
        with pytest.raises(ValueError):
            BootstrapRequest.from_dict(raw)





class TestInstantShareBleService:
    def _make_service(self, bootstrap_handler=None):
        return InstantShareBleService(
            device_name_provider=lambda: DeviceNameAdvertisement(
                device_name="Test PC", receiver_id="dev-001"
            ),
            signature_provider=lambda: DeviceSignatureAdvertisement(
                signature="sha256=abc", signature_key_id="k1", timestamp_ms=1
            ),
            bootstrap_handler=bootstrap_handler or (lambda _: None),
        )

    def test_read_device_name(self) -> None:
        svc = self._make_service()
        result = svc.read_characteristic("DeviceName")
        assert result["device_name"] == "Test PC"
        assert result["receiver_id"] == "dev-001"

    def test_read_device_signature(self) -> None:
        svc = self._make_service()
        result = svc.read_characteristic("DeviceSignature")
        assert result["signature"] == "sha256=abc"

    def test_read_unknown_characteristic_raises(self) -> None:
        svc = self._make_service()
        with pytest.raises(KeyError):
            svc.read_characteristic("Unknown")

    def test_handle_bootstrap(self) -> None:
        handler_called = []

        def handler(cc):
            handler_called.append(cc)

        svc = self._make_service(bootstrap_handler=handler)
        from uuid import uuid4
        metadata = _default_metadata()
        config = ConnectionConfig(
            session_id=str(uuid4()),
            mobile_port=8080,
            mobile_ip_list=("192.168.1.5",),
            correlation_id=str(uuid4()),
            metadata=metadata,
        )
        svc.handle_bootstrap(config)
        assert len(handler_called) == 1
        assert svc.active_connection_config is config

    def test_active_connection_config_none_initially(self) -> None:
        svc = self._make_service()
        assert svc.active_connection_config is None


class TestInstantShareBleDaemon:
    def test_start_stop_lifecycle(self) -> None:
        svc = InstantShareBleService(
            device_name_provider=lambda: DeviceNameAdvertisement("d", "r"),
            signature_provider=lambda: DeviceSignatureAdvertisement("s", "k", 1),
            bootstrap_handler=lambda _: None,
        )
        daemon = InstantShareBleDaemon(
            ble_service=svc,
            is_enabled=lambda: True,
        )
        assert not daemon.is_running
        started = daemon.start()
        assert started
        assert daemon.is_running
        daemon.stop()
        assert not daemon.is_running

    def test_refuses_start_when_disabled(self) -> None:
        svc = InstantShareBleService(
            device_name_provider=lambda: DeviceNameAdvertisement("d", "r"),
            signature_provider=lambda: DeviceSignatureAdvertisement("s", "k", 1),
            bootstrap_handler=lambda _: None,
        )
        daemon = InstantShareBleDaemon(
            ble_service=svc,
            is_enabled=lambda: False,
        )
        assert not daemon.start()
        assert not daemon.is_running


class TestInstantShareMDNSAdvertiser:
    def test_constructor(self) -> None:
        svc = InstantShareBleService(
            device_name_provider=lambda: DeviceNameAdvertisement("My Mac", "dev-1"),
            signature_provider=lambda: DeviceSignatureAdvertisement("sig", "k1", 1000),
            bootstrap_handler=lambda _: None,
        )
        advertiser = InstantShareMDNSAdvertiser(
            ble_service=svc,
            device_id="dev-1",
            desktop_name="My Mac",
        )
        assert advertiser.is_advertising is False
        assert advertiser.is_running is False
        assert advertiser.last_error is None

    @patch("dt_image_search.instant_sharing.mdns._local_ip_addresses", return_value=["192.168.1.1"])
    @patch("dt_image_search.instant_sharing.mdns.Zeroconf")
    def test_start_stop(self, mock_zeroconf_cls, mock_local_ips) -> None:
        mock_zc = Mock()
        mock_zeroconf_cls.return_value = mock_zc

        svc = InstantShareBleService(
            device_name_provider=lambda: DeviceNameAdvertisement("Test", "dev-1"),
            signature_provider=lambda: DeviceSignatureAdvertisement("sig", "k1", 1000),
            bootstrap_handler=lambda _: None,
        )
        advertiser = InstantShareMDNSAdvertiser(
            ble_service=svc,
            device_id="dev-1",
            desktop_name="Test",
        )
        started = advertiser.start()
        assert started
        assert advertiser.is_running
        mock_zc.register_service.assert_called_once()
        advertiser.stop()
        mock_zc.close.assert_called_once()


class TestConstants:
    def test_service_type(self) -> None:
        assert INSTANT_SHARE_MDNS_SERVICE_TYPE == "_instantshare._tcp.local."

    def test_mdns_port(self) -> None:
        assert INSTANT_SHARE_MDNS_PORT == 9527





