from __future__ import annotations

import http.client
import json
import os
import time
from dataclasses import dataclass
from typing import Callable, Mapping, Protocol
from urllib.parse import urlsplit

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
from dt_image_search.instant_sharing.trust_crypto import (
    TrustSessionProtector,
    is_trust_session_envelope,
)


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


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int = 3
    backoff_seconds: tuple[float, ...] = (0.1, 0.5, 1.0)

    def delay_for_attempt(self, attempt_index: int) -> float:
        if attempt_index <= 0:
            return 0.0
        if not self.backoff_seconds:
            return 0.0
        capped_index = min(attempt_index - 1, len(self.backoff_seconds) - 1)
        return self.backoff_seconds[capped_index]


class PlainHttpRequester:
    def __call__(self, request: InstantShareHttpRequest) -> InstantShareHttpResponse:
        parsed_url = urlsplit(request.url)
        if parsed_url.scheme != "http":
            raise ValueError(f"Instant-share requester requires http URLs, got {request.url}.")
        if parsed_url.hostname is None:
            raise ValueError(f"Instant-share URL is missing a hostname: {request.url}.")

        request_path = parsed_url.path or "/"
        if parsed_url.query:
            request_path = f"{request_path}?{parsed_url.query}"

        connection = http.client.HTTPConnection(
            host=parsed_url.hostname,
            port=parsed_url.port or 8443,
            timeout=request.timeout_seconds,
        )
        try:
            connection.request(
                method=request.method,
                url=request_path,
                body=request.body,
                headers=dict(request.headers),
            )
            response = connection.getresponse()
            response_body = response.read()
            return InstantShareHttpResponse(
                status_code=response.status,
                headers=dict(response.getheaders()),
                body=response_body,
            )
        finally:
            connection.close()


class InstantShareHttpClient:
    def __init__(
        self,
        *,
        connection_config: ConnectionConfig,
        device_id: str,
        requester: HttpRequester | None = None,
        session_signer: SessionRequestSigner | None = None,
        trust_session_protector: TrustSessionProtector | None = None,
        correlation_id: str,
        retry_policy: RetryPolicy | None = None,
        sleep_func: Callable[[float], None] = time.sleep,
        timeout_seconds: float = 15.0,
    ) -> None:
        self._connection_config = connection_config
        self._device_id = device_id
        self._requester = requester if requester is not None else PlainHttpRequester()
        self._session_signer = session_signer
        self._trust_session_protector = trust_session_protector
        self._retry_policy = retry_policy if retry_policy is not None else RetryPolicy()
        self._sleep_func = sleep_func
        self._timeout_seconds = timeout_seconds

    def trust_handshake(self, *, pc_dh_public_key: str, pc_nonce: str, correlation_id: str) -> dict[str, object]:
        handshake_request_payload = {
            "pc_dh_public_key": pc_dh_public_key,
            "pc_nonce": pc_nonce,
        }
        response_payload = self._post_json(
            path="/trust/handshake",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=False,

            payload=handshake_request_payload,
        )
        if self._trust_session_protector is not None:
            self._trust_session_protector.establish_from_handshake(
                handshake_request=handshake_request_payload,
                handshake_response=response_payload,
            )
        return response_payload

    def trust_apply(
        self,
        *,
        correlation_id: str,
        key_id: str | None = None,
    ) -> str:
        pin_code = _generate_pin_code()
        apply_payload: dict[str, object] = {
            "pin_code": pin_code,
        }
        payload: dict[str, object] = {}
        if self._trust_session_protector is not None and self._trust_session_protector.is_established:
            payload["encrypted_payload"] = _base64url_encode_bytes(
                json.dumps(apply_payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
            )
            payload["encryption_alg"] = "aes-256-gcm"
        else:
            payload.update(apply_payload)
        if key_id is not None:
            payload["key_id"] = key_id
        self._post_json(
            path="/trust/apply",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=False,

            protect_with_trust_session=self._trust_session_protector is not None,
            payload=payload,
        )
        return pin_code

    def trust_confirm(self, *, correlation_id: str) -> dict[str, object]:
        response_payload = self._post_json(
            path="/trust/confirm",
            metadata=self._connection_config.metadata,
            correlation_id=correlation_id,
            requires_signature=False,

            protect_with_trust_session=self._trust_session_protector is not None,
            payload={},
        )
        return response_payload

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
        protect_with_trust_session: bool = False,
    ) -> dict[str, object]:
        response = self._send_request(
            path=path,
            metadata=metadata,
            correlation_id=correlation_id,
            requires_signature=requires_signature,
            payload=payload,
            protect_with_trust_session=protect_with_trust_session,
        )
        response_payload = response.json()
        if (
            protect_with_trust_session
            and self._trust_session_protector is not None
            and is_trust_session_envelope(response_payload)
        ):
            return self._trust_session_protector.decrypt_json_payload(
                encrypted_payload=response_payload,
                correlation_id=correlation_id,
            )
        return response_payload

    def _send_request(
        self,
        *,
        path: str,
        metadata: InstantShareMetadata,
        correlation_id: str,
        requires_signature: bool,
        payload: Mapping[str, object],
        protect_with_trust_session: bool = False,
    ) -> InstantShareHttpResponse:
        metadata.validate()
        headers = self._build_headers(correlation_id=correlation_id, requires_signature=requires_signature)
        logical_payload = {**metadata.as_dict(), **payload}
        request_payload: Mapping[str, object] = logical_payload
        if protect_with_trust_session and self._trust_session_protector is not None:
            request_payload = self._trust_session_protector.encrypt_json_payload(
                payload=logical_payload,
                correlation_id=correlation_id,
            )
        request_body = json.dumps(dict(request_payload), ensure_ascii=False).encode("utf-8")
        request_headers = dict(headers)
        request_headers["Content-Type"] = "application/json"
        request_headers["Accept"] = "application/json, image/*, application/octet-stream"

        last_error: Exception | None = None
        prioritized_error: InstantShareError | None = None
        for attempt_index in range(1, self._retry_policy.max_attempts + 1):
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
                    if isinstance(exc, InstantShareError):
                        prioritized_error = exc
                    if self._is_retryable_error(exc):
                        continue
                    raise self._coerce_exception_to_instant_share_error(
                        exc=exc,
                        correlation_id=correlation_id,
                    )
                if response.status_code >= 400:
                    http_error = self._build_http_error(response=response, correlation_id=correlation_id)
                    last_error = http_error
                    prioritized_error = http_error
                    if http_error.retryable:
                        continue
                    raise http_error
                return response

            if attempt_index < self._retry_policy.max_attempts:
                self._sleep_func(self._retry_policy.delay_for_attempt(attempt_index))

        exhausted_retry_error = self._timeout_error_for_path(
            path=path,
            correlation_id=correlation_id,
            last_error=prioritized_error or last_error,
        )
        if exhausted_retry_error is not None:
            raise exhausted_retry_error

        if prioritized_error is not None:
            raise prioritized_error
        if isinstance(last_error, InstantShareError):
            raise last_error
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
            base_urls.append(f"http://{host}:{self._connection_config.mobile_port}")
        return tuple(base_urls)

    @staticmethod
    def _is_retryable_error(error: Exception) -> bool:
        if isinstance(error, InstantShareError):
            return error.retryable
        return isinstance(error, (OSError, TimeoutError))

    @staticmethod
    def _coerce_exception_to_instant_share_error(
        *,
        exc: Exception,
        correlation_id: str,
    ) -> InstantShareError:
        if isinstance(exc, InstantShareError):
            return exc
        return InstantShareError(
            ErrorCode.HTTP_REQUEST_FAILED,
            f"Instant-share HTTP request failed: {exc}",
            correlation_id=correlation_id,
            retryable=False,
        )

    @staticmethod
    def _timeout_error_for_path(
        *,
        path: str,
        correlation_id: str,
        last_error: Exception | None,
    ) -> InstantShareError | None:
        if last_error is None:
            return None
        error_code = ErrorCode.CONFIRM_TIMEOUT if path == "/trust/confirm" else ErrorCode.TRANSFER_TIMEOUT
        return InstantShareError(
            error_code,
            f"Instant-share request retry limit exhausted for {path}: {last_error}",
            correlation_id=correlation_id,
            retryable=False,
            details={"path": path},
        )

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


def _generate_pin_code() -> str:
    return f"{int.from_bytes(os.urandom(3), 'big') % 1000000:06d}"


def _base64url_encode_bytes(data: bytes) -> str:
    import base64
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")