import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import call, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

import pc_common.build_flavor as build_flavor
from pc_common.build_flavor import DesktopApp
from pc_common.model.dts_fs import get_app_private_name


class _FakePackageRoot:
    def __init__(self, root: Path):
        self._root = root

    def joinpath(self, *parts: str) -> Path:
        return self._root.joinpath(*parts)


class TestBuildFlavor(unittest.TestCase):
    def setUp(self) -> None:
        self._original_env_value = os.environ.get("DTIS_BUILD_TYPE")
        self._original_desktop_app_env_value = os.environ.get("DTIS_DESKTOP_APP")
        build_flavor.clear_build_type_cache()
        build_flavor.clear_desktop_app_cache()
        os.environ.pop("DTIS_BUILD_TYPE", None)
        os.environ.pop("DTIS_DESKTOP_APP", None)

    def tearDown(self) -> None:
        build_flavor.clear_build_type_cache()
        if self._original_env_value is None:
            os.environ.pop("DTIS_BUILD_TYPE", None)
        else:
            os.environ["DTIS_BUILD_TYPE"] = self._original_env_value
        if self._original_desktop_app_env_value is None:
            os.environ.pop("DTIS_DESKTOP_APP", None)
        else:
            os.environ["DTIS_DESKTOP_APP"] = self._original_desktop_app_env_value
        build_flavor.clear_build_type_cache()
        build_flavor.clear_desktop_app_cache()

    def test_get_build_type_defaults_to_prod_without_env_or_resource(self) -> None:
        with patch.object(build_flavor, "_read_build_type_from_resource", return_value=None):
            self.assertEqual(build_flavor.get_build_type(), "prod")
            self.assertEqual(get_app_private_name(), "DTImageSearch")

    def test_get_build_type_uses_env_override_before_resource(self) -> None:
        os.environ["DTIS_BUILD_TYPE"] = "dev"
        with patch.object(build_flavor, "_read_build_type_from_resource", return_value="prod") as resource_mock:
            self.assertEqual(build_flavor.get_build_type(), "dev")
        resource_mock.assert_not_called()

    def test_read_build_type_from_resource_parses_build_vars_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            resource_root = Path(temp_dir) / "resources"
            resource_root.mkdir(parents=True, exist_ok=True)
            (resource_root / "build_vars").write_text(json.dumps({"build_type": "dev"}), encoding="utf-8")
            fake_package_root = _FakePackageRoot(resource_root)
            with patch.object(build_flavor, "files", return_value=fake_package_root):
                self.assertEqual(build_flavor._read_build_type_from_resource(), "dev")

    def test_read_build_type_from_resource_uses_shared_package(self) -> None:
        with patch.object(build_flavor, "files", wraps=build_flavor.files) as files_mock:
            self.assertEqual(build_flavor._read_build_type_from_resource(), "prod")
        files_mock.assert_has_calls([call("pc_common.resources")])

    def test_read_build_type_from_resource_returns_none_for_unsupported_value(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            resource_root = Path(temp_dir) / "resources"
            resource_root.mkdir(parents=True, exist_ok=True)
            (resource_root / "build_vars").write_text(json.dumps({"build_type": "qa"}), encoding="utf-8")
            fake_package_root = _FakePackageRoot(resource_root)
            with patch.object(build_flavor, "files", return_value=fake_package_root):
                self.assertIsNone(build_flavor._read_build_type_from_resource())

    def test_get_desktop_app_defaults_to_ausearch_without_resource(self) -> None:
        with patch.object(build_flavor, "_read_desktop_app_from_resource", return_value=None):
            self.assertEqual(build_flavor.get_desktop_app(), DesktopApp.AU_SEARCH)

    def test_read_desktop_app_from_resource_parses_build_vars_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            resource_root = Path(temp_dir) / "resources"
            resource_root.mkdir(parents=True, exist_ok=True)
            (resource_root / "build_vars").write_text(
                json.dumps({"desktop_app": "snap_get"}), encoding="utf-8"
            )
            fake_package_root = _FakePackageRoot(resource_root)
            with patch.object(build_flavor, "files", return_value=fake_package_root):
                self.assertEqual(
                    build_flavor._read_desktop_app_from_resource(), DesktopApp.SNAP_GET
                )

    def test_get_desktop_app_uses_env_override_before_resource(self) -> None:
        os.environ["DTIS_DESKTOP_APP"] = "snap_get"
        with patch.object(
            build_flavor,
            "_read_desktop_app_from_resource",
            return_value=DesktopApp.AU_SEARCH,
        ) as resource_mock:
            self.assertEqual(build_flavor.get_desktop_app(), DesktopApp.SNAP_GET)
        resource_mock.assert_not_called()

    def test_get_desktop_app_rejects_unsupported_resource_value(self) -> None:
        with patch.object(build_flavor, "_read_desktop_app_from_resource") as resource_mock:
            resource_mock.side_effect = ValueError("Unsupported desktop app")
            with self.assertRaises(ValueError):
                build_flavor.get_desktop_app()


if __name__ == "__main__":
    unittest.main()
