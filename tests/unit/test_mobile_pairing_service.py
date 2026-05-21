import errno
import http.client
import json
import os
import sys
import tempfile
import threading
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from urllib.parse import urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_service import (
    MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT,
    MobileBackupAgainDecision,
    MobileBackupAgainSessionContext,
    MobilePairingService,
    PAIRING_CAPABILITY_EXCHANGE_PATH,
    PAIRING_CAPABILITY_EXCHANGE_SCHEMA,
    PAIRING_STATE_PATH,
    PairingResultState,
    _desktop_name_for_build,
    _is_ignorable_socket_disconnect,
)
from dt_image_search.mobile.mobile_capability_exchange_service import (
    MOBILE_CAPABILITY_EXCHANGE_PATH,
    MOBILE_CAPABILITY_EXCHANGE_PROOF_PURPOSE,
    MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
)
from dt_image_search.mobile.mobile_update_prompt_service import (
    MOBILE_UPDATE_PROMPT_PATH,
    MOBILE_UPDATE_PROMPT_PROOF_PURPOSE,
    MOBILE_UPDATE_PROMPT_REQUESTED_EVENT,
    MOBILE_UPDATE_PROMPT_SCHEMA,
)
from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import derive_pairing_key_b64
from dt_image_search.mobile.mobile_trust_proof import derive_trust_proof_b64
from dt_image_search.mobile.transport.lan_http_adapter import LanHttpEndpointInfo
from dt_image_search.mobile.transport.contracts import (
    PAIRING_STATE_OPERATION,
    MobileTransportContext,
    MobileTransportKind,
)
from dt_image_search.mobile.transport.usb_ws_adapter import (
    UsbBootstrapConfig,
    UsbTransportState,
)
from dt_image_search.model.dts_db import create_db_conn, delete_folders
from dt_image_search.tools.dts_event_bus import default_bus


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
        self.assertEqual(response_payload["backup_state"], "pairing_completed")
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
                platform="ios",
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

    def test_handle_pairing_request_logs_correlated_telemetry_attributes(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)

        with patch("dt_image_search.telemetry.telemetry_client.log") as log_mock:
            session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
            token = session.token_for(MobilePlatform.IOS)

            status_code, _ = self._pairing_service.handle_pairing_request(
                {
                    "schema": "dtis.mobile-pairing.v1",
                    "sid": session.session_id,
                    "opt": token.one_time_passcode,
                    "platform": "ios",
                    "device_uuid": "ios-device-telemetry-001",
                    "device_name": "Telemetry iPhone",
                    "client_nonce": "client-nonce-telemetry-123",
                },
                now=now + timedelta(seconds=5),
            )

        self.assertEqual(status_code, 200)
        accepted_attributes = [
            call.kwargs["attributes"]
            for call in log_mock.call_args_list
            if (call.kwargs.get("attributes") or {}).get("backup.result") == "accepted"
        ]
        self.assertTrue(accepted_attributes)
        self.assertEqual(accepted_attributes[-1]["correlation.session_id"], session.session_id)
        self.assertEqual(accepted_attributes[-1]["mobile.device.uuid"], "ios-device-telemetry-001")
        self.assertEqual(accepted_attributes[-1]["pairing.transport"], "lan")

    def test_pairing_state_http_endpoint_returns_latest_pairing_state(self):
        now = datetime(2026, 4, 10, 6, 30, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-state-001",
                "device_name": "Alice iPhone",
                "client_nonce": "pairing-state-client-nonce",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(status_code, 200)

        poll_status, poll_payload = self._post_pairing_state_request(
            session_id=session.session_id,
            device_uuid="ios-device-state-001",
        )

        self.assertEqual(poll_status, 200)
        self.assertEqual(poll_payload["backup_state"], "pairing_completed")
        self.assertEqual(poll_payload["session_id"], session.session_id)
        self.assertEqual(poll_payload["device_uuid"], "ios-device-state-001")

    def test_pairing_state_transport_route_dispatches_usb_requests(self):
        now = datetime(2026, 4, 10, 6, 45, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)

        status_code, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-route-001",
                "device_name": "Alice iPhone",
                "client_nonce": "pairing-route-client-nonce",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(status_code, 200)

        dispatch_response = self._pairing_service._transport_router.dispatch(
            operation=PAIRING_STATE_OPERATION,
            payload={
                "schema": "dtis.mobile-pairing.v1",
                "session_id": session.session_id,
                "device_uuid": "ios-device-route-001",
            },
            context=MobileTransportContext(
                transport=MobileTransportKind.USB_WEBSOCKET,
                operation=PAIRING_STATE_OPERATION,
                request_id="pairing-state-route-001",
                remote_address="usb://route",
            ),
        )

        self.assertEqual(dispatch_response.status_code, 200)
        self.assertEqual(dispatch_response.payload["backup_state"], "pairing_completed")

    def test_pairing_service_uses_event_bus_to_track_app_foreground_state(self):
        self.assertTrue(self._pairing_service._is_desktop_foreground())

        default_bus.publish(
            MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT,
            is_foreground=False,
        )
        self.assertFalse(self._pairing_service._is_desktop_foreground())

        default_bus.publish(
            MOBILE_APP_FOREGROUND_STATE_CHANGED_EVENT,
            is_foreground=True,
        )
        self.assertTrue(self._pairing_service._is_desktop_foreground())

    def test_desktop_name_for_build_appends_suffix_only_for_non_prod(self):
        self.assertEqual(_desktop_name_for_build("Studio Mac", "prod"), "Studio Mac")
        self.assertEqual(_desktop_name_for_build("Studio Mac", "dev"), "Studio Mac-dev")
        self.assertEqual(_desktop_name_for_build("Studio Mac-dev", "dev"), "Studio Mac-dev")

    def test_handle_pairing_request_uses_build_suffix_for_non_prod_desktop_name(self):
        now = datetime(2026, 4, 10, 6, 0, tzinfo=timezone.utc)
        with patch("dt_image_search.mobile.mobile_pairing_service.get_build_type", return_value="dev"):
            pairing_service = MobilePairingService(
                self._ctx,
                listen_host="127.0.0.1",
                advertised_host="127.0.0.1",
                desktop_name="Studio Mac",
            )
        self.addCleanup(pairing_service.shutdown)

        session = pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)
        status_code, response_payload = pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-dev-001",
                "device_name": "Alice iPhone",
                "client_nonce": "client-nonce-dev-123",
            },
            now=now + timedelta(seconds=5),
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response_payload["desktop_name"], "Studio Mac-dev")

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
        self.assertEqual(response_payload["backup_state"], "pairing_expired")
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
        self.assertEqual(response_payload["backup_state"], "pairing_completed")
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
        self.assertEqual(response_payload["backup_state"], "pending_pairing")
        self.assertIn("Desktop failed while processing the pairing request.", response_payload["message"])

    def test_live_pairing_capability_exchange_endpoint_accepts_plaintext_request_without_opt(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)

        capability_status, capability_payload = self._post_json_request(
            path=PAIRING_CAPABILITY_EXCHANGE_PATH,
            payload={
                "schema": PAIRING_CAPABILITY_EXCHANGE_SCHEMA,
                "sid": session.session_id,
                "platform": "ios",
                "capabilities": {
                    "encryption": 1,
                },
            },
        )

        self.assertEqual(capability_status, 200)
        self.assertEqual(capability_payload["schema"], PAIRING_CAPABILITY_EXCHANGE_SCHEMA)
        self.assertEqual(capability_payload["status"], "accepted")
        self.assertEqual(capability_payload["sid"], session.session_id)
        self.assertEqual(capability_payload["platform"], "ios")
        self.assertEqual(capability_payload["capabilities"], {"encryption": 1})

    def test_live_capability_exchange_http_endpoint_accepts_authenticated_request(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)
        client_nonce = "feature-exchange-nonce-001"
        device_uuid = "ios-live-feature-001"
        status_code, pairing_response = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": device_uuid,
                "device_name": "Capability Exchange iPhone",
                "client_nonce": client_nonce,
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(status_code, 200)

        trust_key = derive_pairing_key_b64(
            session_id=session.session_id,
            one_time_passcode=token.one_time_passcode,
            platform="ios",
        )
        exchange_status, exchange_payload = self._post_json_request(
            path=MOBILE_CAPABILITY_EXCHANGE_PATH,
            payload={
                "schema": MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
                "session_id": session.session_id,
                "device_uuid": device_uuid,
                "trust_key": trust_key,
                "capabilities": {
                    "encrypted_transfer": 1,
                    "bluetooth": 1,
                },
            },
        )

        self.assertEqual(exchange_status, 200)
        self.assertEqual(exchange_payload["schema"], MOBILE_CAPABILITY_EXCHANGE_SCHEMA)
        self.assertEqual(exchange_payload["status"], "accepted")
        self.assertEqual(exchange_payload["session_id"], session.session_id)
        self.assertEqual(exchange_payload["device_uuid"], device_uuid)
        self.assertEqual(exchange_payload["capabilities"], {"encryption": 1})

    def test_live_capability_exchange_http_endpoint_rejects_invalid_trust_key(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)
        status_code, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-live-feature-reject-001",
                "device_name": "Feature Reject iPhone",
                "client_nonce": "feature-exchange-reject-nonce-001",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(status_code, 200)

        exchange_status, exchange_payload = self._post_json_request(
            path=MOBILE_CAPABILITY_EXCHANGE_PATH,
            payload={
                "schema": MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
                "session_id": session.session_id,
                "device_uuid": "ios-live-feature-reject-001",
                "trust_key": "invalid-trust-key",
                "capabilities": {
                    "encrypted_transfer": 1,
                },
            },
        )

        self.assertEqual(exchange_status, 403)
        self.assertEqual(exchange_payload["schema"], MOBILE_CAPABILITY_EXCHANGE_SCHEMA)
        self.assertEqual(exchange_payload["status"], "rejected")
        self.assertEqual(exchange_payload["capabilities"], {})
        self.assertIn("rejected", exchange_payload["message"])

    def test_live_update_prompt_http_endpoint_accepts_authenticated_request(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)
        client_nonce = "update-prompt-nonce-001"
        device_uuid = "ios-live-update-001"
        status_code, pairing_response = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": device_uuid,
                "device_name": "Update Prompt iPhone",
                "client_nonce": client_nonce,
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(status_code, 200)

        observed_events: list[dict[str, object]] = []
        subscription = default_bus.subscribe(
            MOBILE_UPDATE_PROMPT_REQUESTED_EVENT,
            lambda **kwargs: observed_events.append(dict(kwargs)),
        )
        self.addCleanup(subscription.dispose)

        trust_key = derive_pairing_key_b64(
            session_id=session.session_id,
            one_time_passcode=token.one_time_passcode,
            platform="ios",
        )
        update_status, update_payload = self._post_json_request(
            path=MOBILE_UPDATE_PROMPT_PATH,
            payload={
                "schema": MOBILE_UPDATE_PROMPT_SCHEMA,
                "session_id": session.session_id,
                "device_uuid": device_uuid,
                "trust_key": trust_key,
                "required": True,
                "body_text": "Please install the latest update now.",
                "update_destination": "https://example.com/update",
            },
        )

        self.assertEqual(update_status, 200)
        self.assertEqual(update_payload["schema"], MOBILE_UPDATE_PROMPT_SCHEMA)
        self.assertEqual(update_payload["status"], "accepted")
        self.assertEqual(update_payload["required"], True)
        self.assertEqual(len(observed_events), 1)
        self.assertEqual(observed_events[0]["required"], True)
        self.assertEqual(observed_events[0]["session_id"], session.session_id)
        self.assertEqual(
            observed_events[0]["update_destination"],
            "https://example.com/update",
        )

    def test_live_update_prompt_http_endpoint_rejects_invalid_trust_key(self):
        now = datetime.now(timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.IOS)
        status_code, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-live-update-reject-001",
                "device_name": "Update Reject iPhone",
                "client_nonce": "update-prompt-reject-nonce-001",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(status_code, 200)

        observed_events: list[dict[str, object]] = []
        subscription = default_bus.subscribe(
            MOBILE_UPDATE_PROMPT_REQUESTED_EVENT,
            lambda **kwargs: observed_events.append(dict(kwargs)),
        )
        self.addCleanup(subscription.dispose)

        update_status, update_payload = self._post_json_request(
            path=MOBILE_UPDATE_PROMPT_PATH,
            payload={
                "schema": MOBILE_UPDATE_PROMPT_SCHEMA,
                "session_id": session.session_id,
                "device_uuid": "ios-live-update-reject-001",
                "trust_key": "invalid-trust-key",
                "required": False,
            },
        )

        self.assertEqual(update_status, 403)
        self.assertEqual(update_payload["schema"], MOBILE_UPDATE_PROMPT_SCHEMA)
        self.assertEqual(update_payload["status"], "rejected")
        self.assertEqual(len(observed_events), 0)

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
        self.assertEqual(first_response["backup_state"], "pairing_completed")

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
        self.assertEqual(second_response["backup_state"], "pairing_completed")

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

    def test_close_active_session_keeps_usb_running_after_accepted_pairing(self):
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
        pairing_service.close_active_session()
        self.assertEqual(transport_manager.stop_usb_calls, 0)

    def test_close_active_session_stops_usb_when_pairing_not_accepted(self):
        pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(pairing_service.shutdown)
        transport_manager = _StubTransportManager()
        pairing_service._transport_manager = transport_manager

        pairing_service.start_pairing_session(self._temp_dir.name)
        pairing_service.close_active_session()
        self.assertEqual(transport_manager.stop_usb_calls, 1)

    def test_backup_again_mismatch_can_repair_selected_mobile_folder_binding(self):
        now = datetime(2026, 4, 10, 10, 0, tzinfo=timezone.utc)
        first_session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        first_token = first_session.token_for(MobilePlatform.IOS)
        first_status, first_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": first_session.session_id,
                "opt": first_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-old-001",
                "device_name": "Alice iPhone",
                "client_nonce": "backup-again-old-client-nonce",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(first_status, 200)

        with create_db_conn(self._ctx) as conn:
            original_folder_row = conn.execute(
                """
                SELECT mobile_folders.folder_id AS folder_id, folders.path AS folder_path
                FROM mobile_folders
                JOIN folders ON folders.id = mobile_folders.folder_id
                WHERE mobile_folders.device_uuid = ?
                """,
                ("ios-device-old-001",),
            ).fetchone()
            self.assertIsNotNone(original_folder_row)
            conn.execute(
                """
                INSERT INTO mobile_assets (
                    device_uuid,
                    remote_asset_id,
                    local_relative_path,
                    last_transferred_at
                ) VALUES (?, ?, ?, ?)
                """,
                (
                    "ios-device-old-001",
                    "ph://asset-old-001",
                    "2026-04/IMG_0001.JPG",
                    now.isoformat(),
                ),
            )
            conn.commit()

        observed_mismatch_contexts = []

        def mismatch_resolver(context):
            observed_mismatch_contexts.append(context)
            return MobileBackupAgainDecision.CONTINUE_IN_SELECTED_FOLDER

        second_session = self._pairing_service.start_pairing_session(
            self._temp_dir.name,
            backup_again_context=MobileBackupAgainSessionContext(
                selected_folder_id=int(original_folder_row["folder_id"]),
                selected_folder_path=original_folder_row["folder_path"],
                expected_device_uuid="ios-device-old-001",
                mismatch_resolver=mismatch_resolver,
            ),
            now=now + timedelta(minutes=1),
        )
        second_token = second_session.token_for(MobilePlatform.IOS)
        second_status, second_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": second_session.session_id,
                "opt": second_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-new-001",
                "device_name": "Alice iPhone Reinstalled",
                "client_nonce": "backup-again-new-client-nonce",
            },
            now=now + timedelta(minutes=1, seconds=5),
        )
        completed_payload = self._wait_for_pairing_state(
            session_id=second_session.session_id,
            device_uuid="ios-device-new-001",
            expected_states={"pairing_completed"},
        )

        self.assertEqual(second_status, 200)
        self.assertEqual(second_payload["backup_state"], "pairing_mismatched")
        self.assertEqual(completed_payload["folder_path"], original_folder_row["folder_path"])
        self.assertEqual(len(observed_mismatch_contexts), 1)
        self.assertEqual(observed_mismatch_contexts[0].previous_device_uuid, "ios-device-old-001")
        self.assertEqual(observed_mismatch_contexts[0].replacement_device_uuid, "ios-device-new-001")

        with create_db_conn(self._ctx) as conn:
            folders_count = conn.execute("SELECT COUNT(*) AS count FROM folders").fetchone()["count"]
            self.assertEqual(folders_count, 1)

            folder_binding_row = conn.execute(
                "SELECT device_uuid FROM mobile_folders WHERE folder_id = ?",
                (int(original_folder_row["folder_id"]),),
            ).fetchone()
            self.assertIsNotNone(folder_binding_row)
            self.assertEqual(folder_binding_row["device_uuid"], "ios-device-new-001")

            self.assertIsNone(
                conn.execute("SELECT 1 FROM mobile_devices WHERE device_uuid = ?", ("ios-device-old-001",)).fetchone()
            )
            self.assertIsNotNone(
                conn.execute("SELECT 1 FROM mobile_devices WHERE device_uuid = ?", ("ios-device-new-001",)).fetchone()
            )

            migrated_asset = conn.execute(
                """
                SELECT local_relative_path
                FROM mobile_assets
                WHERE device_uuid = ? AND remote_asset_id = ?
                """,
                ("ios-device-new-001", "ph://asset-old-001"),
            ).fetchone()
            self.assertIsNotNone(migrated_asset)
            self.assertIsNone(
                conn.execute(
                    "SELECT 1 FROM mobile_assets WHERE device_uuid = ?",
                    ("ios-device-old-001",),
                ).fetchone()
            )

            old_session_rows = conn.execute(
                "SELECT COUNT(*) AS count FROM mobile_backup_sessions WHERE device_uuid = ?",
                ("ios-device-old-001",),
            ).fetchone()
            self.assertEqual(old_session_rows["count"], 0)
            new_session_rows = conn.execute(
                "SELECT COUNT(*) AS count FROM mobile_backup_sessions WHERE device_uuid = ?",
                ("ios-device-new-001",),
            ).fetchone()
            self.assertEqual(new_session_rows["count"], 2)

    def test_backup_again_mismatch_can_continue_in_new_mobile_folder(self):
        now = datetime(2026, 4, 10, 11, 0, tzinfo=timezone.utc)
        first_session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        first_token = first_session.token_for(MobilePlatform.IOS)
        first_status, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": first_session.session_id,
                "opt": first_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-old-002",
                "device_name": "Alice iPhone",
                "client_nonce": "backup-again-old-client-nonce-2",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(first_status, 200)

        with create_db_conn(self._ctx) as conn:
            original_folder_row = conn.execute(
                """
                SELECT mobile_folders.folder_id AS folder_id, folders.path AS folder_path
                FROM mobile_folders
                JOIN folders ON folders.id = mobile_folders.folder_id
                WHERE mobile_folders.device_uuid = ?
                """,
                ("ios-device-old-002",),
            ).fetchone()
            self.assertIsNotNone(original_folder_row)
            conn.execute(
                """
                INSERT INTO mobile_assets (
                    device_uuid,
                    remote_asset_id,
                    local_relative_path,
                    last_transferred_at
                ) VALUES (?, ?, ?, ?)
                """,
                (
                    "ios-device-old-002",
                    "ph://asset-old-002",
                    "2026-04/IMG_0002.JPG",
                    now.isoformat(),
                ),
            )
            conn.commit()

        second_session = self._pairing_service.start_pairing_session(
            self._temp_dir.name,
            backup_again_context=MobileBackupAgainSessionContext(
                selected_folder_id=int(original_folder_row["folder_id"]),
                selected_folder_path=original_folder_row["folder_path"],
                expected_device_uuid="ios-device-old-002",
                mismatch_resolver=lambda _context: MobileBackupAgainDecision.BACKUP_IN_NEW_FOLDER,
            ),
            now=now + timedelta(minutes=1),
        )
        second_token = second_session.token_for(MobilePlatform.IOS)
        second_status, second_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": second_session.session_id,
                "opt": second_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-new-002",
                "device_name": "Alice iPhone Reinstalled",
                "client_nonce": "backup-again-new-client-nonce-2",
            },
            now=now + timedelta(minutes=1, seconds=5),
        )
        completed_payload = self._wait_for_pairing_state(
            session_id=second_session.session_id,
            device_uuid="ios-device-new-002",
            expected_states={"pairing_completed"},
        )

        self.assertEqual(second_status, 200)
        self.assertEqual(second_payload["backup_state"], "pairing_mismatched")
        self.assertNotEqual(completed_payload["folder_path"], original_folder_row["folder_path"])

        with create_db_conn(self._ctx) as conn:
            old_binding = conn.execute(
                "SELECT folder_id FROM mobile_folders WHERE device_uuid = ?",
                ("ios-device-old-002",),
            ).fetchone()
            self.assertIsNotNone(old_binding)
            self.assertEqual(int(old_binding["folder_id"]), int(original_folder_row["folder_id"]))

            new_binding = conn.execute(
                "SELECT folder_id FROM mobile_folders WHERE device_uuid = ?",
                ("ios-device-new-002",),
            ).fetchone()
            self.assertIsNotNone(new_binding)
            self.assertNotEqual(int(new_binding["folder_id"]), int(original_folder_row["folder_id"]))

            self.assertIsNotNone(
                conn.execute(
                    "SELECT 1 FROM mobile_assets WHERE device_uuid = ? AND remote_asset_id = ?",
                    ("ios-device-old-002", "ph://asset-old-002"),
                ).fetchone()
            )
            self.assertIsNone(
                conn.execute(
                    "SELECT 1 FROM mobile_assets WHERE device_uuid = ? AND remote_asset_id = ?",
                    ("ios-device-new-002", "ph://asset-old-002"),
                ).fetchone()
            )

    def test_backup_again_mismatch_resolver_does_not_block_current_result_reads(self):
        now = datetime(2026, 4, 10, 12, 0, tzinfo=timezone.utc)
        first_session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        first_token = first_session.token_for(MobilePlatform.IOS)
        first_status, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": first_session.session_id,
                "opt": first_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-old-003",
                "device_name": "Alice iPhone",
                "client_nonce": "backup-again-old-client-nonce-3",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(first_status, 200)

        with create_db_conn(self._ctx) as conn:
            original_folder_row = conn.execute(
                """
                SELECT mobile_folders.folder_id AS folder_id, folders.path AS folder_path
                FROM mobile_folders
                JOIN folders ON folders.id = mobile_folders.folder_id
                WHERE mobile_folders.device_uuid = ?
                """,
                ("ios-device-old-003",),
            ).fetchone()
            self.assertIsNotNone(original_folder_row)

        def mismatch_resolver(_context):
            read_complete = threading.Event()

            def _read_current_result():
                self._pairing_service.current_result()
                read_complete.set()

            reader = threading.Thread(target=_read_current_result, daemon=True)
            reader.start()
            reader.join(timeout=1.0)
            self.assertTrue(read_complete.is_set())
            return MobileBackupAgainDecision.BACKUP_IN_NEW_FOLDER

        second_session = self._pairing_service.start_pairing_session(
            self._temp_dir.name,
            backup_again_context=MobileBackupAgainSessionContext(
                selected_folder_id=int(original_folder_row["folder_id"]),
                selected_folder_path=original_folder_row["folder_path"],
                expected_device_uuid="ios-device-old-003",
                mismatch_resolver=mismatch_resolver,
            ),
            now=now + timedelta(minutes=1),
        )
        second_token = second_session.token_for(MobilePlatform.IOS)
        second_status, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": second_session.session_id,
                "opt": second_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-new-003",
                "device_name": "Alice iPhone Reinstalled",
                "client_nonce": "backup-again-new-client-nonce-3",
            },
            now=now + timedelta(minutes=1, seconds=5),
        )
        self.assertEqual(second_status, 200)

    def test_backup_again_mismatch_can_cancel_pairing_request(self):
        now = datetime(2026, 4, 10, 13, 0, tzinfo=timezone.utc)
        first_session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        first_token = first_session.token_for(MobilePlatform.IOS)
        first_status, _ = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": first_session.session_id,
                "opt": first_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-old-004",
                "device_name": "Alice iPhone",
                "client_nonce": "backup-again-old-client-nonce-4",
            },
            now=now + timedelta(seconds=5),
        )
        self.assertEqual(first_status, 200)

        with create_db_conn(self._ctx) as conn:
            original_folder_row = conn.execute(
                """
                SELECT mobile_folders.folder_id AS folder_id, folders.path AS folder_path
                FROM mobile_folders
                JOIN folders ON folders.id = mobile_folders.folder_id
                WHERE mobile_folders.device_uuid = ?
                """,
                ("ios-device-old-004",),
            ).fetchone()
            self.assertIsNotNone(original_folder_row)

        second_session = self._pairing_service.start_pairing_session(
            self._temp_dir.name,
            backup_again_context=MobileBackupAgainSessionContext(
                selected_folder_id=int(original_folder_row["folder_id"]),
                selected_folder_path=original_folder_row["folder_path"],
                expected_device_uuid="ios-device-old-004",
                mismatch_resolver=lambda _context: MobileBackupAgainDecision.CANCEL,
            ),
            now=now + timedelta(minutes=1),
        )
        second_token = second_session.token_for(MobilePlatform.IOS)
        second_status, second_payload = self._pairing_service.handle_pairing_request(
            {
                "schema": "dtis.mobile-pairing.v1",
                "sid": second_session.session_id,
                "opt": second_token.one_time_passcode,
                "platform": "ios",
                "device_uuid": "ios-device-new-004",
                "device_name": "Alice iPhone Reinstalled",
                "client_nonce": "backup-again-new-client-nonce-4",
            },
            now=now + timedelta(minutes=1, seconds=5),
        )
        stopped_payload = self._wait_for_pairing_state(
            session_id=second_session.session_id,
            device_uuid="ios-device-new-004",
            expected_states={"pairing_stopped"},
        )

        self.assertEqual(second_status, 200)
        self.assertEqual(second_payload["backup_state"], "pairing_mismatched")
        self.assertEqual(stopped_payload["backup_state"], "pairing_stopped")
        self.assertIn("canceled", str(stopped_payload["message"]).lower())

        with create_db_conn(self._ctx) as conn:
            self.assertIsNotNone(
                conn.execute("SELECT 1 FROM mobile_devices WHERE device_uuid = ?", ("ios-device-old-004",)).fetchone()
            )
            self.assertIsNone(
                conn.execute("SELECT 1 FROM mobile_devices WHERE device_uuid = ?", ("ios-device-new-004",)).fetchone()
            )

    def _post_pairing_request(self, payload: dict[str, str]) -> tuple[int, dict[str, object]]:
        endpoint = urlsplit(self._pairing_service.endpoint_url)
        return self._post_json_request(path=endpoint.path, payload=payload)

    def _post_pairing_state_request(
        self,
        *,
        session_id: str,
        device_uuid: str,
    ) -> tuple[int, dict[str, object]]:
        return self._post_json_request(
            path=PAIRING_STATE_PATH,
            payload={
                "schema": "dtis.mobile-pairing.v1",
                "session_id": session_id,
                "device_uuid": device_uuid,
            },
        )

    def _wait_for_pairing_state(
        self,
        *,
        session_id: str,
        device_uuid: str,
        expected_states: set[str],
        max_attempts: int = 25,
    ) -> dict[str, object]:
        last_payload: dict[str, object] | None = None
        for _ in range(max_attempts):
            status_code, payload = self._post_pairing_state_request(
                session_id=session_id,
                device_uuid=device_uuid,
            )
            self.assertEqual(status_code, 200)
            backup_state = payload.get("backup_state")
            self.assertIsInstance(backup_state, str)
            if isinstance(backup_state, str) and backup_state in expected_states:
                return payload
            last_payload = payload
            threading.Event().wait(0.05)

        self.fail(
            "Desktop pairing state did not reach expected states "
            f"{sorted(expected_states)}. Last payload: {last_payload}"
        )

    def _post_json_request(self, *, path: str, payload: dict[str, object]) -> tuple[int, dict[str, object]]:
        endpoint = urlsplit(self._pairing_service.endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            normalized_payload = dict(payload)
            raw_trust_key = normalized_payload.pop("trust_key", None)
            proof_purpose = self._proof_purpose_for_path(path)
            if isinstance(raw_trust_key, str) and raw_trust_key and proof_purpose is not None:
                normalized_payload["trust_proof"] = derive_trust_proof_b64(
                    trust_key_b64=raw_trust_key,
                    purpose=proof_purpose,
                    schema=str(normalized_payload.get("schema", "")),
                    session_id=str(normalized_payload.get("session_id", "")),
                    device_uuid=str(normalized_payload.get("device_uuid", "")),
                )
            encoded_payload = json.dumps(normalized_payload).encode("utf-8")
            connection.request(
                "POST",
                path,
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

    @staticmethod
    def _proof_purpose_for_path(path: str) -> str | None:
        if path == MOBILE_CAPABILITY_EXCHANGE_PATH:
            return MOBILE_CAPABILITY_EXCHANGE_PROOF_PURPOSE
        if path == MOBILE_UPDATE_PROMPT_PATH:
            return MOBILE_UPDATE_PROMPT_PROOF_PURPOSE
        return None
