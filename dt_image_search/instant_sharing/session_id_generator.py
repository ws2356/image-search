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
