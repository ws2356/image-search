from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass, replace

from dt_image_search.instant_sharing.mdns import ConnectionConfig
from dt_image_search.instant_sharing.contracts import ErrorCode, SessionState
from dt_image_search.instant_sharing.errors import InstantShareError


_logger = logging.getLogger(__name__)


DEFAULT_MAX_SESSIONS = 8
_TERMINAL_SESSION_CLEANUP_SECONDS = 60

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
    last_updated: float = 0.0

    def __post_init__(self) -> None:
        if self.started_monotonic <= 0:
            now = time.monotonic()
            object.__setattr__(self, "started_monotonic", now)
            object.__setattr__(self, "last_updated", now)


class InstantShareSessionRegistry:
    def __init__(self, max_sessions: int | None = None) -> None:
        self._lock = threading.RLock()
        self._active_sessions: dict[str, InstantShareSession] = {}
        self._max_sessions: int = DEFAULT_MAX_SESSIONS if max_sessions is None else max_sessions
        self._cleanup_timers: dict[str, threading.Timer] = {}

    def bootstrap(self, connection_config: ConnectionConfig) -> InstantShareSession:
        connection_config.validate()
        with self._lock:
            # Idempotent: return existing session if session_id already known
            existing = self._active_sessions.get(connection_config.session_id)
            if existing is not None:
                return existing

            # Enforce max concurrent non-terminal sessions
            active_count = sum(1 for s in self._active_sessions.values() if s.state in _ACTIVE_STATES)
            if active_count >= self._max_sessions:
                raise InstantShareError(
                    ErrorCode.RECEIVER_BUSY_MAX_SESSIONS,
                    "Maximum concurrent sessions reached.",
                    correlation_id=connection_config.correlation_id,
                    retryable=True,
                    status_code=503,
                )

            session = InstantShareSession(connection_config=connection_config)
            self._active_sessions[connection_config.session_id] = session
            return session

    def bootstrap_revisit(self, connection_config: ConnectionConfig) -> InstantShareSession:
        session = self.bootstrap(connection_config)
        return self.transition(session.connection_config.session_id, SessionState.TRANSFERRING)

    def get_active_sessions(self) -> list[InstantShareSession]:
        with self._lock:
            return [s for s in self._active_sessions.values() if s.state in _ACTIVE_STATES]

    def get_session(self, session_id: str) -> InstantShareSession | None:
        with self._lock:
            return self._active_sessions.get(session_id)

    def require_session(self, session_id: str) -> InstantShareSession:
        with self._lock:
            session = self._active_sessions.get(session_id)
            if session is None:
                _logger.warning(
                    "Session mismatch: requested=%s", session_id,
                )
                raise InstantShareError(
                    ErrorCode.SESSION_ID_MISMATCH,
                    "No active instant-share session matches the provided session id.",
                    correlation_id=None,
                )
            return session

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
            updated_session = replace(current_session, state=next_state, last_updated=time.monotonic())
            self._active_sessions[session_id] = updated_session
            if next_state not in _ACTIVE_STATES:
                self._schedule_cleanup(session_id)
            return updated_session

    def _schedule_cleanup(self, session_id: str) -> None:
        timer = threading.Timer(_TERMINAL_SESSION_CLEANUP_SECONDS, self._cleanup_session, args=[session_id])
        timer.daemon = True
        self._cleanup_timers[session_id] = timer
        timer.start()

    def _cleanup_session(self, session_id: str) -> None:
        with self._lock:
            self._active_sessions.pop(session_id, None)
            self._cleanup_timers.pop(session_id, None)
