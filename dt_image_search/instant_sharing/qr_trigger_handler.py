from __future__ import annotations

import logging
import secrets
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry

_logger = logging.getLogger(__name__)

TRIGGER_PATH = "/api/instant-share/v1/qr-trigger"
OPT_CODE_TTL_SECONDS = 300
MAX_CLAIM_ATTEMPTS = 3
DEFAULT_MAX_BATCH_FILE_COUNT = 50


@dataclass
class StashEntry:
    stash_id: str
    content_type: str
    content: str | None
    files: list = field(default_factory=list)  # list[FileEntry] — avoids circular import
    opt_code: str = ""
    created_at: float = 0.0
    expires_at: float = 0.0
    attempt_count: int = 0
    max_attempts: int = MAX_CLAIM_ATTEMPTS
    claimed: bool = False
    expired: bool = False


class QRTriggerHandler:
    def __init__(
        self,
        *,
        trust_session_registry: TrustSessionRegistry | None = None,
        on_stash_created: Callable[[StashEntry], None] | None = None,
        on_stash_expired: Callable[[str], None] | None = None,
        on_stash_claimed: Callable[[str, str], None] | None = None,
    ) -> None:
        self._trust_session_registry = trust_session_registry
        self._stashes: dict[str, StashEntry] = {}
        self._session_ids: dict[str, str] = {}
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

    @property
    def _max_batch_file_count(self) -> int:
        try:
            from dt_image_search.model.dts_config import is_instant_share_feature_enabled
            # Read from config if available, otherwise use default
            import configparser
            config = configparser.ConfigParser()
            # Try reading the config file used by the app
            # Fall back to default if not available
            try:
                from dt_image_search.model.dts_config import _config as _dts_config
                raw = _dts_config.get("instant_share", {}).get("max_batch_file_count", DEFAULT_MAX_BATCH_FILE_COUNT)
                return int(raw)
            except Exception:
                return DEFAULT_MAX_BATCH_FILE_COUNT
        except Exception:
            return DEFAULT_MAX_BATCH_FILE_COUNT

    def handle_trigger(self, body: dict[str, object]) -> dict[str, object]:
        payload_type = body.get("type")
        if payload_type not in ("text", "file", "html"):
            return {"_status": 400, "status": "error", "error": "Invalid type, must be 'text', 'file', or 'html'"}

        if payload_type == "text":
            content = body.get("content")
            if not content or not isinstance(content, str):
                return {"_status": 400, "status": "error", "error": "Missing or invalid 'content' for text type"}
            stash = self._create_text_stash(content_type="text/plain", content=content)

        elif payload_type == "html":
            content = body.get("content")
            if not content or not isinstance(content, str):
                return {"_status": 400, "status": "error", "error": "Missing or invalid 'content' for html type"}
            stash = self._create_text_stash(content_type="text/html", content=content)

        else:
            # type "file" — the only path for file sharing
            files_raw = body.get("files")
            if files_raw is not None:
                if not isinstance(files_raw, list):
                    return {"_status": 400, "status": "error", "error": "'files' must be an array"}
                stash = self._create_file_stash(files_raw)
            else:
                # Legacy single-file format: wrap into one-element files list
                file_path = body.get("file_path")
                if not file_path or not isinstance(file_path, str):
                    return {"_status": 400, "status": "error", "error": "Missing 'files' array or 'file_path'"}
                filename = body.get("filename", "")
                if not isinstance(filename, str):
                    filename = ""
                legacy_entry: dict[str, object] = {"file_path": file_path}
                if filename:
                    legacy_entry["filename"] = filename
                stash = self._create_file_stash([legacy_entry])

        session_id = str(uuid.uuid4())
        if self._trust_session_registry is not None:
            from dt_image_search.instant_sharing.trust_server import TrustFlowType
            self._trust_session_registry.create_session(
                session_id=session_id,
                correlation_id=session_id,
                flow_type=TrustFlowType.PC_TO_MOBILE,
                opt_code=stash.opt_code,
                stash_id=stash.stash_id,
            )
            with self._lock:
                self._session_ids[stash.stash_id] = session_id
            _logger.info(
                "[QRTriggerHandler] trust session created for pc-to-mobile flow session_id=%s stash_id=%s",
                session_id, stash.stash_id,
            )

        if self._on_stash_created is not None:
            self._on_stash_created(stash)

        response: dict[str, object] = {
            "status": "stashed",
            "session_id": session_id,
            "stash_id": stash.stash_id,
            "content_type": stash.content_type,
        }
        if stash.files:
            response["file_count"] = len(stash.files)
        return response

    def _create_file_stash(self, files_raw: list) -> StashEntry:
        """Process a multi-file batch trigger request."""
        max_count = self._max_batch_file_count
        if len(files_raw) > max_count:
            raise ValueError(f"Too many files. Maximum is {max_count}.")
        if len(files_raw) == 0:
            raise ValueError("files list must not be empty.")

        from dt_image_search.instant_sharing.contracts import FileEntry

        file_entries: list = []
        for item in files_raw:
            if not isinstance(item, dict):
                raise ValueError("Each entry in files must be an object with 'file_path'.")
            fp = item.get("file_path")
            if not fp or not isinstance(fp, str):
                raise ValueError("Missing or invalid 'file_path' in files entry.")
            if not Path(fp).is_file():
                raise ValueError(f"File not found: {fp}")
            fn = item.get("filename", "")
            if not isinstance(fn, str):
                fn = ""
            ct = self._detect_mime(fp)
            size = 0
            try:
                size = Path(fp).stat().st_size
            except OSError:
                pass
            file_entries.append(FileEntry(
                file_path=fp,
                filename=fn or None,
                content_type=ct,
                size_bytes=size,
            ))

        stash_id = str(uuid.uuid4())
        now = time.time()
        opt_code = self._generate_opt_code()
        entry = StashEntry(
            stash_id=stash_id,
            content_type="multi/image",
            content=None,
            files=file_entries,
            opt_code=opt_code,
            created_at=now,
            expires_at=now + OPT_CODE_TTL_SECONDS,
        )
        with self._lock:
            self._stashes[stash_id] = entry
        self._start_expiry_timer(stash_id)
        _logger.info(
            "Batch stash created: id=%s count=%d opt=%s ttl=%ds",
            stash_id, len(file_entries), opt_code, OPT_CODE_TTL_SECONDS,
        )
        return entry

    def get_session_id_for_stash(self, stash_id: str) -> str | None:
        with self._lock:
            return self._session_ids.get(stash_id)

    def _get_peer_device_name_for_stash(self, stash_id: str) -> str:
        session_id = self.get_session_id_for_stash(stash_id)
        if session_id is None or self._trust_session_registry is None:
            return ""
        trust_session = self._trust_session_registry.get_session(session_id)
        if trust_session is None:
            return ""
        return trust_session.peer_device_name

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

    def _create_text_stash(
        self,
        *,
        content_type: str,
        content: str,
    ) -> StashEntry:
        stash_id = str(uuid.uuid4())
        now = time.time()
        opt_code = self._generate_opt_code()
        from dt_image_search.instant_sharing.contracts import FileEntry
        files_list = [FileEntry(
            file_path="",
            content_type=content_type,
            content=content,
        )]
        entry = StashEntry(
            stash_id=stash_id,
            content_type=content_type,
            content=content,
            files=files_list,
            opt_code=opt_code,
            created_at=now,
            expires_at=now + OPT_CODE_TTL_SECONDS,
        )
        with self._lock:
            self._stashes[stash_id] = entry
        self._start_expiry_timer(stash_id)
        _logger.info("Stash created: id=%s type=%s opt=%s ttl=%ds", stash_id, content_type, opt_code, OPT_CODE_TTL_SECONDS)
        return entry

    def retrieve_stash_content(self, stash_id: str) -> dict[str, object]:
        """Retrieve stash manifest for the /transfer/manifest endpoint.
        Always returns a JSON manifest with file_count and files array.
        Actual file bytes are served by the per-index /transfer/download/<index> endpoint.
        """
        stash_id = stash_id.strip()
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

        # Manifest fetch is discovery-only — do not claim the stash.
        # Individual files are claimed on download via retrieve_stash_file.

        _logger.info(
            "[QRTriggerHandler] stash manifest retrieved: id=%s file_count=%d",
            stash_id, len(entry.files),
        )

        # Build manifest from files list — covers text, html, and file stashes uniformly
        manifest_files: list[dict[str, object]] = []
        for i, fe in enumerate(entry.files):
            item: dict[str, object] = {
                "index": i,
                "type": fe.entry_type,
            }
            if fe.content is not None:
                item["content"] = fe.content
                item["content_type"] = fe.content_type
            else:
                item["filename"] = fe.filename or ""
                item["content_type"] = fe.content_type
                item["size_bytes"] = fe.size_bytes
            manifest_files.append(item)

        if not manifest_files:
            return {"_status": 500, "status": "error", "error": "Invalid stash state"}

        return {
            "_status": 200,
            "status": "ok",
            "file_count": len(manifest_files),
            "files": manifest_files,
        }

    def retrieve_stash_file(self, stash_id: str, file_index: int) -> tuple[int, bytes, str, str]:
        """Retrieve a single file's bytes from a stash by index.
        Returns (status_code, bytes, content_type, filename).
        """
        stash_id = stash_id.strip()
        with self._lock:
            entry = self._stashes.get(stash_id)

        if entry is None:
            return 404, b"", "", ""
        if entry.expired:
            return 410, b"", "", ""

        if not entry.files:
            return 400, b"", "", ""
        if file_index < 0 or file_index >= len(entry.files):
            return 400, b"", "", ""
        fe = entry.files[file_index]
        try:
            with open(fe.file_path, "rb") as f:
                file_bytes = f.read()
        except FileNotFoundError:
            self._invalidate_stash(entry, expired=True)
            return 410, b"", "", ""

        # Claim on first file download
        if not entry.claimed:
            entry.claimed = True
            self._cancel_timer(stash_id)
            if self._on_stash_claimed is not None:
                peer_name = self._get_peer_device_name_for_stash(stash_id)
                self._on_stash_claimed(stash_id, peer_name)

        return 200, file_bytes, fe.content_type, fe.filename or ""

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
