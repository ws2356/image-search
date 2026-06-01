from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Callable, Mapping, Protocol

from dt_image_search.instant_sharing.ble import ConnectionConfig
from dt_image_search.instant_sharing.contracts import (
    API_PREFIX,
    ErrorCode,
    InstantShareHeaders,
    InstantShareMetadata,
    DownloadedImagePayload,
    DownloadedTextPayload,
    DeliveryResult,
)
from dt_image_search.instant_sharing.errors import InstantShareError


class SessionRequestSigner(Protocol):
    def sign(self, session_id: str) -> tuple[str, str]:
        ...


@dataclass(frozen=True)
class InstantShareHttpRequest:
    method: str
    url: str
    headers: Mapping[str, str]
    body: bytes | None = None
    timeout_seconds: float = 15.0


@dataclass(frozen=True)
class InstantShareHttpResponse:
    status_code: int
    headers: Mapping[str, str]
    body: bytes = b""

    def json(self) -> dict[str, object]:
        if not self.body:
            return {}
        parsed = json.loads(self.body.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise ValueError("Instant-share JSON response must be an object.")
        return parsed


HttpRequester = Callable[[InstantShareHttpRequest], InstantShareHttpResponse]


class InstantShareHttpClient:
    def __init__(
        self,
        *,
        connection_config: ConnectionConfig,
        device_id: str,
        requester: HttpRequester,
        session_signer: SessionRequestSigner | None = None,
        timeout_seconds: float = 15.0,
    ) -> None:
        self._connection_config = connection_config
        self._device_id = device_id
        self._requester = requester
        self._session_signer = session_signer
        self._timeout_seconds = timeout_seconds

    def trust_handshake(self, *, pc_dh_public_key: str, pc_nonce: str, correlation_id: str) -> dict[str, object]:
        return self._post_json(
            path="/trust/handshake",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=False,
            payload={
                "pc_dh_public_key": pc_dh_public_key,
                "pc_nonce": pc_nonce,
            },
        )

    def trust_apply(
        self,
        *,
        encrypted_payload: str,
        encryption_alg: str,
        correlation_id: str,
        key_id: str | None = None,
    ) -> dict[str, object]:
        payload: dict[str, object] = {
            "encrypted_payload": encrypted_payload,
            "encryption_alg": encryption_alg,
        }
        if key_id is not None:
            payload["key_id"] = key_id
        return self._post_json(
            path="/trust/apply",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=False,
            payload=payload,
        )

    def trust_confirm(self, *, pc_public_key_pem: str, correlation_id: str) -> dict[str, object]:
        return self._post_json(
            path="/trust/confirm",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=False,
            payload={"pc_public_key_pem": pc_public_key_pem},
        )

    def download_text_payload(self, *, correlation_id: str, requires_signature: bool = True) -> DownloadedTextPayload:
        response_payload = self._post_json(
            path="/payload/text",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=requires_signature,
            payload={},
        )
        text_utf8 = response_payload.get("text_utf8")
        if not isinstance(text_utf8, str):
            raise InstantShareError(
                ErrorCode.PAYLOAD_UNREADABLE,
                "Instant-share text payload response is missing text_utf8.",
                correlation_id=correlation_id,
            )
        return DownloadedTextPayload(metadata=self._connection_config.metadata, text_utf8=text_utf8)

    def download_image_payload(self, *, correlation_id: str, requires_signature: bool = True) -> DownloadedImagePayload:
        response = self._send_request(
            path="/payload/image",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=requires_signature,
            payload={},
        )
        content_type = str(response.headers.get("Content-Type", "application/octet-stream"))
        filename_header = response.headers.get("X-Instant-Share-Filename")
        filename = str(filename_header) if filename_header is not None else None
        manifest_header = response.headers.get("X-Instant-Share-Manifest")
        manifest: Mapping[str, object] = {}
        if isinstance(manifest_header, str) and manifest_header.strip():
            parsed_manifest = json.loads(manifest_header)
            if isinstance(parsed_manifest, dict):
                manifest = parsed_manifest
        return DownloadedImagePayload(
            metadata=self._connection_config.metadata,
            image_bytes=response.body,
            filename=filename,
            content_type=content_type,
            manifest=manifest,
        )

    def report_delivery_result(
        self,
        *,
        result: DeliveryResult,
        correlation_id: str,
        requires_signature: bool = True,
    ) -> dict[str, object]:
        return self._post_json(
            path="/delivery-result",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=requires_signature,
            payload=result.as_dict(),
        )

    def _post_json(
        self,
        *,
        path: str,
        metadata: InstantShareMetadata,
        correlation_id: str,
        requires_signature: bool,
        payload: Mapping[str, object],
    ) -> dict[str, object]:
        response = self._send_request(
            path=path,
            metadata=metadata,
            correlation_id=correlation_id,
            requires_signature=requires_signature,
            payload=payload,
        )
        return response.json()

    def _send_request(
        self,
        *,
        path: str,
        metadata: InstantShareMetadata,
        correlation_id: str,
        requires_signature: bool,
        payload: Mapping[str, object],
    ) -> InstantShareHttpResponse:
        metadata.validate()
        headers = self._build_headers(correlation_id=correlation_id, requires_signature=requires_signature)
        request_body = json.dumps({**metadata.as_dict(), **payload}, ensure_ascii=False).encode("utf-8")
        request_headers = dict(headers)
        request_headers["Content-Type"] = "application/json"
        request_headers["Accept"] = "application/json, image/*, application/octet-stream"

        last_error: Exception | None = None
        for base_url in self._candidate_base_urls():
            request = InstantShareHttpRequest(
                method="POST",
                url=f"{base_url}{API_PREFIX}{path}",
                headers=request_headers,
                body=request_body,
                timeout_seconds=self._timeout_seconds,
            )
            try:
                response = self._requester(request)
            except Exception as exc:
                last_error = exc
                continue
            if response.status_code >= 400:
                raise self._build_http_error(response=response, correlation_id=correlation_id)
            return response

        if last_error is not None:
            raise InstantShareError(
                ErrorCode.HTTP_REQUEST_FAILED,
                f"Instant-share HTTP request failed: {last_error}",
                correlation_id=correlation_id,
                retryable=True,
            ) from last_error
        raise InstantShareError(
            ErrorCode.HTTP_REQUEST_FAILED,
            "Instant-share HTTP request failed without a response.",
            correlation_id=correlation_id,
            retryable=True,
        )

    def _build_headers(self, *, correlation_id: str, requires_signature: bool) -> dict[str, str]:
        session_signature = None
        session_signature_algorithm = None
        if requires_signature:
            if self._session_signer is None:
                raise InstantShareError(
                    ErrorCode.TRUSTED_KEY_NOT_FOUND,
                    "Instant-share session signer is required for authenticated requests.",
                    correlation_id=correlation_id,
                )
            session_signature, session_signature_algorithm = self._session_signer.sign(
                self._connection_config.session_id
            )
        headers = InstantShareHeaders(
            correlation_id=correlation_id,
            session_id=self._connection_config.session_id,
            device_id=self._device_id,
            session_signature=session_signature,
            session_signature_algorithm=session_signature_algorithm,
        )
        return headers.as_http_headers(requires_signature=requires_signature)

    def _candidate_base_urls(self) -> tuple[str, ...]:
        base_urls: list[str] = []
        for ip_value in self._connection_config.mobile_ip_list:
            if ":" in ip_value:
                host = f"[{ip_value}]"
            else:
                host = ip_value
            base_urls.append(f"https://{host}:{self._connection_config.mobile_port}")
        return tuple(base_urls)

    def _build_http_error(self, *, response: InstantShareHttpResponse, correlation_id: str) -> InstantShareError:
        payload: dict[str, object] = {}
        if response.body:
            try:
                parsed_payload = response.json()
            except Exception:
                parsed_payload = {}
            if isinstance(parsed_payload, dict):
                payload = parsed_payload
        error_code_value = payload.get("error_code", ErrorCode.HTTP_REQUEST_FAILED.value)
        try:
            error_code = ErrorCode(str(error_code_value))
        except ValueError:
            error_code = ErrorCode.HTTP_REQUEST_FAILED
        message = str(payload.get("message", f"Instant-share HTTP request failed with status {response.status_code}."))
        retryable = bool(payload.get("retryable", response.status_code >= 500))
        details = payload.get("details")
        if not isinstance(details, Mapping):
            details = {}
        return InstantShareError(
            error_code,
            message,
            correlation_id=correlation_id,
            retryable=retryable,
            details=details,
        )