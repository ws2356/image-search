import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.model import feature_flags


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

        with patch.object(feature_flags, "_fetch_feature_flags_payload", return_value={"other_feature": {"enabled": False}}):
            store._refresh_worker()

        self.assertTrue(store.is_mobile_folder_enabled())

    def test_extract_mobile_folder_enabled_supports_bool_and_string_values(self):
        self.assertTrue(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": True}}))
        self.assertTrue(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": "true"}}))
        self.assertFalse(feature_flags._extract_mobile_folder_enabled({"mobile_folder": {"enabled": "false"}}))


if __name__ == "__main__":
    unittest.main()
