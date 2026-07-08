# Short Session ID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace UUID session IDs with monotonic hex counters (1-ff) in the PC-to-Mobile QR flow to shorten QR URLs.

**Architecture:** A new `SessionIdGenerator` class persists a counter to disk and emits 1-2 char hex strings. Three Python validation sites relax UUID checks to accept any non-empty string. iOS and web clients need no changes.

**Tech Stack:** Python 3.10, pathlib, threading

## Global Constraints

- Session ID range: `1` to `0xff` (decimal 255)
- Output format: lowercase hex without leading zero (`hex(value)[2:]`)
- Persistence file: `get_app_data_path() / "session_id_counter.txt"`
- Thread safety via `threading.Lock`
- Wrap to `1` when counter exceeds `0xff`

---

### Task 1: Create SessionIdGenerator Module

**Files:**
- Create: `dt_image_search/instant_sharing/session_id_generator.py`
- Test: `dt_image_search/instant_sharing/test_session_id_generator.py`

**Interfaces:**
- Produces: `SessionIdGenerator` class with `next_session_id() -> str` method

- [ ] **Step 1: Write the failing test**

```python
# dt_image_search/instant_sharing/test_session_id_generator.py
"""Unit tests for SessionIdGenerator."""

import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch

from dt_image_search.instant_sharing.session_id_generator import SessionIdGenerator


class TestSessionIdGenerator(unittest.TestCase):
    def setUp(self):
        self._tmp_dir = tempfile.mkdtemp()
        self._counter_file = Path(self._tmp_dir) / "session_id_counter.txt"

    def _make_gen(self) -> SessionIdGenerator:
        return SessionIdGenerator(counter_file=self._counter_file)

    def test_first_id_is_1(self):
        gen = self._make_gen()
        self.assertEqual(gen.next_session_id(), "1")

    def test_ids_increment_monotonically(self):
        gen = self._make_gen()
        self.assertEqual(gen.next_session_id(), "1")
        self.assertEqual(gen.next_session_id(), "2")
        self.assertEqual(gen.next_session_id(), "3")

    def test_hex_format_no_leading_zero(self):
        gen = self._make_gen()
        for _ in range(9):
            gen.next_session_id()
        # 10th call -> value=10 -> hex is "a"
        self.assertEqual(gen.next_session_id(), "a")

    def test_last_id_is_ff(self):
        gen = self._make_gen()
        for _ in range(254):
            gen.next_session_id()
        # 255th call -> value=255 -> hex is "ff"
        self.assertEqual(gen.next_session_id(), "ff")

    def test_wrap_around_after_ff(self):
        gen = self._make_gen()
        for _ in range(255):
            gen.next_session_id()
        # 256th call -> wraps to 1
        self.assertEqual(gen.next_session_id(), "1")

    def test_persistence_across_instances(self):
        gen1 = self._make_gen()
        gen1.next_session_id()  # "1"
        gen1.next_session_id()  # "2"
        gen2 = self._make_gen()
        self.assertEqual(gen2.next_session_id(), "3")

    def test_persistence_wrap_around(self):
        self._counter_file.write_text("255")
        gen = self._make_gen()
        self.assertEqual(gen.next_session_id(), "1")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest dt_image_search/instant_sharing/test_session_id_generator.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'dt_image_search.instant_sharing.session_id_generator'`

- [ ] **Step 3: Write minimal implementation**

```python
# dt_image_search/instant_sharing/session_id_generator.py
"""Monotonic hex session ID generator for instant sharing QR links."""

from __future__ import annotations

import threading
from pathlib import Path


_MAX_COUNTER = 0xFF  # 255


class SessionIdGenerator:
    """Generates short hex session IDs (1..ff) with disk persistence.

    Counter wraps to 1 after surpassing 0xff.
    """

    def __init__(self, *, counter_file: Path) -> None:
        self._counter_file = counter_file
        self._lock = threading.Lock()
        self._current = self._read_persisted()

    def next_session_id(self) -> str:
        with self._lock:
            self._current += 1
            if self._current > _MAX_COUNTER:
                self._current = 1
            self._persist(self._current)
            return hex(self._current)[2:]

    def _read_persisted(self) -> int:
        try:
            text = self._counter_file.read_text().strip()
            value = int(text)
            if 0 < value <= _MAX_COUNTER:
                return value
        except (FileNotFoundError, ValueError):
            pass
        return 0

    def _persist(self, value: int) -> None:
        try:
            self._counter_file.parent.mkdir(parents=True, exist_ok=True)
            self._counter_file.write_text(str(value))
        except OSError:
            pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest dt_image_search/instant_sharing/test_session_id_generator.py -v`
Expected: All 8 tests PASS

- [ ] **Step 5: Commit**

```bash
git add dt_image_search/instant_sharing/session_id_generator.py dt_image_search/instant_sharing/test_session_id_generator.py
git commit -m "feat: add SessionIdGenerator for short hex session IDs"
```

---

### Task 2: Relax UUID Validation in contracts.py

**Files:**
- Modify: `dt_image_search/instant_sharing/contracts.py:123-128,180-181,1-8`

**Interfaces:**
- Consumes: `_normalize_uuid` function (to be replaced)
- Produces: `_require_non_empty` function; `InstantShareHeaders.validate()` accepts non-UUID session_id

- [ ] **Step 1: Write the failing test**

```python
# Add to dt_image_search/instant_sharing/test_session.py (or new file)
"""Test that InstantShareHeaders accepts short hex session IDs."""

import unittest
from dt_image_search.instant_sharing.contracts import InstantShareHeaders


class TestInstantShareHeadersShortSid(unittest.TestCase):
    def test_validate_accepts_short_hex_session_id(self):
        headers = InstantShareHeaders(
            correlation_id="abc123",
            session_id="a",
            device_id="dev1",
        )
        # Should not raise
        headers.validate(requires_signature=False)

    def test_validate_accepts_ff_session_id(self):
        headers = InstantShareHeaders(
            correlation_id="abc123",
            session_id="ff",
            device_id="dev1",
        )
        headers.validate(requires_signature=False)

    def test_validate_rejects_empty_session_id(self):
        headers = InstantShareHeaders(
            correlation_id="abc123",
            session_id="",
            device_id="dev1",
        )
        with self.assertRaises(ValueError):
            headers.validate(requires_signature=False)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v -k "short_sid or ff_session or empty_session"`
Expected: FAIL with `ValueError` from UUID validation on short session_id

- [ ] **Step 3: Implement the change**

In `dt_image_search/instant_sharing/contracts.py`:

Replace the `_normalize_uuid` function (lines 123-128):
```python
def _normalize_uuid(value: str, *, field_name: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{field_name} must not be empty.")
    UUID(normalized)
    return normalized
```
with:
```python
def _require_non_empty(value: str, *, field_name: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{field_name} must not be empty.")
    return normalized
```

In `InstantShareHeaders.validate()` (lines 180-181), replace:
```python
        _normalize_uuid(self.correlation_id, field_name="correlation_id")
        _normalize_uuid(self.session_id, field_name="session_id")
```
with:
```python
        _require_non_empty(self.correlation_id, field_name="correlation_id")
        _require_non_empty(self.session_id, field_name="session_id")
```

Remove the unused `UUID` import (line 8):
```python
from uuid import UUID
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v -k "short_sid or ff_session or empty_session"`
Expected: All 3 tests PASS

- [ ] **Step 5: Run full test_session.py to check no regressions**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add dt_image_search/instant_sharing/contracts.py
git commit -m "feat: relax UUID validation to accept short hex session IDs"
```

---

### Task 3: Relax UUID Validation in mdns.py

**Files:**
- Modify: `dt_image_search/instant_sharing/mdns.py:63-67,144-148,1-11`

**Interfaces:**
- Consumes: `ConnectionConfig.validate()`, `BootstrapRequest.validate()` (UUID checks to remove)
- Produces: Both methods accept non-UUID session_id

- [ ] **Step 1: Write the failing test**

```python
# Add to dt_image_search/instant_sharing/test_session.py
"""Test that ConnectionConfig and BootstrapRequest accept short hex session IDs."""

import unittest
from dt_image_search.instant_sharing.mdns import ConnectionConfig, BootstrapRequest
from dt_image_search.instant_sharing.contracts import InstantShareMetadata, PayloadClass, TargetIntent, TrustMode


class TestConnectionConfigShortSid(unittest.TestCase):
    def test_validate_accepts_short_hex_session_id(self):
        config = ConnectionConfig(
            session_id="a",
            mobile_port=8080,
            mobile_ip_list=("192.168.1.1",),
            correlation_id="abc123",
            metadata=InstantShareMetadata(
                payload_class=PayloadClass.TEXT,
                target_intent=TargetIntent.CLIPBOARD_ONLY,
                trust_mode=TrustMode.TRUSTED_DIRECT,
            ),
        )
        # Should not raise
        config.validate()

    def test_validate_rejects_empty_session_id(self):
        with self.assertRaises(ValueError):
            ConnectionConfig(
                session_id="",
                mobile_port=8080,
                mobile_ip_list=("192.168.1.1",),
                correlation_id="abc123",
                metadata=InstantShareMetadata(
                    payload_class=PayloadClass.TEXT,
                    target_intent=TargetIntent.CLIPBOARD_ONLY,
                    trust_mode=TrustMode.TRUSTED_DIRECT,
                ),
            ).validate()


class TestBootstrapRequestShortSid(unittest.TestCase):
    def test_validate_accepts_short_hex_session_id(self):
        req = BootstrapRequest(
            session_id="ff",
            mobile_port=8080,
            mobile_ip_list=("192.168.1.1",),
            correlation_id="abc123",
            payload_class="text",
            target_intent="clipboard_only",
        )
        # Should not raise
        req.validate()

    def test_validate_rejects_empty_session_id(self):
        with self.assertRaises(ValueError):
            BootstrapRequest(
                session_id="",
                mobile_port=8080,
                mobile_ip_list=("192.168.1.1",),
                correlation_id="abc123",
                payload_class="text",
                target_intent="clipboard_only",
            ).validate()


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v -k "short_sid or empty_session"`
Expected: FAIL with `ValueError` from UUID validation

- [ ] **Step 3: Implement the changes**

In `dt_image_search/instant_sharing/mdns.py`:

In `ConnectionConfig.validate()` (lines 63-67), replace:
```python
    def validate(self) -> None:
        from uuid import UUID

        UUID(self.session_id)
        UUID(self.correlation_id)
```
with:
```python
    def validate(self) -> None:
        if not self.session_id.strip():
            raise ValueError("session_id must not be empty.")
        if not self.correlation_id.strip():
            raise ValueError("correlation_id must not be empty.")
```

In `BootstrapRequest.validate()` (lines 144-148), replace:
```python
    def validate(self) -> None:
        from uuid import UUID

        UUID(self.session_id)
        UUID(self.correlation_id)
```
with:
```python
    def validate(self) -> None:
        if not self.session_id.strip():
            raise ValueError("session_id must not be empty.")
        if not self.correlation_id.strip():
            raise ValueError("correlation_id must not be empty.")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v -k "short_sid or empty_session"`
Expected: All tests PASS

- [ ] **Step 5: Run full test_session.py to check no regressions**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add dt_image_search/instant_sharing/mdns.py
git commit -m "feat: relax UUID validation in ConnectionConfig and BootstrapRequest"
```

---

### Task 4: Integrate Generator into QR Trigger Handler

**Files:**
- Modify: `dt_image_search/instant_sharing/qr_trigger_handler.py:1-11,130`

**Interfaces:**
- Consumes: `SessionIdGenerator.next_session_id() -> str`
- Produces: `QRTriggerHandler` uses generator instead of `uuid.uuid4()`

- [ ] **Step 1: Write the failing test**

```python
# Add to dt_image_search/instant_sharing/test_session.py
"""Test that QRTriggerHandler uses short hex session IDs."""

import unittest
import tempfile
from pathlib import Path
from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler
from dt_image_search.instant_sharing.session_id_generator import SessionIdGenerator


class TestQRTriggerHandlerShortSid(unittest.TestCase):
    def setUp(self):
        self._tmp_dir = tempfile.mkdtemp()
        self._counter_file = Path(self._tmp_dir) / "session_id_counter.txt"
        self._generator = SessionIdGenerator(counter_file=self._counter_file)
        self._handler = QRTriggerHandler(session_id_generator=self._generator)

    def test_handle_trigger_returns_short_session_id(self):
        body = {"type": "text", "content": "hello"}
        result = self._handler.handle_trigger(body)
        sid = result["session_id"]
        # Should be 1-2 hex chars, not a UUID
        self.assertRegex(sid, r"^[0-9a-f]{1,2}$")
        self.assertNotIn("-", sid)

    def test_session_ids_increment(self):
        r1 = self._handler.handle_trigger({"type": "text", "content": "a"})
        r2 = self._handler.handle_trigger({"type": "text", "content": "b"})
        self.assertEqual(r1["session_id"], "1")
        self.assertEqual(r2["session_id"], "2")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v -k "short_sid or increment"`
Expected: FAIL — `QRTriggerHandler.__init__` does not accept `session_id_generator` parameter

- [ ] **Step 3: Implement the change**

In `dt_image_search/instant_sharing/qr_trigger_handler.py`:

Add import at the top (after existing imports):
```python
from dt_image_search.instant_sharing.session_id_generator import SessionIdGenerator
```

In `QRTriggerHandler.__init__` (lines 40-55), add the parameter and store it:
```python
    def __init__(
        self,
        *,
        trust_session_registry: TrustSessionRegistry | None = None,
        on_stash_created: Callable[[StashEntry], None] | None = None,
        on_stash_expired: Callable[[str], None] | None = None,
        on_stash_claimed: Callable[[str, str], None] | None = None,
        session_id_generator: SessionIdGenerator | None = None,
    ) -> None:
        self._trust_session_registry = trust_session_registry
        self._stashes: dict[str, StashEntry] = {}
        self._session_ids: dict[str, str] = {}
        self._lock = threading.Lock()
        self._timers: dict[str, threading.Timer] = {}
        self._on_stash_created = on_stash_created
        self._on_stash_expired = on_stash_expired
        self._on_stash_claimed = on_stash_claimed
        self._session_id_generator = session_id_generator
```

At line 130, replace:
```python
        session_id = str(uuid.uuid4())
```
with:
```python
        if self._session_id_generator is not None:
            session_id = self._session_id_generator.next_session_id()
        else:
            session_id = str(uuid.uuid4())
```

Remove the now-unused `import uuid` (line 8) if it's no longer used elsewhere in the file. Check first — `stash_id` generation at lines 195 and 312 still uses `uuid.uuid4()`, so keep the import.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v -k "short_sid or increment"`
Expected: All tests PASS

- [ ] **Step 5: Run full test_session.py to check no regressions**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add dt_image_search/instant_sharing/qr_trigger_handler.py
git commit -m "feat: integrate SessionIdGenerator into QRTriggerHandler"
```

---

### Task 5: Wire Generator into Runtime Bootstrap

**Files:**
- Modify: `dt_image_search/instant_sharing/runtime.py`

**Interfaces:**
- Consumes: `SessionIdGenerator`, `get_app_data_path()`
- Produces: `QRTriggerHandler` created with generator in `InstantShareRuntime`

- [ ] **Step 1: Find the QRTriggerHandler creation site**

Read `dt_image_search/instant_sharing/runtime.py` and find where `QRTriggerHandler` is instantiated.

- [ ] **Step 2: Implement the change**

Add import:
```python
from dt_image_search.instant_sharing.session_id_generator import SessionIdGenerator
```

Where `QRTriggerHandler` is created, add the generator:
```python
session_id_gen = SessionIdGenerator(
    counter_file=get_app_data_path() / "session_id_counter.txt"
)
handler = QRTriggerHandler(
    ...,
    session_id_generator=session_id_gen,
)
```

- [ ] **Step 3: Run existing tests**

Run: `python -m pytest dt_image_search/instant_sharing/test_session.py -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add dt_image_search/instant_sharing/runtime.py
git commit -m "feat: wire SessionIdGenerator into runtime bootstrap"
```

---

### Task 6: Run Full Test Suite and Verify

**Files:**
- Test: `dt_image_search/instant_sharing/test_session.py`
- Test: `dt_image_search/instant_sharing/test_session_id_generator.py`

- [ ] **Step 1: Run all instant sharing tests**

Run: `python -m pytest dt_image_search/instant_sharing/ -v`
Expected: All tests PASS

- [ ] **Step 2: Verify QR URL format manually**

Run: `python -c "
from dt_image_search.instant_sharing.session_id_generator import SessionIdGenerator
from pathlib import Path
import tempfile
gen = SessionIdGenerator(counter_file=Path(tempfile.mkdtemp()) / 'counter.txt')
for i in range(5):
    print(f'sid={gen.next_session_id()}')
"`
Expected output:
```
sid=1
sid=2
sid=3
sid=4
sid=5
```

- [ ] **Step 3: Final commit with all changes**

```bash
git add -A
git commit -m "feat: short hex session IDs for instant sharing QR links"
```
