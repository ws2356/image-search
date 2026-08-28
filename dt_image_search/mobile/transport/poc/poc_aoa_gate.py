from __future__ import annotations

import argparse
from pathlib import Path
import sys

from dt_image_search.mobile.transport.poc.summarize_aoa_runs import (
    discover_aoa_run_summaries,
    latest_by_host,
)
from dt_image_search.telemetry.telemetry_client import log

EXIT_OK = 0
EXIT_MISSING_REQUIRED_HOST = 2
EXIT_THRESHOLD_FAILED = 3


def evaluate_latest_host_gate(
    *,
    runs_root: Path,
    required_hosts: tuple[str, ...] = ("macos", "windows"),
) -> tuple[int, str]:
    summaries = discover_aoa_run_summaries(runs_root)
    latest = latest_by_host(summaries)

    missing_hosts = [
        host for host in required_hosts if host not in latest
    ]
    if missing_hosts:
        return (
            EXIT_MISSING_REQUIRED_HOST,
            f"Gate failed: missing latest run for host(s): {', '.join(missing_hosts)}",
        )

    failed_hosts = [
        host for host in required_hosts if not latest[host].overall_pass
    ]
    if failed_hosts:
        return (
            EXIT_THRESHOLD_FAILED,
            f"Gate failed: latest run did not pass threshold(s) on host(s): {', '.join(failed_hosts)}",
        )

    return (
        EXIT_OK,
        f"Gate passed: latest run(s) for {', '.join(required_hosts)} passed thresholds.",
    )


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Gate Android AOA POC runs by latest host metrics verdicts.",
    )
    parser.add_argument(
        "--runs-root",
        default="dt_image_search/mobile/transport/poc/runs",
        help="Root folder that contains per-run metrics subfolders.",
    )
    parser.add_argument(
        "--required-hosts",
        default="macos,windows",
        help="Comma-separated host list to gate, e.g. 'macos,windows' or 'macos'.",
    )
    return parser


def main() -> int:
    parser = _build_arg_parser()
    args = parser.parse_args()
    runs_root = Path(args.runs_root).expanduser().resolve()
    required_hosts = tuple(
        host.strip().lower()
        for host in str(args.required_hosts).split(",")
        if host.strip()
    )
    invalid_hosts = [
        host for host in required_hosts if host not in ("macos", "windows")
    ]
    if invalid_hosts:
        raise ValueError(
            f"Invalid --required-hosts values: {', '.join(invalid_hosts)}. "
            "Allowed values are macos, windows."
        )
    if not required_hosts:
        raise ValueError("--required-hosts must include at least one host.")

    exit_code, message = evaluate_latest_host_gate(
        runs_root=runs_root,
        required_hosts=required_hosts,
    )
    sys.stdout.write(message + "\n")
    log(
        "info",
        message=(
            "poc_aoa_gate/main: "
            f"runs_root={runs_root.as_posix()} exit_code={exit_code} message={message}"
        ),
        attributes={
            "backup.transport": "usb_aoa_poc",
            "backup.poc.gate.runs_root": runs_root.as_posix(),
            "backup.poc.gate.exit_code": exit_code,
            "backup.poc.gate.required_hosts": ",".join(required_hosts),
        },
    )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
