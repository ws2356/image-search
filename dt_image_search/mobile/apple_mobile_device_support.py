from __future__ import annotations

import base64
from dataclasses import dataclass
from importlib.resources import as_file, files
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Callable

from dt_image_search.bm_context import get_context
from dt_image_search.model.dts_fs import get_app_data_path
from dt_image_search.telemetry.telemetry_client import log

APPLE_MOBILE_DEVICE_SERVICE_NAME = "Apple Mobile Device Service"
APPLE_MOBILE_DEVICE_SUPPORT_MSI = "AppleMobileDeviceSupport64.msi"
APPLE_USB_DRIVER_INF = "usbaapl64.inf"
APPLE_USB_DRIVER_CAT = "usbaapl64.cat"
APPLE_USB_DRIVER_SYS = "usbaapl64.sys"
APPLE_USB_DRIVER_DLL = "usbaaplrc.dll"
APPLE_NETWORK_DRIVER_INF = "netaapl64.inf"
APPLE_NETWORK_DRIVER_CAT = "netaapl64.cat"
APPLE_NETWORK_DRIVER_SYS = "netaapl64.sys"
APPLE_NETWORK_DRIVER_WDF_COINSTALLER = "WdfCoInstaller01009.dll"
APPLE_USB_DRIVER_PACKAGE_FILES = (
    APPLE_USB_DRIVER_INF,
    APPLE_USB_DRIVER_CAT,
    APPLE_USB_DRIVER_SYS,
    APPLE_USB_DRIVER_DLL,
)
APPLE_NETWORK_DRIVER_PACKAGE_FILES = (
    APPLE_NETWORK_DRIVER_INF,
    APPLE_NETWORK_DRIVER_CAT,
    APPLE_NETWORK_DRIVER_SYS,
    APPLE_NETWORK_DRIVER_WDF_COINSTALLER,
)
APPLE_BUNDLED_INSTALLER_FILES = (
    APPLE_MOBILE_DEVICE_SUPPORT_MSI,
    *APPLE_USB_DRIVER_PACKAGE_FILES,
    *APPLE_NETWORK_DRIVER_PACKAGE_FILES,
)


class AppleMobileDeviceSupportInstallError(RuntimeError):
    """Raised when desktop cannot launch the bundled Apple support installer."""


@dataclass(frozen=True)
class AppleMobileDeviceSupportStatus:
    is_windows: bool
    apple_service_installed: bool
    usb_driver_installed: bool
    network_driver_installed: bool
    bundled_msi_available: bool
    bundled_usb_driver_available: bool
    bundled_network_driver_available: bool
    missing_bundled_asset_names: tuple[str, ...] = tuple()
    probe_error: str | None = None

    @property
    def is_ready(self) -> bool:
        if not self.is_windows:
            return True
        return (
            self.apple_service_installed
            and self.usb_driver_installed
            and self.network_driver_installed
            and self.probe_error is None
        )

    @property
    def can_install(self) -> bool:
        return self.is_windows and not self.missing_bundled_asset_names

    @property
    def missing_system_components(self) -> tuple[str, ...]:
        missing_components: list[str] = []
        if not self.apple_service_installed:
            missing_components.append("Apple Mobile Device Support service")
        if not self.usb_driver_installed:
            missing_components.append(f"Apple USB driver ({APPLE_USB_DRIVER_INF})")
        if not self.network_driver_installed:
            missing_components.append(f"Apple network driver ({APPLE_NETWORK_DRIVER_INF})")
        if self.probe_error:
            missing_components.append(self.probe_error)
        return tuple(missing_components)

    @property
    def missing_bundled_assets(self) -> tuple[str, ...]:
        return self.missing_bundled_asset_names


class AppleMobileDeviceSupportManager:
    def __init__(
        self,
        *,
        platform: str | None = None,
        command_runner: Callable[[list[str]], subprocess.CompletedProcess[str]] | None = None,
        shell_execute_runner: Callable[[str, str], int] | None = None,
        temp_dir_factory: Callable[[], str] | None = None,
        installer_log_path_factory: Callable[[], Path] | None = None,
        resource_exists: Callable[[str], bool] | None = None,
        resource_copier: Callable[[str, Path], Path] | None = None,
    ):
        self._platform = platform or sys.platform
        self._command_runner = command_runner or _run_command
        self._shell_execute_runner = shell_execute_runner or _run_shell_execute
        self._temp_dir_factory = temp_dir_factory or _create_temp_dir
        self._installer_log_path_factory = installer_log_path_factory or _create_installer_log_path
        self._resource_exists = resource_exists or _resource_exists
        self._resource_copier = resource_copier or _copy_resource_to_dir

    def probe(self) -> AppleMobileDeviceSupportStatus:
        missing_bundled_assets = _missing_bundled_assets(self._resource_exists)
        if self._platform != "win32":
            return AppleMobileDeviceSupportStatus(
                is_windows=False,
                apple_service_installed=True,
                usb_driver_installed=True,
                network_driver_installed=True,
                bundled_msi_available=self._resource_exists(APPLE_MOBILE_DEVICE_SUPPORT_MSI),
                bundled_usb_driver_available=self._resource_exists(APPLE_USB_DRIVER_INF),
                bundled_network_driver_available=self._resource_exists(APPLE_NETWORK_DRIVER_INF),
                missing_bundled_asset_names=missing_bundled_assets,
            )

        probe_error: str | None = None
        try:
            driver_inventory = self._enumerate_installed_drivers()
        except (OSError, subprocess.SubprocessError) as exc:
            probe_error = (
                "Desktop could not verify the installed Apple USB drivers. "
                "Use Install to repair the desktop Apple support components."
            )
            driver_inventory = ""
            log(
                "warning",
                message=f"AppleMobileDeviceSupportManager/probe: driver probe failed: {exc}",
            )

        status = AppleMobileDeviceSupportStatus(
            is_windows=True,
            apple_service_installed=self._apple_service_installed(),
            usb_driver_installed=_driver_original_name_installed(
                driver_inventory,
                APPLE_USB_DRIVER_INF,
            ),
            network_driver_installed=_driver_original_name_installed(
                driver_inventory,
                APPLE_NETWORK_DRIVER_INF,
            ),
            bundled_msi_available=self._resource_exists(APPLE_MOBILE_DEVICE_SUPPORT_MSI),
            bundled_usb_driver_available=self._resource_exists(APPLE_USB_DRIVER_INF),
            bundled_network_driver_available=self._resource_exists(APPLE_NETWORK_DRIVER_INF),
            missing_bundled_asset_names=missing_bundled_assets,
            probe_error=probe_error,
        )
        log(
            "info",
            message=(
                "AppleMobileDeviceSupportManager/probe: "
                f"service={status.apple_service_installed} "
                f"usb_driver={status.usb_driver_installed} "
                f"net_driver={status.network_driver_installed} "
                f"missing_bundle_assets={status.missing_bundled_assets or ('none',)} "
                f"bundle_ready={status.can_install} "
                f"ready={status.is_ready}"
            ),
        )
        return status

    def launch_installer(self) -> None:
        status = self.probe()
        if not status.is_windows:
            raise AppleMobileDeviceSupportInstallError(
                "Apple Mobile Device Support installation is only available on Windows.",
            )
        if not status.can_install:
            missing_assets = ", ".join(status.missing_bundled_assets)
            raise AppleMobileDeviceSupportInstallError(
                "Desktop is missing bundled Apple support setup files: "
                f"{missing_assets}.",
            )

        staging_dir = Path(self._temp_dir_factory())
        installer_log_path = self._installer_log_path_factory()
        launched = False
        try:
            staged_msi_path = self._resource_copier(
                APPLE_MOBILE_DEVICE_SUPPORT_MSI,
                staging_dir,
            )
            staged_usb_driver_path = self._resource_copier(
                APPLE_USB_DRIVER_INF,
                staging_dir,
            )
            staged_network_driver_path = self._resource_copier(
                APPLE_NETWORK_DRIVER_INF,
                staging_dir,
            )
            for asset_name in APPLE_BUNDLED_INSTALLER_FILES:
                if asset_name in (
                    APPLE_MOBILE_DEVICE_SUPPORT_MSI,
                    APPLE_USB_DRIVER_INF,
                    APPLE_NETWORK_DRIVER_INF,
                ):
                    continue
                self._resource_copier(asset_name, staging_dir)
            command = _build_elevated_install_command(
                staging_dir=staging_dir,
                staged_msi_path=staged_msi_path,
                staged_usb_driver_path=staged_usb_driver_path,
                staged_network_driver_path=staged_network_driver_path,
                installer_log_path=installer_log_path,
            )
            launch_result = self._shell_execute_runner("powershell.exe", command)
            if launch_result <= 32:
                raise AppleMobileDeviceSupportInstallError(
                    _shell_execute_error_message(launch_result),
                )
            launched = True
        finally:
            if not launched:
                shutil.rmtree(staging_dir, ignore_errors=True)

        log(
            "info",
            message=(
                "AppleMobileDeviceSupportManager/launch_installer: launched elevated install "
                f"from {staging_dir} diagnostics_log={installer_log_path}"
            ),
        )

    def _apple_service_installed(self) -> bool:
        result = self._command_runner(
            ["sc.exe", "query", APPLE_MOBILE_DEVICE_SERVICE_NAME],
        )
        return result.returncode == 0 and "SERVICE_NAME" in result.stdout

    def _enumerate_installed_drivers(self) -> str:
        result = self._command_runner(["pnputil.exe", "/enum-drivers"])
        if result.returncode != 0:
            stderr_text = result.stderr.strip()
            raise subprocess.SubprocessError(
                stderr_text or "pnputil.exe /enum-drivers failed.",
            )
        return result.stdout


def _build_elevated_install_command(
    *,
    staging_dir: Path,
    staged_msi_path: Path,
    staged_usb_driver_path: Path,
    staged_network_driver_path: Path,
    installer_log_path: Path,
) -> str:
    script = "\n".join(
        [
            "$ErrorActionPreference = 'Stop'",
            f"$stageDir = {_powershell_string_literal(staging_dir)}",
            f"$msiPath = {_powershell_string_literal(staged_msi_path)}",
            f"$usbDriverPath = {_powershell_string_literal(staged_usb_driver_path)}",
            f"$networkDriverPath = {_powershell_string_literal(staged_network_driver_path)}",
            f"$installerLogPath = {_powershell_string_literal(installer_log_path)}",
            "$installerLogDir = Split-Path -Parent $installerLogPath",
            "if ($installerLogDir -and -not (Test-Path -LiteralPath $installerLogDir)) {",
            "    New-Item -ItemType Directory -Path $installerLogDir -Force | Out-Null",
            "}",
            "function Write-InstallLog([string]$message) {",
            "    Add-Content -LiteralPath $installerLogPath -Encoding UTF8 -Value ((Get-Date -Format o) + ' ' + $message)",
            "}",
            "try {",
            "    Write-InstallLog \"Starting Apple Mobile Device Support install.\"",
            "    Write-InstallLog \"Stage directory: $stageDir\"",
            "    Write-InstallLog \"MSI path: $msiPath\"",
            "    Write-InstallLog \"USB driver path: $usbDriverPath\"",
            "    Write-InstallLog \"Network driver path: $networkDriverPath\"",
            "    $installer = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $msiPath, '/quiet', '/norestart') -Wait -PassThru",
            "    Write-InstallLog \"msiexec exit code: $($installer.ExitCode)\"",
            "    if ($installer.ExitCode -ne 0) { throw \"Apple Mobile Device Support installer exited with code $($installer.ExitCode).\" }",
            "    $usbDriverOutput = & pnputil.exe /add-driver $usbDriverPath /install 2>&1",
            "    if ($usbDriverOutput) { Write-InstallLog ((\"Apple USB pnputil output:`n\" + ($usbDriverOutput | Out-String)).TrimEnd()) }",
            "    Write-InstallLog \"Apple USB pnputil exit code: $LASTEXITCODE\"",
            "    if ($LASTEXITCODE -ne 0) { throw \"Installing Apple USB driver failed with exit code $LASTEXITCODE.\" }",
            "    $networkDriverOutput = & pnputil.exe /add-driver $networkDriverPath /install 2>&1",
            "    if ($networkDriverOutput) { Write-InstallLog ((\"Apple network pnputil output:`n\" + ($networkDriverOutput | Out-String)).TrimEnd()) }",
            "    Write-InstallLog \"Apple network pnputil exit code: $LASTEXITCODE\"",
            "    if ($LASTEXITCODE -ne 0) { throw \"Installing Apple network driver failed with exit code $LASTEXITCODE.\" }",
            "    $postInstallDriverInventory = & pnputil.exe /enum-drivers 2>&1",
            "    if ($postInstallDriverInventory) { Write-InstallLog ((\"Post-install driver inventory excerpt:`n\" + ($postInstallDriverInventory | Out-String)).TrimEnd()) }",
            "    Write-InstallLog (\"Post-install driver status: usb=\" + ($postInstallDriverInventory -match 'Original Name:\\s*usbaapl64\\.inf\\b') + ' network=' + ($postInstallDriverInventory -match 'Original Name:\\s*netaapl64\\.inf\\b'))",
            "    Write-InstallLog 'Apple Mobile Device Support install completed.'",
            "} catch {",
            "    Write-InstallLog ((\"Installer error: \" + $_.Exception.Message).TrimEnd())",
            "    Write-InstallLog ((\"Installer error detail:`n\" + ($_ | Out-String)).TrimEnd())",
            "    throw",
            "}",
            "finally {",
            "    Write-InstallLog 'Cleaning installer staging directory.'",
            "    if (Test-Path -LiteralPath $stageDir) {",
            "        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue",
            "    }",
            "}",
        ]
    )
    encoded_script = base64.b64encode(script.encode("utf-16le")).decode("ascii")
    return f"-NoProfile -ExecutionPolicy Bypass -EncodedCommand {encoded_script}"


def _run_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="ignore",
    )


def _run_shell_execute(file_path: str, parameters: str) -> int:
    import ctypes

    return int(
        ctypes.windll.shell32.ShellExecuteW(
            None,
            "runas",
            file_path,
            parameters,
            None,
            1,
        )
    )


def _create_temp_dir() -> str:
    return tempfile.mkdtemp(prefix="dtis-apple-mobile-support-")


def _create_installer_log_path() -> Path:
    log_dir = get_app_data_path(get_context()) / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix="apple-mobile-support-install-",
        suffix=".log",
        dir=log_dir,
        delete=False,
    ) as installer_log_file:
        return Path(installer_log_file.name)


def _resource_exists(file_name: str) -> bool:
    return files("dt_image_search").joinpath("resources", file_name).is_file()


def _copy_resource_to_dir(file_name: str, destination_dir: Path) -> Path:
    destination_dir.mkdir(parents=True, exist_ok=True)
    resource = files("dt_image_search").joinpath("resources", file_name)
    if not resource.is_file():
        raise AppleMobileDeviceSupportInstallError(
            f"Desktop bundle does not include '{file_name}'.",
        )
    destination_path = destination_dir / file_name
    with as_file(resource) as source_path:
        shutil.copy2(Path(source_path), destination_path)
    return destination_path


def _driver_original_name_installed(driver_inventory: str, original_name: str) -> bool:
    return (
        re.search(
            rf"Original Name:\s*{re.escape(original_name)}\b",
            driver_inventory,
            flags=re.IGNORECASE,
        )
        is not None
    )


def _missing_bundled_assets(resource_exists: Callable[[str], bool]) -> tuple[str, ...]:
    return tuple(
        asset_name
        for asset_name in APPLE_BUNDLED_INSTALLER_FILES
        if not resource_exists(asset_name)
    )


def _powershell_string_literal(path: Path) -> str:
    return "'" + str(path).replace("'", "''") + "'"


def _shell_execute_error_message(shell_execute_result: int) -> str:
    shell_execute_errors = {
        0: "Desktop could not launch the elevated Apple support installer.",
        2: "Desktop could not find PowerShell to launch the Apple support installer.",
        3: "Desktop could not find the elevated Apple support installer path.",
        5: "Windows denied the elevated Apple support installer request.",
        8: "Windows ran out of memory while launching the Apple support installer.",
        26: "Desktop could not share the elevated Apple support installer command.",
        27: "The file association for the elevated Apple support installer is incomplete.",
        28: "Windows timed out while launching the elevated Apple support installer.",
        29: "Desktop could not launch the elevated Apple support installer because the DDE transaction failed.",
        30: "Desktop could not launch the elevated Apple support installer because another DDE transaction is busy.",
        31: "Desktop could not launch the elevated Apple support installer because no file association is registered.",
        32: "Desktop could not launch the elevated Apple support installer because the file is busy.",
        1223: "The elevated Apple support installer was cancelled at the Windows admin prompt.",
    }
    return shell_execute_errors.get(
        shell_execute_result,
        (
            "Desktop could not launch the elevated Apple support installer "
            f"(Windows code {shell_execute_result})."
        ),
    )
