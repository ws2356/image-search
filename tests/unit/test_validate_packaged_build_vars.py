"""Tests for packaged build metadata validation."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


_validator_path = (
    Path(__file__).parents[2]
    / "dt_image_search"
    / "scripts"
    / "validate_packaged_build_vars.py"
)
_spec = importlib.util.spec_from_file_location("validate_packaged_build_vars", _validator_path)
validate_packaged_build_vars = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate_packaged_build_vars)


class TestValidatePackagedBuildVars(unittest.TestCase):
    def test_finds_only_physical_build_vars_in_macos_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            package_path = Path(temp_dir)
            build_vars_path = (
                package_path
                / "Contents/Resources/pc_common/resources/build_vars"
            )
            build_vars_path.parent.mkdir(parents=True)
            build_vars_path.write_text(json.dumps({"build_type": "prod"}), encoding="utf-8")

            frameworks_link = package_path / "Contents/Frameworks/pc_common"
            frameworks_link.parent.mkdir(parents=True)
            frameworks_link.symlink_to("../../Resources/pc_common")

            found_path = validate_packaged_build_vars._find_build_vars(package_path)

            self.assertEqual(found_path, build_vars_path)

    def test_rejects_multiple_physical_build_vars(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            package_path = Path(temp_dir)
            for package_root in ("one/pc_common/resources", "two/pc_common/resources"):
                build_vars_path = package_path / package_root / "build_vars"
                build_vars_path.parent.mkdir(parents=True)
                build_vars_path.write_text("{}", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "found 2"):
                validate_packaged_build_vars._find_build_vars(package_path)

    def test_validates_expected_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            package_path = Path(temp_dir)
            build_vars_path = package_path / "pc_common/resources/build_vars"
            build_vars_path.parent.mkdir(parents=True)
            build_vars_path.write_text(
                json.dumps({"build_type": "dev", "desktop_app": "snap_get"}),
                encoding="utf-8",
            )

            found_path = validate_packaged_build_vars.validate_build_vars(
                package_path, "snap_get", "dev"
            )

            self.assertEqual(found_path, build_vars_path)


if __name__ == "__main__":
    unittest.main()
