from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import BinaryIO

PAIRING_CLAIM_OPERATION = "pairing.claim"
CAPABILITY_EXCHANGE_OPERATION = "capabilities.exchange"
UPDATE_PROMPT_OPERATION = "update.prompt"
TRANSFER_START_OPERATION = "transfer.start"
TRANSFER_EXISTENCE_OPERATION = "transfer.existence"
TRANSFER_ASSET_OPERATION = "transfer.asset"
TRANSFER_COMPLETE_OPERATION = "transfer.complete"


class MobileTransportKind(str, Enum):
    LAN_HTTP = "lan_http"
    USB_WEBSOCKET = "usb_websocket"


@dataclass(frozen=True)
class MobileTransportContext:
    transport: MobileTransportKind
    operation: str
    request_id: str | None = None
    remote_address: str | None = None


@dataclass(frozen=True)
class TransferAssetUploadPayload:
    metadata_payload: dict[str, object]
    body_stream: BinaryIO | None
    content_length: int
    temp_file_path: str | None = None
    content_sha1: str | None = None


@dataclass(frozen=True)
class MobileTransportRequest:
    operation: str
    payload: object
    context: MobileTransportContext


@dataclass(frozen=True)
class MobileTransportResponse:
    status_code: int
    payload: dict[str, object]
