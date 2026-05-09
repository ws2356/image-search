# Linux Support Plan (Ubuntu/Debian, APT + `.deb`)

## Goal
Add production-grade Linux support for AuSearch (including Mobile Folder GA) with a complete **build → package → install → run → release** lifecycle.

## Scope (v1)
- Target distros: **Ubuntu/Debian only**
- Package format: **`.deb`**
- Mobile Folder support: **GA**
- Privileged dependency install: **auto via `pkexec`**

---

## 1. Runtime and dependency strategy
1. Define Linux system dependency set:
   - `usbmuxd`
   - `libimobiledevice-utils`
   - `avahi-daemon`
   - `libusb-1.0-0` (or distro-equivalent)
   - `openssl`
2. Keep Python/app runtime self-contained in app bundle where feasible; keep only true OS-level/mobile stack in APT.
3. Add Linux dependency probe manager (parallel to Windows Apple Mobile Support manager) with:
   - detection (installed + service running where needed),
   - install command generation,
   - diagnostics logging.

## 2. Privileged install flow (pkexec)
1. Add root-owned installer helper script:
   - `dt_image_search/scripts/linux/install_mobile_support.sh`
2. Helper responsibilities:
   - `apt-get update` (bounded retry),
   - install required packages non-interactively,
   - enable/start required services (`usbmuxd`, `avahi-daemon`),
   - emit structured logs to app log directory.
3. Desktop flow:
   - trigger helper through `pkexec`,
   - show progress/error UI,
   - re-probe dependencies after install.

## 3. Packaging (`.deb`) pipeline
1. Add build script:
   - `dt_image_search/scripts/package_deb.sh`
2. Package contents:
   - app binary/bundle,
   - desktop entry (`.desktop`),
   - icon assets,
   - launcher in `/usr/bin` (or equivalent),
   - policykit action file for pkexec helper.
3. Debian metadata:
   - `Depends`, version, architecture, maintainer, description.
4. Add post-install hooks as needed (desktop db/icon cache refresh).

## 4. Release workflow
1. Add Linux lane to release docs/scripts:
   - build artifact naming/versioning,
   - checksum generation,
   - GitHub Release upload.
2. Add rollback/uninstall instructions.
3. Add support matrix doc for tested Ubuntu/Debian versions.

## 5. App runtime integration (Linux)
1. Extend platform gating for Linux in mobile backup and USB transport initialization.
2. Ensure service/process expectations are Linux-correct (usbmuxd + avahi paths).
3. Ensure logs/telemetry include Linux-specific install and runtime diagnostics.

## 6. Testing and quality gates
1. Unit tests:
   - dependency detection parsing,
   - pkexec command builder,
   - installer result/error mapping.
2. Integration checks (Ubuntu runner/VM):
   - fresh machine install via `.deb`,
   - first-launch dependency auto-install,
   - iPhone pairing + backup happy path.
3. Add Linux tests to:
   - `dt_image_search/scripts/run_tests.sh` (where applicable),
   - release validation checklist.

## 7. Security and reliability requirements
1. Keep privileged operations in minimal helper scope only.
2. Validate/sanitize all external command arguments.
3. Fail loudly with actionable remediation (no silent fallback).
4. Preserve least-privilege runtime for normal app execution.

---

## Phased implementation checklist

### P0 — Packaging and install foundation
1. Add Linux dependency probe manager and OS package checks.
2. Add `pkexec` helper script for APT install + service enable/start.
3. Add `.deb` packaging script + metadata + desktop entry + icons.
4. Add policykit integration for privileged helper.
5. Validate install/uninstall on fresh Ubuntu/Debian VM.

### P1 — Mobile Folder GA on Linux
1. Enable Linux runtime wiring for mobile pairing/transfer paths.
2. Ensure usbmuxd/avahi readiness checks gate UI and flows.
3. Add Linux-specific diagnostics/telemetry around install and transfer.
4. Validate end-to-end iPhone pairing + backup on Linux.

### P2 — Release hardening and operations
1. Add Linux release lane (artifact naming, checksums, publishing).
2. Add Linux entries to runbook, troubleshooting, and support matrix.
3. Add/expand Linux unit + integration tests in `run_tests.sh` path.
4. Freeze GA checklist and sign off exit criteria.

---

## Deliverables
- Linux dependency manager + pkexec helper flow
- `.deb` packaging script and metadata
- release script/docs updates for Linux artifacts
- Linux-focused tests and validation checklist
- user-facing install/run troubleshooting guide

## Exit criteria
- Fresh Ubuntu/Debian user can install `.deb`, launch AuSearch, complete Mobile Folder pairing/backup, and run core search/view features without manual dependency commands.
