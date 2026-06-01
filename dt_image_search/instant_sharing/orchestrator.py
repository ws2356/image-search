from __future__ import annotations

from dataclasses import dataclass

from dt_image_search.instant_sharing.contracts import ErrorCode, SessionState
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.http_client import InstantShareHttpClient
from dt_image_search.instant_sharing.session import InstantShareSession, InstantShareSessionRegistry
from dt_image_search.tools.dts_event_bus import default_bus


INSTANT_SHARE_LIFECYCLE_EVENT = "instant_share.lifecycle"


@dataclass(frozen=True)
class TrustHandshakeRequest:
    pc_dh_public_key: str
    pc_nonce: str
    encrypted_payload: str
    encryption_alg: str
    pc_public_key_pem: str
    key_id: str | None = None


class InstantShareReceiverOrchestrator:
    def __init__(
        self,
        *,
        session_registry: InstantShareSessionRegistry,
        delivery_service: InstantShareDeliveryService,
    ) -> None:
        self._session_registry = session_registry
        self._delivery_service = delivery_service

    def handle_connection_config(self, connection_config) -> InstantShareSession:
        session = self._session_registry.bootstrap(connection_config)
        session = self._session_registry.transition(connection_config.session_id, SessionState.QUEUED)
        self._publish(session)
        return session

    def complete_trust(
        self,
        *,
        session_id: str,
        client: InstantShareHttpClient,
        request: TrustHandshakeRequest,
        correlation_id: str,
    ) -> dict[str, object]:
        session = self._session_registry.transition(session_id, SessionState.NEGOTIATING)
        self._publish(session)
        client.trust_handshake(
            pc_dh_public_key=request.pc_dh_public_key,
            pc_nonce=request.pc_nonce,
            correlation_id=correlation_id,
        )
        client.trust_apply(
            encrypted_payload=request.encrypted_payload,
            encryption_alg=request.encryption_alg,
            correlation_id=correlation_id,
            key_id=request.key_id,
        )
        confirm_payload = client.trust_confirm(
            pc_public_key_pem=request.pc_public_key_pem,
            correlation_id=correlation_id,
        )
        mobile_public_key_pem = confirm_payload.get("mobile_public_key_pem")
        if not isinstance(mobile_public_key_pem, str) or not mobile_public_key_pem.strip():
            raise InstantShareError(
                ErrorCode.CONFIRM_TIMEOUT,
                "Instant-share trust confirm did not return mobile_public_key_pem.",
                correlation_id=correlation_id,
            )
        self._session_registry.set_trusted_mobile_public_key(session_id, mobile_public_key_pem)
        return confirm_payload

    def receive_payload(
        self,
        *,
        session_id: str,
        client: InstantShareHttpClient,
        correlation_id: str,
        requires_signature: bool = True,
    ) -> object:
        session = self._session_registry.require_session(session_id)
        session = self._session_registry.transition(session_id, SessionState.TRANSFERRING)
        self._publish(session)

        if session.connection_config.metadata.payload_class.value == "text":
            downloaded_payload = client.download_text_payload(
                correlation_id=correlation_id,
                requires_signature=requires_signature,
            )
        else:
            downloaded_payload = client.download_image_payload(
                correlation_id=correlation_id,
                requires_signature=requires_signature,
            )

        session = self._session_registry.transition(session_id, SessionState.DELIVERING)
        self._publish(session)
        delivery_result = self._delivery_service.deliver(downloaded_payload)

        terminal_state = delivery_result.state
        session = self._session_registry.transition(session_id, terminal_state)
        self._publish(session)
        client.report_delivery_result(
            result=delivery_result,
            correlation_id=correlation_id,
            requires_signature=requires_signature,
        )
        return downloaded_payload

    def fail_session(self, *, session_id: str, error: InstantShareError) -> InstantShareSession:
        session = self._session_registry.transition(session_id, SessionState.FAILED)
        self._publish(session, error=error)
        return session

    @staticmethod
    def _publish(session: InstantShareSession, *, error: InstantShareError | None = None) -> None:
        event = {
            "session_id": session.connection_config.session_id,
            "correlation_id": session.connection_config.correlation_id,
            "state": session.state.value,
            "payload_class": session.connection_config.metadata.payload_class.value,
            "target_intent": session.connection_config.metadata.target_intent.value,
            "trust_mode": session.connection_config.metadata.trust_mode.value,
        }
        if error is not None:
            event["error_code"] = error.error_code.value
            event["error_message"] = error.message
        default_bus.publish(INSTANT_SHARE_LIFECYCLE_EVENT, **event)