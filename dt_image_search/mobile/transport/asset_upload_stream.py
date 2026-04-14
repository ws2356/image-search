from __future__ import annotations

from dataclasses import dataclass
import tempfile

from dt_image_search.mobile.transport.contracts import TransferAssetUploadPayload

TRANSFER_ASSET_STREAM_STATE_FIELD = "stream_state"
TRANSFER_ASSET_STREAM_STATE_START = "start"
TRANSFER_ASSET_STREAM_STATE_CHUNK = "chunk"
TRANSFER_ASSET_STREAM_STATE_COMPLETE = "complete"
TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES = 2 * 1024 * 1024


@dataclass
class _PendingTransferAssetUpload:
    request_id: str
    metadata_payload: dict[str, object]
    body_stream: tempfile.SpooledTemporaryFile
    content_length: int = 0

    def append_chunk(self, chunk: bytes) -> None:
        self.body_stream.write(chunk)
        self.content_length += len(chunk)

    def to_payload(self) -> TransferAssetUploadPayload:
        self.body_stream.seek(0)
        return TransferAssetUploadPayload(
            metadata_payload=self.metadata_payload,
            body_stream=self.body_stream,
            content_length=self.content_length,
        )

    def close(self) -> None:
        self.body_stream.close()


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
        pending_upload = _PendingTransferAssetUpload(
            request_id=request_id,
            metadata_payload=metadata_payload,
            body_stream=tempfile.SpooledTemporaryFile(
                max_size=TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES * 4,
                mode="w+b",
            ),
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
