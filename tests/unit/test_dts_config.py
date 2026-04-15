import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.model import dts_config


class TestDtsConfig(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
