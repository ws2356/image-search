import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
import json

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobilePlatform


class TestMobilePairingSession(unittest.TestCase):
    def test_create_builds_platform_tokens_with_expected_payload(self):
        now = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(temp_dir, now=now)

        self.assertEqual(session.destination_parent, os.path.realpath(temp_dir).replace('\\', '/'))

        android_token = session.token_for(MobilePlatform.ANDROID)
        ios_token = session.token_for(MobilePlatform.IOS)

        self.assertNotEqual(android_token.token_id, ios_token.token_id)
        self.assertNotEqual(android_token.bootstrap_secret, ios_token.bootstrap_secret)
        self.assertEqual(android_token.expires_at, now + timedelta(minutes=15))

        payload = json.loads(android_token.payload)
        self.assertEqual(payload["platform"], "android")
        self.assertEqual(payload["session_id"], session.session_id)
        self.assertEqual(payload["token_id"], android_token.token_id)

    def test_refresh_replaces_only_requested_platform_token(self):
        now = datetime(2026, 4, 9, 12, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(temp_dir, now=now)

        original_android = session.token_for(MobilePlatform.ANDROID)
        original_ios = session.token_for(MobilePlatform.IOS)

        refreshed_android = session.refresh_token(MobilePlatform.ANDROID, now=now + timedelta(minutes=16))

        self.assertNotEqual(refreshed_android.token_id, original_android.token_id)
        self.assertEqual(refreshed_android.refresh_generation, 1)
        self.assertEqual(session.token_for(MobilePlatform.IOS).token_id, original_ios.token_id)

    def test_update_destination_parent_normalizes_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            session = MobilePairingSessionDraft.create(temp_dir)

        session.set_destination_parent(".")

        self.assertTrue(session.destination_parent.endswith("/image-search"))


if __name__ == '__main__':
    unittest.main()