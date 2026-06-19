from __future__ import annotations

import logging
from typing import Any

from dt_image_search.instant_sharing.activation_policy import (
    acquire_activation_policy,
    bring_to_front,
    release_activation_policy,
)
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
        text_content: object = "",
        file_path: object = "",
        device_name: object = "",
        **_: object,
    ) -> None:
        state_value = str(state) if state is not None else "unknown"
        session_id_value = str(session_id) if session_id is not None else ""
        payload_class_value = str(payload_class) if payload_class is not None else ""
        error_message_value = str(error_message) if error_message is not None else ""
        text_content_value = str(text_content) if text_content is not None else ""
        file_path_value = str(file_path) if file_path is not None else ""
        device_name_value = str(device_name) if device_name else ""

        phase = InstantShareMiniWindow.build_phase(state_value)
        is_new_session = session_id_value and session_id_value != self._current_session_id

        if is_new_session:
            self._current_session_id = session_id_value
            dispatcher.post(lambda: self._create_or_show_window(
                session_id=session_id_value,
                state=state_value,
                payload_class=payload_class_value,
                error_message=error_message_value,
                text_content=text_content_value,
                file_path=file_path_value,
                device_name=device_name_value,
            ))
        elif session_id_value == self._current_session_id:
            dispatcher.post(lambda: self._apply_event_to_window(
                state=state_value,
                payload_class=payload_class_value,
                error_message=error_message_value,
                text_content=text_content_value,
                file_path=file_path_value,
                device_name=device_name_value,
            ))

    def _create_or_show_window(
        self,
        session_id: str,
        state: str,
        payload_class: str,
        error_message: str,
        text_content: str = "",
        file_path: str = "",
        device_name: str = "",
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
            text_content=text_content,
            file_path=file_path,
            device_name=device_name,
        )
        window.destroyed.connect(self._on_window_destroyed)
        window.show()
        bring_to_front(window)
        acquire_activation_policy()
        self._active_window = window
        _logger.info(
            "[InstantShareMiniWindowFactory] window shown: session=%s state=%s",
            session_id,
            state,
        )

    def show_pin(self, pin_code: str) -> None:
        dispatcher.post(lambda: self._show_pin(pin_code))

    def _show_pin(self, pin_code: str) -> None:
        if self._active_window is not None:
            self._active_window.show_pin(pin_code)

    def _on_window_destroyed(self) -> None:
        self._active_window = None
        release_activation_policy()

    def _apply_event_to_window(
        self,
        state: str,
        payload_class: str,
        error_message: str,
        text_content: str = "",
        file_path: str = "",
        device_name: str = "",
    ) -> None:
        if self._active_window is not None:
            self._active_window.apply_session_event(
                state=state,
                payload_class=payload_class,
                error_message=error_message,
                text_content=text_content,
                file_path=file_path,
                device_name=device_name,
            )

    def _close_window(self) -> None:
        if self._active_window is not None:
            try:
                self._active_window.close()
            except RuntimeError:
                pass
        self._active_window = None
        release_activation_policy()
        self._current_session_id = None
