import os
import sys
import tempfile
import unittest
from pathlib import Path
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
            patch.object(feature_flags, "_load_cached_feature_flags_payload", return_value=None),
            patch.object(feature_flags, "is_mobile_folder_feature_enabled", return_value=True),
            patch.object(store, "refresh_async") as refresh_async_mock,
        ):
            store.initialize()
            self.assertTrue(store.is_mobile_folder_enabled())

        refresh_async_mock.assert_called_once()

    def test_refresh_worker_updates_mobile_folder_flag_from_remote_payload(self):
        store = feature_flags._FeatureFlagStore()
        with (
            patch.object(feature_flags, "_fetch_feature_flags_payload", return_value={"mobile_folder": {"enabled": True}}),
            patch.object(feature_flags, "_save_cached_feature_flags_payload"),
        ):
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

    def test_is_mobile_folder_enabled_prefers_cached_remote_payload_over_config(self):
        store = feature_flags._FeatureFlagStore()
        with (
            patch.object(feature_flags, "_load_cached_feature_flags_payload", return_value={"mobile_folder": {"enabled": False}}),
            patch.object(feature_flags, "is_mobile_folder_feature_enabled", return_value=True) as config_mock,
        ):
            self.assertFalse(store.is_mobile_folder_enabled())

        config_mock.assert_not_called()

    def test_is_mobile_folder_enabled_falls_back_to_config_when_cached_payload_missing_flag(self):
        store = feature_flags._FeatureFlagStore()
        with (
            patch.object(feature_flags, "_load_cached_feature_flags_payload", return_value={"other_feature": {"enabled": False}}),
            patch.object(feature_flags, "is_mobile_folder_feature_enabled", return_value=True) as config_mock,
        ):
            self.assertTrue(store.is_mobile_folder_enabled())

        config_mock.assert_called_once()

    def test_refresh_worker_saves_remote_payload_cache(self):
        payload = {"mobile_folder": {"enabled": True}, "other_feature": {"enabled": False}}
        store = feature_flags._FeatureFlagStore()
        with (
            patch.object(feature_flags, "_fetch_feature_flags_payload", return_value=payload),
            patch.object(feature_flags, "_save_cached_feature_flags_payload") as save_payload_mock,
        ):
            store._refresh_worker()

        save_payload_mock.assert_called_once_with(payload)

    def test_cached_payload_roundtrip_uses_json_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_path = Path(temp_dir) / "feature_flags_remote_cache.json"
            payload = {"mobile_folder": {"enabled": True}}
            with patch.object(feature_flags, "_feature_flags_cache_path", return_value=cache_path):
                feature_flags._save_cached_feature_flags_payload(payload)
                loaded_payload = feature_flags._load_cached_feature_flags_payload()

        self.assertEqual(loaded_payload, payload)

    def test_load_cached_payload_returns_none_for_invalid_json(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            cache_path = Path(temp_dir) / "feature_flags_remote_cache.json"
            cache_path.write_text("{invalid json", encoding="utf-8")
            with patch.object(feature_flags, "_feature_flags_cache_path", return_value=cache_path):
                loaded_payload = feature_flags._load_cached_feature_flags_payload()

        self.assertIsNone(loaded_payload)

    def test_extract_mobile_folder_enabled_supports_bool_and_string_values(self):
        self.assertTrue(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": True}}))
        self.assertTrue(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": "true"}}))
        self.assertFalse(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": "false"}}))

    def test_extract_desktop_root_trace_sample_rate_reads_only_supported_schema(self):
        payload = {"desktop": {"telemetry": {"root_trace_sample_rate": 0.25}}}
        self.assertEqual(feature_flags._extract_desktop_root_trace_sample_rate(payload), 0.25)
        self.assertIsNone(feature_flags._extract_desktop_root_trace_sample_rate({"desktop": {"root_trace_sample_rate": 0.25}}))
        self.assertIsNone(feature_flags._extract_desktop_root_trace_sample_rate({"desktop_root_trace_sample_rate": 0.25}))

    def test_extract_desktop_root_trace_sample_rate_clamps_values(self):
        self.assertEqual(
            feature_flags._extract_desktop_root_trace_sample_rate(
                {"desktop": {"telemetry": {"root_trace_sample_rate": 1.5}}}
            ),
            1.0,
        )
        self.assertEqual(
            feature_flags._extract_desktop_root_trace_sample_rate(
                {"desktop": {"telemetry": {"root_trace_sample_rate": -0.5}}}
            ),
            0.0,
        )

    def test_desktop_root_trace_sample_rate_defaults_to_ten_percent(self):
        store = feature_flags._FeatureFlagStore()
        with patch.object(feature_flags, "_load_cached_feature_flags_payload", return_value=None):
            self.assertEqual(store.desktop_root_trace_sample_rate(), 0.1)

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
