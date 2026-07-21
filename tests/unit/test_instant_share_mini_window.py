from __future__ import annotations

import pytest

from dt_image_search.instant_sharing.mini_window import (
    InstantShareMiniWindow,
    MiniWindowPhase,
    MiniWindowState,
    _TERMINAL_PHASES,
    _phase_message,
    _payload_label,
)


class TestMiniWindowPhase:
    def test_build_phase_mapping(self) -> None:
        assert InstantShareMiniWindow.build_phase("bootstrapped") == MiniWindowPhase.CONNECTING
        assert InstantShareMiniWindow.build_phase("queued") == MiniWindowPhase.CONNECTING
        assert InstantShareMiniWindow.build_phase("negotiating") == MiniWindowPhase.NEGOTIATING
        assert InstantShareMiniWindow.build_phase("transferring") == MiniWindowPhase.TRANSFERRING
        assert InstantShareMiniWindow.build_phase("delivering") == MiniWindowPhase.DELIVERING
        assert InstantShareMiniWindow.build_phase("done") == MiniWindowPhase.SUCCESS
        assert InstantShareMiniWindow.build_phase("failed") == MiniWindowPhase.FAILED
        assert InstantShareMiniWindow.build_phase("timed_out") == MiniWindowPhase.TIMED_OUT
        assert InstantShareMiniWindow.build_phase("aborted") == MiniWindowPhase.ABORTED
        assert InstantShareMiniWindow.build_phase("unknown") == MiniWindowPhase.CONNECTING

    def test_build_phase_case_insensitive(self) -> None:
        assert InstantShareMiniWindow.build_phase("DONE") == MiniWindowPhase.SUCCESS
        assert InstantShareMiniWindow.build_phase("Negotiating") == MiniWindowPhase.NEGOTIATING


class TestPhaseMessages:
    def test_connecting(self) -> None:
        msg = _phase_message(MiniWindowPhase.CONNECTING, "My Mac", "shared text")
        assert "My Mac" in msg

    def test_connecting_no_device(self) -> None:
        msg = _phase_message(MiniWindowPhase.CONNECTING, "", "shared text")
        assert "your Mac" in msg

    def test_transferring(self) -> None:
        msg = _phase_message(MiniWindowPhase.TRANSFERRING, "PC", "shared image")
        assert "shared image" in msg

    def test_success(self) -> None:
        msg = _phase_message(MiniWindowPhase.SUCCESS, "", "shared text")
        assert "received successfully" in msg.lower()

    def test_failed(self) -> None:
        msg = _phase_message(MiniWindowPhase.FAILED, "", "")
        assert "failed" in msg.lower()

    def test_timed_out(self) -> None:
        msg = _phase_message(MiniWindowPhase.TIMED_OUT, "", "")
        assert "timed out" in msg.lower()

    def test_aborted(self) -> None:
        msg = _phase_message(MiniWindowPhase.ABORTED, "", "")
        assert "canceled" in msg.lower()

    def test_busy(self) -> None:
        msg = _phase_message(MiniWindowPhase.BUSY, "", "")
        assert "already in progress" in msg.lower()


class TestPayloadLabel:
    def test_text(self) -> None:
        assert _payload_label("text") == "shared text"

    def test_image(self) -> None:
        assert _payload_label("image") == "shared image"

    def test_unknown(self) -> None:
        assert _payload_label("video") == "shared item"


class TestTerminalPhases:
    def test_terminal_phases_set(self) -> None:
        assert MiniWindowPhase.SUCCESS in _TERMINAL_PHASES
        assert MiniWindowPhase.FAILED in _TERMINAL_PHASES
        assert MiniWindowPhase.TIMED_OUT in _TERMINAL_PHASES
        assert MiniWindowPhase.ABORTED in _TERMINAL_PHASES
        assert MiniWindowPhase.BUSY in _TERMINAL_PHASES

    def test_non_terminal_not_in_set(self) -> None:
        assert MiniWindowPhase.CONNECTING not in _TERMINAL_PHASES
        assert MiniWindowPhase.NEGOTIATING not in _TERMINAL_PHASES
        assert MiniWindowPhase.TRANSFERRING not in _TERMINAL_PHASES
        assert MiniWindowPhase.DELIVERING not in _TERMINAL_PHASES


class TestMiniWindowState:
    def test_default(self) -> None:
        state = MiniWindowState()
        assert state.phase == MiniWindowPhase.CONNECTING
        assert state.device_name == ""
        assert state.payload_label == "shared item"
        assert state.error_message == ""
        assert state.download_progress == 0.0

    def test_custom(self) -> None:
        state = MiniWindowState(
            phase=MiniWindowPhase.SUCCESS,
            device_name="My Mac",
            payload_label="shared text",
            download_progress=1.0,
        )
        assert state.phase == MiniWindowPhase.SUCCESS
        assert state.device_name == "My Mac"
        assert state.download_progress == 1.0


class TestMiniWindowApplySessionEvent:
    def test_apply_event_updates_state(self) -> None:
        from PySide6.QtWidgets import QApplication
        _qapp = QApplication.instance()
        if _qapp is None:
            _qapp = QApplication([])
        window = InstantShareMiniWindow()
        window.apply_session_event(
            state="transferring",
            device_name="My Mac",
            payload_class="text",
        )
        assert window._state.phase == MiniWindowPhase.TRANSFERRING
        assert window._state.device_name == "My Mac"
        assert window._state.payload_label == "shared text"

    def test_apply_terminal_state(self) -> None:
        from PySide6.QtWidgets import QApplication
        _qapp = QApplication.instance()
        if _qapp is None:
            _qapp = QApplication([])
        window = InstantShareMiniWindow()
        window.apply_session_event(
            state="done",
            device_name="PC",
            payload_class="image",
        )
        assert window._state.phase == MiniWindowPhase.SUCCESS
        assert window._state.download_progress == 1.0

    def test_apply_error_message(self) -> None:
        from PySide6.QtWidgets import QApplication
        _qapp = QApplication.instance()
        if _qapp is None:
            _qapp = QApplication([])
        window = InstantShareMiniWindow()
        window.apply_session_event(
            state="failed",
            error_message="Connection refused",
        )
        assert window._state.phase == MiniWindowPhase.FAILED
        assert window._state.error_message == "Connection refused"


class TestMiniWindowFactory:
    def test_start_stop_lifecycle(self) -> None:
        from dt_image_search.instant_sharing.mini_window_factory import InstantShareMiniWindowFactory

        factory = InstantShareMiniWindowFactory()
        factory.start()
        assert factory._subscription is not None
        factory.stop()
        assert factory._subscription is None
        assert factory._active_window is None

    def test_same_session_updates_window(self) -> None:
        from PySide6.QtWidgets import QApplication
        _qapp = QApplication.instance()
        if _qapp is None:
            _qapp = QApplication([])

        from dt_image_search.instant_sharing.mini_window_factory import InstantShareMiniWindowFactory

        factory = InstantShareMiniWindowFactory()
        factory.start()

        factory._on_lifecycle_event(
            state="queued",
            session_id="session-1",
            payload_class="text",
        )

        factory._on_lifecycle_event(
            state="transferring",
            session_id="session-1",
            payload_class="text",
        )

        factory.stop()
