from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
from typing import BinaryIO
import uuid

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_store import (
    MOBILE_BACKUP_SESSION_STATUS_COMPLETED,
    MOBILE_BACKUP_SESSION_STATUS_FAILED,
    MOBILE_BACKUP_SESSION_STATUS_TRANSFERRING,
    MOBILE_TRANSFER_STATE_COMPLETED,
    MOBILE_TRANSFER_STATE_FAILED,
    MOBILE_TRANSFER_STATE_TRANSFERRING,
    get_mobile_asset_record,
    get_mobile_transfer_context,
    update_mobile_transfer_state,
    upsert_mobile_asset_record,
)
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_event_bus import default_bus

MOBILE_TRANSFER_SCHEMA = "dtis.mobile-transfer.v1"
MOBILE_TRANSFER_START_PATH = "/api/mobile/transfer/start"
MOBILE_TRANSFER_ASSET_PATH = "/api/mobile/transfer/asset"
MOBILE_TRANSFER_COMPLETE_PATH = "/api/mobile/transfer/complete"
MOBILE_TRANSFER_STARTED_EVENT = "mobile_transfer_started"


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
    filename: str
    media_type: str | None
    created_at: datetime | None
    updated_at: datetime | None


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
            )

        default_bus.publish(
            MOBILE_TRANSFER_STARTED_EVENT,
            session_id=request.session_id,
            device_uuid=request.device_uuid,
            folder_path=transfer_context.folder_path,
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

    def handle_asset_upload(
        self,
        *,
        metadata_payload: dict[str, object],
        body_stream: BinaryIO,
        content_length: int,
        now: datetime | None = None,
    ) -> tuple[int, dict[str, object]]:
        current_time = _utc_now(now)
        try:
            metadata = _parse_transfer_asset_metadata(metadata_payload)
        except ValueError as exc:
            return _response(status_code=400, status="rejected", message=str(exc))

        if metadata.schema != MOBILE_TRANSFER_SCHEMA:
            return _response(status_code=400, status="rejected", message="The transfer request schema version is unsupported.")
        if content_length < 0:
            return _response(status_code=400, status="rejected", message="Desktop received an invalid transfer content length.")

        with create_db_conn(ctx=self._ctx) as conn:
            transfer_context = get_mobile_transfer_context(
                conn,
                session_id=metadata.session_id,
                device_uuid=metadata.device_uuid,
                trust_key_b64=metadata.trust_key_b64,
            )
            if transfer_context is None:
                return _response(status_code=403, status="rejected", message="Desktop rejected the transfer session.")

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
                local_relative_path = _write_asset_to_folder(
                    folder_path=transfer_context.folder_path,
                    filename=metadata.filename,
                    created_at=metadata.created_at,
                    updated_at=metadata.updated_at,
                    body_stream=body_stream,
                    content_length=content_length,
                )
            except OSError as exc:
                update_mobile_transfer_state(
                    conn,
                    session_id=metadata.session_id,
                    device_uuid=metadata.device_uuid,
                    session_status=MOBILE_BACKUP_SESSION_STATUS_FAILED,
                    folder_transfer_state=MOBILE_TRANSFER_STATE_FAILED,
                    updated_at=current_time,
                    ended_at=current_time,
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
                local_relative_path=local_relative_path,
                last_transferred_at=current_time,
            )

        return (
            200,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "status": "stored",
                "message": "Desktop stored the asset successfully.",
                "local_relative_path": local_relative_path,
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
            update_mobile_transfer_state(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                session_status=MOBILE_BACKUP_SESSION_STATUS_COMPLETED if failed_count == 0 else MOBILE_BACKUP_SESSION_STATUS_FAILED,
                folder_transfer_state=MOBILE_TRANSFER_STATE_COMPLETED if failed_count == 0 else MOBILE_TRANSFER_STATE_FAILED,
                updated_at=current_time,
                ended_at=current_time,
            )

        return (
            200,
            {
                "schema": MOBILE_TRANSFER_SCHEMA,
                "status": "completed",
                "message": (
                    f"Desktop finished the transfer session after receiving {request.transferred_count or 0} assets "
                    f"with {request.failed_count or 0} failures."
                ),
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
        filename=_require_non_empty_string(metadata_payload, "filename"),
        media_type=_optional_non_empty_string(metadata_payload, "media_type"),
        created_at=_parse_optional_timestamp(_optional_non_empty_string(metadata_payload, "created_at")),
        updated_at=_parse_optional_timestamp(_optional_non_empty_string(metadata_payload, "updated_at")),
    )


def _write_asset_to_folder(
    *,
    folder_path: str,
    filename: str,
    created_at: datetime | None,
    updated_at: datetime | None,
    body_stream: BinaryIO,
    content_length: int,
) -> str:
    root_path = Path(folder_path)
    month_directory_name = _target_month_directory(created_at=created_at, updated_at=updated_at)
    month_directory = root_path / month_directory_name
    month_directory.mkdir(parents=True, exist_ok=True)

    safe_filename = _sanitize_filename(filename)
    final_path = _resolve_conflict_safe_path(month_directory, safe_filename)
    temp_path = month_directory / f".{final_path.name}.{uuid.uuid4().hex}.part"

    try:
        remaining_bytes = content_length
        with temp_path.open("wb") as destination_file:
            while remaining_bytes > 0:
                chunk = body_stream.read(min(1024 * 1024, remaining_bytes))
                if not chunk:
                    raise OSError("Desktop received an incomplete asset body.")
                destination_file.write(chunk)
                remaining_bytes -= len(chunk)

        temp_path.replace(final_path)
        timestamp_source = updated_at or created_at
        if timestamp_source is not None:
            timestamp_value = timestamp_source.timestamp()
            os.utime(final_path, (timestamp_value, timestamp_value))
    finally:
        if temp_path.exists():
            temp_path.unlink()

    return final_path.relative_to(root_path).as_posix()


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


def _require_non_negative_int(payload: dict[str, object], field_name: str) -> int:
    field_value = payload.get(field_name)
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
