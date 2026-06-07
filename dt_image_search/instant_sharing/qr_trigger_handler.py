from __future__ import annotations

import logging
import secrets
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

_logger = logging.getLogger(__name__)

TRIGGER_PATH = "/api/instant-share/v1/qr-trigger"
CLAIM_PATH = "/api/instant-share/v1/qr-claim"
OPT_CODE_TTL_SECONDS = 300
MAX_CLAIM_ATTEMPTS = 3


@dataclass
class StashEntry:
    stash_id: str
    content_type: str
    content: str | None
    file_path: str | None
    filename: str | None
    opt_code: str
    created_at: float
    expires_at: float
    attempt_count: int = 0
    max_attempts: int = MAX_CLAIM_ATTEMPTS
    claimed: bool = False
    expired: bool = False


class QRTriggerHandler:
    def __init__(
        self,
        *,
        on_stash_created: Callable[[StashEntry], None] | None = None,
        on_stash_expired: Callable[[str], None] | None = None,
        on_stash_claimed: Callable[[str], None] | None = None,
    ) -> None:
        self._stashes: dict[str, StashEntry] = {}
        self._lock = threading.Lock()
        self._timers: dict[str, threading.Timer] = {}
        self._on_stash_created = on_stash_created
        self._on_stash_expired = on_stash_expired
        self._on_stash_claimed = on_stash_claimed

    @property
    def active_stash(self) -> StashEntry | None:
        with self._lock:
            for entry in self._stashes.values():
                if not entry.claimed and not entry.expired:
                    return entry
            return None

    def get_stash(self, stash_id: str) -> StashEntry | None:
        with self._lock:
            return self._stashes.get(stash_id)

    def handle_trigger(self, body: dict[str, object]) -> dict[str, object]:
        payload_type = body.get("type")
        if payload_type not in ("text", "image"):
            return {"_status": 400, "status": "error", "error": "Invalid type, must be 'text' or 'image'"}

        if payload_type == "text":
            content = body.get("content")
            if not content or not isinstance(content, str):
                return {"_status": 400, "status": "error", "error": "Missing or invalid 'content' for text type"}
            stash = self._create_stash(content_type="text/plain", content=content, file_path=None, filename=None)

        else:
            file_path = body.get("file_path")
            if not file_path or not isinstance(file_path, str):
                return {"_status": 400, "status": "error", "error": "Missing or invalid 'file_path' for image type"}
            if not Path(file_path).is_file():
                return {"_status": 400, "status": "error", "error": "File not found"}
            filename = body.get("filename", "")
            if not isinstance(filename, str):
                filename = ""
            content_type = self._detect_mime(file_path)
            stash = self._create_stash(content_type=content_type, content=None, file_path=file_path, filename=filename or None)

        return {
            "status": "stashed",
            "stash_id": stash.stash_id,
            "content_type": stash.content_type,
        }

    @staticmethod
    def _detect_mime(file_path: str) -> str:
        lower = file_path.lower()
        if lower.endswith(".png"):
            return "image/png"
        if lower.endswith((".jpg", ".jpeg")):
            return "image/jpeg"
        if lower.endswith(".gif"):
            return "image/gif"
        if lower.endswith(".webp"):
            return "image/webp"
        if lower.endswith(".bmp"):
            return "image/bmp"
        return "application/octet-stream"

    def _create_stash(
        self,
        *,
        content_type: str,
        content: str | None,
        file_path: str | None,
        filename: str | None,
    ) -> StashEntry:
        stash_id = str(uuid.uuid4())
        now = time.time()
        opt_code = self._generate_opt_code()
        entry = StashEntry(
            stash_id=stash_id,
            content_type=content_type,
            content=content,
            file_path=file_path,
            filename=filename,
            opt_code=opt_code,
            created_at=now,
            expires_at=now + OPT_CODE_TTL_SECONDS,
        )
        with self._lock:
            self._stashes[stash_id] = entry
        self._start_expiry_timer(stash_id)
        _logger.info("Stash created: id=%s type=%s opt=%s ttl=%ds", stash_id, content_type, opt_code, OPT_CODE_TTL_SECONDS)
        if self._on_stash_created is not None:
            self._on_stash_created(entry)
        return entry

    @staticmethod
    def _generate_opt_code() -> str:
        return f"{secrets.randbelow(1_000_000):06d}"
