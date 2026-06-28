from __future__ import annotations

from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.instant_sharing.mobile_to_pc.state import (
    MiniWindowPhase,
    MiniWindowState,
    _TERMINAL_PHASES,
    _payload_label,
)
from dt_image_search.instant_sharing.mobile_to_pc.pin_code_widget import PinCodeWidget
from dt_image_search.instant_sharing.mobile_to_pc.loading_widget import LoadingWidget
from dt_image_search.instant_sharing.mobile_to_pc.upload_completion_widget import UploadCompletionWidget


WINDOW_WIDTH = 360
WINDOW_HEIGHT = 520

_PIN_PAGE = 0
_LOADING_PAGE = 1
_COMPLETION_PAGE = 2


class InstantShareMiniWindow(QDialog):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._state = MiniWindowState()
        self._auto_close_timer: QTimer | None = None
        self._setup_ui()

    @staticmethod
    def build_phase(state_value: str) -> MiniWindowPhase:
        state_lower = state_value.lower()
        if state_lower in ("bootstrapped", "queued", "connecting"):
            return MiniWindowPhase.CONNECTING
        if state_lower == "negotiating":
            return MiniWindowPhase.NEGOTIATING
        if state_lower == "displaying_pin":
            return MiniWindowPhase.DISPLAYING_PIN
        if state_lower == "transferring":
            return MiniWindowPhase.TRANSFERRING
        if state_lower == "delivering":
            return MiniWindowPhase.DELIVERING
        if state_lower == "done":
            return MiniWindowPhase.SUCCESS
        if state_lower == "failed":
            return MiniWindowPhase.FAILED
        if state_lower == "timed_out":
            return MiniWindowPhase.TIMED_OUT
        if state_lower == "aborted":
            return MiniWindowPhase.ABORTED
        return MiniWindowPhase.CONNECTING

    def apply_session_event(
        self,
        *,
        state: str,
        device_name: str = "",
        payload_class: str = "",
        error_message: str = "",
        text_content: str = "",
        file_path: str = "",
        image_count: int = 0,
        received_count: int = 0,
    ) -> None:
        phase = self.build_phase(state)
        label = _payload_label(payload_class) if payload_class else self._state.payload_label
        device = device_name or self._state.device_name

        # Calculate progress based on batch count when multiple images
        if image_count > 1 and received_count > 0:
            download_progress = received_count / image_count
        elif phase == MiniWindowPhase.SUCCESS:
            download_progress = 1.0
        else:
            download_progress = 0.0

        self._state = MiniWindowState(
            phase=phase,
            device_name=device,
            payload_label=label,
            error_message=error_message,
            download_progress=download_progress,
            pin_code=self._state.pin_code,
            text_content=text_content or self._state.text_content,
            file_path=file_path or self._state.file_path,
            image_count=image_count or self._state.image_count,
            received_count=received_count or self._state.received_count,
        )
        self._refresh_ui()
        self._bring_to_front()

        if phase in _TERMINAL_PHASES:
            self._schedule_auto_close()

    def show_pin(self, pin_code: str) -> None:
        self._state = MiniWindowState(
            phase=MiniWindowPhase.DISPLAYING_PIN,
            device_name=self._state.device_name,
            payload_label=self._state.payload_label,
            pin_code=pin_code,
        )
        self._refresh_ui()
        self._bring_to_front()

    def _bring_to_front(self) -> None:
        self.raise_()
        self.activateWindow()

    def _schedule_auto_close(self) -> None:
        if self._auto_close_timer is not None:
            self._auto_close_timer.stop()
        if self._state.phase == MiniWindowPhase.SUCCESS and (self._state.text_content or self._state.file_path):
            return
        delay = 4000 if self._state.phase == MiniWindowPhase.SUCCESS else 8000
        self._auto_close_timer = QTimer(self)
        self._auto_close_timer.setSingleShot(True)
        self._auto_close_timer.timeout.connect(self.close)
        self._auto_close_timer.start(delay)

    def _setup_ui(self) -> None:
        self.setWindowTitle("Instant Share")
        self.setFixedSize(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.setAttribute(Qt.WA_DeleteOnClose)

        app_icon = QApplication.windowIcon()
        if not app_icon.isNull():
            self.setWindowIcon(app_icon)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 24, 24, 24)
        layout.setSpacing(16)

        self._pin_widget = PinCodeWidget()
        self._loading_widget = LoadingWidget()
        self._completion_widget = UploadCompletionWidget()

        self._stack = QStackedWidget()
        self._stack.addWidget(self._pin_widget)
        self._stack.addWidget(self._loading_widget)
        self._stack.addWidget(self._completion_widget)
        layout.addWidget(self._stack)

        # Connect widget signals to parent handlers
        self._pin_widget.cancelled.connect(self._on_abort)
        self._loading_widget.cancelled.connect(self._on_abort)
        self._completion_widget.dismissed.connect(self.close)
        self._completion_widget.copy_requested.connect(self._on_copy)
        self._completion_widget.open_requested.connect(self._on_open)

        self._refresh_ui()

    def _on_abort(self) -> None:
        self._state.phase = MiniWindowPhase.ABORTED
        self._state.error_message = "Canceled by user."
        self._refresh_ui()
        self._schedule_auto_close()

    def _on_copy(self) -> None:
        text = self._state.text_content
        if text:
            QApplication.clipboard().setText(text)

    def _on_open(self) -> None:
        path = self._state.file_path
        if path:
            import subprocess
            subprocess.Popen(["open", "-R", path])

    def _refresh_ui(self) -> None:
        page_index = self._page_for_phase(self._state.phase)
        self._stack.setCurrentIndex(page_index)
        self._stack.currentWidget().set_state(self._state)

    @staticmethod
    def _page_for_phase(phase: MiniWindowPhase) -> int:
        if phase == MiniWindowPhase.DISPLAYING_PIN:
            return _PIN_PAGE
        if phase in _TERMINAL_PHASES:
            return _COMPLETION_PAGE
        return _LOADING_PAGE

    def closeEvent(self, event) -> None:
        if self._auto_close_timer is not None:
            self._auto_close_timer.stop()
            self._auto_close_timer = None
        super().closeEvent(event)
