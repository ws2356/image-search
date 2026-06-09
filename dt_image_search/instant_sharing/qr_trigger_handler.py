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
        if payload_type not in ("text", "image", "html"):
            return {"_status": 400, "status": "error", "error": "Invalid type, must be 'text', 'image', or 'html'"}

        if payload_type == "text":
            content = body.get("content")
            if not content or not isinstance(content, str):
                return {"_status": 400, "status": "error", "error": "Missing or invalid 'content' for text type"}
            stash = self._create_stash(content_type="text/plain", content=content, file_path=None, filename=None)

        elif payload_type == "html":
            content = body.get("content")
            if not content or not isinstance(content, str):
                return {"_status": 400, "status": "error", "error": "Missing or invalid 'content' for html type"}
            stash = self._create_stash(content_type="text/html", content=content, file_path=None, filename=None)

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

    def handle_claim(self, body: dict[str, object]) -> dict[str, object]:
        stash_id = body.get("stash_id")
        opt_code = body.get("opt")
        if not isinstance(stash_id, str) or not isinstance(opt_code, str):
            return {"_status": 400, "status": "error", "error": "Missing stash_id or opt"}

        with self._lock:
            entry = self._stashes.get(stash_id)

        if entry is None:
            return {"_status": 404, "status": "not_found", "error": "Stash not found"}

        if entry.expired:
            return {"_status": 410, "status": "expired", "error": "Stash has expired"}

        if entry.claimed:
            return {"_status": 410, "status": "expired", "error": "Stash already claimed"}

        if time.time() > entry.expires_at:
            self._invalidate_stash(entry, expired=True)
            return {"_status": 410, "status": "expired", "error": "Stash has expired"}

        if entry.opt_code != opt_code:
            entry.attempt_count += 1
            remaining = entry.max_attempts - entry.attempt_count
            _logger.warning("Invalid opt-code for stash %s (attempt %d/%d)", stash_id, entry.attempt_count, entry.max_attempts)
            if entry.attempt_count >= entry.max_attempts:
                self._invalidate_stash(entry, expired=True)
                return {"_status": 410, "status": "expired", "error": "Too many failed attempts"}
            return {"_status": 401, "status": "unauthorized", "error": "Invalid opt-code"}

        self._cancel_timer(stash_id)
        entry.claimed = True
        if self._on_stash_claimed is not None:
            self._on_stash_claimed(stash_id)

        _logger.info("Stash claimed: id=%s type=%s", stash_id, entry.content_type)

        if entry.content is not None:
            _logger.info("Stash content delivered: id=%s content_type=%s", stash_id, entry.content_type)
            return {
                "status": "claimed",
                "content_type": entry.content_type,
                "content": entry.content,
            }

        if entry.file_path is not None:
            try:
                with open(entry.file_path, "rb") as f:
                    file_bytes = f.read()
            except FileNotFoundError:
                self._invalidate_stash(entry, expired=True)
                return {"_status": 410, "status": "expired", "error": "Source file no longer available"}
            _logger.info("Stash file delivered: id=%s content_type=%s filename=%s path=%s filesize=%d", stash_id, entry.content_type, entry.filename, entry.file_path, len(file_bytes))
            return {
                "status": "claimed",
                "content_type": entry.content_type,
                "filename": entry.filename or "",
                "file_bytes_base64": file_bytes,
            }

        return {"_status": 500, "status": "error", "error": "Invalid stash state"}

    def cancel_stash(self, stash_id: str) -> bool:
        with self._lock:
            entry = self._stashes.get(stash_id)
            if entry is None or entry.claimed or entry.expired:
                return False
            entry.expired = True
            entry.claimed = False
            self._cancel_timer(stash_id)
        _logger.info("Stash cancelled by user: id=%s", stash_id)
        if self._on_stash_expired is not None:
            self._on_stash_expired(stash_id)
        return True

    def _invalidate_stash(self, entry: StashEntry, *, expired: bool) -> None:
        entry.expired = expired
        entry.claimed = False
        self._cancel_timer(entry.stash_id)
        if self._on_stash_expired is not None:
            self._on_stash_expired(entry.stash_id)

    def _start_expiry_timer(self, stash_id: str) -> None:
        timer = threading.Timer(OPT_CODE_TTL_SECONDS, self._on_expiry_timer_fired, args=[stash_id])
        timer.daemon = True
        self._timers[stash_id] = timer
        timer.start()

    def _on_expiry_timer_fired(self, stash_id: str) -> None:
        with self._lock:
            entry = self._stashes.get(stash_id)
            if entry is None or entry.claimed:
                return
            entry.expired = True
        _logger.info("Stash expired: id=%s", stash_id)
        if self._on_stash_expired is not None:
            self._on_stash_expired(stash_id)

    def _cancel_timer(self, stash_id: str) -> None:
        timer = self._timers.pop(stash_id, None)
        if timer is not None:
            timer.cancel()

    @staticmethod
    def _generate_opt_code() -> str:
        return f"{secrets.randbelow(1_000_000):06d}"
