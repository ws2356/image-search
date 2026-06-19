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
        self._windows: dict[str, InstantShareMiniWindow | None] = {}
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
        # Close all windows; each close() will trigger destroyed signal
        # which calls _on_window_destroyed and release_activation_policy.
        # Iterate over a snapshot of keys to avoid changing dict during iteration.
        for session_id in list(self._windows):
            window = self._windows.pop(session_id, None)
            if window is not None:
                try:
                    window.close()
                except RuntimeError:
                    pass
            release_activation_policy()
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

        if session_id_value and session_id_value not in self._windows:
            # New session: create a placeholder and schedule window creation
            self._windows[session_id_value] = None
            dispatcher.post(lambda sid=session_id_value: self._create_or_show_window(
                session_id=sid,
                state=state_value,
                payload_class=payload_class_value,
                error_message=error_message_value,
                text_content=text_content_value,
                file_path=file_path_value,
                device_name=device_name_value,
            ))
        elif session_id_value in self._windows:
            # Existing session: apply event to its window
            dispatcher.post(lambda sid=session_id_value: self._apply_event_to_window(
                session_id=sid,
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
        existing = self._windows.get(session_id)
        if existing is not None:
            # Window already exists for this session; bring it to front
            try:
                bring_to_front(existing)
            except RuntimeError:
                pass
            _logger.info(
                "[InstantShareMiniWindowFactory] window brought to front: session=%s state=%s",
                session_id,
                state,
            )
            return

        window = InstantShareMiniWindow()
        window.apply_session_event(
            state=state,
            payload_class=payload_class,
            error_message=error_message,
            text_content=text_content,
            file_path=file_path,
            device_name=device_name,
        )
        window.destroyed.connect(lambda sid=session_id: self._on_window_destroyed(sid))
        window.show()
        bring_to_front(window)
        acquire_activation_policy()
        self._windows[session_id] = window
        _logger.info(
            "[InstantShareMiniWindowFactory] window shown: session=%s state=%s",
            session_id,
            state,
        )

    def show_pin(self, pin_code: str, session_id: str = "") -> None:
        dispatcher.post(lambda: self._show_pin(pin_code, session_id))

    def _show_pin(self, pin_code: str, session_id: str = "") -> None:
        if session_id:
            window = self._windows.get(session_id)
            if window is not None:
                try:
                    window.show_pin(pin_code)
                except RuntimeError:
                    pass
            return
        for window in list(self._windows.values()):
            if window is not None:
                try:
                    window.show_pin(pin_code)
                except RuntimeError:
                    pass

    def _on_window_destroyed(self, session_id: str) -> None:
        self._windows.pop(session_id, None)
        release_activation_policy()

    def _apply_event_to_window(
        self,
        session_id: str,
        state: str,
        payload_class: str,
        error_message: str,
        text_content: str = "",
        file_path: str = "",
        device_name: str = "",
    ) -> None:
        window = self._windows.get(session_id)
        if window is not None:
            try:
                window.apply_session_event(
                    state=state,
                    payload_class=payload_class,
                    error_message=error_message,
                    text_content=text_content,
                    file_path=file_path,
                    device_name=device_name,
                )
            except RuntimeError:
                # Window was already deleted (e.g. auto-close race); clean up
                self._windows.pop(session_id, None)
                release_activation_policy()
