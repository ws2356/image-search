from __future__ import annotations

import sys

from PySide6.QtCore import QUrl, Qt
from PySide6.QtGui import QCloseEvent, QDesktopServices
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.telemetry.telemetry_client import log

DEFAULT_UPDATE_BODY_TEXT = "Check out the new features by updating to the latest version."
WINDOWS_UPDATE_DESTINATION = "https://apps.microsoft.com/detail/9n5n8gvnrzdn"
MACOS_UPDATE_DESTINATION = "https://aurora.boldman.net"
UPDATE_AVAILABLE_TITLE = "Update Available"
UPDATE_REQUIRED_TITLE = "Update Required"


def default_update_destination(platform: str | None = None) -> str:
    resolved_platform = (platform or sys.platform).lower()
    if resolved_platform == "darwin":
        return MACOS_UPDATE_DESTINATION
    return WINDOWS_UPDATE_DESTINATION


DEFAULT_UPDATE_DESTINATION = default_update_destination()


class UpdatePromptDialog(QDialog):
    def __init__(
        self,
        *,
        is_required: bool,
        body_text: str | None = None,
        update_destination: str | None = None,
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self._is_required = is_required
        self._body_text = (body_text or DEFAULT_UPDATE_BODY_TEXT).strip() or DEFAULT_UPDATE_BODY_TEXT
        self._update_destination = (
            update_destination or default_update_destination()
        ).strip() or default_update_destination()

        self.setWindowTitle(UPDATE_REQUIRED_TITLE if self._is_required else UPDATE_AVAILABLE_TITLE)
        self.setModal(True)
        self.setWindowModality(Qt.ApplicationModal)
        self.setWindowFlag(Qt.WindowContextHelpButtonHint, False)
        self.setWindowFlag(Qt.WindowMaximizeButtonHint, False)
        self.setWindowFlag(Qt.WindowCloseButtonHint, not self._is_required)
        self.setMinimumWidth(460)
        self.setMinimumHeight(180)
        self._init_ui()

    def _init_ui(self) -> None:
        root_layout = QVBoxLayout(self)
        root_layout.setContentsMargins(20, 16, 20, 16)
        root_layout.setSpacing(16)

        body_label = QLabel(self._body_text, self)
        body_label.setWordWrap(True)
        body_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        root_layout.addWidget(body_label)

        button_layout = QHBoxLayout()
        button_layout.addStretch(1)

        if not self._is_required:
            cancel_button = QPushButton("Not Now", self)
            cancel_button.clicked.connect(self._on_cancel_clicked)
            button_layout.addWidget(cancel_button)

        update_button = QPushButton("Update", self)
        update_button.setDefault(True)
        update_button.clicked.connect(self._on_update_clicked)
        button_layout.addWidget(update_button)

        root_layout.addLayout(button_layout)

    def _on_update_clicked(self) -> None:
        update_url = QUrl(self._update_destination)
        if not update_url.isValid() or not update_url.scheme() or not update_url.host():
            log(
                "error",
                message=(
                    "UpdatePromptDialog/update: invalid destination URL "
                    f"destination={self._update_destination}"
                ),
            )
            return

        opened = QDesktopServices.openUrl(update_url)
        if not opened:
            log(
                "error",
                message=(
                    "UpdatePromptDialog/update: failed to open destination URL "
                    f"destination={self._update_destination}"
                ),
            )
            return

        if not self._is_required:
            self.accept()

    def _on_cancel_clicked(self) -> None:
        self.reject()

    def closeEvent(self, event: QCloseEvent) -> None:
        if self._is_required:
            event.ignore()
            return
        super().closeEvent(event)


def show_update_prompt_dialog(
    *,
    is_required: bool,
    body_text: str | None = None,
    update_destination: str | None = None,
    parent: QWidget | None = None,
) -> bool:
    dialog = UpdatePromptDialog(
        is_required=is_required,
        body_text=body_text,
        update_destination=update_destination,
        parent=parent,
    )
    return dialog.exec() == QDialog.DialogCode.Accepted
