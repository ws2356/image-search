import errno
import http.client
import json
import os
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from urllib.parse import urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_service import (
    MobilePairingService,
    PairingResultState,
    _is_ignorable_socket_disconnect,
)
from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import derive_pairing_key_b64
from dt_image_search.mobile.transport.lan_http_adapter import LanHttpEndpointInfo
from dt_image_search.mobile.transport.usb_ws_adapter import (
    UsbBootstrapConfig,
    UsbTransportState,
)
from dt_image_search.model.dts_db import create_db_conn, delete_folders


class _StubTransportManager:
    def __init__(self, *, usb_state_after_start: UsbTransportState = UsbTransportState.READY):
        self._endpoint_info = LanHttpEndpointInfo(
            endpoint_url="http://127.0.0.1:50123/api/mobile/pairing/claim",
            endpoint_urls=("http://127.0.0.1:50123/api/mobile/pairing/claim",),
        )
        self._usb_state_after_start = usb_state_after_start
        self._usb_state = UsbTransportState.STOPPED
        self._usb_last_probe_error = None
        self._usb_bootstrap_config = None
        self.start_lan_calls = 0
        self.configure_usb_calls: list[UsbBootstrapConfig] = []
        self.start_usb_calls = 0
        self.stop_usb_calls = 0
        self.stop_all_calls = 0

    def start_lan(self) -> LanHttpEndpointInfo:
        self.start_lan_calls += 1
        return self._endpoint_info

    def configure_usb_bootstrap(self, config: UsbBootstrapConfig) -> None:
        self.configure_usb_calls.append(config)
        self._usb_bootstrap_config = config
        self._usb_state = UsbTransportState.CONFIGURED

    def start_usb(self) -> UsbTransportState:
        self.start_usb_calls += 1
        self._usb_state = self._usb_state_after_start
        return self._usb_state

    def stop_usb(self) -> None:
        self.stop_usb_calls += 1
        self._usb_state = UsbTransportState.STOPPED

    def stop_all(self) -> None:
        self.stop_all_calls += 1
        self._usb_state = UsbTransportState.STOPPED

    @property
    def usb_state(self) -> UsbTransportState:
        return self._usb_state

    @property
    def usb_last_probe_error(self) -> str | None:
        return self._usb_last_probe_error

    @property
    def usb_bootstrap_config(self) -> UsbBootstrapConfig | None:
        return self._usb_bootstrap_config


class TestMobilePairingService(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"pairing-tests-{uuid.uuid4().hex}",
            model_name="test-model",
            pretrained_model="test-pretrained",
            offline_mode=True,
            model_file_info_url="https://example.invalid/model.json",
        )
        self._data_path_key = f"BM_DATA_PATH_{self._ctx.subfolder}"
        os.environ[self._data_path_key] = self._temp_dir.name
        self.addCleanup(os.environ.pop, self._data_path_key, None)

        self._pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            advertised_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(self._pairing_service.shutdown)

    def test_handle_pairing_request_accepts_and_persists_trust(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-123",
            },
            now=now + timedelta(seconds=5),
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response_payload["status"], "accepted")
        self.assertEqual(response_payload["desktop_name"], "Studio Mac")
        self.assertEqual(response_payload["device_uuid"], "ios-device-001")
        self.assertEqual(response_payload["transport"], "lan")
        self.assertTrue(response_payload["folder_path"].endswith("/Alice iPhone"))
        self.assertNotIn(".", response_payload["paired_at"])

        pairing_result = self._pairing_service.current_result()
        self.assertEqual(pairing_result.state, PairingResultState.ACCEPTED)
        self.assertEqual(pairing_result.device_name, "Alice iPhone")

        with create_db_conn(self._ctx) as conn:
            device_row = conn.execute(
                """
                SELECT device_uuid, platform, device_name, trust_key_b64
                FROM mobile_devices
                WHERE device_uuid = ?
                """,
                ("ios-device-001",),
            ).fetchone()
            self.assertIsNotNone(device_row)
            self.assertEqual(device_row["platform"], "ios")
            self.assertEqual(device_row["device_name"], "Alice iPhone")

            expected_key = derive_pairing_key_b64(
                session_id=session.session_id,
                one_time_passcode=token.one_time_passcode,
                device_uuid="ios-device-001",
                platform="ios",
                client_nonce="client-nonce-123",
                server_nonce=response_payload["server_nonce"],
                desktop_device_id=response_payload["desktop_device_id"],
            )
            self.assertEqual(device_row["trust_key_b64"], expected_key)

            folder_row = conn.execute(
                """
                SELECT folders.path AS folder_path
                FROM mobile_folders
                JOIN folders ON folders.id = mobile_folders.folder_id
                WHERE mobile_folders.device_uuid = ?
                """,
                ("ios-device-001",),
            ).fetchone()
            self.assertIsNotNone(folder_row)
            self.assertEqual(folder_row["folder_path"], response_payload["folder_path"])

            session_row = conn.execute(
                "SELECT status FROM mobile_backup_sessions WHERE session_id = ?",
                (session.session_id,),
            ).fetchone()
            self.assertIsNotNone(session_row)
            self.assertEqual(session_row["status"], "paired")

    def test_handle_pairing_request_rejects_expired_token(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-123",
            },
            now=now + timedelta(minutes=16),
        )

        self.assertEqual(status_code, 410)
        self.assertEqual(response_payload["status"], "expired")
        self.assertEqual(self._pairing_service.current_result().state, PairingResultState.EXPIRED)

    def test_is_ignorable_socket_disconnect_recognizes_client_disconnect_errors(self):
        self.assertTrue(_is_ignorable_socket_disconnect(OSError(errno.ENOTCONN, "Socket is not connected")))
        self.assertTrue(_is_ignorable_socket_disconnect(BrokenPipeError()))
        self.assertTrue(_is_ignorable_socket_disconnect(ConnectionResetError()))
        self.assertFalse(_is_ignorable_socket_disconnect(OSError(errno.EINVAL, "Invalid argument")))

    def test_live_pairing_http_endpoint_accepts_request(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = self._post_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-live-http-001",
                "device_name": "Live HTTP iPhone",
                "client_nonce": "live-http-nonce-001",
            }
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response_payload["status"], "accepted")
        self.assertEqual(response_payload["session_id"], session.session_id)

    def test_live_pairing_http_endpoint_returns_json_for_unhandled_error(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        with patch.object(self._pairing_service, "handle_pairing_request", side_effect=RuntimeError("boom")):
            status_code, response_payload = self._post_pairing_request(
                {
                    "schema": "dtis.mobile-pairing.v1",
                    "sid": session.session_id,
                    "opt": token.one_time_passcode,
                    "platform": "ios",
                    "device_uuid": "ios-live-http-err-001",
                    "device_name": "Live HTTP Error iPhone",
                    "client_nonce": "live-http-nonce-err-001",
                }
            )

        self.assertEqual(status_code, 500)
        self.assertEqual(response_payload["status"], "rejected")
        self.assertIn("Desktop failed while processing the pairing request.", response_payload["message"])

    def test_pairing_succeeds_after_mobile_folder_row_is_removed(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)
        first_session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        first_token = first_session.token_for(MobilePlatform.IOS)
        first_status, first_response = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": first_session.session_id,
                "opt": first_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-001",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(first_status, 200)
        self.assertEqual(first_response["status"], "accepted")

        with create_db_conn(self._ctx) as conn:
            conn.execute(
                """
                INSERT INTO mobile_assets (
                    device_uuid,
                    remote_asset_id,
                    local_relative_path,
                    last_transferred_at
                ) VALUES (?, ?, ?, ?)
                """,
                ("ios-device-001", "ph://asset-001", "2026-04/IMG_0001.JPG", now.isoformat()),
            )
            conn.commit()
            delete_folders(conn, [first_response["folder_path"]])

            self.assertIsNone(
                conn.execute("SELECT 1 FROM mobile_devices WHERE device_uuid = ?", ("ios-device-001",)).fetchone()
            )
            self.assertIsNone(
                conn.execute("SELECT 1 FROM mobile_folders WHERE device_uuid = ?", ("ios-device-001",)).fetchone()
            )
            self.assertIsNone(
                conn.execute("SELECT 1 FROM mobile_backup_sessions WHERE device_uuid = ?", ("ios-device-001",)).fetchone()
            )
            self.assertIsNone(
                conn.execute("SELECT 1 FROM mobile_assets WHERE device_uuid = ?", ("ios-device-001",)).fetchone()
            )

        second_session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now + timedelta(minutes=1))
        second_token = second_session.token_for(MobilePlatform.IOS)
        second_status, second_response = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": second_session.session_id,
                "opt": second_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-002",
            },
            now=now + timedelta(minutes=1, seconds=5),
        )
        self.assertEqual(second_status, 200)
        self.assertEqual(second_response["status"], "accepted")

    def test_start_pairing_session_includes_all_advertised_endpoints_in_qr_payload(self):
        pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(pairing_service.shutdown)

        with patch(
            "dt_image_search.mobile.mobile_pairing_service.discover_advertised_hosts",
            return_value=("192.168.50.17", "10.0.0.5"),
        ):
            session = pairing_service.start_pairing_session(self._temp_dir.name)

        ios_token = session.token_for(MobilePlatform.IOS)

        self.assertEqual(
            ios_token.endpoint_targets,
            tuple(urlsplit(endpoint_url).netloc for endpoint_url in pairing_service.endpoint_urls),
        )

    def test_start_pairing_session_configures_usb_bootstrap_from_ios_token(self):
        pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(pairing_service.shutdown)
        transport_manager = _StubTransportManager()
        pairing_service._transport_manager = transport_manager

        session = pairing_service.start_pairing_session(self._temp_dir.name)
        ios_token = session.token_for(MobilePlatform.IOS)

        self.assertEqual(len(transport_manager.configure_usb_calls), 1)
        bootstrap_config = transport_manager.configure_usb_calls[0]
        self.assertEqual(bootstrap_config.session_id, session.session_id)
        self.assertEqual(bootstrap_config.one_time_passcode, ios_token.one_time_passcode)
        self.assertEqual(bootstrap_config.suggested_port, ios_token.suggested_usb_port)
        self.assertEqual(bootstrap_config.fallback_port_window, 20)
        self.assertEqual(transport_manager.start_usb_calls, 1)

    def test_refresh_ios_token_reconfigures_usb_bootstrap(self):
        pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(pairing_service.shutdown)
        transport_manager = _StubTransportManager()
        pairing_service._transport_manager = transport_manager

        now = datetime(2026, 4, 10, 8, 0, tzinfo=timezone.utc)
        session = pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        refreshed_ios_token = pairing_service.refresh_token(
            MobilePlatform.IOS,
            now=now + timedelta(seconds=30),
        )

        self.assertEqual(len(transport_manager.configure_usb_calls), 2)
        refreshed_config = transport_manager.configure_usb_calls[1]
        self.assertEqual(refreshed_config.session_id, session.session_id)
        self.assertEqual(refreshed_config.one_time_passcode, refreshed_ios_token.one_time_passcode)
        self.assertEqual(refreshed_config.suggested_port, refreshed_ios_token.suggested_usb_port)
        self.assertEqual(transport_manager.start_usb_calls, 2)

    def test_handle_pairing_request_prefers_usb_transport_when_connected(self):
        pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(pairing_service.shutdown)
        transport_manager = _StubTransportManager(usb_state_after_start=UsbTransportState.CONNECTED)
        pairing_service._transport_manager = transport_manager

        now = datetime(2026, 4, 10, 9, 0, tzinfo=timezone.utc)
        session = pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, response_payload = pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-usb-001",
                "device_name": "USB iPhone",
                "client_nonce": "usb-client-nonce-123",
            },
            now=now + timedelta(seconds=5),
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response_payload["transport"], "usb")
        self.assertIn("USB transfer", response_payload["message"])
        self.assertEqual(pairing_service.current_result().transport, "usb")

    def _post_pairing_request(self, payload: dict[str, str]) -> tuple[int, dict[str, object]]:
        endpoint = urlsplit(self._pairing_service.endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            encoded_payload = json.dumps(payload).encode("utf-8")
            connection.request(
                "POST",
                endpoint.path,
                body=encoded_payload,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            response_body = response.read().decode("utf-8")
            return response.status, json.loads(response_body)
        finally:
            connection.close()
