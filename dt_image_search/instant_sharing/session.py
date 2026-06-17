from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass, replace

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import ErrorCode, SessionState
from dt_image_search.instant_sharing.errors import InstantShareError


_logger = logging.getLogger(__name__)


_ACTIVE_STATES = {
    SessionState.BOOTSTRAPPED,
    SessionState.QUEUED,
    SessionState.NEGOTIATING,
    SessionState.TRANSFERRING,
    SessionState.DELIVERING,
}
_ALLOWED_TRANSITIONS = {
    SessionState.BOOTSTRAPPED: {SessionState.QUEUED, SessionState.NEGOTIATING, SessionState.TRANSFERRING},
    SessionState.QUEUED: {SessionState.NEGOTIATING, SessionState.TRANSFERRING, SessionState.FAILED, SessionState.TIMED_OUT},
    SessionState.NEGOTIATING: {SessionState.TRANSFERRING, SessionState.FAILED, SessionState.TIMED_OUT},
    SessionState.TRANSFERRING: {
        SessionState.DELIVERING,
        SessionState.FAILED,
        SessionState.TIMED_OUT,
        SessionState.ABORTED,
    },
    SessionState.DELIVERING: {SessionState.DONE, SessionState.FAILED},
    SessionState.DONE: set(),
    SessionState.FAILED: set(),
    SessionState.TIMED_OUT: set(),
    SessionState.ABORTED: set(),
}


@dataclass(frozen=True)
class InstantShareSession:
    connection_config: ConnectionConfig
    state: SessionState = SessionState.BOOTSTRAPPED
    started_monotonic: float = 0.0

    def __post_init__(self) -> None:
        if self.started_monotonic <= 0:
            object.__setattr__(self, "started_monotonic", time.monotonic())


class InstantShareSessionRegistry:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._active_session: InstantShareSession | None = None

    def bootstrap(self, connection_config: ConnectionConfig) -> InstantShareSession:
        connection_config.validate()
        with self._lock:
            if self._active_session is not None and self._active_session.state in _ACTIVE_STATES:
                raise InstantShareError(
                    ErrorCode.RECEIVER_BUSY_SINGLE_SESSION,
                    "An instant-share session is already active.",
                    correlation_id=connection_config.correlation_id,
                    retryable=True,
                )
            self._active_session = InstantShareSession(connection_config=connection_config)
            return self._active_session

    def replace_active_session(self, connection_config: ConnectionConfig) -> InstantShareSession:
        connection_config.validate()
        with self._lock:
            self._active_session = InstantShareSession(connection_config=connection_config)
            return self._active_session

    def bootstrap_revisit(self, connection_config: ConnectionConfig) -> InstantShareSession:
        connection_config.validate()
        with self._lock:
            if self._active_session is not None and self._active_session.state in _ACTIVE_STATES:
                _logger.info(
                    "Revisit overriding active session old_id=%s old_state=%s new_id=%s",
                    self._active_session.connection_config.session_id,
                    self._active_session.state.value,
                    connection_config.session_id,
                )
            session = InstantShareSession(
                connection_config=connection_config,
                state=SessionState.TRANSFERRING,
            )
            self._active_session = session
            return session

    def get_active_session(self) -> InstantShareSession | None:
        with self._lock:
            return self._active_session

    def require_session(self, session_id: str) -> InstantShareSession:
        if self._active_session is None or self._active_session.connection_config.session_id != session_id:
            active_id = self._active_session.connection_config.session_id if self._active_session else None
            _logger.warning(
                "Session mismatch: requested=%s active=%s active_state=%s",
                session_id, active_id,
                self._active_session.state.value if self._active_session else "None",
            )
            correlation_id = self._active_session.connection_config.correlation_id if self._active_session else None
            raise InstantShareError(
                ErrorCode.SESSION_ID_MISMATCH,
                "No active instant-share session matches the provided session id.",
                correlation_id=correlation_id,
            )
        return self._active_session

    def transition(self, session_id: str, next_state: SessionState) -> InstantShareSession:
        with self._lock:
            current_session = self.require_session(session_id)
            allowed_next_states = _ALLOWED_TRANSITIONS[current_session.state]
            if next_state not in allowed_next_states:
                raise InstantShareError(
                    ErrorCode.INVALID_REQUEST,
                    (
                        f"Cannot transition instant-share session from {current_session.state.value} "
                        f"to {next_state.value}."
                    ),
                    correlation_id=current_session.connection_config.correlation_id,
                )
            updated_session = replace(current_session, state=next_state)
            self._active_session = updated_session
            return updated_session