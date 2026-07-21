# Short Session ID for PC-to-Mobile QR Links

**Date:** 2026-07-08
**Author:** opencode (AI agent)
**Status:** Approved

## Problem

The current session ID for instant sharing (PC-to-Mobile flow) is a UUID v4 string (36 chars, e.g. `550e8400-e29b-41d4-a716-446655440000`). This makes QR codes dense and hard to scan. The `sid` parameter in the QR URL contributes significantly to overall URL length.

## Goal

Shorten the session ID to 1-2 hex characters (`1` through `ff`) to dramatically reduce QR code density and improve scan reliability.

## Design

### 1. New Session ID Generator

Add a `SessionIdGenerator` class in a new dedicated module `dt_image_search/instant_sharing/session_id_generator.py` with:

- **Counter range:** `1` to `0xff` (255 decimal)
- **Output format:** Lowercase hex string without leading zero — `"1"`, `"2"`, ..., `"9"`, `"a"`, `"b"`, ..., `"ff"`
- **Persistence:** Last used counter value saved to `get_app_data_path() / "session_id_counter.txt"` (following the same pattern as `dt_device_id.py`) so the ID grows monotonically across app restarts
- **Wrap-around:** When counter surpasses `0xff`, restart from `1`
- **Thread safety:** Protected by `threading.Lock`

**Lifecycle:**
1. On init: read persisted value `N`, set next to `N + 1`
2. On each request: increment counter, persist new value, return `hex(value)[2:]` (strips `0x` prefix)
3. If value > `0xff`: wrap to `1`

### 2. Integration Point

In `qr_trigger_handler.py:130`, replace:
```python
session_id = str(uuid.uuid4())
```
with a call to the generator singleton.

### 3. Validation Relaxation (PC Python side)

Three places enforce UUID format on session_id. Relax all to accept any non-empty string:

| File | Line | Current | Change |
|------|------|---------|--------|
| `contracts.py` | 181 | `_normalize_uuid(self.session_id, field_name="session_id")` | Replace with `if not self.session_id.strip(): raise ValueError(...)` |
| `mdns.py` | 66 | `UUID(self.session_id)` in `ConnectionConfig.validate()` | Remove, keep non-empty check only |
| `mdns.py` | 147 | `UUID(self.session_id)` in `BootstrapRequest.validate()` | Remove, keep non-empty check only |

Also remove unused `from uuid import UUID` imports in those files.

### 4. Client Side — No Changes Needed

- **iOS** (`MobileAppServices.swift:858`): `URLQueryQRCodePayloadDecoder` reads `sid` as plain `String`. No UUID validation.
- **Web** (`urlParams.ts:15`): `parseShareUrlParams` reads `sid` as plain `String`. No UUID validation.
- **Security** (`security.py:96`): `sign()` operates on raw string bytes. Format-agnostic.
- **iOS `lastSessionID`** (`MobileAppServices.swift:653`): stored as plain `String`. No format constraint.

### 5. QR URL Impact

**Before:** `https://dl.boldman.net/share?ips=192.168.1.5&p=8080&sp=8443&sid=550e8400-e29b-41d4-a716-446655440000&opt=123456`
**After:** `https://dl.boldman.net/share?ips=192.168.1.5&p=8080&sp=8443&sid=a&opt=123456`

The `sid` parameter shrinks from 36 chars to 1-2 chars.

## Files to Modify

1. `dt_image_search/instant_sharing/session_id_generator.py` — **new file** with `SessionIdGenerator` class
2. `dt_image_search/instant_sharing/qr_trigger_handler.py` — import and use generator, replace uuid4()
3. `dt_image_search/instant_sharing/contracts.py` — relax UUID validation in `InstantShareHeaders.validate()`
4. `dt_image_search/instant_sharing/mdns.py` — relax UUID validation in `ConnectionConfig.validate()` and `BootstrapRequest.validate()`

## Testing

- Verify QR URL contains short hex sid (1-2 chars)
- Verify persistence: restart app, sid continues from last value
- Verify wrap-around: after ff, next sid is 1
- Verify existing instant share flow still works end-to-end
- Run existing tests in `test_session.py`
