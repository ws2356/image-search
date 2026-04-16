import os
import sys
import unittest
from urllib.error import HTTPError, URLError
from unittest.mock import call
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.model import feature_flags


class _FakeResponse:
    def __init__(self, payload: bytes, status: int = 200):
        self._payload = payload
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self) -> bytes:
        return self._payload


class TestFeatureFlags(unittest.TestCase):
    def test_initialize_uses_config_default_before_remote_refresh(self):
        store = feature_flags._FeatureFlagStore()
        with (
            patch.object(feature_flags, "is_mobile_folder_feature_enabled", return_value=True),
            patch.object(store, "refresh_async") as refresh_async_mock,
        ):
            store.initialize()
            self.assertTrue(store.is_mobile_folder_enabled())

        refresh_async_mock.assert_called_once()

    def test_refresh_worker_updates_mobile_folder_flag_from_remote_payload(self):
        store = feature_flags._FeatureFlagStore()
        with patch.object(feature_flags, "_fetch_feature_flags_payload", return_value={"mobile_folder": {"enabled": True}}):
            store._refresh_worker()

        self.assertTrue(store.is_mobile_folder_enabled())

    def test_refresh_worker_keeps_existing_value_when_remote_payload_missing_flag(self):
        store = feature_flags._FeatureFlagStore()
        with patch.object(feature_flags, "is_mobile_folder_feature_enabled", return_value=True), patch.object(
            store, "refresh_async"
        ):
            store.initialize()
            self.assertTrue(store.is_mobile_folder_enabled())

        with patch.object(feature_flags, "_fetch_feature_flags_payload", return_value={"other_feature": {"enabled": False}}):
            store._refresh_worker()

        self.assertTrue(store.is_mobile_folder_enabled())

    def test_extract_mobile_folder_enabled_supports_bool_and_string_values(self):
        self.assertTrue(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": True}}))
        self.assertTrue(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": "true"}}))
        self.assertFalse(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": "false"}}))

    def test_fetch_feature_flags_retries_temporary_url_errors(self):
        success_response = _FakeResponse(b'{"mobile_folder": {"enabled": true}}')
        with (
            patch.object(
                feature_flags,
                "urlopen",
                side_effect=[URLError("timed out"), URLError("timed out"), success_response],
            ) as urlopen_mock,
            patch.object(feature_flags, "_sleep_before_retry") as sleep_before_retry_mock,
        ):
            payload = feature_flags._fetch_feature_flags_payload()

        self.assertEqual(payload, {"mobile_folder": {"enabled": True}})
        self.assertEqual(urlopen_mock.call_count, 3)
        self.assertEqual(sleep_before_retry_mock.call_count, 2)

    def test_fetch_feature_flags_does_not_retry_non_temporary_url_errors(self):
        with (
            patch.object(feature_flags, "urlopen", side_effect=URLError("certificate verify failed")) as urlopen_mock,
            patch.object(feature_flags, "_sleep_before_retry") as sleep_before_retry_mock,
        ):
            with self.assertRaises(RuntimeError):
                feature_flags._fetch_feature_flags_payload()

        self.assertEqual(urlopen_mock.call_count, 1)
        sleep_before_retry_mock.assert_not_called()

    def test_fetch_feature_flags_does_not_retry_http_errors(self):
        with (
            patch.object(
                feature_flags,
                "urlopen",
                side_effect=[
                    HTTPError(feature_flags._FEATURE_FLAGS_ENDPOINT, 503, "service unavailable", None, None),
                    _FakeResponse(b'{"mobile_folder": {"enabled": false}}'),
                ],
            ) as urlopen_mock,
            patch.object(feature_flags, "_sleep_before_retry") as sleep_before_retry_mock,
        ):
            with self.assertRaises(RuntimeError):
                feature_flags._fetch_feature_flags_payload()

        self.assertEqual(urlopen_mock.call_count, 1)
        sleep_before_retry_mock.assert_not_called()

    def test_fetch_feature_flags_retries_up_to_three_times_for_temporary_network_errors(self):
        with (
            patch.object(
                feature_flags,
                "urlopen",
                side_effect=[URLError("timed out"), URLError("timed out"), URLError("timed out"), URLError("timed out")],
            ) as urlopen_mock,
            patch.object(feature_flags, "_sleep_before_retry") as sleep_before_retry_mock,
        ):
            with self.assertRaises(RuntimeError):
                feature_flags._fetch_feature_flags_payload()

        self.assertEqual(urlopen_mock.call_count, 4)
        self.assertEqual(sleep_before_retry_mock.call_count, 3)
        sleep_before_retry_mock.assert_has_calls(
            [
                call(retry_attempt=1, reason="network_timed out"),
                call(retry_attempt=2, reason="network_timed out"),
                call(retry_attempt=3, reason="network_timed out"),
            ]
        )


if __name__ == "__main__":
    unittest.main()
