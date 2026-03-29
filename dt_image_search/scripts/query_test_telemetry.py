import argparse
import json
import shlex
import subprocess
import sys
import time
import urllib.parse


DEFAULT_SSH_TARGET = "ubuntu@tc.boldman.net"
DEFAULT_SERVICE_NAME = "imagesearch_telemetry_test"
DEFAULT_METRIC_NAME = "test_counter"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query recent test telemetry from the remote Loki, Mimir, and Tempo backends over SSH."
    )
    parser.add_argument(
        "kind",
        nargs="?",
        choices=["all", "logs", "metrics", "traces"],
        default="all",
        help="Which telemetry backend to query.",
    )
    parser.add_argument(
        "--ssh-target",
        default=DEFAULT_SSH_TARGET,
        help="SSH target for the telemetry host.",
    )
    parser.add_argument(
        "--service-name",
        default=DEFAULT_SERVICE_NAME,
        help="service.name emitted by the test telemetry sender.",
    )
    parser.add_argument(
        "--metric-name",
        default=DEFAULT_METRIC_NAME,
        help="Metric name emitted by the test telemetry sender.",
    )
    parser.add_argument(
        "--lookback-minutes",
        type=int,
        default=15,
        help="How far back to search for logs and traces.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Maximum number of results to request per backend.",
    )
    parser.add_argument(
        "--log-contains",
        default="",
        help="Optional substring filter for log lines.",
    )
    return parser.parse_args()


def _remote_http_get(ssh_target: str, url: str) -> str:
    remote_python = "\n".join(
        [
            "import sys",
            "import urllib.request",
            "url = sys.argv[1]",
            "with urllib.request.urlopen(url, timeout=20) as response:",
            "    sys.stdout.write(response.read().decode('utf-8'))",
        ]
    )
    remote_command = f"python3 -c {shlex.quote(remote_python)} {shlex.quote(url)}"
    result = subprocess.run(
        ["ssh", ssh_target, remote_command],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or "unknown remote error"
        raise RuntimeError(f"Remote request failed for {url}: {stderr}")
    return result.stdout


def _print_section(title: str, payload: object) -> None:
    print(f"\n## {title}")
    print(json.dumps(payload, indent=2, ensure_ascii=True))


def _extract_trace_ids(logs_payload: dict) -> list[str]:
    trace_ids: list[str] = []
    seen = set()
    for stream in logs_payload.get("data", {}).get("result", []):
        for _, raw_line in stream.get("values", []):
            try:
                parsed_line = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            trace_id = parsed_line.get("traceid", "")
            if not trace_id or trace_id in seen:
                continue
            seen.add(trace_id)
            trace_ids.append(trace_id)
    return trace_ids


def _query_trace_by_id(args: argparse.Namespace, trace_id: str) -> dict:
    url = f"http://127.0.0.1:3200/api/traces/{trace_id}"
    return json.loads(_remote_http_get(args.ssh_target, url))


def query_metrics(args: argparse.Namespace) -> dict:
    promql = f'{args.metric_name}{{service_name="{args.service_name}"}}'
    url = (
        "http://127.0.0.1:9009/prometheus/api/v1/query?"
        + urllib.parse.urlencode({"query": promql})
    )
    return json.loads(_remote_http_get(args.ssh_target, url))


def query_logs(args: argparse.Namespace) -> dict:
    start_ns = int((time.time() - args.lookback_minutes * 60) * 1_000_000_000)
    end_ns = int(time.time() * 1_000_000_000)
    query = f'{{service_name="{args.service_name}"}}'
    if args.log_contains:
        query += f' |= "{args.log_contains}"'
    url = (
        "http://127.0.0.1:3100/loki/api/v1/query_range?"
        + urllib.parse.urlencode(
            {
                "query": query,
                "limit": args.limit,
                "start": str(start_ns),
                "end": str(end_ns),
                "direction": "backward",
            }
        )
    )
    return json.loads(_remote_http_get(args.ssh_target, url))


def query_traces(args: argparse.Namespace, logs_payload: dict | None = None) -> dict:
    if logs_payload is None:
        logs_payload = query_logs(args)
    trace_ids = _extract_trace_ids(logs_payload)[: args.limit]
    traces = []
    for trace_id in trace_ids:
        traces.append(
            {
                "trace_id": trace_id,
                "trace": _query_trace_by_id(args, trace_id),
            }
        )
    return {"trace_ids": trace_ids, "traces": traces}


def main() -> int:
    args = parse_args()
    had_error = False
    logs_payload: dict | None = None

    try:
        if args.kind in {"all", "metrics"}:
            _print_section("Metrics", query_metrics(args))
    except Exception as exc:
        had_error = True
        print(f"\n## Metrics\n{exc}", file=sys.stderr)

    try:
        if args.kind in {"all", "logs"}:
            logs_payload = query_logs(args)
            _print_section("Logs", logs_payload)
    except Exception as exc:
        had_error = True
        print(f"\n## Logs\n{exc}", file=sys.stderr)

    try:
        if args.kind in {"all", "traces"}:
            _print_section("Traces", query_traces(args, logs_payload))
    except Exception as exc:
        had_error = True
        print(f"\n## Traces\n{exc}", file=sys.stderr)

    if had_error:
        print(
            "\nOne or more queries failed. If Loki/Tempo are unreachable, redeploy the telemetry stack so localhost ports 3100 and 3200 are bound on the remote host.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())