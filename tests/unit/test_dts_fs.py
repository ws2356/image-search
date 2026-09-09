"""Tests for build-injected desktop app data paths."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import pc_common.model.dts_fs as dts_fs
from pc_common.build_flavor import DesktopApp
from pc_common.model.dts_fs import get_app_data_path, get_app_private_name


class TestDtsFs(unittest.TestCase):
    def setUp(self) -> None:
        self._original_data_path_values = {
            key: os.environ.get(key)
            for key in ("BM_DATA_PATH_DTImageSearch", "BM_DATA_PATH_SnapGet")
        }
        for key in self._original_data_path_values:
            os.environ.pop(key, None)

    def tearDown(self) -> None:
        for key, value in self._original_data_path_values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_ausearch_preserves_legacy_private_name(self) -> None:
        with patch.object(dts_fs, "get_desktop_app", return_value=DesktopApp.AU_SEARCH), patch.object(
            dts_fs, "get_build_type", return_value="prod"
        ):
            self.assertEqual(get_app_private_name(), "DTImageSearch")

    def test_snapget_uses_isolated_private_name(self) -> None:
        with patch.object(dts_fs, "get_desktop_app", return_value=DesktopApp.SNAP_GET), patch.object(
            dts_fs, "get_build_type", return_value="dev"
        ):
            self.assertEqual(get_app_private_name(), "SnapGet-dev")

    def test_ausearch_uses_existing_data_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(dts_fs.QStandardPaths, "writableLocation", return_value=temp_dir):
                data_path = get_app_data_path()

        self.assertEqual(data_path, Path(temp_dir) / "DTImageSearch")

    def test_snapget_uses_isolated_data_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(dts_fs, "get_desktop_app", return_value=DesktopApp.SNAP_GET), patch.object(
                dts_fs.QStandardPaths, "writableLocation", return_value=temp_dir
            ):
                data_path = get_app_data_path()

        self.assertEqual(data_path, Path(temp_dir) / "SnapGet")


if __name__ == "__main__":
    unittest.main()
