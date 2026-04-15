from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timezone
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
from typing import BinaryIO
import uuid

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_store import (
    MOBILE_BACKUP_SESSION_STATUS_COMPLETED,
    MOBILE_BACKUP_SESSION_STATUS_FAILED,
    MOBILE_BACKUP_SESSION_STATUS_STOPPED,
    MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING,
    MOBILE_TRANSFER_STATE_PAIRED,
    MOBILE_TRANSFER_STATE_COMPLETED,
    MOBILE_TRANSFER_STATE_FAILED,
    MOBILE_TRANSFER_STATE_TRANSFERRING,
    get_mobile_asset_record,
    get_mobile_asset_record_by_signature,
    get_mobile_asset_records_by_signatures,
    get_mobile_transfer_context,
    increment_mobile_backup_session_transferred_count,
    mobile_asset_signature_key,
    update_mobile_transfer_state,
    upsert_mobile_asset_record,
)
from dt_image_search.mobile.transport.asset_upload_stream import (
    TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
)
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_event_bus import default_bus

MOBILE_TRANSFER_SCHEMA = "dtis.mobile-transfer.v1"
MOBILE_TRANSFER_START_PATH = "/api/mobile/transfer/start"
MOBILE_TRANSFER_EXISTENCE_PATH = "/api/mobile/transfer/existence"
MOBILE_TRANSFER_ASSET_PATH = "/api/mobile/transfer/asset"
MOBILE_TRANSFER_COMPLETE_PATH = "/api/mobile/transfer/complete"
MOBILE_TRANSFER_STARTED_EVENT = "mobile_transfer_started"
MOBILE_TRANSFER_STATE_UPDATED_EVENT = "mobile_transfer_state_updated"
MOBILE_TRANSFER_INTERRUPTION_REASON_STOPPED_BY_USER = "stopped_by_user"


@dataclass(frozen=True)
class MobileTransferSessionRequest:
    schema: str
    session_id: str
    device_uuid: str
    trust_key_b64: str
    total_assets: int | None = None
    transferred_count: int | None = None
    failed_count: int | None = None


@dataclass(frozen=True)
class MobileTransferAssetMetadata:
    schema: str
    session_id: str
    device_uuid: str
    trust_key_b64: str
    asset_id: str
    asset_version: str | None
    content_sha1: str | None
    file_size_bytes: int | None
    filename: str
    media_type: str | None
    created_at: datetime | None
    updated_at: datetime | None


@dataclass(frozen=True)
class MobileTransferAssetExistenceRequest:
    schema: str
    session_id: str
    device_uuid: str
    trust_key_b64: str
    assets: tuple["MobileTransferAssetSignature", ...]


@dataclass(frozen=True)
class MobileTransferAssetSignature:
    asset_id: str
    content_sha1: str
    file_size_bytes: int
    created_at: datetime


@dataclass(frozen=True)
class StoredMobileTransferAsset:
    local_relative_path: str
    content_sha1: str
    file_size_bytes: int


class MobileTransferService:
    def __init__(self, ctx: BMContext):
        self._ctx = ctx

    def handle_start_request(
        self,
        request_payload: dict[str, object],
        *,
        now: datetime | None = None,
    ) -> tuple[int, dict[str, object]]:
        current_time = _utc_now(now)
        try:
            request = _parse_transfer_session_request(request_payload, require_total_assets=True)
        except ValueError as exc:
            return _response(status_code=400, status="rejected", message=str(exc))

        if request.schema != MOBILE_TRANSFER_SCHEMA:
            return _response(status_code=400, status="rejected", message="The transfer request schema version is unsupported.")

        with create_db_conn(ctx=self._ctx) as conn:
            transfer_context = get_mobile_transfer_context(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                trust_key_b64=request.trust_key_b64,
            )
            if transfer_context is None:
                return _response(status_code=403, status="rejected", message="Desktop rejected the transfer session.")

            update_mobile_transfer_state(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                session_status=MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING,
                folder_transfer_state=MOBILE_TRANSFER_STATE_TRANSFERRING,
                updated_at=current_time,
                transferred_count=0,
                failed_count=0,
            )

        default_bus.publish(
            MOBILE_TRANSFER_STARTED_EVENT,
            session_id=request.session_id,
            device_uuid=request.device_uuid,
            folder_path=transfer_context.folder_path,
        )
        default_bus.publish(
            MOBILE_TRANSFER_STATE_UPDATED_EVENT,
            session_id=request.session_id,
            device_uuid=request.device_uuid,
            folder_path=transfer_context.folder_path,
            transfer_state=MOBILE_TRANSFER_STATE_TRANSFERRING,
        )
        log(
            "info",
            message=(
                "MobileTransferService/handle_start_request: ready for transfer session "
                f"{request.session_id} with {request.total_assets or 0} assets"
            ),
        )
        return (
            200,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "status": "accepted",
                "message": f"Desktop is ready to receive {request.total_assets or 0} assets.",
                "session_id": request.session_id,
                "device_uuid": request.device_uuid,
                "total_assets": request.total_assets or 0,
            },
        )

    def handle_asset_existence_request(
        self,
        request_payload: dict[str, object],
    ) -> tuple[int, dict[str, object]]:
        try:
            request = _parse_transfer_asset_existence_request(request_payload)
        except ValueError as exc:
            return _response(status_code=400, status="rejected", message=str(exc))

        if request.schema != MOBILE_TRANSFER_SCHEMA:
            return _response(status_code=400, status="rejected", message="The transfer request schema version is unsupported.")

        with create_db_conn(ctx=self._ctx) as conn:
            transfer_context = get_mobile_transfer_context(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                trust_key_b64=request.trust_key_b64,
            )
            if transfer_context is None:
                return _response(status_code=403, status="rejected", message="Desktop rejected the transfer session.")

            matching_assets = get_mobile_asset_records_by_signatures(
                conn,
                device_uuid=request.device_uuid,
                signature_keys=[
                    mobile_asset_signature_key(
                        content_sha1=asset.content_sha1,
                        file_size_bytes=asset.file_size_bytes,
                        asset_created_at=asset.created_at,
                    )
                    for asset in request.assets
                ],
            )

        matched_assets_payload = []
        for asset in request.assets:
            signature_key = mobile_asset_signature_key(
                content_sha1=asset.content_sha1,
                file_size_bytes=asset.file_size_bytes,
                asset_created_at=asset.created_at,
            )
            match = matching_assets.get(signature_key)
            if match is None:
                continue
            matched_assets_payload.append(
                {
                    "asset_id": asset.asset_id,
                    "local_relative_path": match["local_relative_path"],
                }
            )

        return (
            200,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "status": "checked",
                "message": (
                    f"Desktop matched {len(matched_assets_payload)} of {len(request.assets)} candidate transfer assets."
                ),
                "session_id": request.session_id,
                "device_uuid": request.device_uuid,
                "matches": matched_assets_payload,
            },
        )

    def handle_asset_upload(
        self,
        *,
        metadata_payload: dict[str, object],
        body_stream: BinaryIO | None,
        content_length: int,
        temp_file_path: str | None = None,
        content_sha1: str | None = None,
        now: datetime | None = None,
    ) -> tuple[int, dict[str, object]]:
        current_time = _utc_now(now)
        staged_temp_file_path = temp_file_path
        if body_stream is None and staged_temp_file_path is None:
            return _response(
                status_code=400,
                status="rejected",
                message="Desktop did not receive transfer asset content.",
            )
        try:
            metadata = _parse_transfer_asset_metadata(metadata_payload)
        except ValueError as exc:
            _cleanup_temp_upload_file(staged_temp_file_path)
            return _response(status_code=400, status="rejected", message=str(exc))

        if metadata.schema != MOBILE_TRANSFER_SCHEMA:
            _cleanup_temp_upload_file(staged_temp_file_path)
            return _response(status_code=400, status="rejected", message="The transfer request schema version is unsupported.")
        if content_length < 0:
            _cleanup_temp_upload_file(staged_temp_file_path)
            return _response(status_code=400, status="rejected", message="Desktop received an invalid transfer content length.")
        if metadata.file_size_bytes is not None and metadata.file_size_bytes != content_length:
            _cleanup_temp_upload_file(staged_temp_file_path)
            return _response(
                status_code=400,
                status="rejected",
                message="Desktop received an asset body whose content length did not match the declared file size.",
            )

        with create_db_conn(ctx=self._ctx) as conn:
            transfer_context = get_mobile_transfer_context(
                conn,
                session_id=metadata.session_id,
                device_uuid=metadata.device_uuid,
                trust_key_b64=metadata.trust_key_b64,
            )
            if transfer_context is None:
                _cleanup_temp_upload_file(staged_temp_file_path)
                return _response(status_code=403, status="rejected", message="Desktop rejected the transfer session.")

            existing_signature_asset = None
            if metadata.content_sha1 is not None and metadata.file_size_bytes is not None and metadata.created_at is not None:
                existing_signature_asset = get_mobile_asset_record_by_signature(
                    conn,
                    device_uuid=metadata.device_uuid,
                    content_sha1=metadata.content_sha1,
                    file_size_bytes=metadata.file_size_bytes,
                    asset_created_at=metadata.created_at,
                )
            if existing_signature_asset is not None:
                _cleanup_temp_upload_file(staged_temp_file_path)
                increment_mobile_backup_session_transferred_count(
                    conn,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    delta=1,
                )
                default_bus.publish(
                    MOBILE_TRANSFER_STATE_UPDATED_EVENT,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    folder_path=transfer_context.folder_path,
                    transfer_state=MOBILE_TRANSFER_STATE_TRANSFERRING,
                )
                return (
                    200,
                    {
                        "schema": MOBILE_TRANSFER_SCHEMA,
                        "status": "skipped",
                        "message": "Desktop already has the transferred asset content.",
                        "local_relative_path": existing_signature_asset["local_relative_path"],
                    },
                )

            existing_asset = get_mobile_asset_record(
                conn,
                device_uuid=metadata.device_uuid,
                remote_asset_id=metadata.asset_id,
            )
            if (
                existing_asset is not None
                and existing_asset["remote_asset_version"] == metadata.asset_version
                and (Path(transfer_context.folder_path) / existing_asset["local_relative_path"]).exists()
            ):
                _cleanup_temp_upload_file(staged_temp_file_path)
                increment_mobile_backup_session_transferred_count(
                    conn,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    delta=1,
                )
                default_bus.publish(
                    MOBILE_TRANSFER_STATE_UPDATED_EVENT,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    folder_path=transfer_context.folder_path,
                    transfer_state=MOBILE_TRANSFER_STATE_TRANSFERRING,
                )
                return (
                    200,
                    {
                        "schema": MOBILE_TRANSFER_SCHEMA,
                        "status": "skipped",
                        "message": "Desktop already has the current asset version.",
                        "local_relative_path": existing_asset["local_relative_path"],
                    },
                )

            try:
                if staged_temp_file_path is not None:
                    stored_asset = _move_staged_asset_to_folder(
                        folder_path=transfer_context.folder_path,
                        filename=metadata.filename,
                        created_at=metadata.created_at,
                        updated_at=metadata.updated_at,
                        staged_file_path=staged_temp_file_path,
                        content_length=content_length,
                        provided_content_sha1=content_sha1,
                        expected_content_sha1=metadata.content_sha1,
                    )
                    staged_temp_file_path = None
                else:
                    if body_stream is None:
                        raise OSError("Desktop did not receive transfer asset stream content.")
                    stored_asset = _write_asset_to_folder(
                        folder_path=transfer_context.folder_path,
                        filename=metadata.filename,
                        created_at=metadata.created_at,
                        updated_at=metadata.updated_at,
                        body_stream=body_stream,
                        content_length=content_length,
                    )
            except OSError as exc:
                _cleanup_temp_upload_file(staged_temp_file_path)
                update_mobile_transfer_state(
                    conn,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    session_status=MOBILE_BACKUP_SESSION_STATUS_FAILED,
                    folder_transfer_state=MOBILE_TRANSFER_STATE_FAILED,
                    updated_at=current_time,
                    ended_at=current_time,
                )
                default_bus.publish(
                    MOBILE_TRANSFER_STATE_UPDATED_EVENT,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    folder_path=transfer_context.folder_path,
                    transfer_state=MOBILE_TRANSFER_STATE_FAILED,
                )
                return _response(
                    status_code=500,
                    status="rejected",
                    message=f"Desktop failed while writing the incoming asset: {exc}",
                )

            upsert_mobile_asset_record(
                conn,
                device_uuid=metadata.device_uuid,
                remote_asset_id=metadata.asset_id,
                remote_asset_version=metadata.asset_version,
                content_sha1=stored_asset.content_sha1,
                file_size_bytes=stored_asset.file_size_bytes,
                asset_created_at=metadata.created_at,
                local_relative_path=stored_asset.local_relative_path,
                last_transferred_at=current_time,
            )
            increment_mobile_backup_session_transferred_count(
                conn,
                session_id=metadata.session_id,
                device_uuid=metadata.device_uuid,
                delta=1,
            )
            default_bus.publish(
                MOBILE_TRANSFER_STATE_UPDATED_EVENT,
                session_id=metadata.session_id,
                device_uuid=metadata.device_uuid,
                folder_path=transfer_context.folder_path,
                transfer_state=MOBILE_TRANSFER_STATE_TRANSFERRING,
            )

        return (
            200,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "status": "stored",
                "message": "Desktop stored the asset successfully.",
                "local_relative_path": stored_asset.local_relative_path,
            },
        )

    def handle_complete_request(
        self,
        request_payload: dict[str, object],
        *,
        now: datetime | None = None,
    ) -> tuple[int, dict[str, object]]:
        current_time = _utc_now(now)
        try:
            request = _parse_transfer_session_request(request_payload, require_completion_counts=True)
        except ValueError as exc:
            return _response(status_code=400, status="rejected", message=str(exc))

        if request.schema != MOBILE_TRANSFER_SCHEMA:
            return _response(status_code=400, status="rejected", message="The transfer request schema version is unsupported.")

        with create_db_conn(ctx=self._ctx) as conn:
            transfer_context = get_mobile_transfer_context(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                trust_key_b64=request.trust_key_b64,
            )
            if transfer_context is None:
                return _response(status_code=403, status="rejected", message="Desktop rejected the transfer session.")

            failed_count = request.failed_count or 0
            interruption_reason = _optional_non_empty_string(request_payload, "interruption_reason")
            if interruption_reason == MOBILE_TRANSFER_INTERRUPTION_REASON_STOPPED_BY_USER:
                session_status = MOBILE_BACKUP_SESSION_STATUS_STOPPED
                folder_transfer_state = MOBILE_TRANSFER_STATE_PAIRED
                response_message = (
                    "Desktop marked the transfer session as stopped after receiving "
                    f"{request.transferred_count or 0} assets with {request.failed_count or 0} failures."
                )
            else:
                session_status = MOBILE_BACKUP_SESSION_STATUS_COMPLETED if failed_count == 0 else MOBILE_BACKUP_SESSION_STATUS_FAILED
                folder_transfer_state = MOBILE_TRANSFER_STATE_COMPLETED if failed_count == 0 else MOBILE_TRANSFER_STATE_FAILED
                response_message = (
                    f"Desktop finished the transfer session after receiving {request.transferred_count or 0} assets "
                    f"with {request.failed_count or 0} failures."
                )
            update_mobile_transfer_state(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                session_status=session_status,
                folder_transfer_state=folder_transfer_state,
                updated_at=current_time,
                ended_at=current_time,
                transferred_count=request.transferred_count or 0,
                failed_count=failed_count,
            )
            default_bus.publish(
                MOBILE_TRANSFER_STATE_UPDATED_EVENT,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                folder_path=transfer_context.folder_path,
                transfer_state=folder_transfer_state,
            )

        return (
            200,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "status": "completed",
                "message": response_message,
                "session_id": request.session_id,
                "device_uuid": request.device_uuid,
            },
        )


def decode_transfer_asset_metadata(encoded_metadata: str) -> dict[str, object]:
    padding = "=" * (-len(encoded_metadata) % 4)
    decoded_bytes = base64.urlsafe_b64decode((encoded_metadata + padding).encode("ascii"))
    decoded_value = json.loads(decoded_bytes.decode("utf-8"))
    if not isinstance(decoded_value, dict):
        raise ValueError("Desktop could not parse the transfer asset metadata.")
    return decoded_value


def _parse_transfer_session_request(
    request_payload: dict[str, object],
    *,
    require_total_assets: bool = False,
    require_completion_counts: bool = False,
) -> MobileTransferSessionRequest:
    schema = _require_non_empty_string(request_payload, "schema")
    session_id = _require_non_empty_string(request_payload, "session_id")
    device_uuid = _require_non_empty_string(request_payload, "device_uuid")
    trust_key_b64 = _require_non_empty_string(request_payload, "trust_key")

    total_assets: int | None = None
    transferred_count: int | None = None
    failed_count: int | None = None
    if require_total_assets:
        total_assets = _require_non_negative_int(request_payload, "total_assets")
    if require_completion_counts:
        transferred_count = _require_non_negative_int(request_payload, "transferred_count")
        failed_count = _require_non_negative_int(request_payload, "failed_count")

    return MobileTransferSessionRequest(
        schema=schema,
        session_id=session_id,
        device_uuid=device_uuid,
        trust_key_b64=trust_key_b64,
        total_assets=total_assets,
        transferred_count=transferred_count,
        failed_count=failed_count,
    )


def _parse_transfer_asset_metadata(metadata_payload: dict[str, object]) -> MobileTransferAssetMetadata:
    return MobileTransferAssetMetadata(
        schema=_require_non_empty_string(metadata_payload, "schema"),
        session_id=_require_non_empty_string(metadata_payload, "session_id"),
        device_uuid=_require_non_empty_string(metadata_payload, "device_uuid"),
        trust_key_b64=_require_non_empty_string(metadata_payload, "trust_key"),
        asset_id=_require_non_empty_string(metadata_payload, "asset_id"),
        asset_version=_optional_non_empty_string(metadata_payload, "asset_version"),
        content_sha1=_optional_sha1_hex(metadata_payload, "sha1"),
        file_size_bytes=_optional_non_negative_int(metadata_payload, "file_size"),
        filename=_require_non_empty_string(metadata_payload, "filename"),
        media_type=_optional_non_empty_string(metadata_payload, "media_type"),
        created_at=_parse_optional_timestamp(_optional_non_empty_string(metadata_payload, "created_at")),
        updated_at=_parse_optional_timestamp(_optional_non_empty_string(metadata_payload, "updated_at")),
    )


def _parse_transfer_asset_existence_request(
    request_payload: dict[str, object],
) -> MobileTransferAssetExistenceRequest:
    session_request = _parse_transfer_session_request(request_payload)
    assets_payload = request_payload.get("assets")
    if not isinstance(assets_payload, list):
        raise ValueError("The transfer request field 'assets' must be a JSON array.")

    parsed_assets: list[MobileTransferAssetSignature] = []
    for asset_payload in assets_payload:
        if not isinstance(asset_payload, dict):
            raise ValueError("The transfer request field 'assets' must contain only JSON object items.")
        parsed_assets.append(
            MobileTransferAssetSignature(
                asset_id=_require_non_empty_string(asset_payload, "asset_id"),
                content_sha1=_require_sha1_hex(asset_payload, "sha1"),
                file_size_bytes=_require_non_negative_int(asset_payload, "file_size"),
                created_at=_require_timestamp(asset_payload, "created_at"),
            )
        )

    return MobileTransferAssetExistenceRequest(
        schema=session_request.schema,
        session_id=session_request.session_id,
        device_uuid=session_request.device_uuid,
        trust_key_b64=session_request.trust_key_b64,
        assets=tuple(parsed_assets),
    )


def _write_asset_to_folder(
    *,
    folder_path: str,
    filename: str,
    created_at: datetime | None,
    updated_at: datetime | None,
    body_stream: BinaryIO,
    content_length: int,
) -> StoredMobileTransferAsset:
    root_path = Path(folder_path)
    month_directory_name = _target_month_directory(created_at=created_at, updated_at=updated_at)
    month_directory = root_path / month_directory_name
    month_directory.mkdir(parents=True, exist_ok=True)

    safe_filename = _sanitize_filename(filename)
    final_path = _resolve_conflict_safe_path(month_directory, safe_filename)
    temp_path = month_directory / f".{final_path.name}.{uuid.uuid4().hex}.part"
    content_sha1 = hashlib.sha1()
    written_bytes = 0

    try:
        remaining_bytes = content_length
        with temp_path.open("wb") as destination_file:
            while remaining_bytes > 0:
                chunk = body_stream.read(
                    min(TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES, remaining_bytes)
                )
                if not chunk:
                    raise OSError("Desktop received an incomplete asset body.")
                destination_file.write(chunk)
                content_sha1.update(chunk)
                written_bytes += len(chunk)
                remaining_bytes -= len(chunk)

        temp_path.replace(final_path)
        timestamp_source = updated_at or created_at
        if timestamp_source is not None:
            timestamp_value = timestamp_source.timestamp()
            os.utime(final_path, (timestamp_value, timestamp_value))
    finally:
        if temp_path.exists():
            temp_path.unlink()

    return StoredMobileTransferAsset(
        local_relative_path=final_path.relative_to(root_path).as_posix(),
        content_sha1=content_sha1.hexdigest(),
        file_size_bytes=written_bytes,
    )


def _move_staged_asset_to_folder(
    *,
    folder_path: str,
    filename: str,
    created_at: datetime | None,
    updated_at: datetime | None,
    staged_file_path: str,
    content_length: int,
    provided_content_sha1: str | None,
    expected_content_sha1: str | None,
) -> StoredMobileTransferAsset:
    root_path = Path(folder_path)
    month_directory_name = _target_month_directory(created_at=created_at, updated_at=updated_at)
    month_directory = root_path / month_directory_name
    month_directory.mkdir(parents=True, exist_ok=True)

    safe_filename = _sanitize_filename(filename)
    final_path = _resolve_conflict_safe_path(month_directory, safe_filename)
    staged_path = Path(staged_file_path)
    if not staged_path.exists():
        raise OSError("Desktop transfer staged file is missing.")

    actual_size_bytes = staged_path.stat().st_size
    if actual_size_bytes != content_length:
        raise OSError("Desktop received a staged asset file with a mismatched byte length.")

    content_sha1 = (provided_content_sha1 or "").strip().lower()
    if not content_sha1:
        content_sha1 = _compute_file_sha1(staged_path)
    if expected_content_sha1 is not None and content_sha1 != expected_content_sha1.lower():
        raise OSError("Desktop received a staged asset file with a mismatched SHA-1 digest.")

    try:
        staged_path.replace(final_path)
    except OSError as exc:
        if exc.errno != errno.EXDEV:
            raise

        shutil.move(str(staged_path), str(final_path))

    timestamp_source = updated_at or created_at
    if timestamp_source is not None:
        timestamp_value = timestamp_source.timestamp()
        os.utime(final_path, (timestamp_value, timestamp_value))

    return StoredMobileTransferAsset(
        local_relative_path=final_path.relative_to(root_path).as_posix(),
        content_sha1=content_sha1,
        file_size_bytes=actual_size_bytes,
    )


def _compute_file_sha1(file_path: Path) -> str:
    hasher = hashlib.sha1()
    with file_path.open("rb") as source_file:
        while True:
            chunk = source_file.read(TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest()


def _cleanup_temp_upload_file(temp_file_path: str | None) -> None:
    if temp_file_path is None:
        return
    try:
        Path(temp_file_path).unlink(missing_ok=True)
    except OSError:
        return


def _target_month_directory(*, created_at: datetime | None, updated_at: datetime | None) -> str:
    timestamp = updated_at or created_at or datetime.now(timezone.utc)
    normalized_timestamp = _utc_now(timestamp)
    return normalized_timestamp.strftime("%Y-%m")


def _resolve_conflict_safe_path(parent_directory: Path, filename: str) -> Path:
    candidate_path = parent_directory / filename
    if not candidate_path.exists():
        return candidate_path

    stem = Path(filename).stem
    suffix = Path(filename).suffix
    attempt_number = 2
    while True:
        candidate_path = parent_directory / f"{stem}-{attempt_number}{suffix}"
        if not candidate_path.exists():
            return candidate_path
        attempt_number += 1


def _sanitize_filename(filename: str) -> str:
    candidate = Path(filename).name
    candidate = re.sub(r'[<>:"/\\\\|?*\x00-\x1f]+', "-", candidate).strip().strip(".")
    if candidate:
        return candidate
    return "asset.bin"


def _require_non_empty_string(payload: dict[str, object], field_name: str) -> str:
    field_value = payload.get(field_name)
    if not isinstance(field_value, str) or not field_value.strip():
        raise ValueError(f"The transfer request is missing the required field '{field_name}'.")
    return field_value.strip()


def _optional_non_empty_string(payload: dict[str, object], field_name: str) -> str | None:
    field_value = payload.get(field_name)
    if field_value is None:
        return None
    if not isinstance(field_value, str):
        raise ValueError(f"The transfer request field '{field_name}' must be a string.")
    normalized_value = field_value.strip()
    return normalized_value or None


def _require_sha1_hex(payload: dict[str, object], field_name: str) -> str:
    field_value = _require_non_empty_string(payload, field_name)
    if not re.fullmatch(r"[0-9a-fA-F]{40}", field_value):
        raise ValueError(f"The transfer request field '{field_name}' must be a SHA-1 hex digest.")
    return field_value.lower()


def _optional_sha1_hex(payload: dict[str, object], field_name: str) -> str | None:
    field_value = _optional_non_empty_string(payload, field_name)
    if field_value is None:
        return None
    if not re.fullmatch(r"[0-9a-fA-F]{40}", field_value):
        raise ValueError(f"The transfer request field '{field_name}' must be a SHA-1 hex digest.")
    return field_value.lower()


def _require_non_negative_int(payload: dict[str, object], field_name: str) -> int:
    field_value = payload.get(field_name)
    if isinstance(field_value, bool) or not isinstance(field_value, int) or field_value < 0:
        raise ValueError(f"The transfer request field '{field_name}' must be a non-negative integer.")
    return field_value


def _optional_non_negative_int(payload: dict[str, object], field_name: str) -> int | None:
    field_value = payload.get(field_name)
    if field_value is None:
        return None
    if isinstance(field_value, bool) or not isinstance(field_value, int) or field_value < 0:
        raise ValueError(f"The transfer request field '{field_name}' must be a non-negative integer.")
    return field_value


def _parse_optional_timestamp(value: str | None) -> datetime | None:
    if value is None:
        return None
    normalized_value = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        return _utc_now(datetime.fromisoformat(normalized_value))
    except ValueError as exc:
        raise ValueError(f"The transfer request field contains an invalid timestamp '{value}'.") from exc


def _require_timestamp(payload: dict[str, object], field_name: str) -> datetime:
    field_value = _require_non_empty_string(payload, field_name)
    parsed_value = _parse_optional_timestamp(field_value)
    if parsed_value is None:
        raise ValueError(f"The transfer request is missing the required field '{field_name}'.")
    return parsed_value


def _utc_now(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    if now.tzinfo is None:
        return now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _response(
    *,
    status_code: int,
    status: str,
    message: str,
) -> tuple[int, dict[str, object]]:
    return (
        status_code,
        {
            "schema": MOBILE_TRANSFER_SCHEMA,
            "status": status,
            "message": message,
        },
    )
