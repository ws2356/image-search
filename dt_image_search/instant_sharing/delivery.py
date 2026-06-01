from __future__ import annotations

import re
from pathlib import Path
from typing import Protocol

from dt_image_search.instant_sharing.contracts import (
    DeliveryResult,
    DeliveryTargetResult,
    DownloadedImagePayload,
    DownloadedTextPayload,
    ErrorCode,
    PayloadClass,
    SessionState,
)
from dt_image_search.instant_sharing.errors import InstantShareError


class ClipboardWriter(Protocol):
    def write_text(self, text: str) -> None:
        ...

    def write_image_bytes(self, image_bytes: bytes) -> None:
        ...


class QtClipboardWriter:
    def write_text(self, text: str) -> None:
        from PySide6.QtWidgets import QApplication

        application = QApplication.instance()
        if application is None:
            raise RuntimeError("Qt application instance is not available.")
        application.clipboard().setText(text)

    def write_image_bytes(self, image_bytes: bytes) -> None:
        from PySide6.QtGui import QImage
        from PySide6.QtWidgets import QApplication

        application = QApplication.instance()
        if application is None:
            raise RuntimeError("Qt application instance is not available.")
        image = QImage.fromData(image_bytes)
        if image.isNull():
            raise ValueError("image_bytes do not decode into a valid image.")
        application.clipboard().setImage(image)


class InstantShareDeliveryService:
    def __init__(
        self,
        *,
        clipboard_writer: ClipboardWriter | None = None,
        image_delivery_mode: str = "file",
        downloads_dir: Path | None = None,
    ) -> None:
        self._clipboard_writer = clipboard_writer
        self._image_delivery_mode = image_delivery_mode
        self._downloads_dir = downloads_dir

    def deliver(self, payload: DownloadedTextPayload | DownloadedImagePayload) -> DeliveryResult:
        if isinstance(payload, DownloadedTextPayload):
            return self.deliver_text(payload)
        return self.deliver_image(payload)

    def deliver_text(self, payload: DownloadedTextPayload) -> DeliveryResult:
        if self._clipboard_writer is None:
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Text payload delivery requires a clipboard writer.",
            )
        self._clipboard_writer.write_text(payload.text_utf8)
        return DeliveryResult(
            state=SessionState.DONE,
            target_result=DeliveryTargetResult(clipboard_written=True),
        )

    def deliver_image(self, payload: DownloadedImagePayload) -> DeliveryResult:
        if self._image_delivery_mode == "clipboard":
            if self._clipboard_writer is None:
                raise InstantShareError(
                    ErrorCode.PAYLOAD_UNREADABLE,
                    "Image clipboard delivery requires a clipboard writer.",
                )
            self._clipboard_writer.write_image_bytes(payload.image_bytes)
            return DeliveryResult(
                state=SessionState.DONE,
                target_result=DeliveryTargetResult(clipboard_written=True),
            )

        output_path = self._write_image_file(payload)
        return DeliveryResult(
            state=SessionState.DONE,
            target_result=DeliveryTargetResult(
                clipboard_written=False,
                files_written_count=1,
                output_paths=(output_path.as_posix(),),
            ),
        )

    def _write_image_file(self, payload: DownloadedImagePayload) -> Path:
        downloads_dir = self._default_downloads_dir().resolve()
        downloads_dir.mkdir(parents=True, exist_ok=True)
        filename = self._resolve_filename(payload)
        output_path = self._resolve_output_path(downloads_dir=downloads_dir, filename=filename)
        output_path.write_bytes(payload.image_bytes)
        return output_path

    def _default_downloads_dir(self) -> Path:
        if self._downloads_dir is not None:
            return self._downloads_dir
        return Path.home() / "Downloads"

    def _resolve_filename(self, payload: DownloadedImagePayload) -> str:
        if payload.metadata.payload_class is not PayloadClass.IMAGE:
            raise InstantShareError(
                ErrorCode.TARGET_INTENT_INVALID_FOR_PAYLOAD,
                "Instant-share delivery currently supports image binary payloads only.",
            )
        if payload.filename is not None and payload.filename.strip():
            filename = payload.filename.strip()
        else:
            filename = f"instant-share-image{self._infer_extension(payload.content_type)}"
        if Path(filename).is_absolute() or ".." in Path(filename).parts:
            raise InstantShareError(
                ErrorCode.DELIVERY_PATH_INVALID,
                f"Unsafe output filename requested: {filename}",
            )
        return self._sanitize_filename(Path(filename).name)

    def _resolve_output_path(self, *, downloads_dir: Path, filename: str) -> Path:
        candidate = (downloads_dir / filename).resolve()
        if not self._is_within(candidate, downloads_dir):
            raise InstantShareError(
                ErrorCode.DELIVERY_PATH_INVALID,
                f"Resolved delivery path escapes the downloads directory: {candidate}",
            )
        if not candidate.exists():
            return candidate

        stem = candidate.stem
        suffix = candidate.suffix
        collision_index = 2
        while True:
            next_candidate = (downloads_dir / f"{stem}-{collision_index}{suffix}").resolve()
            if not self._is_within(next_candidate, downloads_dir):
                raise InstantShareError(
                    ErrorCode.DELIVERY_PATH_INVALID,
                    f"Resolved delivery path escapes the downloads directory: {next_candidate}",
                )
            if not next_candidate.exists():
                return next_candidate
            collision_index += 1

    @staticmethod
    def _sanitize_filename(filename: str) -> str:
        sanitized = re.sub(r"[^A-Za-z0-9._-]+", "-", filename).strip("-.")
        if not sanitized:
            return "instant-share-image.bin"
        return sanitized

    @staticmethod
    def _infer_extension(content_type: str) -> str:
        normalized_content_type = content_type.strip().lower()
        if normalized_content_type == "image/png":
            return ".png"
        if normalized_content_type in {"image/jpeg", "image/jpg"}:
            return ".jpg"
        if normalized_content_type == "image/webp":
            return ".webp"
        return ".bin"

    @staticmethod
    def _is_within(path: Path, base_dir: Path) -> bool:
        try:
            path.relative_to(base_dir)
        except ValueError:
            return False
        return True