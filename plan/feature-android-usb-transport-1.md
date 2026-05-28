---
goal: Android USB transport support across RN app and desktop app with LAN fallback
version: 1.0
date_created: 2026-05-28
last_updated: 2026-05-28
owner: Mobile Backup Team
status: 'Planned'
tags: [feature, architecture, android, usb, transport, rn, desktop]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

This plan defines deterministic implementation steps to add Android USB transport support for the AuBackup RN app and desktop app while preserving current LAN behavior and existing iOS USB behavior.

## 1. Requirements & Constraints

- **REQ-001**: Keep all existing LAN pairing and transfer APIs (`/api/mobile/pairing/*`, `/api/mobile/transfer/*`) behavior-compatible.
- **REQ-002**: Support Android USB transport for `pairing.claim`, `pairing.state`, `capabilities.exchange`, `transfer.start`, `transfer.existence`, `transfer.asset`, `transfer.complete`.
- **REQ-003**: RN must continue computing SHA1 for every asset in transfer existence checks.
- **REQ-004**: USB and LAN must share the same domain handlers on desktop (`MobilePairingService`, `MobileTransferService`) through transport router dispatch.
- **REQ-005**: Pairing QR v2 fields (`sid`, `opt`, `usp`, `ept`) must remain the bootstrap contract for USB transport.
- **REQ-006**: Desktop must auto-fallback to LAN when Android USB connection is unavailable or drops.
- **REQ-007**: Android USB transport must not depend on end-user enabling Developer Options or USB debugging.
- **REQ-008**: Execute and pass an AOA POC on both macOS and Windows before starting Phase 1 production implementation.
- **REQ-009**: Phase 0 POC acceptance thresholds must be met on both macOS and Windows: handshake <= 5 seconds (p95), reconnect-after-replug success >= 95% across 20 cycles, and sustained throughput >= 8 MB/s for 30-second transfer sample.
- **SEC-001**: USB auth challenge must keep `SHA256(opt + rand)` challenge/response validation semantics.
- **SEC-002**: Encrypted transfer payload behavior must stay identical across LAN and USB paths when encryption is negotiated.
- **CON-001**: Do not remove iOS USB support (`usbmuxd` path) while adding Android USB support.
- **CON-002**: RN business logic must remain unidirectional; transport-specific I/O must stay in infrastructure/native layers.
- **CON-003**: Do not introduce broad exception swallowing; return explicit rejected responses consistent with existing schema.
- **GUD-001**: Python logging must use `dt_image_search.telemetry.telemetry_client.log`; do not use `print()`.
- **GUD-002**: RN code must remain strict TypeScript and preserve current `AbortController` stop semantics.
- **PAT-001**: Follow transport strategy pattern in RN (`TransportStrategy`, `TransportKind`) and adapter/router pattern in desktop transport package.

## 2. Implementation Steps

### Implementation Phase 0

- GOAL-000: Produce a validated AOA transport proof-of-concept on macOS and Windows to de-risk API usage, framing, and integration pattern before production refactor work.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-031 | Create `dt_image_search/mobile/transport/poc/android_aoa_poc.py` as an isolated executable spike that performs AOA accessory negotiation, endpoint discovery, and bidirectional framed message exchange (`request_id`, payload length, payload bytes) without touching existing pairing/transfer services. |  |  |
| TASK-032 | Create `mobile/rn/android/app/src/main/java/com/ausearch/aubackup/usb/poc/AoaPocAccessoryService.kt` implementing a minimal Android accessory endpoint responder used only for POC validation builds. |  |  |
| TASK-033 | Add host-platform runners `dt_image_search/scripts/poc_aoa_macos.sh` and `dt_image_search/scripts/poc_aoa_windows.ps1` with deterministic output fields: device detected, accessory negotiated, first message RTT, sustained throughput sample, disconnect behavior. |  |  |
| TASK-034 | Define POC pass/fail contract in `dt_image_search/specs/[dev]usb-transfer-plan.md` with explicit acceptance thresholds for both macOS and Windows (successful negotiation, >=1 stable request/response loop, clean reconnect after cable replug). |  |  |
| TASK-035 | Add automated POC smoke tests `tests/unit/test_android_aoa_poc_contract.py` that validate framing codec and host-side AOA state-machine transitions using mocks (no physical device required in CI). |  |  |
| TASK-036 | Record POC integration findings and required production adjustments (threading model, timeout defaults, error mapping, cleanup semantics) directly into this plan’s Risks/Assumptions and Phase 1 task notes before Phase 1 execution. |  |  |
| TASK-037 | Add POC instrumentation in `android_aoa_poc.py` and host runners to write per-run metrics JSON files into dedicated folder `dt_image_search/mobile/transport/poc/runs/<timestamp>-<host_os>/metrics.json` including handshake_ms, reconnect_success_count, reconnect_total_count, throughput_bytes_per_second, error events, and final threshold verdict. |  |  |
| TASK-038 | Add metrics summarizer CLI `dt_image_search/mobile/transport/poc/summarize_aoa_runs.py` to print macOS/Windows side-by-side pass/fail status from `poc/runs/**/metrics.json` for threshold gate decisions. |  |  |
| TASK-039 | Add threshold gate command `dt_image_search/mobile/transport/poc/poc_aoa_gate.py` that exits non-zero unless latest macOS and latest Windows runs both pass (`overall_pass=true`) for CI/local release gates. |  |  |

#### Phase 0 `metrics.json` schema (deterministic)

```json
{
  "schema": "dtis.android-aoa-poc-metrics.v1",
  "run_id": "20260528T153015Z-macos-001",
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

### Implementation Phase 1

- GOAL-001: Add desktop Android USB tunnel capability without regressing existing iOS USB tunnel behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Create `dt_image_search/mobile/transport/android_aoa_tunnel.py` implementing Android Open Accessory host tunnel provider with deterministic methods: `list_accessory_devices()`, `probe_accessory_port()`, `connect_accessory_port()`, using AOA bulk endpoints for transport payload framing. |  |  |
| TASK-002 | Extend `dt_image_search/mobile/transport/usb_tunnel.py` data model to carry device platform metadata (`ios`/`android`) while preserving current iOS provider API contract used by `UsbWebSocketTransportAdapter`. |  |  |
| TASK-003 | Update `dt_image_search/mobile/transport/usb_ws_adapter.py` to accept both iOS and Android tunnel providers via a provider registry/composite and retain existing probe order logic (`usp`, `usp +/- window`). |  |  |
| TASK-004 | Add deterministic cleanup for AOA session handles/endpoints on adapter stop and reconnect paths in `UsbWebSocketTransportAdapter.stop()` and connection teardown helpers. |  |  |
| TASK-005 | Add desktop unit tests for Android AOA tunnel provider and adapter probe/connection lifecycle: new `tests/unit/test_android_aoa_tunnel.py` and updates in `tests/unit/test_usb_ws_adapter.py`. |  |  |

### Implementation Phase 2

- GOAL-002: Enable desktop pairing transport resolution and QR bootstrap flow for Android USB.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-006 | Update `dt_image_search/mobile/mobile_pairing_service.py::_configure_usb_bootstrap_for_session` to configure USB bootstrap for both platform tokens instead of `MobilePlatform.IOS` only. |  |  |
| TASK-007 | Update `dt_image_search/mobile/mobile_pairing_service.py::refresh_token` to refresh USB bootstrap config for Android token refresh events as well as iOS. |  |  |
| TASK-008 | Update `dt_image_search/mobile/mobile_pairing_service.py::_resolve_pairing_transport` to return `usb` for Android when USB state is connected for the same session. |  |  |
| TASK-009 | Update transport telemetry attributes in `mobile_pairing_service.py` to include platform-specific USB transport selection for Android claims. |  |  |
| TASK-010 | Add regression tests in `tests/unit/test_mobile_pairing_service.py` for Android claim returning `transport=usb` when Android USB tunnel is connected. |  |  |

### Implementation Phase 3

- GOAL-003: Implement Android-side USB runtime in RN and bridge it into TypeScript transport strategy infrastructure.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-011 | Add native Android USB runtime module under `mobile/rn/android/app/src/main/java/com/ausearch/aubackup/usb/` to host WebSocket server on `usp`, process desktop auth challenge, and expose request/response events to JS. |  |  |
| TASK-012 | Register native module in `MainApplication.kt` and package file `UsbTransportPackage.kt`; add required Android permissions/service declarations if needed for USB accessory/runtime stability. |  |  |
| TASK-013 | Replace `mobile/rn/infrastructure/transport/usb/usb-transport-strategy.ts` stub with concrete `UsbTransportStrategy` implementing envelope request/response correlation for all pairing/transfer operations. |  |  |
| TASK-014 | Add `mobile/rn/infrastructure/transport/usb/usb-runtime-client.android.ts` and `usb-runtime-client.ios.ts` (unsupported placeholder) to isolate platform-specific USB runtime bridging from business logic. |  |  |
| TASK-015 | Add binary frame encoder/decoder helpers in RN transport infrastructure for `transfer.asset` chunk frames compatible with desktop USB framing (`version + request_id + payload_length + payload`). |  |  |

### Implementation Phase 4

- GOAL-004: Integrate RN flow orchestration to select and use USB transport end-to-end on Android with LAN fallback.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-016 | Extend RN pairing session model in `mobile/rn/features/backup/pairing/models.ts` and persistence services to store selected transport and USB bootstrap runtime readiness metadata. |  |  |
| TASK-017 | Update `mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts` to remove hard-coded `claim_platform='ios'` for Android USB path and use actual `identity.platform`, gated by a runtime feature flag if compatibility fallback is still required. |  |  |
| TASK-018 | Introduce transport strategy selection factory (`lan` vs `usb`) and inject strategy into `PairingService` and `TransferService` call sites in `use-pairing-screen-controller.ts`, `start-transfer.ts`, and `stop-transfer.ts`. |  |  |
| TASK-019 | Update transfer progress transport field emission in `mobile/rn/features/backup/use-cases/start-transfer.ts` so UI reflects active transport (`TransferTransport.Usb` when USB strategy is active). |  |  |
| TASK-020 | Integrate Android foreground/headless runtime (`android-headless-transfer-task.ts`) with USB runtime lifecycle start/stop hooks to ensure stop semantics and notification behavior stay consistent. |  |  |

### Implementation Phase 5

- GOAL-005: Add desktop prerequisites and diagnostic readiness for Android USB development and validation.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-021 | Add `dt_image_search/mobile/android_mobile_device_support.py` to probe AOA host prerequisites (USB permissions, required host libraries/drivers, accessory enumeration capability) on macOS/Windows. |  |  |
| TASK-022 | Update `dt_image_search/mobile/mobile_folder_controller.py::_ensure_usb_prerequisites` to run both Apple and Android USB prerequisite checks, with platform-specific user guidance dialogs. |  |  |
| TASK-023 | Update mobile USB prerequisite dialogs in `dt_image_search/mobile/mobile_dialogs.py` to include Android AOA setup actions (OTG/accessory mode guidance and cable validation) without USB-debugging instructions. |  |  |
| TASK-024 | Add telemetry events for Android USB probe lifecycle and fallback transitions in desktop transport manager without logging file/media-sensitive data. |  |  |
| TASK-025 | Add unit tests for Android prerequisite manager and controller integration in `tests/unit/test_mobile_folder_controller.py` and new `tests/unit/test_android_mobile_device_support.py`. |  |  |

### Implementation Phase 6

- GOAL-006: Validate full Android USB flow and finalize rollout controls.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-026 | Add RN tests for USB transport strategy request/response correlation and transfer asset frame handling in new test files under `mobile/rn/features/backup/**/__tests__/`. |  |  |
| TASK-027 | Execute desktop regression suite (`dt_image_search/scripts/run_tests.sh`) and targeted transport tests (`tests/unit/test_mobile_pairing_service.py`, `tests/unit/test_mobile_transfer_service.py`, USB-specific tests). |  |  |
| TASK-028 | Execute RN compile/type validation (`cd mobile/rn && pnpm -s exec tsc --noEmit`) and focused integration/manual tests for Android USB pairing and transfer start/stop. |  |  |
| TASK-029 | Add feature flag gating for Android USB enablement in desktop and RN to allow staged rollout; default to LAN fallback when disabled. |  |  |
| TASK-030 | Update specs with final Android USB contract decisions in `dt_image_search/specs/[dev]transport-refactor plan.md` and `dt_image_search/specs/[dev] service discovery.md`. |  |  |

## 3. Alternatives

- **ALT-001**: Use LAN-only for Android and defer USB support; rejected because Phase 2 roadmap explicitly requires Android USB support.
- **ALT-002**: Use adb-based USB tunnel; rejected because it requires end users to enable USB debugging and weakens product UX for mainstream users.
- **ALT-003**: Build a separate desktop transfer domain for USB; rejected because existing router/adapter architecture already supports protocol reuse and avoids domain duplication.

## 4. Dependencies

- **DEP-001**: Desktop Python runtime dependency `websockets` must remain installed for USB WebSocket transport adapter.
- **DEP-002**: Desktop host environment must include Android AOA-compatible USB host stack/libraries and platform-specific driver support.
- **DEP-003**: Existing iOS USB dependency path (`pymobiledevice3`, `usbmuxd` where applicable) must remain intact.
- **DEP-004**: RN Android native USB module requires Gradle dependency updates for WebSocket server runtime if not provided by current dependencies.
- **DEP-005**: Existing desktop transport router contracts in `dt_image_search/mobile/transport/contracts.py` and `router.py` are required integration points.

## 5. Files

- **FILE-001**: `dt_image_search/mobile/transport/android_aoa_tunnel.py` — new Android Open Accessory tunnel provider.
- **FILE-002**: `dt_image_search/mobile/transport/usb_tunnel.py` — shared USB provider abstractions and metadata model updates.
- **FILE-003**: `dt_image_search/mobile/transport/usb_ws_adapter.py` — multi-provider USB probe/connect lifecycle integration.
- **FILE-004**: `dt_image_search/mobile/mobile_pairing_service.py` — USB bootstrap config and pairing transport resolution for Android.
- **FILE-005**: `dt_image_search/mobile/mobile_folder_controller.py` — prerequisite orchestration updates.
- **FILE-006**: `dt_image_search/mobile/mobile_dialogs.py` — Android USB prerequisite UX updates.
- **FILE-007**: `mobile/rn/android/app/src/main/java/com/ausearch/aubackup/usb/*` — native Android USB runtime module/package files.
- **FILE-008**: `mobile/rn/infrastructure/transport/usb/usb-transport-strategy.ts` — concrete USB transport strategy implementation.
- **FILE-009**: `mobile/rn/infrastructure/transport/usb/usb-runtime-client.android.ts` and `usb-runtime-client.ios.ts` — runtime client bridge.
- **FILE-010**: `mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts` — platform claim and transport selection logic.
- **FILE-011**: `mobile/rn/features/backup/use-cases/start-transfer.ts` and `stop-transfer.ts` — transport strategy integration.
- **FILE-012**: `mobile/rn/features/backup/pairing/models.ts` and persistence/store files — transport/session metadata persistence.
- **FILE-013**: `tests/unit/test_mobile_pairing_service.py`, `tests/unit/test_mobile_transfer_service.py`, `tests/unit/test_mobile_folder_controller.py`, plus new Android USB test files.

## 6. Testing

- **TEST-001**: Desktop unit regression: `dt_image_search/scripts/run_tests.sh`.
- **TEST-002**: Targeted desktop pairing/transfer tests with Android USB additions: `python -m pytest -q tests/unit/test_mobile_pairing_service.py tests/unit/test_mobile_transfer_service.py tests/unit/test_mobile_folder_controller.py tests/unit/test_android_aoa_tunnel.py tests/unit/test_android_mobile_device_support.py`.
- **TEST-003**: RN TypeScript compile check: `cd mobile/rn && pnpm -s exec tsc --noEmit`.
- **TEST-004**: Android manual functional matrix: pairing via QR + USB connected, USB disconnected during transfer, LAN fallback after USB failure, stop-transfer during USB upload, resume flow after reconnect.
- **TEST-005**: Protocol compatibility validation: verify USB envelope fields and transfer binary frame structure match desktop adapter expectations (`dtis.mobile-transport.v1`, `request_id`, frame header sizes).
- **TEST-006**: Phase 0 threshold validation from per-run metrics files in `dt_image_search/mobile/transport/poc/runs/`: handshake p95 <= 5000 ms, reconnect_success_rate >= 95% over at least 20 replug cycles, throughput >= 8 MB/s sustained over 30 seconds on both macOS and Windows.
- **TEST-007**: Validate summarizer output with fixture runs using `tests/unit/test_android_aoa_poc_summary_cli.py`.
- **TEST-008**: Validate gate command exit-code behavior with fixture runs using `tests/unit/test_android_aoa_poc_gate_cli.py`.

## 7. Risks & Assumptions

- **RISK-001**: Android USB accessory negotiation and host behavior can differ across OEMs, causing connection variability that may fail REQ-009 thresholds on one host OS.
- **RISK-002**: Removing temporary `platform='ios'` claim workaround may break compatibility with older desktop builds if token handling is still platform-sensitive.
- **RISK-003**: Large-video USB skip-path latency may persist if desktop signature records contain incomplete historical metadata.
- **RISK-004**: New native Android WebSocket runtime may introduce lifecycle race conditions with foreground/headless transfer services.
- **ASSUMPTION-001**: Android app build can request/handle USB accessory mode permissions without requiring Developer Options.
- **ASSUMPTION-002**: Existing desktop transport router and service domain handlers are stable and reusable for Android USB operations.
- **ASSUMPTION-003**: LAN remains the guaranteed fallback path during staged rollout and troubleshooting.
- **ASSUMPTION-004**: POC run folder (`dt_image_search/mobile/transport/poc/runs/`) is writable in developer environments on macOS and Windows.

## 8. Related Specifications / Further Reading

- `dt_image_search/specs/[dev]transport-refactor plan.md`
- `dt_image_search/specs/[dev] service discovery.md`
- `dt_image_search/specs/[WIP] [dev] [pc] mobile-folder.md`
- `dt_image_search/specs/feature roadmap - mobile-folder.md`
- `mobile/rn/AGENTS.md`
- `mobile/ios/Agents.md`
