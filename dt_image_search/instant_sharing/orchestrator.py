from __future__ import annotations

from dataclasses import dataclass
import threading

from dt_image_search.instant_sharing.contracts import ErrorCode, SessionState
from dt_image_search.instant_sharing.delivery import InstantShareDeliveryService
from dt_image_search.instant_sharing.errors import InstantShareError
from dt_image_search.instant_sharing.http_client import InstantShareHttpClient
from dt_image_search.instant_sharing.session import InstantShareSession, InstantShareSessionRegistry
from dt_image_search.telemetry.telemetry_client import add_span, log
from dt_image_search.tools.dts_event_bus import default_bus


INSTANT_SHARE_LIFECYCLE_EVENT = "instant_share.lifecycle"


@dataclass(frozen=True)
class TrustHandshakeRequest:
    pc_dh_public_key: str
    pc_nonce: str
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
        with add_span(
            "instant_share.session.bootstrap",
            attributes=_session_attributes(connection_config),
        ):
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

    def complete_trust(
        self,
        *,
        session_id: str,
        client: InstantShareHttpClient,
        request: TrustHandshakeRequest,
        correlation_id: str,
    ) -> dict[str, object]:
        session = self._session_registry.require_session(session_id)
        with add_span(
            "instant_share.trust.complete",
            attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
        ):
            session = self._session_registry.transition(session_id, SessionState.NEGOTIATING)
            self._publish(session)
            try:
                client.trust_handshake(
                    pc_dh_public_key=request.pc_dh_public_key,
                    pc_nonce=request.pc_nonce,
                    correlation_id=correlation_id,
                )
                log(
                    "info",
                    message="Instant-share trust handshake completed",
                    where="instant_share.orchestrator.complete_trust",
                    attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
                )
                confirm_payload_holder: dict[str, object] = {}
                confirm_error_holder: list[BaseException] = []
                confirm_completed = threading.Event()

                def _run_trust_confirm() -> None:
                    try:
                        confirm_payload_holder.update(
                            client.trust_confirm(
                                correlation_id=correlation_id,
                            )
                        )
                    except BaseException as exc:
                        confirm_error_holder.append(exc)
                    finally:
                        confirm_completed.set()

                confirm_thread = threading.Thread(
                    target=_run_trust_confirm,
                    name="instant_share_trust_confirm",
                    daemon=True,
                )
                confirm_thread.start()

                client.trust_apply(
                    correlation_id=correlation_id,
                    key_id=request.key_id,
                )
                confirm_completed.wait()
                if confirm_error_holder:
                    raise confirm_error_holder[0]
                confirm_payload = dict(confirm_payload_holder)
            except InstantShareError as error:
                self._transition_on_error(session_id=session_id, error=error)
                raise
            log(
                "info",
                message="Instant-share trust established",
                where="instant_share.orchestrator.complete_trust",
                attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
            )
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
        with add_span(
            "instant_share.payload.receive",
            attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
        ):
            session = self._session_registry.transition(session_id, SessionState.TRANSFERRING)
            self._publish(session)

            try:
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
            except InstantShareError as error:
                self._transition_on_error(session_id=session_id, error=error)
                raise

            log(
                "info",
                message="Instant-share payload downloaded",
                where="instant_share.orchestrator.receive_payload",
                attributes=_session_attributes(session.connection_config, correlation_id=correlation_id),
            )

            session = self._session_registry.transition(session_id, SessionState.DELIVERING)
            self._publish(session)
            try:
                delivery_result = self._delivery_service.deliver(downloaded_payload)
            except InstantShareError as error:
                self._transition_on_error(session_id=session_id, error=error)
                raise

            terminal_state = delivery_result.state
            session = self._session_registry.transition(session_id, terminal_state)
            self._publish(session)
            client.report_delivery_result(
                result=delivery_result,
                correlation_id=correlation_id,
                requires_signature=requires_signature,
            )
            log(
                "info",
                message="Instant-share delivery complete",
                where="instant_share.orchestrator.receive_payload",
                attributes={
                    **_session_attributes(session.connection_config, correlation_id=correlation_id),
                    "instant_share.delivery_state": terminal_state.value,
                },
            )
            return downloaded_payload

    def fail_session(self, *, session_id: str, error: InstantShareError) -> InstantShareSession:
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

    def _transition_on_error(self, *, session_id: str, error: InstantShareError) -> InstantShareSession:
        desired_state = self._desired_terminal_state_for_error(error)
        try:
            session = self._session_registry.transition(session_id, desired_state)
        except InstantShareError:
            session = self._session_registry.transition(session_id, SessionState.FAILED)
        self._publish(session, error=error)
        return session

    @staticmethod
    def _desired_terminal_state_for_error(error: InstantShareError) -> SessionState:
        if error.error_code is ErrorCode.USER_ABORTED:
            return SessionState.ABORTED
        if error.error_code in {ErrorCode.TRANSFER_TIMEOUT, ErrorCode.CONFIRM_TIMEOUT}:
            return SessionState.TIMED_OUT
        return SessionState.FAILED

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