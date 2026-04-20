import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

import dt_image_search.build_flavor as build_flavor


class _FakePackageRoot:
    def __init__(self, root: Path):
        self._root = root

    def joinpath(self, *parts: str) -> Path:
        return self._root.joinpath(*parts)


class TestBuildFlavor(unittest.TestCase):
    def setUp(self) -> None:
        self._original_env_value = os.environ.get("DTIS_BUILD_TYPE")
        build_flavor.clear_build_type_cache()
        os.environ.pop("DTIS_BUILD_TYPE", None)

    def tearDown(self) -> None:
        build_flavor.clear_build_type_cache()
        if self._original_env_value is None:
            os.environ.pop("DTIS_BUILD_TYPE", None)
        else:
            os.environ["DTIS_BUILD_TYPE"] = self._original_env_value

    def test_get_build_type_defaults_to_prod_without_env_or_resource(self) -> None:
        with patch.object(build_flavor, "_read_build_type_from_resource", return_value=None):
            self.assertEqual(build_flavor.get_build_type(), "prod")
            self.assertEqual(build_flavor.get_app_data_segment(), "DTImageSearch")

    def test_get_build_type_uses_env_override_before_resource(self) -> None:
        os.environ["DTIS_BUILD_TYPE"] = "dev"
        with patch.object(build_flavor, "_read_build_type_from_resource", return_value="prod") as resource_mock:
            self.assertEqual(build_flavor.get_build_type(), "dev")
        resource_mock.assert_not_called()

    def test_read_build_type_from_resource_parses_build_vars_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            resource_root = Path(temp_dir) / "resources"
            resource_root.mkdir(parents=True, exist_ok=True)
            (resource_root / "build_vars").write_text("# comment\nbuild_type=dev\n", encoding="utf-8")
            fake_package_root = _FakePackageRoot(Path(temp_dir))
            with patch.object(build_flavor, "files", return_value=fake_package_root):
                self.assertEqual(build_flavor._read_build_type_from_resource(), "dev")

    def test_read_build_type_from_resource_returns_none_for_unsupported_value(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            resource_root = Path(temp_dir) / "resources"
            resource_root.mkdir(parents=True, exist_ok=True)
            (resource_root / "build_vars").write_text("build_type=qa\n", encoding="utf-8")
            fake_package_root = _FakePackageRoot(Path(temp_dir))
            with patch.object(build_flavor, "files", return_value=fake_package_root):
                self.assertIsNone(build_flavor._read_build_type_from_resource())


if __name__ == "__main__":
    unittest.main()
