from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime
import hashlib
import http.client
import json
import logging
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from dt_image_search.mobile.mobile_pairing_session import MobilePlatform
from dt_image_search.mobile.mobile_pairing_store import derive_pairing_key_b64
from dt_image_search.mobile.mobile_transfer_service import (
    MOBILE_TRANSFER_ASSET_PATH,
    MOBILE_TRANSFER_COMPLETE_PATH,
    MOBILE_TRANSFER_EXISTENCE_PATH,
    MOBILE_TRANSFER_SCHEMA,
    MOBILE_TRANSFER_START_PATH,
)

PAIRING_PROTOCOL_SCHEMA = "dtis.mobile-pairing.v1"
PAIRING_CLAIM_PATH = "/api/mobile/pairing/claim"


@dataclass(frozen=True)
class MockBackupAsset:
    asset_id: str
    file_path: Path
    filename: str
    media_type: str
    created_at: datetime
    updated_at: datetime
    asset_version: str


@dataclass(frozen=True)
class MockPairingRecord:
    endpoint_url: str
    session_id: str
    trust_key_b64: str
    folder_path: str
    server_response: dict[str, object]


@dataclass(frozen=True)
class MockBackupResult:
    pairing: MockPairingRecord
    start_response: dict[str, object]
    existence_response: dict[str, object]
    asset_responses: tuple[dict[str, object], ...]
    complete_response: dict[str, object]


class MockMobileBackupClient:
    def __init__(
        self,
        *,
        pairing_payload: str,
        device_uuid: str,
        device_name: str,
        platform: MobilePlatform = MobilePlatform.IOS,
        client_nonce: str = "functional-client-nonce",
    ):
        self._pairing_payload = pairing_payload
        self._device_uuid = device_uuid
        self._device_name = device_name
        self._platform = platform
        self._client_nonce = client_nonce

    def pair_and_backup(self, assets: list[MockBackupAsset]) -> MockBackupResult:
        pairing_record = self.claim_pairing()
        start_response = self._start_transfer(pairing_record=pairing_record, total_assets=len(assets))
        existence_response = self._check_existing_assets(pairing_record=pairing_record, assets=assets)
        matched_asset_ids = {
            str(match["asset_id"])
            for match in _require_list(existence_response, "matches")
        }

        asset_responses: list[dict[str, object]] = []
        transferred_count = 0
        failed_count = 0
        for asset in assets:
            if asset.asset_id in matched_asset_ids:
                transferred_count += 1
                continue
            response_payload = self._upload_asset(pairing_record=pairing_record, asset=asset)
            asset_responses.append(response_payload)
            if response_payload.get("status") in {"stored", "skipped"}:
                transferred_count += 1
            else:
                failed_count += 1

        complete_response = self._complete_transfer(
            pairing_record=pairing_record,
            transferred_count=transferred_count,
            failed_count=failed_count,
        )
        return MockBackupResult(
            pairing=pairing_record,
            start_response=start_response,
            existence_response=existence_response,
            asset_responses=tuple(asset_responses),
            complete_response=complete_response,
        )

    def claim_pairing(self) -> MockPairingRecord:
        payload_fields = self._parse_pairing_payload()
        session_id = payload_fields["sid"]
        one_time_passcode = payload_fields["opt"]

        last_error: RuntimeError | None = None
        for endpoint_url in payload_fields["bootstrap_urls"]:
            try:
                response_payload = self._post_json(
                    endpoint_url=endpoint_url,
                    path=PAIRING_CLAIM_PATH,
                    payload={
                        "schema": PAIRING_PROTOCOL_SCHEMA,
                        "sid": session_id,
                        "opt": one_time_passcode,
                        "platform": self._platform.value,
                        "device_uuid": self._device_uuid,
                        "device_name": self._device_name,
                        "client_nonce": self._client_nonce,
                    },
                )
                trust_key_b64 = derive_pairing_key_b64(
                    session_id=session_id,
                    one_time_passcode=one_time_passcode,
                    device_uuid=self._device_uuid,
                    platform=self._platform.value,
                    client_nonce=self._client_nonce,
                    server_nonce=_require_string(response_payload, "server_nonce"),
                    desktop_device_id=_require_string(response_payload, "desktop_device_id"),
                )
                return MockPairingRecord(
                    endpoint_url=endpoint_url,
                    session_id=session_id,
                    trust_key_b64=trust_key_b64,
                    folder_path=_require_string(response_payload, "folder_path"),
                    server_response=response_payload,
                )
            except RuntimeError as exc:
                last_error = exc

        if last_error is None:
            raise RuntimeError("The pairing payload did not contain any bootstrap endpoints.")
        raise last_error

    def _start_transfer(self, *, pairing_record: MockPairingRecord, total_assets: int) -> dict[str, object]:
        return self._post_json(
            endpoint_url=pairing_record.endpoint_url,
            path=MOBILE_TRANSFER_START_PATH,
            payload={
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_record.session_id,
                "device_uuid": self._device_uuid,
                "trust_key": pairing_record.trust_key_b64,
                "total_assets": total_assets,
            },
        )

    def _check_existing_assets(
        self,
        *,
        pairing_record: MockPairingRecord,
        assets: list[MockBackupAsset],
    ) -> dict[str, object]:
        return self._post_json(
            endpoint_url=pairing_record.endpoint_url,
            path=MOBILE_TRANSFER_EXISTENCE_PATH,
            payload={
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_record.session_id,
                "device_uuid": self._device_uuid,
                "trust_key": pairing_record.trust_key_b64,
                "assets": [self._existence_metadata(asset) for asset in assets],
            },
        )

    def _upload_asset(
        self,
        *,
        pairing_record: MockPairingRecord,
        asset: MockBackupAsset,
    ) -> dict[str, object]:
        from dt_image_search.telemetry.telemetry_client import log
        endpoint = urlsplit(pairing_record.endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            metadata = self._upload_metadata(pairing_record=pairing_record, asset=asset)
            encoded_metadata = _urlsafe_b64encode_json(metadata)
            connection.request(
                "POST",
                f"{MOBILE_TRANSFER_ASSET_PATH}?meta={encoded_metadata}",
                body=asset.file_path.read_bytes(),
                headers={
                    "Content-Type": "application/octet-stream",
                    "Accept": "application/json",
                },
            )
            log("info", message=f"Uploaded asset {asset.asset_id} to {pairing_record.endpoint_url}{MOBILE_TRANSFER_ASSET_PATH} with metadata: {metadata}")
            response = connection.getresponse()
            response_payload = json.loads(response.read().decode("utf-8"))
        finally:
            connection.close()

        if response.status != 200:
            raise RuntimeError(f"Desktop rejected asset upload for {asset.asset_id}: {response_payload}")
        return response_payload

    def _complete_transfer(
        self,
        *,
        pairing_record: MockPairingRecord,
        transferred_count: int,
        failed_count: int,
    ) -> dict[str, object]:
        return self._post_json(
            endpoint_url=pairing_record.endpoint_url,
            path=MOBILE_TRANSFER_COMPLETE_PATH,
            payload={
                "schema": MOBILE_TRANSFER_SCHEMA,
                "session_id": pairing_record.session_id,
                "device_uuid": self._device_uuid,
                "trust_key": pairing_record.trust_key_b64,
                "transferred_count": transferred_count,
                "failed_count": failed_count,
            },
        )

    def _post_json(
        self,
        *,
        endpoint_url: str,
        path: str,
        payload: dict[str, object],
    ) -> dict[str, object]:
        endpoint = urlsplit(endpoint_url)
        connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)
        try:
            encoded_payload = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            connection.request(
                "POST",
                path,
                body=encoded_payload,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            response_payload = json.loads(response.read().decode("utf-8"))
        finally:
            connection.close()

        if response.status != 200:
            raise RuntimeError(f"Desktop request failed for {path}: {response_payload}")
        return response_payload

    def _parse_pairing_payload(self) -> dict[str, object]:
        payload_url = urlsplit(self._pairing_payload)
        query = parse_qs(payload_url.query)
        endpoint_targets = [
            endpoint_target
            for endpoint_target in query.get("ept", [""])[0].split(",")
            if endpoint_target
        ]
        return {
            "sid": _first_query_value(query, "sid"),
            "opt": _first_query_value(query, "opt"),
            "bootstrap_urls": tuple(f"http://{endpoint_target}{PAIRING_CLAIM_PATH}" for endpoint_target in endpoint_targets),
        }

    def _existence_metadata(self, asset: MockBackupAsset) -> dict[str, object]:
        asset_bytes = asset.file_path.read_bytes()
        return {
            "asset_id": asset.asset_id,
            "sha1": hashlib.sha1(asset_bytes).hexdigest(),
            "file_size": len(asset_bytes),
            "created_at": asset.created_at.isoformat(),
        }

    def _upload_metadata(
        self,
        *,
        pairing_record: MockPairingRecord,
        asset: MockBackupAsset,
    ) -> dict[str, object]:
        asset_bytes = asset.file_path.read_bytes()
        return {
            "schema": MOBILE_TRANSFER_SCHEMA,
            "session_id": pairing_record.session_id,
            "device_uuid": self._device_uuid,
            "trust_key": pairing_record.trust_key_b64,
            "asset_id": asset.asset_id,
            "asset_version": asset.asset_version,
            "sha1": hashlib.sha1(asset_bytes).hexdigest(),
            "file_size": len(asset_bytes),
            "filename": asset.filename,
            "media_type": asset.media_type,
            "created_at": asset.created_at.isoformat(),
            "updated_at": asset.updated_at.isoformat(),
        }


def _first_query_value(query: dict[str, list[str]], key: str) -> str:
    values = query.get(key)
    if not values or not values[0]:
        raise RuntimeError(f"The pairing payload is missing '{key}'.")
    return values[0]


def _require_string(payload: dict[str, object], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"The desktop response is missing '{key}'.")
    return value


def _require_list(payload: dict[str, object], key: str) -> list[dict[str, object]]:
    value = payload.get(key)
    if not isinstance(value, list):
        raise RuntimeError(f"The desktop response is missing '{key}'.")
    normalized_items: list[dict[str, object]] = []
    for item in value:
        if not isinstance(item, dict):
            raise RuntimeError(f"The desktop response field '{key}' contains a non-object item.")
        normalized_items.append(item)
    return normalized_items


def _urlsafe_b64encode_json(payload: dict[str, object]) -> str:
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii").rstrip("=")
