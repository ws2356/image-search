import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from dt_image_search.mobile.mobile_pairing_session import (
    USB_SUGGESTED_PORT_MAX,
    USB_SUGGESTED_PORT_MIN,
    MobilePairingSessionDraft,
    MobilePlatform,
)


class TestMobilePairingSession(unittest.TestCase):
    def test_create_builds_platform_tokens_with_expected_qr_payload(self):
        now = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(
                temp_dir,
                desktop_endpoint_urls=[
                    "http://192.168.50.12:38933/api/mobile/pairing/claim",
                    "http://10.0.0.5:38933/api/mobile/pairing/claim",
                ],
                now=now,
            )

        self.assertEqual(session.destination_parent, os.path.realpath(temp_dir).replace('\\', '/'))

        android_token = session.token_for(MobilePlatform.ANDROID)
        ios_token = session.token_for(MobilePlatform.IOS)

        self.assertNotEqual(android_token.one_time_passcode, ios_token.one_time_passcode)
        self.assertEqual(android_token.endpoint_targets, ("192.168.50.12:38933", "10.0.0.5:38933"))
        self.assertEqual(android_token.expires_at, now + timedelta(minutes=15))

        payload_components = urlsplit(android_token.payload)
        payload_query = parse_qs(payload_components.query)

        self.assertEqual(payload_components.scheme, "https")
        self.assertEqual(payload_components.netloc, "dl.boldman.net")
        self.assertEqual(payload_query["v"][0], "2")
        self.assertEqual(payload_query["ept"][0], "192.168.50.12:38933,10.0.0.5:38933")
        self.assertEqual(payload_query["sid"][0], session.session_id)
        self.assertEqual(payload_query["opt"][0], android_token.one_time_passcode)
        self.assertEqual(payload_query["usp"][0], str(android_token.suggested_usb_port))
        self.assertNotIn("sec", payload_query)
        self.assertGreaterEqual(android_token.suggested_usb_port, USB_SUGGESTED_PORT_MIN)
        self.assertLessEqual(android_token.suggested_usb_port, USB_SUGGESTED_PORT_MAX)
        self.assertGreaterEqual(ios_token.suggested_usb_port, USB_SUGGESTED_PORT_MIN)
        self.assertLessEqual(ios_token.suggested_usb_port, USB_SUGGESTED_PORT_MAX)

    def test_create_adds_strict_security_flag_to_qr_payload_when_enabled(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(
                temp_dir,
                desktop_endpoint_url="http://127.0.0.1:38933/api/mobile/pairing/claim",
                strict_security_enabled=True,
            )

        payload_query = parse_qs(urlsplit(session.token_for(MobilePlatform.IOS).payload).query)

        self.assertEqual(payload_query["sec"][0], "1")

    def test_refresh_replaces_only_requested_platform_token(self):
        now = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(
                temp_dir,
                desktop_endpoint_url="http://127.0.0.1:38933/api/mobile/pairing/claim",
                now=now,
            )

        original_android = session.token_for(MobilePlatform.ANDROID)
        original_ios = session.token_for(MobilePlatform.IOS)

        refreshed_android = session.refresh_token(MobilePlatform.ANDROID, now=now + timedelta(minutes=16))

        self.assertNotEqual(refreshed_android.one_time_passcode, original_android.one_time_passcode)
        self.assertEqual(refreshed_android.refresh_generation, 1)
        self.assertEqual(session.token_for(MobilePlatform.IOS).one_time_passcode, original_ios.one_time_passcode)

    def test_update_destination_parent_normalizes_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(temp_dir, desktop_endpoint_url="http://127.0.0.1:38933/api/mobile/pairing/claim")

        session.set_destination_parent(".")
        # repo root folder name
        repo_root_folder_name = os.path.basename(os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
        self.assertTrue(session.destination_parent.endswith(f"/{repo_root_folder_name}"))

    def test_create_limits_endpoint_targets_to_five(self):
        endpoint_urls = [
            "http://192.168.50.12:38933/api/mobile/pairing/claim",
            "http://10.0.0.5:38933/api/mobile/pairing/claim",
            "http://10.0.0.6:38933/api/mobile/pairing/claim",
            "http://10.0.0.7:38933/api/mobile/pairing/claim",
            "http://10.0.0.8:38933/api/mobile/pairing/claim",
            "http://10.0.0.9:38933/api/mobile/pairing/claim",
        ]
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(
                temp_dir,
                desktop_endpoint_urls=endpoint_urls,
            )

        self.assertEqual(
            session.token_for(MobilePlatform.IOS).endpoint_targets,
            (
                "192.168.50.12:38933",
                "10.0.0.5:38933",
                "10.0.0.6:38933",
                "10.0.0.7:38933",
                "10.0.0.8:38933",
            ),
        )


if __name__ == '__main__':
    unittest.main()
