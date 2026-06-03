from __future__ import annotations

import logging
from typing import Any

from dt_image_search.instant_sharing.mini_window import (
    InstantShareMiniWindow,
    MiniWindowPhase,
    _TERMINAL_PHASES,
)
from dt_image_search.instant_sharing.orchestrator import INSTANT_SHARE_LIFECYCLE_EVENT
from dt_image_search.tools.dts_dispatcher import dispatcher
from dt_image_search.tools.dts_event_bus import default_bus


_logger = logging.getLogger(__name__)

WINDOW_HEIGHT = 520
WINDOW_WIDTH = 360


class InstantShareMiniWindowFactory:
    def __init__(self) -> None:
        self._active_window: InstantShareMiniWindow | None = None
        self._current_session_id: str | None = None
        self._subscription: Any = None

    def start(self) -> None:
        if self._subscription is not None:
            return
        self._subscription = default_bus.subscribe(
            INSTANT_SHARE_LIFECYCLE_EVENT,
            self._on_lifecycle_event,
        )
        _logger.info("[InstantShareMiniWindowFactory] started, subscribed to event bus")

    def stop(self) -> None:
        if self._subscription is not None:
            self._subscription.dispose()
            self._subscription = None
        if self._active_window is not None:
            self._close_window()
        _logger.info("[InstantShareMiniWindowFactory] stopped")

    def _on_lifecycle_event(
        self,
        *,
        state: object,
        session_id: object,
        payload_class: object,
        error_message: object = None,
        **_: object,
    ) -> None:
        state_value = str(state) if state is not None else "unknown"
        session_id_value = str(session_id) if session_id is not None else ""
        payload_class_value = str(payload_class) if payload_class is not None else ""
        error_message_value = str(error_message) if error_message is not None else ""

        phase = InstantShareMiniWindow.build_phase(state_value)
        is_new_session = session_id_value and session_id_value != self._current_session_id

        if is_new_session:
            dispatcher.post(lambda: self._create_or_show_window(
                session_id=session_id_value,
                state=state_value,
                payload_class=payload_class_value,
                error_message=error_message_value,
            ))
        elif self._active_window is not None:
            dispatcher.post(lambda: self._active_window.apply_session_event(
                state=state_value,
                payload_class=payload_class_value,
                error_message=error_message_value,
            ))

    def _create_or_show_window(
        self,
        session_id: str,
        state: str,
        payload_class: str,
        error_message: str,
    ) -> None:
        if self._active_window is not None:
            try:
                self._active_window.close()
            except RuntimeError:
                pass
            self._active_window = None
        self._current_session_id = session_id
        window = InstantShareMiniWindow()
        window.apply_session_event(
            state=state,
            payload_class=payload_class,
            error_message=error_message,
        )
        window.destroyed.connect(self._on_window_destroyed)
        window.show()
        self._active_window = window
        _logger.info(
            "[InstantShareMiniWindowFactory] window shown: session=%s state=%s",
            session_id,
            state,
        )

    def _on_window_destroyed(self) -> None:
        self._active_window = None

    def _close_window(self) -> None:
        if self._active_window is not None:
            try:
                self._active_window.close()
            except RuntimeError:
                pass
            self._active_window = None
        self._current_session_id = None
