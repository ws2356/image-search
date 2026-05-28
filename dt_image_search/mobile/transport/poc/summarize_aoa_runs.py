from __future__ import annotations

from dataclasses import dataclass
import argparse
import json
from pathlib import Path
import sys

from dt_image_search.telemetry.telemetry_client import log


@dataclass(frozen=True)
class AoaPocRunSummary:
    run_id: str
    host_os: str
    overall_pass: bool
    handshake_p95_ms: int
    reconnect_success_rate: float
    throughput_bps_avg: int
    metrics_path: Path


def discover_aoa_run_summaries(runs_root: Path) -> list[AoaPocRunSummary]:
    if not runs_root.exists():
        return []
    summaries: list[AoaPocRunSummary] = []
    for metrics_path in sorted(runs_root.glob("*/metrics.json")):
        payload = json.loads(metrics_path.read_text(encoding="utf-8"))
        host_os = str(payload.get("host_os", "")).strip().lower()
        run_id = str(payload.get("run_id", "")).strip()
        verdict = payload.get("threshold_verdict")
        measurements = payload.get("measurements")
        if not run_id or host_os not in ("macos", "windows"):
            continue
        if not isinstance(verdict, dict) or not isinstance(measurements, dict):
            continue
        summary = AoaPocRunSummary(
            run_id=run_id,
            host_os=host_os,
            overall_pass=bool(verdict.get("overall_pass", False)),
            handshake_p95_ms=int(measurements.get("handshake_p95_ms", 0) or 0),
            reconnect_success_rate=float(measurements.get("reconnect_success_rate", 0.0) or 0.0),
            throughput_bps_avg=int(measurements.get("throughput_bytes_per_second_avg", 0) or 0),
            metrics_path=metrics_path,
        )
        summaries.append(summary)
    return summaries


def latest_by_host(summaries: list[AoaPocRunSummary]) -> dict[str, AoaPocRunSummary]:
    latest: dict[str, AoaPocRunSummary] = {}
    for summary in summaries:
        previous = latest.get(summary.host_os)
        if previous is None or summary.run_id > previous.run_id:
            latest[summary.host_os] = summary
    return latest


def _format_bps_as_mbps(bps: int) -> str:
    return f"{bps / (1024 * 1024):.2f}"


def render_summary_report(summaries: list[AoaPocRunSummary]) -> str:
    latest = latest_by_host(summaries)
    total_runs = len(summaries)
    pass_count = sum(1 for summary in summaries if summary.overall_pass)
    fail_count = total_runs - pass_count

    lines = [
        "AOA POC Metrics Summary",
        f"Total runs: {total_runs} | Passed: {pass_count} | Failed: {fail_count}",
        "",
        "| Host | Latest Run ID | Overall | Handshake p95 (ms) | Reconnect Rate | Throughput (MB/s) | Metrics Path |",
        "|------|---------------|---------|--------------------|----------------|-------------------|-------------|",
    ]
    for host_os in ("macos", "windows"):
        summary = latest.get(host_os)
        if summary is None:
            lines.append(
                f"| {host_os} | - | - | - | - | - | - |"
            )
            continue
        lines.append(
            f"| {host_os} | {summary.run_id} | {'PASS' if summary.overall_pass else 'FAIL'} | "
            f"{summary.handshake_p95_ms} | {summary.reconnect_success_rate:.2%} | "
            f"{_format_bps_as_mbps(summary.throughput_bps_avg)} | {summary.metrics_path.as_posix()} |"
        )
    return "\n".join(lines) + "\n"


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Summarize Android AOA POC metrics runs by host OS.",
    )
    parser.add_argument(
        "--runs-root",
        default="dt_image_search/mobile/transport/poc/runs",
        help="Root folder that contains per-run metrics subfolders.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()
    runs_root = Path(args.runs_root).expanduser().resolve()
    summaries = discover_aoa_run_summaries(runs_root)
    report = render_summary_report(summaries)
    sys.stdout.write(report)
    log(
        "info",
        message=(
            "summarize_aoa_runs/main: "
            f"runs_root={runs_root.as_posix()} total_runs={len(summaries)}"
        ),
        attributes={
            "backup.transport": "usb_aoa_poc",
            "backup.poc.summary.runs_root": runs_root.as_posix(),
            "backup.poc.summary.total_runs": len(summaries),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

