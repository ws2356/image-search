from __future__ import annotations

from dataclasses import dataclass
import threading

from dt_image_search.instant_sharing.contracts import ErrorCode, SessionState
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.session import InstantShareSession, InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry
from dt_image_search.telemetry.telemetry_client import add_span, log
from dt_image_search.tools.dts_event_bus import default_bus


INSTANT_SHARE_LIFECYCLE_EVENT = "instant_share.lifecycle"


class InstantShareReceiverOrchestrator:
    def __init__(
        self,
        *,
        session_registry: InstantShareSessionRegistry,
        delivery_service: InstantShareDeliveryService,
        trust_session_registry: TrustSessionRegistry | None = None,
    ) -> None:
        self._session_registry = session_registry
        self._delivery_service = delivery_service
        self._trust_session_registry = trust_session_registry

    def handle_connection_config(self, connection_config) -> InstantShareSession:
        session = self._session_registry.bootstrap(connection_config)
        session = self._session_registry.transition(connection_config.session_id, SessionState.QUEUED)
        self._publish(session)
        log(
            "info",
            message="Instant-share session accepted",
            where="instant_share.orchestrator.handle_connection_config",
            attributes=_session_attributes(connection_config),
        )
        return session

    def handle_trust_handshake_received(self, *, session_id: str, correlation_id: str) -> None:
        session = self._session_registry.require_session(session_id)
        with add_span(
            "instant_share.trust.handshake.received",
            attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
        ):
            updated = self._session_registry.transition(session_id, SessionState.NEGOTIATING)
            self._publish(updated)
            log(
                "info",
                message="Instant-share trust handshake received from mobile",
                where="instant_share.orchestrator.handle_trust_handshake_received",
                attributes=_session_attributes(updated.connection_config, correlation_id=correlation_id),
            )

    def handle_trust_confirmed(self, *, session_id: str, correlation_id: str) -> None:
        session = self._session_registry.require_session(session_id)
        with add_span(
            "instant_share.trust.confirmed",
            attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
        ):
            updated = self._session_registry.transition(session_id, SessionState.NEGOTIATING)
            self._publish(updated)
            log(
                "info",
                message="Instant-share trust confirmed by mobile",
                where="instant_share.orchestrator.handle_trust_confirmed",
                attributes=_session_attributes(updated.connection_config, correlation_id=correlation_id),
            )

    def handle_transfer_received(
        self, *, session_id: str, correlation_id: str, image_count: int | None = None,
    ) -> bool:
        session = self._session_registry.require_session(session_id)
        with add_span(
            "instant_share.transfer.received",
            attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
        ):
            # Set batch metadata if provided and not already set
            if image_count is not None and session.image_count == 0:
                self._session_registry.set_batch_metadata(session_id, image_count)
            # Increment received count
            self._session_registry.increment_received_count(session_id)
            # Only transition if not already in TRANSFERRING state
            if session.state is not SessionState.TRANSFERRING:
                session = self._session_registry.transition(session_id, SessionState.TRANSFERRING)
            else:
                session = self._session_registry.require_session(session_id)
            self._publish(session)

        # Check batch completion
        session = self._session_registry.require_session(session_id)
        batch_complete = session.image_count == 0 or session.received_count >= session.image_count
        return batch_complete

    def handle_revisit_transfer(
        self,
        *,
        connection_config,
        peer_device_name: str = "",
        image_count: int | None = None,
    ) -> InstantShareSession:
        with add_span(
            "instant_share.revisit.transfer",
            attributes=_session_attributes(connection_config),
        ):
            session = self._session_registry.bootstrap(connection_config)
            session = self._session_registry.transition(connection_config.session_id, SessionState.TRANSFERRING)
            # Apply batch tracking metadata if provided
            if image_count is not None:
                self._session_registry.set_batch_metadata(connection_config.session_id, image_count)
                self._session_registry.increment_received_count(connection_config.session_id)
            session = self._session_registry.require_session(connection_config.session_id)
            self._publish(session, device_name=peer_device_name)
            log(
                "info",
                message="Instant-share revisit transfer session created",
                where="instant_share.orchestrator.handle_revisit_transfer",
                attributes=_session_attributes(connection_config),
            )
            return session

    def handle_delivery_complete(
        self,
        *,
        session_id: str,
        correlation_id: str,
        text_content: str = "",
        file_path: str = "",
    ) -> None:
        session = self._session_registry.require_session(session_id)
        # For batch transfers, only deliver when all images received
        if session.image_count > 0 and session.received_count < session.image_count:
            log(
                "info",
                message=f"Batch transfer in progress: {session.received_count}/{session.image_count} images received, deferring delivery",
                where="instant_share.orchestrator.handle_delivery_complete",
            )
            return
        if session.state is not SessionState.DELIVERING:
            delivering = self._session_registry.transition(session_id, SessionState.DELIVERING)
            self._publish(delivering, text_content=text_content, file_path=file_path)
        updated = self._session_registry.transition(session_id, SessionState.DONE)
        self._publish(updated, text_content=text_content, file_path=file_path)
        log(
            "info",
            message="Instant-share delivery complete",
            where="instant_share.orchestrator.handle_delivery_complete",
            attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
        )

    def fail_session(self, *, session_id: str, error: InstantShareError) -> InstantShareSession:
        desired_state = self._desired_terminal_state_for_error(error)
        try:
            session = self._session_registry.transition(session_id, desired_state)
        except InstantShareError:
            session = self._session_registry.transition(session_id, SessionState.FAILED)
        self._publish(session, error=error)
        log(
            "error",
            error_type=error.error_code.value,
            message=error.message,
            where="instant_share.orchestrator.fail_session",
            attributes=_session_attributes(session.connection_config),
        )
        return session

    def abort_session(self, *, session_id: str) -> InstantShareSession:
        error = InstantShareError(
            ErrorCode.USER_ABORTED,
            "User aborted the instant-share transfer.",
        )
        session = self._session_registry.transition(session_id, SessionState.ABORTED)
        self._publish(session, error=error)
        log(
            "warning",
            message="Instant-share session aborted by user",
            where="instant_share.orchestrator.abort_session",
            attributes=_session_attributes(session.connection_config),
        )
        return session

    @staticmethod
    def _desired_terminal_state_for_error(error: InstantShareError) -> SessionState:
        if error.error_code is ErrorCode.USER_ABORTED:
            return SessionState.ABORTED
        if error.error_code in {ErrorCode.TRANSFER_TIMEOUT, ErrorCode.CONFIRM_TIMEOUT}:
            return SessionState.TIMED_OUT
        return SessionState.FAILED

    def _publish(
        self,
        session: InstantShareSession,
        *,
        error: InstantShareError | None = None,
        text_content: str = "",
        file_path: str = "",
        device_name: str | None = None,
    ) -> None:
        if device_name is None:
            device_name = self._get_device_name(session.connection_config.session_id)
        event: dict[str, object] = {
            "session_id": session.connection_config.session_id,
            "correlation_id": session.connection_config.correlation_id,
            "state": session.state.value,
            "payload_class": session.connection_config.metadata.payload_class.value,
            "target_intent": session.connection_config.metadata.target_intent.value,
            "trust_mode": session.connection_config.metadata.trust_mode.value,
            "image_count": session.image_count,
            "received_count": session.received_count,
        }
        if device_name:
            event["device_name"] = device_name
        if text_content:
            event["text_content"] = text_content
        if file_path:
            event["file_path"] = file_path
        if error is not None:
            event["error_code"] = error.error_code.value
            event["error_message"] = error.message
        default_bus.publish(INSTANT_SHARE_LIFECYCLE_EVENT, **event)

    def _get_device_name(self, session_id: str) -> str:
        if self._trust_session_registry is None:
            return ""
        trust_session = self._trust_session_registry.get_session(session_id)
        if trust_session is None:
            return ""
        return trust_session.peer_device_name

    @property
    def trust_session_registry(self) -> TrustSessionRegistry | None:
        return self._trust_session_registry


def _session_attributes(connection_config, *, correlation_id: str | None = None) -> dict[str, object]:
    attributes: dict[str, object] = {
        "instant_share.session_id": connection_config.session_id,
        "instant_share.correlation_id": connection_config.correlation_id,
        "instant_share.payload_class": connection_config.metadata.payload_class.value,
        "instant_share.target_intent": connection_config.metadata.target_intent.value,
        "instant_share.trust_mode": connection_config.metadata.trust_mode.value,
    }
    if correlation_id is not None:
        attributes["instant_share.correlation_id"] = correlation_id
    return attributes