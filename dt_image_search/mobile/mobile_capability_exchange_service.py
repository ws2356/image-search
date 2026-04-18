from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping

from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_pairing_store import get_mobile_transfer_context
from dt_image_search.model.dts_db import create_db_conn
from dt_image_search.telemetry.telemetry_client import log

MOBILE_CAPABILITY_EXCHANGE_SCHEMA = "dtis.mobile-capabilities.v1"
MOBILE_CAPABILITY_EXCHANGE_PATH = "/api/mobile/capabilities/exchange"


@dataclass(frozen=True)
class MobileCapabilityExchangeRequest:
    schema: str
    session_id: str
    device_uuid: str
    trust_key_b64: str
    capabilities: dict[str, int]


class MobileCapabilityExchangeService:
    def __init__(
        self,
        ctx: BMContext,
        *,
        desktop_capability_flags: Mapping[str, int] | None = None,
    ):
        self._ctx = ctx
        self._desktop_capability_flags = _normalize_capability_flags(desktop_capability_flags or {})

    def handle_exchange_request(self, request_payload: dict[str, object]) -> tuple[int, dict[str, object]]:
        try:
            request = _parse_capability_exchange_request(request_payload)
        except ValueError as exc:
            return _response(status_code=400, status="rejected", message=str(exc))

        if request.schema != MOBILE_CAPABILITY_EXCHANGE_SCHEMA:
            return _response(
                status_code=400,
                status="rejected",
                message="The capability exchange request schema version is unsupported.",
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
                    message="Desktop rejected the capability exchange request.",
                )

        desktop_capabilities = dict(self._desktop_capability_flags)
        log(
            "info",
            message=(
                "MobileCapabilityExchangeService/handle_exchange_request: "
                f"session_id={request.session_id} device_uuid={request.device_uuid} "
                f"mobile_capabilities={sorted(request.capabilities.keys())} "
                f"desktop_capabilities={sorted(desktop_capabilities.keys())}"
            ),
        )
        return _response(
            status_code=200,
            status="accepted",
            message="Desktop completed capability exchange.",
            session_id=request.session_id,
            device_uuid=request.device_uuid,
            capabilities=desktop_capabilities,
        )


def _response(
    *,
    status_code: int,
    status: str,
    message: str,
    session_id: str | None = None,
    device_uuid: str | None = None,
    capabilities: Mapping[str, int] | None = None,
) -> tuple[int, dict[str, object]]:
    payload: dict[str, object] = {
        "schema": MOBILE_CAPABILITY_EXCHANGE_SCHEMA,
        "status": status,
        "message": message,
        "capabilities": dict(capabilities or {}),
    }
    if session_id is not None:
        payload["session_id"] = session_id
    if device_uuid is not None:
        payload["device_uuid"] = device_uuid
    return status_code, payload


def _parse_capability_exchange_request(payload: dict[str, object]) -> MobileCapabilityExchangeRequest:
    required_fields = ("schema", "session_id", "device_uuid", "trust_key")
    normalized_fields: dict[str, str] = {}
    for field_name in required_fields:
        field_value = payload.get(field_name)
        if not isinstance(field_value, str) or not field_value.strip():
            raise ValueError(
                f"The capability exchange request is missing the required field '{field_name}'."
            )
        normalized_fields[field_name] = field_value.strip()

    raw_capabilities = payload.get("capabilities", {})
    if not isinstance(raw_capabilities, dict):
        raise ValueError("The capability exchange request field 'capabilities' must be a JSON object.")

    return MobileCapabilityExchangeRequest(
        schema=normalized_fields["schema"],
        session_id=normalized_fields["session_id"],
        device_uuid=normalized_fields["device_uuid"],
        trust_key_b64=normalized_fields["trust_key"],
        capabilities=_normalize_capability_flags(raw_capabilities),
    )


def _normalize_capability_flags(raw_capabilities: Mapping[str, object]) -> dict[str, int]:
    normalized_capabilities: dict[str, int] = {}
    for raw_name, raw_value in raw_capabilities.items():
        if not isinstance(raw_name, str):
            raise ValueError("The capability exchange request contains a non-string capability key.")
        capability_name = raw_name.strip()
        if not capability_name:
            raise ValueError("The capability exchange request contains an empty capability key.")

        if isinstance(raw_value, bool):
            normalized_value = 1 if raw_value else 0
        elif isinstance(raw_value, int):
            if raw_value not in (0, 1):
                raise ValueError(
                    f"The capability exchange request contains unsupported value '{raw_value}' for capability '{capability_name}'."
                )
            normalized_value = raw_value
        else:
            raise ValueError(
                f"The capability exchange request contains a non-integer value for capability '{capability_name}'."
            )

        if normalized_value == 1:
            normalized_capabilities[capability_name] = 1
    return normalized_capabilities
