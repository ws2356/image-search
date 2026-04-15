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
        self._pending: _PendingTransferAssetUpload | None = None

    @property
    def active_request_id(self) -> str | None:
        pending_upload = self._pending
        if pending_upload is None:
            return None
        return pending_upload.request_id

    def start(self, *, request_id: str, metadata_payload: dict[str, object]) -> None:
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
        if self._pending is not None:
            self._pending.close()
        self._pending = pending_upload

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

        pending_upload = self._pending
        if pending_upload is None:
            return (
                "Desktop ignored transfer asset stream chunk because metadata was not received first."
            )
        if request_id is not None and pending_upload.request_id != request_id:
            return (
                "Desktop rejected transfer asset stream chunk because request ids do not match the "
                "active binary stream."
            )

        pending_upload.append_chunk(chunk)
        return None

    def complete(self, *, request_id: str) -> TransferAssetUploadPayload | str:
        pending_upload = self._pending
        self._pending = None
        if pending_upload is None:
            return "Desktop did not receive transfer asset stream metadata before completion."
        if pending_upload.request_id != request_id:
            pending_upload.close()
            return (
                "Desktop rejected transfer asset completion because request ids do not match the "
                "active binary stream."
            )
        return pending_upload.to_payload()

    def clear(self) -> None:
        if self._pending is not None:
            self._pending.close()
            self._pending = None
