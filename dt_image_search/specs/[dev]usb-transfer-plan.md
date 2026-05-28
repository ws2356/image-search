# [dev] Android AOA Phase-0 POC Contract

## Goal
Validate Android Open Accessory (AOA) transport viability on both macOS and Windows before production USB transport implementation.

## Scope
- Phase-0 POC only.
- No production pairing/transfer code path replacement in this step.
- Deterministic per-run instrumentation output for threshold verification.

## Host run commands
- macOS:
  - `dt_image_search/scripts/poc_aoa_macos.sh`
- Windows:
  - `powershell -File dt_image_search/scripts/poc_aoa_windows.ps1`

Each run writes:
- `dt_image_search/mobile/transport/poc/runs/<timestamp>-<host_os>/metrics.json`

Summary command:
- `python -m dt_image_search.mobile.transport.poc.summarize_aoa_runs --runs-root dt_image_search/mobile/transport/poc/runs`

## Pass/Fail thresholds
- Handshake p95: `<= 5000 ms`
- Reconnect success rate: `>= 95%` over at least `20` cable replug cycles
- Throughput average: `>= 8 MB/s` sustained over `30` seconds

## Deterministic metrics schema
```json
{
  "schema": "dtis.android-aoa-poc-metrics.v1",
  "run_id": "20260528T153015Z-macos",
  "host_os": "macos|windows",
  "started_at_utc": "ISO-8601",
  "completed_at_utc": "ISO-8601",
  "device": {
    "model": "string",
    "android_version": "string",
    "serial_hash": "sha256-hex"
  },
  "host_readiness": {
    "host_os": "macos|windows",
    "pyusb_imported": true,
    "libusb_backend_available": true,
    "device_enumeration_available": true,
    "detected_usb_device_count": 1,
    "recommended_actions": [],
    "notes": []
  },
  "thresholds": {
    "handshake_p95_ms_max": 5000,
    "reconnect_success_rate_min": 0.95,
    "reconnect_cycles_min": 20,
    "throughput_bytes_per_second_min": 8388608,
    "throughput_sample_seconds": 30
  },
  "measurements": {
    "handshake_ms_samples": [1200, 1300, 1450],
    "handshake_p95_ms": 1450,
    "reconnect_success_count": 19,
    "reconnect_total_count": 20,
    "reconnect_success_rate": 0.95,
    "throughput_bytes_per_second_samples": [10485760, 9437184],
    "throughput_bytes_per_second_avg": 9961472
  },
  "errors": [
    {
      "stage": "aoa_negotiate|aoa_io|reconnect|cleanup",
      "code": "string",
      "message": "string"
    }
  ],
  "threshold_verdict": {
    "handshake_p95_pass": true,
    "reconnect_rate_pass": true,
    "throughput_pass": true,
    "overall_pass": true
  }
}
```

## Exit criteria
- Both host OS runs produce metrics files successfully.
- `threshold_verdict.overall_pass == true` on both host OS runs.
- Any failing threshold has an attached error entry and mitigation note before Phase-1 start.