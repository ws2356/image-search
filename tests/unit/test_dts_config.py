import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.model import dts_config


class TestDtsConfig(unittest.TestCase):
    def test_get_config_merges_build_vars_before_config_json(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "config.json"
            config_path.write_text('{"log_level":"DEBUG","mobile_folder":{"enabled":false}}', encoding="utf-8")
            with (
                patch.object(
                    dts_config,
                    "_read_build_vars_from_resource",
                    return_value={
                        "log_level": "INFO",
                        "revision": "abc123",
                        "mobile_folder": {"enabled": True},
                        "debugpy_port": 9876,
                    },
                ),
                patch.object(dts_config, "get_context", return_value=object()),
                patch.object(dts_config, "get_app_data_path", return_value=Path(temp_dir)),
            ):
                config = dts_config.get_config()
        self.assertEqual(config["log_level"], "DEBUG")
        self.assertEqual(config["revision"], "abc123")
        self.assertEqual(config["mobile_folder"], {"enabled": False})
        self.assertEqual(config["debugpy_port"], 9876)

    def test_get_revision_reads_merged_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"revision": "deadbeef"}):
            self.assertEqual(dts_config.get_revision(), "deadbeef")

    def test_mobile_folder_feature_flag_defaults_to_false(self):
        with patch.object(dts_config, "get_config", return_value={}):
            self.assertFalse(dts_config.is_mobile_folder_feature_enabled(default=False))

    def test_mobile_folder_feature_flag_reads_nested_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"mobile_folder": {"enabled": True}}):
            self.assertTrue(dts_config.is_mobile_folder_feature_enabled(default=False))

    def test_mobile_folder_feature_flag_reads_dotted_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"mobile_folder.enabled": "true"}):
            self.assertTrue(dts_config.is_mobile_folder_feature_enabled(default=False))

    def test_mobile_folder_feature_flag_respects_default_for_unrecognized_value(self):
        with patch.object(dts_config, "get_config", return_value={"mobile_folder": {"enabled": "maybe"}}):
            self.assertFalse(dts_config.is_mobile_folder_feature_enabled(default=False))
            self.assertTrue(dts_config.is_mobile_folder_feature_enabled(default=True))

    def test_encryption_feature_flag_defaults_to_true(self):
        with patch.object(dts_config, "get_config", return_value={}):
            self.assertTrue(dts_config.is_encryption_feature_enabled(default=True))

    def test_encryption_feature_flag_reads_nested_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"encryption": {"enabled": False}}):
            self.assertFalse(dts_config.is_encryption_feature_enabled(default=True))

    def test_encryption_feature_flag_reads_dotted_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"encryption.enabled": "false"}):
            self.assertFalse(dts_config.is_encryption_feature_enabled(default=True))

    def test_encryption_feature_flag_respects_default_for_unrecognized_value(self):
        with patch.object(dts_config, "get_config", return_value={"encryption": {"enabled": "maybe"}}):
            self.assertFalse(dts_config.is_encryption_feature_enabled(default=False))
            self.assertTrue(dts_config.is_encryption_feature_enabled(default=True))

    def test_strict_security_feature_flag_defaults_to_false(self):
        with patch.object(dts_config, "get_config", return_value={}):
            self.assertFalse(dts_config.is_strict_security_feature_enabled())

    def test_strict_security_feature_flag_reads_nested_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"strict_security": {"enabled": True}}):
            self.assertTrue(dts_config.is_strict_security_feature_enabled())

    def test_strict_security_feature_flag_reads_dotted_config_value(self):
        with patch.object(dts_config, "get_config", return_value={"strict_security.enabled": "true"}):
            self.assertTrue(dts_config.is_strict_security_feature_enabled())

    def test_strict_security_feature_flag_respects_default_for_unrecognized_value(self):
        with patch.object(dts_config, "get_config", return_value={"strict_security": {"enabled": "maybe"}}):
            self.assertFalse(dts_config.is_strict_security_feature_enabled(default=False))
            self.assertTrue(dts_config.is_strict_security_feature_enabled(default=True))


if __name__ == "__main__":
    unittest.main()
