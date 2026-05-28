from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
import argparse
import hashlib
import json
import math
from pathlib import Path

from dt_image_search.telemetry.telemetry_client import log

AOA_POC_METRICS_SCHEMA = "dtis.android-aoa-poc-metrics.v1"
AOA_POC_TRANSPORT_FRAME_VERSION = 1
AOA_POC_REQUEST_ID_LENGTH = 36
AOA_POC_TRANSPORT_HEADER_SIZE = 1 + AOA_POC_REQUEST_ID_LENGTH + 4


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


def _serialize_metrics(
    *,
    run_id: str,
    host_os: str,
    started_at: datetime,
    completed_at: datetime,
    thresholds: AoaPocThresholds,
    measurements: AoaPocMeasurements,
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
        "device": {
            "model": "simulated-android-device",
            "android_version": "simulated-14",
            "serial_hash": hashlib.sha256(b"simulated-android-device").hexdigest(),
        },
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

    run_id = f"{started_at.strftime('%Y%m%dT%H%M%SZ')}-{normalized_host_os}"
    run_dir = output_root / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    metrics_path = run_dir / "metrics.json"
    metrics_payload = _serialize_metrics(
        run_id=run_id,
        host_os=normalized_host_os,
        started_at=started_at,
        completed_at=completed_at,
        thresholds=thresholds,
        measurements=measurements,
    )
    metrics_path.write_text(
        json.dumps(metrics_payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    log(
        "info",
        message=(
            "android_aoa_poc/run_simulated_aoa_poc: "
            f"host_os={normalized_host_os} metrics_path={metrics_path.as_posix()} "
            f"overall_pass={metrics_payload['threshold_verdict']['overall_pass']}"
        ),
        attributes={
            "backup.transport": "usb_aoa_poc",
            "backup.poc.schema": AOA_POC_METRICS_SCHEMA,
            "backup.poc.run_id": run_id,
            "backup.poc.host_os": normalized_host_os,
            "backup.poc.metrics_path": metrics_path.as_posix(),
            "backup.poc.overall_pass": bool(metrics_payload["threshold_verdict"]["overall_pass"]),
        },
    )
    return metrics_path


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
        "--simulate",
        action="store_true",
        help="Run simulated POC flow and write deterministic metrics output.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()
    output_root = Path(args.output_root).expanduser().resolve()
    if not args.simulate:
        raise RuntimeError(
            "Non-simulated AOA POC run is not implemented yet. "
            "Use --simulate for Phase 0 scaffolding runs."
        )
    metrics_path = run_simulated_aoa_poc(
        host_os=args.host_os,
        output_root=output_root,
    )
    log(
        "info",
        message=(
            "android_aoa_poc/main: completed simulated run "
            f"metrics_path={metrics_path.as_posix()}"
        ),
        attributes={
            "backup.transport": "usb_aoa_poc",
            "backup.poc.host_os": args.host_os,
            "backup.poc.metrics_path": metrics_path.as_posix(),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

