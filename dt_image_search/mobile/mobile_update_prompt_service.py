from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_store import get_mobile_transfer_context
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_event_bus import default_bus

MOBILE_UPDATE_PROMPT_SCHEMA = "dtis.mobile-update.v1"
MOBILE_UPDATE_PROMPT_PATH = "/api/mobile/update/prompt"
MOBILE_UPDATE_PROMPT_REQUESTED_EVENT = "mobile_update_prompt_requested"


@dataclass(frozen=True)
class MobileUpdatePromptRequest:
    schema: str
    session_id: str
    device_uuid: str
    trust_key_b64: str
    required: bool
    body_text: str | None
    update_destination: str | None


class MobileUpdatePromptService:
    def __init__(self, ctx: BMContext):
        self._ctx = ctx

    def handle_prompt_request(self, request_payload: dict[str, object]) -> tuple[int, dict[str, object]]:
        try:
            request = _parse_update_prompt_request(request_payload)
        except ValueError as exc:
            return _response(status_code=400, status="rejected", message=str(exc))

        if request.schema != MOBILE_UPDATE_PROMPT_SCHEMA:
            return _response(
                status_code=400,
                status="rejected",
                message="The update prompt request schema version is unsupported.",
            )

        with create_db_conn(ctx=self._ctx) as conn:
            transfer_context = get_mobile_transfer_context(
                conn,
                session_id=request.session_id,
                device_uuid=request.device_uuid,
                trust_key_b64=request.trust_key_b64,
            )
            if transfer_context is None:
                return _response(
                    status_code=403,
                    status="rejected",
                    message="Desktop rejected the update prompt request.",
                )

        default_bus.publish(
            MOBILE_UPDATE_PROMPT_REQUESTED_EVENT,
            required=request.required,
            body_text=request.body_text,
            update_destination=request.update_destination,
            session_id=request.session_id,
            device_uuid=request.device_uuid,
        )
        log(
            "info",
            message=(
                "MobileUpdatePromptService/handle_prompt_request: "
                f"session_id={request.session_id} device_uuid={request.device_uuid} "
                f"required={request.required} "
                f"has_body_override={request.body_text is not None} "
                f"has_destination_override={request.update_destination is not None}"
            ),
        )
        return _response(
            status_code=200,
            status="accepted",
            message="Desktop accepted the update prompt request.",
            session_id=request.session_id,
            device_uuid=request.device_uuid,
            required=request.required,
        )


def _response(
    *,
    status_code: int,
    status: str,
    message: str,
    session_id: str | None = None,
    device_uuid: str | None = None,
    required: bool | None = None,
) -> tuple[int, dict[str, object]]:
    payload: dict[str, object] = {
        "schema": MOBILE_UPDATE_PROMPT_SCHEMA,
        "status": status,
        "message": message,
    }
    if session_id is not None:
        payload["session_id"] = session_id
    if device_uuid is not None:
        payload["device_uuid"] = device_uuid
    if required is not None:
        payload["required"] = required
    return status_code, payload


def _parse_update_prompt_request(payload: dict[str, object]) -> MobileUpdatePromptRequest:
    required_string_fields = ("schema", "session_id", "device_uuid", "trust_key")
    normalized_fields: dict[str, str] = {}
    for field_name in required_string_fields:
        field_value = payload.get(field_name)
        if not isinstance(field_value, str) or not field_value.strip():
            raise ValueError(
                f"The update prompt request is missing the required field '{field_name}'."
            )
        normalized_fields[field_name] = field_value.strip()

    required_value = payload.get("required")
    if not isinstance(required_value, bool):
        raise ValueError("The update prompt request field 'required' must be a boolean.")

    body_text = _normalize_optional_text(
        payload.get("body_text"),
        field_name="body_text",
    )
    update_destination = _normalize_optional_text(
        payload.get("update_destination"),
        field_name="update_destination",
    )
    if update_destination is not None:
        _validate_destination(update_destination)

    return MobileUpdatePromptRequest(
        schema=normalized_fields["schema"],
        session_id=normalized_fields["session_id"],
        device_uuid=normalized_fields["device_uuid"],
        trust_key_b64=normalized_fields["trust_key"],
        required=required_value,
        body_text=body_text,
        update_destination=update_destination,
    )


def _normalize_optional_text(raw_value: Any, *, field_name: str) -> str | None:
    if raw_value is None:
        return None
    if not isinstance(raw_value, str):
        raise ValueError(f"The update prompt request field '{field_name}' must be a string.")
    normalized_value = raw_value.strip()
    return normalized_value or None


def _validate_destination(destination: str) -> None:
    parsed = urlparse(destination)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError("The update prompt request field 'update_destination' must be a valid absolute URL.")
