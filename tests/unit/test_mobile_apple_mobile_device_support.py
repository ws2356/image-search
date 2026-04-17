import base64
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.apple_mobile_device_support import (
    APPLE_MOBILE_DEVICE_SUPPORT_MSI,
    APPLE_NETWORK_DRIVER_INF,
    APPLE_USB_DRIVER_INF,
    AppleMobileDeviceSupportInstallError,
    AppleMobileDeviceSupportManager,
)


class TestAppleMobileDeviceSupportManager(unittest.TestCase):
    def test_probe_reports_ready_when_service_and_drivers_are_present(self):
        manager = AppleMobileDeviceSupportManager(
            platform="win32",
            command_runner=self._command_runner(
                service_stdout="SERVICE_NAME: Apple Mobile Device Service",
                driver_stdout=(
                    "Published Name: oem7.inf\n"
                    "Original Name: usbaapl64.inf\n"
                    "Published Name: oem8.inf\n"
                    "Original Name: netaapl64.inf\n"
                ),
            ),
            resource_exists=lambda _name: True,
        )

        status = manager.probe()

        self.assertTrue(status.is_ready)
        self.assertTrue(status.can_install)
        self.assertEqual(status.missing_system_components, tuple())
        self.assertEqual(status.missing_bundled_assets, tuple())

    def test_probe_reports_missing_components_and_bundle_assets(self):
        manager = AppleMobileDeviceSupportManager(
            platform="win32",
            command_runner=self._command_runner(
                service_returncode=1060,
                driver_stdout="Original Name: usbaapl64.inf\n",
            ),
            resource_exists=lambda name: name == APPLE_MOBILE_DEVICE_SUPPORT_MSI,
        )

        status = manager.probe()

        self.assertFalse(status.is_ready)
        self.assertFalse(status.apple_service_installed)
        self.assertTrue(status.usb_driver_installed)
        self.assertFalse(status.network_driver_installed)
        self.assertEqual(
            status.missing_system_components,
            (
                "Apple Mobile Device Support service",
                f"Apple network driver ({APPLE_NETWORK_DRIVER_INF})",
            ),
        )
        self.assertEqual(
            status.missing_bundled_assets,
            (
                APPLE_USB_DRIVER_INF,
                APPLE_NETWORK_DRIVER_INF,
            ),
        )

    def test_launch_installer_builds_elevated_powershell_command(self):
        shell_execute_calls: list[tuple[str, str]] = []
        copied_assets: list[Path] = []

        with tempfile.TemporaryDirectory() as temp_dir:
            staging_dir = Path(temp_dir) / "apple-mobile-support"
            manager = AppleMobileDeviceSupportManager(
                platform="win32",
                command_runner=self._command_runner(
                    service_returncode=1060,
                    driver_stdout="",
                ),
                resource_exists=lambda _name: True,
                resource_copier=lambda name, destination_dir: self._copy_resource(
                    name,
                    destination_dir,
                    copied_assets,
                ),
                shell_execute_runner=lambda file_path, parameters: self._record_shell_execute(
                    file_path,
                    parameters,
                    shell_execute_calls,
                ),
                temp_dir_factory=lambda: str(staging_dir),
            )

            manager.launch_installer()

            self.assertEqual(shell_execute_calls[0][0], "powershell.exe")
            encoded_command = shell_execute_calls[0][1].split()[-1]
            decoded_script = base64.b64decode(encoded_command).decode("utf-16le")
            self.assertIn("msiexec.exe", decoded_script)
            self.assertIn(APPLE_MOBILE_DEVICE_SUPPORT_MSI, decoded_script)
            self.assertIn(APPLE_USB_DRIVER_INF, decoded_script)
            self.assertIn(APPLE_NETWORK_DRIVER_INF, decoded_script)
            self.assertIn("Remove-Item -LiteralPath $stageDir", decoded_script)
            self.assertEqual(
                {asset_path.name for asset_path in copied_assets},
                {
                    APPLE_MOBILE_DEVICE_SUPPORT_MSI,
                    APPLE_USB_DRIVER_INF,
                    APPLE_NETWORK_DRIVER_INF,
                },
            )

    def test_launch_installer_cleans_up_staging_dir_when_elevation_fails(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            staging_dir = Path(temp_dir) / "apple-mobile-support"
            manager = AppleMobileDeviceSupportManager(
                platform="win32",
                command_runner=self._command_runner(
                    service_returncode=1060,
                    driver_stdout="",
                ),
                resource_exists=lambda _name: True,
                resource_copier=lambda name, destination_dir: self._copy_resource(
                    name,
                    destination_dir,
                    [],
                ),
                shell_execute_runner=lambda _file_path, _parameters: 5,
                temp_dir_factory=lambda: str(staging_dir),
            )

            with self.assertRaises(AppleMobileDeviceSupportInstallError):
                manager.launch_installer()

            self.assertFalse(staging_dir.exists())

    @staticmethod
    def _command_runner(
        *,
        service_stdout: str = "",
        service_returncode: int = 0,
        driver_stdout: str = "",
        driver_returncode: int = 0,
    ):
        def _run(args: list[str]) -> subprocess.CompletedProcess[str]:
            if args[0] == "sc.exe":
                return subprocess.CompletedProcess(
                    args=args,
                    returncode=service_returncode,
                    stdout=service_stdout,
                    stderr="",
                )
            if args[0] == "pnputil.exe":
                return subprocess.CompletedProcess(
                    args=args,
                    returncode=driver_returncode,
                    stdout=driver_stdout,
                    stderr="driver failure",
                )
            raise AssertionError(f"Unexpected command: {args}")

        return _run

    @staticmethod
    def _copy_resource(name: str, destination_dir: Path, copied_assets: list[Path]) -> Path:
        destination_dir.mkdir(parents=True, exist_ok=True)
        destination_path = destination_dir / name
        destination_path.write_text("stub", encoding="utf-8")
        copied_assets.append(destination_path)
        return destination_path

    @staticmethod
    def _record_shell_execute(
        file_path: str,
        parameters: str,
        shell_execute_calls: list[tuple[str, str]],
    ) -> int:
        shell_execute_calls.append((file_path, parameters))
        return 33


if __name__ == "__main__":
    unittest.main()
