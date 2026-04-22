from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
import tempfile
from typing import BinaryIO, Protocol

from dt_image_search.mobile.transport.contracts import TransferAssetUploadPayload

TRANSFER_ASSET_STREAM_STATE_FIELD = "stream_state"
TRANSFER_ASSET_STREAM_STATE_START = "start"
TRANSFER_ASSET_STREAM_STATE_CHUNK = "chunk"
TRANSFER_ASSET_STREAM_STATE_COMPLETE = "complete"
TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES = 100 * 1024 * 1024


class _Digest(Protocol):
    def update(self, data: bytes) -> object:
        ...

    def hexdigest(self) -> str:
        ...


@dataclass
class _PendingTransferAssetUpload:
    request_id: str
    metadata_payload: dict[str, object]
    temp_file_path: Path
    temp_file_handle: BinaryIO
    content_sha1: _Digest
    content_length: int = 0

    def append_chunk(self, chunk: bytes) -> None:
        self.temp_file_handle.write(chunk)
        self.content_sha1.update(chunk)
        self.content_length += len(chunk)

    def to_payload(self) -> TransferAssetUploadPayload:
        self.temp_file_handle.flush()
        self.temp_file_handle.close()
        return TransferAssetUploadPayload(
            metadata_payload=self.metadata_payload,
            body_stream=None,
            content_length=self.content_length,
            temp_file_path=str(self.temp_file_path),
            content_sha1=self.content_sha1.hexdigest(),
        )

    def close(self) -> None:
        try:
            self.temp_file_handle.close()
        finally:
            try:
                self.temp_file_path.unlink(missing_ok=True)
            except OSError:
                return


class TransferAssetUploadStream:
    def __init__(self):
        self._pending_by_request_id: dict[str, _PendingTransferAssetUpload] = {}
        self._active_request_id: str | None = None

    @property
    def active_request_id(self) -> str | None:
        active_request_id = self._active_request_id
        if (
            active_request_id is not None
            and active_request_id in self._pending_by_request_id
        ):
            return active_request_id
        if len(self._pending_by_request_id) == 1:
            return next(iter(self._pending_by_request_id.keys()))
        return None

    def start(
        self,
        *,
        request_id: str,
        metadata_payload: dict[str, object],
        exclusive: bool = False,
    ) -> None:
        staged_file = tempfile.NamedTemporaryFile(
            mode="w+b",
            prefix="dtis-transfer-asset-",
            suffix=".part",
            delete=False,
        )
        pending_upload = _PendingTransferAssetUpload(
            request_id=request_id,
            metadata_payload=metadata_payload,
            temp_file_path=Path(staged_file.name),
            temp_file_handle=staged_file,
            content_sha1=hashlib.sha1(),
            content_length=0,
        )
        if exclusive:
            self.clear()
        existing_upload = self._pending_by_request_id.pop(request_id, None)
        if existing_upload is not None:
            existing_upload.close()
        self._pending_by_request_id[request_id] = pending_upload
        self._active_request_id = request_id

    def append_chunk(
        self,
        *,
        chunk: bytes,
        request_id: str | None = None,
    ) -> str | None:
        if not chunk:
            return None
        if len(chunk) > TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES:
            return (
                "Desktop rejected transfer asset stream chunk because the binary payload exceeded "
                f"{TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES} bytes."
            )

        resolved_request_id = request_id
        if resolved_request_id is None:
            resolved_request_id = self.active_request_id
        if resolved_request_id is None:
            if self._pending_by_request_id:
                return (
                    "Desktop rejected transfer asset stream chunk because request ids do not match the "
                    "active binary stream."
                )
            return (
                "Desktop ignored transfer asset stream chunk because metadata was not received first."
            )

        pending_upload = self._pending_by_request_id.get(resolved_request_id)
        if pending_upload is None:
            if self._pending_by_request_id:
                return (
                    "Desktop rejected transfer asset stream chunk because request ids do not match the "
                    "active binary stream."
                )
            return (
                "Desktop ignored transfer asset stream chunk because metadata was not received first."
            )

        pending_upload.append_chunk(chunk)
        self._active_request_id = pending_upload.request_id
        return None

    def complete(self, *, request_id: str) -> TransferAssetUploadPayload | str:
        pending_upload = self._pending_by_request_id.pop(request_id, None)
        if pending_upload is None:
            if self._pending_by_request_id:
                return (
                    "Desktop rejected transfer asset completion because request ids do not match the "
                    "active binary stream."
                )
            return "Desktop did not receive transfer asset stream metadata before completion."
        if self._active_request_id == request_id:
            self._active_request_id = None
        return pending_upload.to_payload()

    def discard(self, *, request_id: str) -> dict[str, object] | None:
        pending_upload = self._pending_by_request_id.pop(request_id, None)
        if pending_upload is None:
            return None
        if self._active_request_id == request_id:
            self._active_request_id = None
        metadata_payload = dict(pending_upload.metadata_payload)
        pending_upload.close()
        return metadata_payload

    def clear(self) -> None:
        pending_uploads = list(self._pending_by_request_id.values())
        self._pending_by_request_id = {}
        self._active_request_id = None
        for pending_upload in pending_uploads:
            pending_upload.close()
