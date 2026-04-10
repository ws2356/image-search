import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobilePlatform


class TestMobilePairingSession(unittest.TestCase):
    def test_create_builds_platform_tokens_with_expected_qr_payload(self):
        now = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(
                temp_dir,
                desktop_endpoint_url="http://192.168.50.12:38933/api/mobile/pairing/claim",
                now=now,
            )

        self.assertEqual(session.destination_parent, os.path.realpath(temp_dir).replace('\\', '/'))

        android_token = session.token_for(MobilePlatform.ANDROID)
        ios_token = session.token_for(MobilePlatform.IOS)

        self.assertNotEqual(android_token.token_id, ios_token.token_id)
        self.assertNotEqual(android_token.bootstrap_secret, ios_token.bootstrap_secret)
        self.assertEqual(android_token.expires_at, now + timedelta(minutes=15))

        payload_components = urlsplit(android_token.payload)
        payload_query = parse_qs(payload_components.query)

        self.assertEqual(payload_components.scheme, "https")
        self.assertEqual(payload_components.netloc, "dl.boldman.net")
        self.assertEqual(payload_query["v"][0], "1")
        self.assertEqual(payload_query["endpoint"][0], "http://192.168.50.12:38933/api/mobile/pairing/claim")
        self.assertEqual(payload_query["pairing_id"][0], session.session_id)
        self.assertEqual(payload_query["token_id"][0], android_token.token_id)
        self.assertEqual(payload_query["secret"][0], android_token.bootstrap_secret)

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

        self.assertNotEqual(refreshed_android.token_id, original_android.token_id)
        self.assertEqual(refreshed_android.refresh_generation, 1)
        self.assertEqual(session.token_for(MobilePlatform.IOS).token_id, original_ios.token_id)

    def test_update_destination_parent_normalizes_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(temp_dir, desktop_endpoint_url="http://127.0.0.1:38933/api/mobile/pairing/claim")

        session.set_destination_parent(".")

        self.assertTrue(session.destination_parent.endswith("/image-search"))


if __name__ == '__main__':
    unittest.main()
