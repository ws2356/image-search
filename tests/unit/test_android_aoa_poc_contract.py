import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.poc.android_aoa_poc import (
    AOA_POC_METRICS_SCHEMA,
    AOA_POC_REQUEST_ID_LENGTH,
    AoaDetectedDevice,
    AoaHostHooks,
    AoaPocHostState,
    AoaPocHostStateMachine,
    AoaPocMeasurements,
    AoaPocThresholds,
    build_aoa_transport_frame,
    evaluate_thresholds,
    parse_aoa_transport_frame,
    run_host_probe_aoa_poc,
    run_simulated_aoa_poc,
)


class _FakeHostHooks(AoaHostHooks):
    def __init__(
        self,
        *,
        accessory_ready: bool = True,
        throughput_bytes_per_second: int | None = 9_500_000,
        reconnect_success: int = 19,
        reconnect_total: int = 20,
    ) -> None:
        self._accessory_ready = accessory_ready
        self._throughput = throughput_bytes_per_second
        self._reconnect_success = reconnect_success
        self._reconnect_total = reconnect_total

    def detect_devices(self) -> tuple[AoaDetectedDevice, ...]:
        return (
            AoaDetectedDevice(
                id_vendor=0x18D1,
                id_product=0x2D00,
                bus=1,
                address=2,
                serial_hash="abc",
                supports_aoa=True,
                is_accessory_mode=self._accessory_ready,
            ),
        )

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        return self._accessory_ready

    def measure_transport_throughput_bytes_per_second(
        self,
        *,
        device: AoaDetectedDevice,
        sample_seconds: int,
    ) -> int | None:
        return self._throughput

    def measure_reconnect_success(
        self,
        *,
        device: AoaDetectedDevice,
        min_cycles: int,
    ) -> tuple[int, int]:
        return self._reconnect_success, self._reconnect_total


class TestAndroidAoaPocContract(unittest.TestCase):
    def test_transport_frame_round_trip(self) -> None:
        request_id = "12345678-1234-1234-1234-123456789abc"
        self.assertEqual(len(request_id), AOA_POC_REQUEST_ID_LENGTH)
        payload = b"hello-aoa"

        frame = build_aoa_transport_frame(request_id=request_id, payload=payload)
        parsed_request_id, parsed_payload = parse_aoa_transport_frame(frame)

        self.assertEqual(parsed_request_id, request_id)
        self.assertEqual(parsed_payload, payload)

    def test_transport_frame_rejects_mismatched_payload_length(self) -> None:
        request_id = "12345678-1234-1234-1234-123456789abc"
        frame = build_aoa_transport_frame(request_id=request_id, payload=b"payload")
        tampered = frame[:-1]

        with self.assertRaises(ValueError):
            parse_aoa_transport_frame(tampered)

    def test_state_machine_happy_path(self) -> None:
        machine = AoaPocHostStateMachine()

        machine.on_device_detected()
        machine.on_accessory_negotiating()
        machine.on_accessory_ready()
        machine.on_streaming_started()
        machine.on_streaming_completed()

        self.assertEqual(machine.state, AoaPocHostState.DISCONNECTED)

    def test_state_machine_invalid_transition_raises(self) -> None:
        machine = AoaPocHostStateMachine()
        with self.assertRaises(RuntimeError):
            machine.on_streaming_started()

    def test_threshold_evaluation_marks_failure_when_handshake_is_slow(self) -> None:
        thresholds = AoaPocThresholds(handshake_p95_ms_max=1000)
        measurements = AoaPocMeasurements(
            handshake_ms_samples=[1200, 1300, 1600],
            reconnect_success_count=20,
            reconnect_total_count=20,
            throughput_bytes_per_second_samples=[10_000_000],
        )

        verdict = evaluate_thresholds(thresholds=thresholds, measurements=measurements)

        self.assertFalse(verdict["handshake_p95_pass"])
        self.assertFalse(verdict["overall_pass"])

    def test_run_simulated_poc_writes_metrics_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir) / "runs"
            metrics_path = run_simulated_aoa_poc(host_os="macos", output_root=output_root)

            self.assertTrue(metrics_path.exists())
            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["schema"], AOA_POC_METRICS_SCHEMA)
            self.assertEqual(payload["host_os"], "macos")
            self.assertIn("host_readiness", payload)
            self.assertIn("pyusb_imported", payload["host_readiness"])
            self.assertIn("threshold_verdict", payload)
            self.assertIn("overall_pass", payload["threshold_verdict"])
            self.assertTrue(str(metrics_path).startswith(str(output_root)))

    def test_run_host_probe_writes_metrics_file_with_host_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir) / "runs"
            metrics_path = run_host_probe_aoa_poc(
                host_os="windows",
                output_root=output_root,
                hooks=_FakeHostHooks(),
            )

            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["schema"], AOA_POC_METRICS_SCHEMA)
            self.assertEqual(payload["host_os"], "windows")
            self.assertEqual(payload["errors"], [])
            self.assertIn("host_readiness", payload)
            self.assertIn("recommended_actions", payload["host_readiness"])
            self.assertIn("throughput_bytes_per_second_avg", payload["measurements"])
            self.assertIn("overall_pass", payload["threshold_verdict"])

    def test_run_host_probe_records_error_when_accessory_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir) / "runs"
            metrics_path = run_host_probe_aoa_poc(
                host_os="macos",
                output_root=output_root,
                hooks=_FakeHostHooks(accessory_ready=False, throughput_bytes_per_second=None, reconnect_success=0, reconnect_total=20),
            )

            payload = json.loads(metrics_path.read_text(encoding="utf-8"))
            self.assertTrue(payload["errors"])
            self.assertIn("host_readiness", payload)
            self.assertFalse(payload["threshold_verdict"]["overall_pass"])


if __name__ == "__main__":
    unittest.main()
