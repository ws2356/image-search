import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.poc.poc_aoa_gate import (
    EXIT_MISSING_REQUIRED_HOST,
    EXIT_OK,
    EXIT_THRESHOLD_FAILED,
    evaluate_latest_host_gate,
)


def _write_metrics(
    runs_root: Path,
    run_id: str,
    host_os: str,
    overall_pass: bool,
) -> None:
    run_dir = runs_root / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "dtis.android-aoa-poc-metrics.v1",
        "run_id": run_id,
        "host_os": host_os,
        "threshold_verdict": {
            "overall_pass": overall_pass,
        },
        "measurements": {
            "handshake_p95_ms": 1200,
            "reconnect_success_rate": 0.98,
            "throughput_bytes_per_second_avg": 10_000_000,
        },
    }
    (run_dir / "metrics.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


class TestAndroidAoaPocGateCli(unittest.TestCase):
    def test_gate_passes_when_latest_macos_and_windows_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runs_root = Path(temp_dir)
            _write_metrics(runs_root, "20260528T100000Z-macos", "macos", True)
            _write_metrics(runs_root, "20260528T100500Z-windows", "windows", True)

            exit_code, message = evaluate_latest_host_gate(runs_root=runs_root)

            self.assertEqual(exit_code, EXIT_OK)
            self.assertIn("passed thresholds", message)

    def test_gate_fails_when_required_host_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runs_root = Path(temp_dir)
            _write_metrics(runs_root, "20260528T100000Z-macos", "macos", True)

            exit_code, message = evaluate_latest_host_gate(runs_root=runs_root)

            self.assertEqual(exit_code, EXIT_MISSING_REQUIRED_HOST)
            self.assertIn("missing latest run", message)

    def test_gate_fails_when_latest_host_run_is_not_passing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runs_root = Path(temp_dir)
            _write_metrics(runs_root, "20260528T100000Z-macos", "macos", True)
            _write_metrics(runs_root, "20260528T100500Z-windows", "windows", False)

            exit_code, message = evaluate_latest_host_gate(runs_root=runs_root)

            self.assertEqual(exit_code, EXIT_THRESHOLD_FAILED)
            self.assertIn("did not pass threshold", message)

    def test_gate_can_target_single_required_host(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runs_root = Path(temp_dir)
            _write_metrics(runs_root, "20260528T100000Z-macos", "macos", True)

            exit_code, message = evaluate_latest_host_gate(
                runs_root=runs_root,
                required_hosts=("macos",),
            )

            self.assertEqual(exit_code, EXIT_OK)
            self.assertIn("passed thresholds", message)


if __name__ == "__main__":
    unittest.main()
