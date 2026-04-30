import argparse
import datetime as dt
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable

project_root = Path(__file__).resolve().parents[2]
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from dt_image_search.mobile.transport.usb_tunnel import (
    Pymobiledevice3UsbTunnelProvider,
    UsbConnectedDevice,
    UsbTunnelConnectError,
    UsbTunnelUnavailableError,
)
from pymobiledevice3 import usbmux as usbmux_module
from pymobiledevice3.lockdown import LockdownClient
from pymobiledevice3.services.syslog import SyslogService

DEFAULT_FILTER_TERMS = [
    "AlbumTransporterKit",
    "AlbumTransporterApp",
    "AuBackup",
    "USBTransport",
    "USBRuntime",
    "AdaptiveTransfer",
    "MobileTransfer",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Capture iOS syslog lines to a local file using pymobiledevice3. "
            "By default this stores only AuBackup mobile-folder related lines."
        )
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("ios-mobile-folder.log"),
        help="Output file path.",
    )
    parser.add_argument(
        "--udid",
        default="",
        help="Optional device UDID. If omitted, uses the first detected USB device.",
    )
    parser.add_argument(
        "--duration-seconds",
        type=int,
        default=0,
        help="Optional capture duration in seconds. Use 0 to run until Ctrl+C.",
    )
    parser.add_argument(
        "--contains",
        action="append",
        default=[],
        help="Additional substring filter (repeatable).",
    )
    parser.add_argument(
        "--all-lines",
        action="store_true",
        help="Disable filtering and capture every syslog line.",
    )
    parser.add_argument(
        "--echo",
        action="store_true",
        help="Echo captured lines to stdout while writing the file.",
    )
    parser.add_argument(
        "--diagnose-only",
        action="store_true",
        help="Print USB/usbmux diagnostics and exit without starting log capture.",
    )
    return parser.parse_args()


def _usbmux_host() -> tuple[str, int] | None:
    mux_connection_type = getattr(usbmux_module, "MuxConnection", None)
    usbmux_host = getattr(mux_connection_type, "ITUNES_HOST", None)
    if (
        isinstance(usbmux_host, tuple)
        and len(usbmux_host) == 2
        and isinstance(usbmux_host[0], str)
        and isinstance(usbmux_host[1], int)
    ):
        return usbmux_host
    return None


def _probe_usbmux_endpoint() -> str:
    host = _usbmux_host()
    if host is None:
        return "unknown (pymobiledevice3 did not expose MuxConnection.ITUNES_HOST)"

    probe_socket: socket.socket | None = None
    try:
        probe_socket = socket.create_connection(host, timeout=0.5)
    except OSError as error:
        return f"{host[0]}:{host[1]} unreachable ({type(error).__name__}: {error})"
    finally:
        if probe_socket is not None:
            probe_socket.close()
    return f"{host[0]}:{host[1]} reachable"


def _windows_service_state(display_name: str) -> str:
    if sys.platform not in ("win32", "cygwin"):
        return "n/a"
    result = subprocess.run(
        ["sc.exe", "query", display_name],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return "not found"
    for line in result.stdout.splitlines():
        if "STATE" not in line:
            continue
        _, _, state = line.partition(":")
        return " ".join(state.split())
    return "unknown"


def _ensure_usbmux_stream_compat() -> None:
    safe_stream_socket_type = getattr(usbmux_module, "SafeStreamSocket", None)
    if not isinstance(safe_stream_socket_type, type):
        return
    tell_method = getattr(safe_stream_socket_type, "tell", None)
    if callable(tell_method):
        return

    def _tell(_self: object) -> int:
        return 0

    setattr(safe_stream_socket_type, "tell", _tell)


def _discover_usb_devices() -> tuple[UsbConnectedDevice, ...]:
    provider = Pymobiledevice3UsbTunnelProvider()
    try:
        return provider.list_usb_devices()
    except UsbTunnelConnectError as error:
        diagnostics = [
            str(error),
            "Diagnostics:",
            f"- usbmux endpoint: {_probe_usbmux_endpoint()}",
        ]
        if sys.platform in ("win32", "cygwin"):
            diagnostics.append(
                "- Apple Mobile Device Service: "
                + _windows_service_state("Apple Mobile Device Service")
            )
        raise RuntimeError("\n".join(diagnostics)) from error
    except UsbTunnelUnavailableError as error:
        raise RuntimeError(str(error)) from error


def _discover_all_mux_devices() -> tuple[UsbConnectedDevice, ...]:
    _ensure_usbmux_stream_compat()
    try:
        raw_devices = usbmux_module.list_devices()
    except Exception:
        return tuple()

    normalized_devices: list[UsbConnectedDevice] = []
    for raw_device in raw_devices:
        serial = str(getattr(raw_device, "serial", "")).strip()
        if not serial:
            continue
        connection_type = str(getattr(raw_device, "connection_type", "") or "Unknown")
        normalized_devices.append(
            UsbConnectedDevice(
                udid=serial,
                connection_type=connection_type,
            )
        )
    return tuple(normalized_devices)


def _device_udid(device: UsbConnectedDevice) -> str:
    return device.udid.strip()


def _build_no_device_message(all_mux_devices: tuple[UsbConnectedDevice, ...]) -> str:
    message_lines = [
        "No USB iOS devices were detected via usbmuxd/iTunes.",
        "Diagnostics:",
        f"- usbmux endpoint: {_probe_usbmux_endpoint()}",
        f"- all usbmux-visible devices: {len(all_mux_devices)}",
    ]
    for device in all_mux_devices:
        message_lines.append(
            f"  - udid={device.udid} connection_type={device.connection_type}"
        )
    if sys.platform in ("win32", "cygwin"):
        message_lines.append(
            "- Apple Mobile Device Service: "
            + _windows_service_state("Apple Mobile Device Service")
        )
        message_lines.append("Next steps:")
        message_lines.append("1. Reconnect the iPhone, unlock it, and tap Trust if prompted.")
        message_lines.append("2. Ensure iTunes or Apple Devices app can see the iPhone.")
        message_lines.append(
            "3. Restart Apple Mobile Device Service, then rerun with --diagnose-only."
        )
    return "\n".join(message_lines)


def _pick_device_udid(
    usb_devices: Iterable[UsbConnectedDevice],
    all_mux_devices: tuple[UsbConnectedDevice, ...],
    requested_udid: str,
) -> tuple[str, str]:
    known_devices = list(usb_devices)
    if requested_udid:
        return requested_udid, "USB"
    if known_devices:
        discovered_udid = _device_udid(known_devices[0])
        if discovered_udid:
            return discovered_udid, known_devices[0].connection_type or "USB"

    if len(all_mux_devices) == 1:
        fallback_device = all_mux_devices[0]
        fallback_udid = _device_udid(fallback_device)
        if fallback_udid:
            print(
                "No USB-labelled devices were found; falling back to the only usbmux-visible device "
                f"(udid={fallback_udid}, connection_type={fallback_device.connection_type}).",
                file=sys.stderr,
            )
            return fallback_udid, fallback_device.connection_type or "Unknown"

    if len(all_mux_devices) > 1:
        message_lines = [
            "No USB-labelled devices were found, but usbmux can see non-USB devices.",
            "Re-run with --udid <device-udid> using one of:",
        ]
        for device in all_mux_devices:
            message_lines.append(
                f"- {device.udid} (connection_type={device.connection_type})"
            )
        raise RuntimeError("\n".join(message_lines))

    raise RuntimeError(_build_no_device_message(all_mux_devices))


def _lockdown_connection_type(connection_type: str) -> str | None:
    normalized = connection_type.strip().lower()
    if normalized == "usb":
        return "USB"
    if normalized == "network":
        return "Network"
    return None


def _should_keep_line(line: str, filter_terms: list[str], capture_all_lines: bool) -> bool:
    if capture_all_lines:
        return True
    if not filter_terms:
        return True
    return any(term in line for term in filter_terms)


def _print_diagnostics(
    *,
    discovered_usb_devices: tuple[UsbConnectedDevice, ...],
    all_mux_devices: tuple[UsbConnectedDevice, ...],
    requested_udid: str,
) -> None:
    print("USB diagnostics:", file=sys.stderr)
    print(f"- usbmux endpoint: {_probe_usbmux_endpoint()}", file=sys.stderr)
    if sys.platform in ("win32", "cygwin"):
        print(
            "- Apple Mobile Device Service: "
            + _windows_service_state("Apple Mobile Device Service"),
            file=sys.stderr,
        )
    if requested_udid:
        print(f"- requested udid: {requested_udid}", file=sys.stderr)
    print(f"- detected USB devices: {len(discovered_usb_devices)}", file=sys.stderr)
    for device in discovered_usb_devices:
        print(
            f"  - udid={device.udid} connection_type={device.connection_type}",
            file=sys.stderr,
        )
    print(f"- all usbmux-visible devices: {len(all_mux_devices)}", file=sys.stderr)
    for device in all_mux_devices:
        print(
            f"  - udid={device.udid} connection_type={device.connection_type}",
            file=sys.stderr,
        )


def run_capture(args: argparse.Namespace) -> int:
    requested_udid = args.udid.strip()
    discovered_usb_devices: tuple[UsbConnectedDevice, ...] = tuple()
    all_mux_devices: tuple[UsbConnectedDevice, ...] = tuple()
    if args.diagnose_only or not requested_udid:
        discovered_usb_devices = _discover_usb_devices()
        all_mux_devices = _discover_all_mux_devices()

    if args.diagnose_only:
        _print_diagnostics(
            discovered_usb_devices=discovered_usb_devices,
            all_mux_devices=all_mux_devices,
            requested_udid=requested_udid,
        )
        if not requested_udid and not discovered_usb_devices and not all_mux_devices:
            print(_build_no_device_message(all_mux_devices), file=sys.stderr)
            return 1
        return 0

    filter_terms = [] if args.all_lines else [*DEFAULT_FILTER_TERMS, *args.contains]
    selected_udid, selected_connection_type = _pick_device_udid(
        discovered_usb_devices,
        all_mux_devices,
        requested_udid,
    )
    output_path = args.output.expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    deadline = (
        time.monotonic() + args.duration_seconds
        if args.duration_seconds > 0
        else None
    )

    print(
        f"Capturing iOS syslog to {output_path} "
        f"(udid={selected_udid}, filter={'none' if args.all_lines else 'default+custom'})",
        file=sys.stderr,
    )

    with output_path.open("a", encoding="utf-8", buffering=1) as sink:
        sink.write(
            f"# capture-start {dt.datetime.now(dt.timezone.utc).isoformat()} udid={selected_udid}\n"
        )
        try:
            with LockdownClient(
                serial=selected_udid,
                usbmux_connection_type=_lockdown_connection_type(selected_connection_type),
            ) as lockdown:
                syslog_service = SyslogService(lockdown)
                for line in syslog_service.watch():
                    text_line = line.rstrip("\r\n")
                    if not _should_keep_line(text_line, filter_terms, args.all_lines):
                        if deadline is not None and time.monotonic() >= deadline:
                            break
                        continue

                    timestamp = dt.datetime.now().isoformat(timespec="seconds")
                    formatted_line = f"{timestamp} {text_line}"
                    sink.write(formatted_line + "\n")
                    if args.echo:
                        print(formatted_line)

                    if deadline is not None and time.monotonic() >= deadline:
                        break
        except Exception as error:
            raise RuntimeError(
                f"Failed to start syslog capture for iPhone '{selected_udid}': "
                f"{type(error).__name__}: {error}"
            ) from error

        sink.write(f"# capture-stop {dt.datetime.now(dt.timezone.utc).isoformat()}\n")

    return 0


def main() -> int:
    args = parse_args()
    try:
        return run_capture(args)
    except KeyboardInterrupt:
        print("Stopped by user.", file=sys.stderr)
        return 130
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    except Exception as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
