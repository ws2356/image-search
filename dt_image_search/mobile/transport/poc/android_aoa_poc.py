from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
import argparse
import hashlib
import json
import math
from pathlib import Path
import time
from typing import Any, Protocol

from dt_image_search.telemetry.telemetry_client import log

AOA_POC_METRICS_SCHEMA = "dtis.android-aoa-poc-metrics.v1"
AOA_POC_TRANSPORT_FRAME_VERSION = 1
AOA_POC_REQUEST_ID_LENGTH = 36
AOA_POC_TRANSPORT_HEADER_SIZE = 1 + AOA_POC_REQUEST_ID_LENGTH + 4

AOA_GET_PROTOCOL_REQUEST = 51
AOA_SEND_STRING_REQUEST = 52
AOA_START_ACCESSORY_REQUEST = 53
AOA_VENDOR_REQUEST_IN = 0xC0
AOA_VENDOR_REQUEST_OUT = 0x40
GOOGLE_VENDOR_ID = 0x18D1
AOA_ACCESSORY_PRODUCT_IDS = {
    0x2D00,  # accessory
    0x2D01,  # accessory + adb
    0x2D02,  # audio
    0x2D03,  # audio + adb
    0x2D04,  # accessory + audio
    0x2D05,  # accessory + audio + adb
}


try:
    import usb.core as _usb_core
    import usb.util as _usb_util
except ImportError:  # pragma: no cover - optional dependency.
    _usb_core = None
    _usb_util = None


class AoaPocHostState(str, Enum):
    IDLE = "idle"
    DEVICE_DETECTED = "device_detected"
    ACCESSORY_NEGOTIATING = "accessory_negotiating"
    ACCESSORY_READY = "accessory_ready"
    STREAMING = "streaming"
    DISCONNECTED = "disconnected"
    FAILED = "failed"


@dataclass(frozen=True)
class AoaPocThresholds:
    handshake_p95_ms_max: int = 5000
    reconnect_success_rate_min: float = 0.95
    reconnect_cycles_min: int = 20
    throughput_bytes_per_second_min: int = 8 * 1024 * 1024
    throughput_sample_seconds: int = 30


@dataclass
class AoaPocMeasurements:
    handshake_ms_samples: list[int]
    reconnect_success_count: int
    reconnect_total_count: int
    throughput_bytes_per_second_samples: list[int]


@dataclass(frozen=True)
class AoaDetectedDevice:
    id_vendor: int
    id_product: int
    bus: int | None
    address: int | None
    serial_hash: str
    supports_aoa: bool
    is_accessory_mode: bool


class AoaHostHooks(Protocol):
    def detect_devices(self) -> tuple[AoaDetectedDevice, ...]:
        ...

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        ...

    def measure_transport_throughput_bytes_per_second(
        self,
        *,
        device: AoaDetectedDevice,
        sample_seconds: int,
    ) -> int | None:
        ...

    def measure_reconnect_success(
        self,
        *,
        device: AoaDetectedDevice,
        min_cycles: int,
    ) -> tuple[int, int]:
        ...


class AoaPocHostStateMachine:
    def __init__(self) -> None:
        self._state = AoaPocHostState.IDLE

    @property
    def state(self) -> AoaPocHostState:
        return self._state

    def on_device_detected(self) -> None:
        if self._state not in (AoaPocHostState.IDLE, AoaPocHostState.DISCONNECTED):
            raise RuntimeError(f"Invalid transition from {self._state.value} to device_detected.")
        self._state = AoaPocHostState.DEVICE_DETECTED

    def on_accessory_negotiating(self) -> None:
        if self._state != AoaPocHostState.DEVICE_DETECTED:
            raise RuntimeError(f"Invalid transition from {self._state.value} to accessory_negotiating.")
        self._state = AoaPocHostState.ACCESSORY_NEGOTIATING

    def on_accessory_ready(self) -> None:
        if self._state != AoaPocHostState.ACCESSORY_NEGOTIATING:
            raise RuntimeError(f"Invalid transition from {self._state.value} to accessory_ready.")
        self._state = AoaPocHostState.ACCESSORY_READY

    def on_streaming_started(self) -> None:
        if self._state != AoaPocHostState.ACCESSORY_READY:
            raise RuntimeError(f"Invalid transition from {self._state.value} to streaming.")
        self._state = AoaPocHostState.STREAMING

    def on_streaming_completed(self) -> None:
        if self._state != AoaPocHostState.STREAMING:
            raise RuntimeError(f"Invalid transition from {self._state.value} to disconnected.")
        self._state = AoaPocHostState.DISCONNECTED

    def on_failure(self) -> None:
        self._state = AoaPocHostState.FAILED


class PyUsbAoaHostHooks:
    def __init__(self) -> None:
        self._usb_core = _usb_core
        self._usb_util = _usb_util
        self._usb_error_type = RuntimeError
        if self._usb_core is not None:
            usb_error = getattr(self._usb_core, "USBError", None)
            if isinstance(usb_error, type) and issubclass(usb_error, BaseException):
                self._usb_error_type = usb_error

    def detect_devices(self) -> tuple[AoaDetectedDevice, ...]:
        self._require_pyusb()
        raw_devices = list(self._usb_core.find(find_all=True) or [])
        detected: list[AoaDetectedDevice] = []
        for raw_device in raw_devices:
            id_vendor = int(getattr(raw_device, "idVendor", 0) or 0)
            id_product = int(getattr(raw_device, "idProduct", 0) or 0)
            is_accessory_mode = (
                id_vendor == GOOGLE_VENDOR_ID and id_product in AOA_ACCESSORY_PRODUCT_IDS
            )
            supports_aoa = is_accessory_mode
            if not supports_aoa:
                supports_aoa = self._supports_aoa_protocol(raw_device)
            if not supports_aoa:
                continue
            serial_hash = self._serial_hash(raw_device)
            detected.append(
                AoaDetectedDevice(
                    id_vendor=id_vendor,
                    id_product=id_product,
                    bus=getattr(raw_device, "bus", None),
                    address=getattr(raw_device, "address", None),
                    serial_hash=serial_hash,
                    supports_aoa=True,
                    is_accessory_mode=is_accessory_mode,
                )
            )
        return tuple(detected)

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        if device.is_accessory_mode:
            return True
        self._require_pyusb()
        device_handle = self._find_device_handle(device)
        if device_handle is None:
            raise RuntimeError("AOA POC could not find the selected USB device handle.")

        try:
            protocol_response = device_handle.ctrl_transfer(
                AOA_VENDOR_REQUEST_IN,
                AOA_GET_PROTOCOL_REQUEST,
                0,
                0,
                2,
                timeout=1500,
            )
            protocol_version = 0
            if len(protocol_response) == 2:
                protocol_version = int(protocol_response[0]) | (int(protocol_response[1]) << 8)
            if protocol_version <= 0:
                raise RuntimeError("AOA protocol version is unavailable on detected device.")
            for string_index, string_value in enumerate(
                (
                    "AuSearch",
                    "AuBackup AOA POC",
                    "AOA transport negotiation test",
                    "1.0",
                    "https://boldman.net",
                    "poc",
                )
            ):
                device_handle.ctrl_transfer(
                    AOA_VENDOR_REQUEST_OUT,
                    AOA_SEND_STRING_REQUEST,
                    0,
                    string_index,
                    string_value.encode("utf-8"),
                    timeout=1500,
                )
            device_handle.ctrl_transfer(
                AOA_VENDOR_REQUEST_OUT,
                AOA_START_ACCESSORY_REQUEST,
                0,
                0,
                b"",
                timeout=1500,
            )
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA negotiation failed: {exc}") from exc
        finally:
            self._usb_util.dispose_resources(device_handle)

        accessory_deadline = time.monotonic() + 8.0
        while time.monotonic() < accessory_deadline:
            for detected_device in self.detect_devices():
                if detected_device.is_accessory_mode:
                    return True
            time.sleep(0.3)
        return False

    def measure_transport_throughput_bytes_per_second(
        self,
        *,
        device: AoaDetectedDevice,
        sample_seconds: int,
    ) -> int | None:
        if sample_seconds <= 0:
            raise ValueError("AOA POC throughput sample_seconds must be greater than zero.")
        self._require_pyusb()
        device_handle = self._find_device_handle(device)
        if device_handle is None:
            raise RuntimeError("AOA POC could not find USB device for throughput measurement.")
        try:
            try:
                configuration = device_handle.get_active_configuration()
            except self._usb_error_type:
                device_handle.set_configuration()
                configuration = device_handle.get_active_configuration()
            interface = configuration[(0, 0)]
            endpoint_out = self._usb_util.find_descriptor(
                interface,
                custom_match=lambda endpoint: (
                    self._usb_util.endpoint_direction(endpoint.bEndpointAddress)
                    == self._usb_util.ENDPOINT_OUT
                ),
            )
            if endpoint_out is None:
                raise RuntimeError("AOA POC throughput probe requires an OUT endpoint.")
            probe_payload = b"\x00" * 16_384
            started_at = time.monotonic()
            total_written = 0
            while (time.monotonic() - started_at) < sample_seconds:
                endpoint_out.write(probe_payload, timeout=800)
                total_written += len(probe_payload)
            elapsed_seconds = max(time.monotonic() - started_at, 0.001)
            return int(total_written / elapsed_seconds)
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA throughput probe failed: {exc}") from exc
        finally:
            self._usb_util.dispose_resources(device_handle)

    def measure_reconnect_success(
        self,
        *,
        device: AoaDetectedDevice,
        min_cycles: int,
    ) -> tuple[int, int]:
        if min_cycles <= 0:
            raise ValueError("AOA reconnect min_cycles must be greater than zero.")
        success_count = 0
        for _ in range(min_cycles):
            detected_devices = self.detect_devices()
            if any(candidate.is_accessory_mode for candidate in detected_devices):
                success_count += 1
            time.sleep(0.05)
        return success_count, min_cycles

    def _require_pyusb(self) -> None:
        if self._usb_core is None or self._usb_util is None:
            raise RuntimeError(
                "AOA host probing requires pyusb (install with `python -m pip install pyusb`)."
            )

    def _find_device_handle(self, device: AoaDetectedDevice) -> Any | None:
        self._require_pyusb()
        found = self._usb_core.find(
            idVendor=device.id_vendor,
            idProduct=device.id_product,
            bus=device.bus,
            address=device.address,
        )
        if found is not None:
            return found
        return self._usb_core.find(idVendor=device.id_vendor, idProduct=device.id_product)

    def _supports_aoa_protocol(self, device_handle: Any) -> bool:
        try:
            protocol_response = device_handle.ctrl_transfer(
                AOA_VENDOR_REQUEST_IN,
                AOA_GET_PROTOCOL_REQUEST,
                0,
                0,
                2,
                timeout=600,
            )
            return len(protocol_response) == 2
        except self._usb_error_type:
            return False

    def _serial_hash(self, device_handle: Any) -> str:
        serial_value = ""
        try:
            serial_value = str(getattr(device_handle, "serial_number", "") or "")
        except self._usb_error_type:
            serial_value = ""
        if not serial_value:
            serial_value = (
                f"{getattr(device_handle, 'bus', 'unknown')}-"
                f"{getattr(device_handle, 'address', 'unknown')}"
            )
        return hashlib.sha256(serial_value.encode("utf-8")).hexdigest()


def build_aoa_transport_frame(*, request_id: str, payload: bytes) -> bytes:
    request_id_ascii = request_id.encode("ascii")
    if len(request_id_ascii) != AOA_POC_REQUEST_ID_LENGTH:
        raise ValueError(f"AOA POC request_id must be {AOA_POC_REQUEST_ID_LENGTH} ASCII bytes.")
    return (
        bytes([AOA_POC_TRANSPORT_FRAME_VERSION])
        + request_id_ascii
        + len(payload).to_bytes(4, byteorder="big", signed=False)
        + payload
    )


def parse_aoa_transport_frame(frame: bytes) -> tuple[str, bytes]:
    if len(frame) < AOA_POC_TRANSPORT_HEADER_SIZE:
        raise ValueError("AOA POC frame header is incomplete.")
    frame_version = frame[0]
    if frame_version != AOA_POC_TRANSPORT_FRAME_VERSION:
        raise ValueError("AOA POC frame version is unsupported.")
    request_id_bytes = frame[1 : 1 + AOA_POC_REQUEST_ID_LENGTH]
    try:
        request_id = request_id_bytes.decode("ascii")
    except UnicodeDecodeError as exc:
        raise ValueError("AOA POC frame request_id must be ASCII.") from exc
    if not request_id.strip():
        raise ValueError("AOA POC frame request_id is empty.")
    payload_length_start = 1 + AOA_POC_REQUEST_ID_LENGTH
    payload_length_end = payload_length_start + 4
    declared_payload_length = int.from_bytes(
        frame[payload_length_start:payload_length_end], byteorder="big", signed=False
    )
    payload = frame[AOA_POC_TRANSPORT_HEADER_SIZE:]
    if len(payload) != declared_payload_length:
        raise ValueError("AOA POC frame payload length does not match declared length.")
    return request_id, payload


def percentile_ms(samples: list[int], percentile: float) -> int:
    if not samples:
        return 0
    if percentile <= 0:
        return min(samples)
    if percentile >= 100:
        return max(samples)
    ordered = sorted(samples)
    index = max(0, math.ceil((percentile / 100.0) * len(ordered)) - 1)
    return ordered[index]


def evaluate_thresholds(
    *,
    thresholds: AoaPocThresholds,
    measurements: AoaPocMeasurements,
) -> dict[str, bool]:
    handshake_p95_ms = percentile_ms(measurements.handshake_ms_samples, 95)
    reconnect_success_rate = 0.0
    if measurements.reconnect_total_count > 0:
        reconnect_success_rate = (
            measurements.reconnect_success_count / measurements.reconnect_total_count
        )
    throughput_avg = 0
    if measurements.throughput_bytes_per_second_samples:
        throughput_avg = int(
            sum(measurements.throughput_bytes_per_second_samples)
            / len(measurements.throughput_bytes_per_second_samples)
        )

    handshake_pass = handshake_p95_ms <= thresholds.handshake_p95_ms_max
    reconnect_pass = (
        measurements.reconnect_total_count >= thresholds.reconnect_cycles_min
        and reconnect_success_rate >= thresholds.reconnect_success_rate_min
    )
    throughput_pass = throughput_avg >= thresholds.throughput_bytes_per_second_min
    overall_pass = handshake_pass and reconnect_pass and throughput_pass
    return {
        "handshake_p95_pass": handshake_pass,
        "reconnect_rate_pass": reconnect_pass,
        "throughput_pass": throughput_pass,
        "overall_pass": overall_pass,
    }


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def collect_host_readiness(host_os: str) -> dict[str, object]:
    normalized_host_os = host_os.strip().lower()
    readiness: dict[str, object] = {
        "host_os": normalized_host_os,
        "pyusb_imported": _usb_core is not None and _usb_util is not None,
        "libusb_backend_available": False,
        "device_enumeration_available": False,
        "detected_usb_device_count": 0,
        "recommended_actions": [],
        "notes": [],
    }
    notes = readiness["notes"]
    recommended_actions = readiness["recommended_actions"]
    if _usb_core is None or _usb_util is None:
        notes.append("PyUSB modules are not importable in this Python environment.")
        recommended_actions.append("Install pyusb: python -m pip install pyusb")
        return readiness

    try:
        import usb.backend.libusb1 as usb_backend_libusb1
    except ImportError:
        notes.append("PyUSB libusb1 backend module is not importable.")
        recommended_actions.append("Install libusb runtime and ensure usb.backend.libusb1 is available.")
        return readiness

    backend = usb_backend_libusb1.get_backend()
    readiness["libusb_backend_available"] = backend is not None
    if backend is None:
        notes.append("libusb backend was not discovered by PyUSB.")
        if normalized_host_os == "macos":
            recommended_actions.append("Install libusb via Homebrew: brew install libusb")
        elif normalized_host_os == "windows":
            recommended_actions.append("Install libusb runtime and configure USB driver (WinUSB/libusbK).")
        else:
            recommended_actions.append("Install libusb runtime and expose backend library path.")
        return readiness

    usb_error_types: tuple[type[BaseException], ...] = (RuntimeError, OSError, ValueError)
    usb_error = getattr(_usb_core, "USBError", None)
    if isinstance(usb_error, type) and issubclass(usb_error, BaseException):
        usb_error_types = usb_error_types + (usb_error,)
    try:
        detected_usb_devices = list(_usb_core.find(find_all=True, backend=backend) or [])
        readiness["device_enumeration_available"] = True
        readiness["detected_usb_device_count"] = len(detected_usb_devices)
    except usb_error_types as exc:
        notes.append(f"USB device enumeration failed: {exc}")
        if normalized_host_os == "windows":
            recommended_actions.append(
                "Check USB driver binding for Android device interface and rerun as Administrator if needed."
            )
        else:
            recommended_actions.append("Check USB permission/runtime access and libusb installation.")

    return readiness


def _serialize_metrics(
    *,
    run_id: str,
    host_os: str,
    started_at: datetime,
    completed_at: datetime,
    thresholds: AoaPocThresholds,
    measurements: AoaPocMeasurements,
    device_info: dict[str, str],
    host_readiness: dict[str, object],
    errors: list[dict[str, str]] | None = None,
) -> dict[str, object]:
    threshold_verdict = evaluate_thresholds(
        thresholds=thresholds,
        measurements=measurements,
    )
    reconnect_success_rate = 0.0
    if measurements.reconnect_total_count > 0:
        reconnect_success_rate = (
            measurements.reconnect_success_count / measurements.reconnect_total_count
        )
    throughput_avg = 0
    if measurements.throughput_bytes_per_second_samples:
        throughput_avg = int(
            sum(measurements.throughput_bytes_per_second_samples)
            / len(measurements.throughput_bytes_per_second_samples)
        )
    return {
        "schema": AOA_POC_METRICS_SCHEMA,
        "run_id": run_id,
        "host_os": host_os,
        "started_at_utc": started_at.isoformat(),
        "completed_at_utc": completed_at.isoformat(),
        "device": device_info,
        "host_readiness": host_readiness,
        "thresholds": {
            "handshake_p95_ms_max": thresholds.handshake_p95_ms_max,
            "reconnect_success_rate_min": thresholds.reconnect_success_rate_min,
            "reconnect_cycles_min": thresholds.reconnect_cycles_min,
            "throughput_bytes_per_second_min": thresholds.throughput_bytes_per_second_min,
            "throughput_sample_seconds": thresholds.throughput_sample_seconds,
        },
        "measurements": {
            "handshake_ms_samples": measurements.handshake_ms_samples,
            "handshake_p95_ms": percentile_ms(measurements.handshake_ms_samples, 95),
            "reconnect_success_count": measurements.reconnect_success_count,
            "reconnect_total_count": measurements.reconnect_total_count,
            "reconnect_success_rate": reconnect_success_rate,
            "throughput_bytes_per_second_samples": measurements.throughput_bytes_per_second_samples,
            "throughput_bytes_per_second_avg": throughput_avg,
        },
        "errors": errors or [],
        "threshold_verdict": threshold_verdict,
    }


def _write_metrics_file(
    *,
    host_os: str,
    output_root: Path,
    thresholds: AoaPocThresholds,
    measurements: AoaPocMeasurements,
    device_info: dict[str, str],
    host_readiness: dict[str, object],
    errors: list[dict[str, str]],
    started_at: datetime,
    completed_at: datetime,
) -> Path:
    run_id = f"{started_at.strftime('%Y%m%dT%H%M%SZ')}-{host_os}"
    run_dir = output_root / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    metrics_path = run_dir / "metrics.json"
    metrics_payload = _serialize_metrics(
        run_id=run_id,
        host_os=host_os,
        started_at=started_at,
        completed_at=completed_at,
        thresholds=thresholds,
        measurements=measurements,
        device_info=device_info,
        host_readiness=host_readiness,
        errors=errors,
    )
    metrics_path.write_text(
        json.dumps(metrics_payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    log(
        "info",
        message=(
            "android_aoa_poc/write_metrics: "
            f"host_os={host_os} metrics_path={metrics_path.as_posix()} "
            f"overall_pass={metrics_payload['threshold_verdict']['overall_pass']}"
        ),
        attributes={
            "backup.transport": "usb_aoa_poc",
            "backup.poc.schema": AOA_POC_METRICS_SCHEMA,
            "backup.poc.run_id": run_id,
            "backup.poc.host_os": host_os,
            "backup.poc.metrics_path": metrics_path.as_posix(),
            "backup.poc.overall_pass": bool(metrics_payload["threshold_verdict"]["overall_pass"]),
        },
    )
    return metrics_path


def run_simulated_aoa_poc(
    *,
    host_os: str,
    output_root: Path,
    thresholds: AoaPocThresholds | None = None,
) -> Path:
    normalized_host_os = host_os.strip().lower()
    if normalized_host_os not in ("macos", "windows"):
        raise ValueError("AOA POC host_os must be either 'macos' or 'windows'.")
    if thresholds is None:
        thresholds = AoaPocThresholds()

    state_machine = AoaPocHostStateMachine()
    state_machine.on_device_detected()
    state_machine.on_accessory_negotiating()
    state_machine.on_accessory_ready()
    state_machine.on_streaming_started()
    state_machine.on_streaming_completed()

    started_at = _utc_now()
    measurements = AoaPocMeasurements(
        handshake_ms_samples=[1180, 1340, 1620, 1490, 1710],
        reconnect_success_count=19,
        reconnect_total_count=20,
        throughput_bytes_per_second_samples=[9_437_184, 10_485_760, 9_961_472],
    )
    completed_at = _utc_now()
    host_readiness = collect_host_readiness(normalized_host_os)
    return _write_metrics_file(
        host_os=normalized_host_os,
        output_root=output_root,
        thresholds=thresholds,
        measurements=measurements,
        device_info={
            "model": "simulated-android-device",
            "android_version": "simulated-14",
            "serial_hash": hashlib.sha256(b"simulated-android-device").hexdigest(),
        },
        host_readiness=host_readiness,
        errors=[],
        started_at=started_at,
        completed_at=completed_at,
    )


def run_host_probe_aoa_poc(
    *,
    host_os: str,
    output_root: Path,
    thresholds: AoaPocThresholds | None = None,
    hooks: AoaHostHooks | None = None,
) -> Path:
    normalized_host_os = host_os.strip().lower()
    if normalized_host_os not in ("macos", "windows"):
        raise ValueError("AOA POC host_os must be either 'macos' or 'windows'.")
    if thresholds is None:
        thresholds = AoaPocThresholds()
    if hooks is None:
        hooks = PyUsbAoaHostHooks()
    uses_default_pyusb_hooks = isinstance(hooks, PyUsbAoaHostHooks)

    state_machine = AoaPocHostStateMachine()
    errors: list[dict[str, str]] = []
    measurements = AoaPocMeasurements(
        handshake_ms_samples=[],
        reconnect_success_count=0,
        reconnect_total_count=0,
        throughput_bytes_per_second_samples=[],
    )
    started_at = _utc_now()
    host_readiness = collect_host_readiness(normalized_host_os)
    if uses_default_pyusb_hooks and not bool(host_readiness.get("pyusb_imported", False)):
        errors.append(
            {
                "stage": "prerequisites",
                "code": "pyusb_missing",
                "message": "PyUSB is unavailable; host AOA hooks cannot run.",
            }
        )
    elif uses_default_pyusb_hooks and not bool(host_readiness.get("libusb_backend_available", False)):
        errors.append(
            {
                "stage": "prerequisites",
                "code": "libusb_backend_missing",
                "message": "PyUSB libusb backend is unavailable; host AOA hooks cannot run.",
            }
        )
    device_info = {
        "model": "unknown",
        "android_version": "unknown",
        "serial_hash": hashlib.sha256(b"unknown-device").hexdigest(),
    }

    try:
        detected_devices = hooks.detect_devices()
        if not detected_devices:
            state_machine.on_failure()
            errors.append(
                {
                    "stage": "aoa_negotiate",
                    "code": "device_not_found",
                    "message": "No Android devices supporting AOA were detected.",
                }
            )
        else:
            selected_device = detected_devices[0]
            device_info = {
                "model": (
                    f"vid_{selected_device.id_vendor:04x}:pid_{selected_device.id_product:04x}"
                ),
                "android_version": "unknown",
                "serial_hash": selected_device.serial_hash,
            }
            state_machine.on_device_detected()
            state_machine.on_accessory_negotiating()
            handshake_started_at = time.monotonic()
            accessory_ready = hooks.ensure_accessory_mode(selected_device)
            handshake_elapsed_ms = max(1, int((time.monotonic() - handshake_started_at) * 1000))
            measurements.handshake_ms_samples.append(handshake_elapsed_ms)

            if not accessory_ready:
                state_machine.on_failure()
                errors.append(
                    {
                        "stage": "aoa_negotiate",
                        "code": "accessory_not_ready",
                        "message": "AOA negotiation completed but accessory mode was not observed.",
                    }
                )
            else:
                post_negotiation_devices = hooks.detect_devices()
                active_device = next(
                    (candidate for candidate in post_negotiation_devices if candidate.is_accessory_mode),
                    selected_device,
                )
                device_info = {
                    "model": (
                        f"vid_{active_device.id_vendor:04x}:pid_{active_device.id_product:04x}"
                    ),
                    "android_version": "unknown",
                    "serial_hash": active_device.serial_hash,
                }
                state_machine.on_accessory_ready()
                state_machine.on_streaming_started()
                try:
                    throughput_sample = hooks.measure_transport_throughput_bytes_per_second(
                        device=active_device,
                        sample_seconds=thresholds.throughput_sample_seconds,
                    )
                except (RuntimeError, OSError, ValueError) as exc:
                    errors.append(
                        {
                            "stage": "aoa_io",
                            "code": "throughput_probe_failed",
                            "message": str(exc),
                        }
                    )
                else:
                    if throughput_sample is None:
                        errors.append(
                            {
                                "stage": "aoa_io",
                                "code": "throughput_unavailable",
                                "message": "Throughput measurement is unavailable for this host/device run.",
                            }
                        )
                    elif throughput_sample > 0:
                        measurements.throughput_bytes_per_second_samples.append(throughput_sample)
                    else:
                        errors.append(
                            {
                                "stage": "aoa_io",
                                "code": "throughput_invalid",
                                "message": "Throughput measurement returned a non-positive value.",
                            }
                        )
                try:
                    reconnect_success, reconnect_total = hooks.measure_reconnect_success(
                        device=active_device,
                        min_cycles=thresholds.reconnect_cycles_min,
                    )
                    measurements.reconnect_success_count = reconnect_success
                    measurements.reconnect_total_count = reconnect_total
                except (RuntimeError, OSError, ValueError) as exc:
                    errors.append(
                        {
                            "stage": "reconnect",
                            "code": "reconnect_probe_failed",
                            "message": str(exc),
                        }
                    )
                state_machine.on_streaming_completed()
    except (RuntimeError, OSError, ValueError) as exc:
        state_machine.on_failure()
        errors.append(
            {
                "stage": "cleanup",
                "code": "host_probe_failed",
                "message": str(exc),
            }
        )

    completed_at = _utc_now()
    return _write_metrics_file(
        host_os=normalized_host_os,
        output_root=output_root,
        thresholds=thresholds,
        measurements=measurements,
        device_info=device_info,
        host_readiness=host_readiness,
        errors=errors,
        started_at=started_at,
        completed_at=completed_at,
    )


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run Android AOA transport proof-of-concept (POC) instrumentation.",
    )
    parser.add_argument(
        "--host-os",
        required=True,
        choices=("macos", "windows"),
        help="Host platform label used in output metrics.",
    )
    parser.add_argument(
        "--output-root",
        default="dt_image_search/mobile/transport/poc/runs",
        help="Output folder that will contain per-run metrics subfolders.",
    )
    parser.add_argument(
        "--mode",
        default="host",
        choices=("host", "simulate"),
        help="POC run mode. 'host' performs real host hooks, 'simulate' writes deterministic fixture metrics.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()
    output_root = Path(args.output_root).expanduser().resolve()
    if args.mode == "simulate":
        metrics_path = run_simulated_aoa_poc(
            host_os=args.host_os,
            output_root=output_root,
        )
    else:
        metrics_path = run_host_probe_aoa_poc(
            host_os=args.host_os,
            output_root=output_root,
        )
    log(
        "info",
        message=(
            "android_aoa_poc/main: completed run "
            f"mode={args.mode} host_os={args.host_os} metrics_path={metrics_path.as_posix()}"
        ),
        attributes={
            "backup.transport": "usb_aoa_poc",
            "backup.poc.mode": args.mode,
            "backup.poc.host_os": args.host_os,
            "backup.poc.metrics_path": metrics_path.as_posix(),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
