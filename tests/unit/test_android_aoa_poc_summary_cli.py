import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.mobile.transport.poc.summarize_aoa_runs import (
    discover_aoa_run_summaries,
    latest_by_host,
    render_summary_report,
)


def _write_metrics(
    runs_root: Path,
    run_id: str,
    host_os: str,
    *,
    overall_pass: bool,
    handshake_p95_ms: int,
    reconnect_success_rate: float,
    throughput_avg: int,
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
            "handshake_p95_ms": handshake_p95_ms,
            "reconnect_success_rate": reconnect_success_rate,
            "throughput_bytes_per_second_avg": throughput_avg,
        },
    }
    (run_dir / "metrics.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


class TestAndroidAoaPocSummaryCli(unittest.TestCase):
    def test_discover_summaries_and_pick_latest_per_host(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runs_root = Path(temp_dir)
            _write_metrics(
                runs_root,
                "20260528T100000Z-macos",
                "macos",
                overall_pass=False,
                handshake_p95_ms=5200,
                reconnect_success_rate=0.9,
                throughput_avg=7_000_000,
            )
            _write_metrics(
                runs_root,
                "20260528T110000Z-macos",
                "macos",
                overall_pass=True,
                handshake_p95_ms=2100,
                reconnect_success_rate=0.98,
                throughput_avg=11_000_000,
            )
            _write_metrics(
                runs_root,
                "20260528T105000Z-windows",
                "windows",
                overall_pass=True,
                handshake_p95_ms=2500,
                reconnect_success_rate=0.96,
                throughput_avg=9_500_000,
            )

            summaries = discover_aoa_run_summaries(runs_root)
            latest = latest_by_host(summaries)

            self.assertEqual(len(summaries), 3)
            self.assertEqual(latest["macos"].run_id, "20260528T110000Z-macos")
            self.assertEqual(latest["windows"].run_id, "20260528T105000Z-windows")

    def test_render_summary_report_contains_both_hosts(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runs_root = Path(temp_dir)
            _write_metrics(
                runs_root,
                "20260528T110000Z-macos",
                "macos",
                overall_pass=True,
                handshake_p95_ms=2100,
                reconnect_success_rate=0.98,
                throughput_avg=11_000_000,
            )
            summaries = discover_aoa_run_summaries(runs_root)
            report = render_summary_report(summaries)

            self.assertIn("AOA POC Metrics Summary", report)
            self.assertIn("| macos |", report)
            self.assertIn("| windows | - | - | - | - | - | - |", report)


if __name__ == "__main__":
    unittest.main()

