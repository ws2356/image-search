# Android AOA Phase-0 POC

This folder contains Phase-0 proof-of-concept (POC) tooling for Android Open Accessory (AOA) USB transport.

## Goals

1. Run host-side AOA probes on macOS/Windows.
2. Write deterministic per-run metrics files.
3. Summarize run quality.
4. Gate progression using pass/fail thresholds.

## Output

Each run writes:

- `dt_image_search/mobile/transport/poc/runs/<timestamp>-<host_os>/metrics.json`

Schema:

- `dtis.android-aoa-poc-metrics.v1`

## Do I need an Android device connected to the PC?

- **`simulate` mode:** **No device required.**
- **`host` mode:** **Yes, a physical Android device over USB is required** for real host-hook probing.
  - USB debugging is **not** the target requirement for this POC path.
  - If prerequisites/device are missing, the run still writes `metrics.json` with explicit readiness/errors and typically fails thresholds.

## Step-by-step instructions

### A) Quick wiring check (no device needed)

1. From repository root, run a simulated POC sample:
   - macOS:
     ```bash
     dt_image_search/scripts/poc_aoa_macos.sh simulate
     ```
   - Windows:
     ```powershell
     powershell -File dt_image_search/scripts/poc_aoa_windows.ps1 simulate
     ```
2. Summarize runs:
   ```bash
   python -m dt_image_search.mobile.transport.poc.summarize_aoa_runs \
     --runs-root dt_image_search/mobile/transport/poc/runs
   ```
3. Gate the current host only:
   - macOS:
     ```bash
     python -m dt_image_search.mobile.transport.poc.poc_aoa_gate \
       --runs-root dt_image_search/mobile/transport/poc/runs \
       --required-hosts macos
     ```
   - Windows:
     ```powershell
     python -m dt_image_search.mobile.transport.poc.poc_aoa_gate --runs-root dt_image_search/mobile/transport/poc/runs --required-hosts windows
     ```

### B) Real host probe (device required)

1. Connect an Android device to the PC with a data-capable USB cable.
2. Launch an AuBackup Android build on the phone (POC-capable build), keep it in foreground, and accept any USB accessory permission prompt.
3. On macOS, install libusb runtime:
   ```bash
   brew install libusb
   ```
4. On Windows, ensure a libusb-compatible backend is available (for example WinUSB/libusbK driver binding for the relevant USB interface).
5. Ensure Python environment can import PyUSB:
   ```bash
   python -m pip install pyusb
   ```
6. Run host-mode POC:
   - macOS:
     ```bash
     dt_image_search/scripts/poc_aoa_macos.sh host
     ```
   - Windows:
     ```powershell
     powershell -File dt_image_search/scripts/poc_aoa_windows.ps1 host
     ```
7. Inspect latest `metrics.json` under:
   - `dt_image_search/mobile/transport/poc/runs/<timestamp>-<host_os>/metrics.json`
8. Summarize:
   ```bash
   python -m dt_image_search.mobile.transport.poc.summarize_aoa_runs \
     --runs-root dt_image_search/mobile/transport/poc/runs
   ```
9. Gate:
   - current host only during local iteration: `--required-hosts macos` or `--required-hosts windows`
   - both hosts for cross-platform readiness: `--required-hosts macos,windows`

## Core commands

### 1) Run one POC sample

macOS:

```bash
dt_image_search/scripts/poc_aoa_macos.sh [host|simulate]
```

Windows:

```powershell
powershell -File dt_image_search/scripts/poc_aoa_windows.ps1 [host|simulate]
```

### 2) Summarize all runs

```bash
python -m dt_image_search.mobile.transport.poc.summarize_aoa_runs \
  --runs-root dt_image_search/mobile/transport/poc/runs
```

### 3) Gate by thresholds

```bash
python -m dt_image_search.mobile.transport.poc.poc_aoa_gate \
  --runs-root dt_image_search/mobile/transport/poc/runs \
  --required-hosts macos,windows
```

`--required-hosts` examples:

- `macos`
- `windows`
- `macos,windows`

## One-command pipeline

macOS:

```bash
dt_image_search/scripts/poc_aoa_pipeline_macos.sh [host|simulate] [runs_root] [required_hosts]
```

Windows:

```powershell
powershell -File dt_image_search/scripts/poc_aoa_pipeline_windows.ps1 [host|simulate] [runs_root] [required_hosts]
```

Examples:

```bash
dt_image_search/scripts/poc_aoa_pipeline_macos.sh simulate /tmp/aoa-pipeline-runs macos
```

```powershell
powershell -File dt_image_search/scripts/poc_aoa_pipeline_windows.ps1 host dt_image_search/mobile/transport/poc/runs windows
```

## Gate exit codes

- `0`: pass (all required host latest runs passed thresholds)
- `2`: missing required host run(s)
- `3`: threshold failure on at least one required host

## Notes

- `host` mode uses real host hooks and may fail thresholds if prerequisites are not ready.
- `simulate` mode is deterministic and useful for wiring verification and script smoke tests.
- Readiness diagnostics are embedded in `metrics.json.host_readiness` (pyusb/libusb/enumeration checks plus remediation hints).
