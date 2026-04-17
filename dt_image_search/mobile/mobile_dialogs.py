from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Callable

from PIL import Image
from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QColor, QFont, QImage, QPainter, QPixmap
from PySide6.QtWidgets import (
    QFileDialog,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.mobile.apple_mobile_device_support import (
    APPLE_NETWORK_DRIVER_INF,
    APPLE_USB_DRIVER_INF,
    AppleMobileDeviceSupportInstallError,
    AppleMobileDeviceSupportManager,
    AppleMobileDeviceSupportStatus,
)
from dt_image_search.mobile.mobile_pairing_service import MobilePairingService, PairingResultState
from dt_image_search.mobile.mobile_pairing_session import (
    MobilePairingSessionDraft,
    MobilePairingToken,
    MobilePlatform,
    MobileSourceType,
)
from dt_image_search.telemetry.telemetry_client import log

try:
    import qrcode
except Exception:
    qrcode = None


def _endpoint_urls_detail(endpoint_urls: tuple[str, ...]) -> str:
    if len(endpoint_urls) == 1:
        endpoint_heading = f"Desktop endpoint: {endpoint_urls[0]}"
    else:
        endpoint_heading = "Desktop endpoints:\n" + "\n".join(endpoint_urls)
    return (
        f"{endpoint_heading}"
    )


class SourceSelectionDialog(QDialog):
    _ICON_LOCAL = "🖥"
    _ICON_MOBILE = "📱"

    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        self._selected_source: MobileSourceType | None = None
        self.setWindowTitle("Add Folder")
        self.setModal(True)
        self.resize(500, 300)
        self.setStyleSheet("QDialog { background: #f5f5f5; border-radius: 12px; }")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        title = QLabel("Choose a source")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setWeight(QFont.Weight.DemiBold)
        title.setFont(title_font)
        title.setStyleSheet("color: #1f2937;")
        layout.addWidget(title)

        subtitle = QLabel(
            "**Local Device** create index for semantic search for images in a folder on this computer.\n"
            "**Mobile Device** starts a paired backup flow over USB or Wi-Fi LAN, before creating an index."
        )
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #666666; font-size: 12px;")
        layout.addWidget(subtitle)

        button_row = QHBoxLayout()
        button_row.setSpacing(14)
        button_row.addWidget(
            self._build_source_card(
                icon=self._ICON_LOCAL,
                title="Local Device",
                description="Index a folder that already exists on this computer.",
                source=MobileSourceType.LOCAL_DEVICE,
            )
        )
        button_row.addWidget(
            self._build_source_card(
                icon=self._ICON_MOBILE,
                title="Mobile Device",
                description="Pair a phone or tablet for local backup transfer and index creation.",
                source=MobileSourceType.MOBILE_DEVICE,
            )
        )
        layout.addLayout(button_row)

        bottom_row = QHBoxLayout()
        bottom_row.addStretch()
        cancel_button = QPushButton("Cancel")
        cancel_button.setCursor(Qt.PointingHandCursor)
        cancel_button.setStyleSheet(
            """
            QPushButton {
                background: #e0e0e0; border: 1px solid #c0c0c0; border-radius: 6px;
                padding: 6px 18px; font-size: 13px; font-weight: 500; color: #333333;
            }
            QPushButton:hover { background: #d4d4d4; }
            """
        )
        cancel_button.clicked.connect(self.reject)
        bottom_row.addWidget(cancel_button)
        layout.addLayout(bottom_row)

    def _build_source_card(
        self, icon: str, title: str, description: str, source: MobileSourceType
    ) -> QFrame:
        card = QFrame()
        card.setFixedHeight(160)
        card.setCursor(Qt.PointingHandCursor)
        card.setStyleSheet(self._card_style())

        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(16, 16, 16, 16)
        card_layout.setSpacing(8)

        icon_label = QLabel(icon)
        icon_label.setStyleSheet("font-size: 28px; border: none; background: transparent;")
        card_layout.addWidget(icon_label)

        title_label = QLabel(title)
        title_label.setStyleSheet(
            "font-size: 14px; font-weight: 600; color: #1f2937; border: none; background: transparent;"
        )
        card_layout.addWidget(title_label)

        desc_label = QLabel(description)
        desc_label.setWordWrap(True)
        desc_label.setStyleSheet(
            "font-size: 12px; color: #666666; border: none; background: transparent;"
        )
        card_layout.addWidget(desc_label)
        card_layout.addStretch()

        card.mousePressEvent = lambda _event, s=source: self._confirm_source(s)
        return card

    @staticmethod
    def _card_style() -> str:
        return (
            "QFrame { background: #ffffff; border: 1.5px solid #d8d8d8;"
            " border-radius: 12px; }"
            "QFrame:hover { border-color: #90b8ff; }"
        )

    def _confirm_source(self, source: MobileSourceType) -> None:
        self._selected_source = source
        self.accept()

    @classmethod
    def select_source(cls, parent: QWidget | None = None) -> MobileSourceType | None:
        dialog = cls(parent)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            return dialog._selected_source
        return None


class ParentFolderSelectionDialog(QDialog):
    def __init__(self, initial_directory: str, parent: QWidget | None = None):
        super().__init__(parent)
        self._selected_directory = self._normalize_directory(initial_directory)
        self.setWindowTitle("Choose Backup Location")
        self.setModal(True)
        self.resize(560, 320)
        self.setStyleSheet("QDialog { background: #f5f5f5; border-radius: 12px; }")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(12)

        title = QLabel("Choose Backup Location")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setWeight(QFont.Weight.DemiBold)
        title.setFont(title_font)
        title.setStyleSheet("color: #1f2937;")
        layout.addWidget(title)

        subtitle = QLabel("Select where images from your mobile device will be stored.")
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #666666; font-size: 13px;")
        layout.addWidget(subtitle)

        info_banner = QFrame()
        info_banner.setStyleSheet(
            "QFrame { background: #f0f8ff; border: 1px solid #c4dcff; border-radius: 8px; }"
        )
        info_layout = QHBoxLayout(info_banner)
        info_layout.setContentsMargins(12, 10, 12, 10)
        info_layout.setSpacing(8)

        info_icon = QLabel("ℹ")
        info_icon.setStyleSheet("color: #1a5a9c; font-size: 15px; font-weight: 600;")
        info_layout.addWidget(info_icon, alignment=Qt.AlignTop)

        info_text = QLabel(
            "Your mobile photos will be transferred directly over your local network and stored on this computer.\n"
            "This keeps your images private and allows DTImageSearch to index them for fast semantic search.\n"
            "No cloud upload required."
        )
        info_text.setWordWrap(True)
        info_text.setStyleSheet("color: #3a5a9c; font-size: 12px; line-height: 1.5;")
        info_layout.addWidget(info_text, stretch=1)
        layout.addWidget(info_banner)

        destination_label = QLabel("Destination Folder")
        destination_label.setStyleSheet("font-size: 12px; font-weight: 600; color: #444;")
        layout.addWidget(destination_label)

        destination_row = QHBoxLayout()
        destination_row.setSpacing(8)
        self._path_input = QLineEdit(self._selected_directory)
        self._path_input.setReadOnly(True)
        self._path_input.setStyleSheet(
            """
            QLineEdit {
                background: #ffffff; border: 1.5px solid #c8c8c8; border-radius: 6px;
                padding: 7px 10px; color: #333333; font-size: 12px;
            }
            """
        )
        destination_row.addWidget(self._path_input, stretch=1)

        browse_button = QPushButton("Browse…")
        browse_button.setCursor(Qt.PointingHandCursor)
        browse_button.setStyleSheet(
            """
            QPushButton {
                background: #e0e0e0; border: 1px solid #c0c0c0; border-radius: 6px;
                padding: 7px 16px; font-size: 12px; color: #333333; font-weight: 500;
            }
            QPushButton:hover { background: #d4d4d4; }
            """
        )
        browse_button.clicked.connect(self._browse_directory)
        destination_row.addWidget(browse_button)
        layout.addLayout(destination_row)

        bottom_row = QHBoxLayout()
        bottom_row.addStretch()
        cancel_button = QPushButton("Cancel")
        cancel_button.setCursor(Qt.PointingHandCursor)
        cancel_button.setStyleSheet(
            """
            QPushButton {
                background: #e0e0e0; border: 1px solid #c0c0c0; border-radius: 6px;
                padding: 7px 16px; font-size: 13px; color: #333333; font-weight: 500;
            }
            QPushButton:hover { background: #d4d4d4; }
            """
        )
        cancel_button.clicked.connect(self.reject)
        bottom_row.addWidget(cancel_button)

        self._continue_button = QPushButton("Continue")
        self._continue_button.setCursor(Qt.PointingHandCursor)
        self._continue_button.setStyleSheet(
            """
            QPushButton {
                background: #007AFF; border: 1px solid #0068dd; border-radius: 6px;
                padding: 7px 18px; font-size: 13px; color: #ffffff; font-weight: 600;
            }
            QPushButton:hover { background: #0070ef; }
            QPushButton:disabled { background: #b0d4ff; border-color: #90c0ef; }
            """
        )
        self._continue_button.clicked.connect(self._confirm_selection)
        bottom_row.addWidget(self._continue_button)
        layout.addLayout(bottom_row)

        self._path_input.textChanged.connect(self._update_continue_state)
        self._update_continue_state()

    @property
    def selected_directory(self) -> str:
        return self._selected_directory

    @classmethod
    def select_destination_parent(
        cls,
        initial_directory: str,
        parent: QWidget | None = None,
    ) -> str | None:
        dialog = cls(initial_directory=initial_directory, parent=parent)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            return dialog.selected_directory
        return None

    @staticmethod
    def _normalize_directory(directory_path: str) -> str:
        if directory_path:
            return Path(directory_path).expanduser().resolve().as_posix()
        return Path.home().resolve().as_posix()

    def _browse_directory(self) -> None:
        initial_directory = self._path_input.text().strip() or self._selected_directory
        selected_directory = QFileDialog.getExistingDirectory(
            self,
            "Select Mobile Backup Parent Folder",
            initial_directory,
        )
        if not selected_directory:
            return
        normalized_directory = self._normalize_directory(selected_directory)
        self._selected_directory = normalized_directory
        self._path_input.setText(normalized_directory)

    def _confirm_selection(self) -> None:
        selected_directory = self._path_input.text().strip()
        if not selected_directory:
            self._update_continue_state()
            return

        normalized_directory = self._normalize_directory(selected_directory)
        if not Path(normalized_directory).is_dir():
            QMessageBox.warning(
                self,
                "Invalid Destination Folder",
                "The selected destination folder does not exist. Please choose an existing folder.",
            )
            return

        self._selected_directory = normalized_directory
        self.accept()

    def _update_continue_state(self) -> None:
        self._continue_button.setEnabled(bool(self._path_input.text().strip()))


class PairingQrCard(QFrame):
    def __init__(
        self,
        platform: MobilePlatform,
        token: MobilePairingToken,
        on_refresh: Callable[[MobilePlatform], MobilePairingToken],
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self._platform = platform
        self._token = token
        self._on_refresh = on_refresh
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "QFrame { border: 1.5px solid #ddd; border-radius: 12px; background: #ffffff; }"
        )

        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(10)

        self.qr_label = QLabel()
        self.qr_label.setFixedSize(200, 200)
        self.qr_label.setAlignment(Qt.AlignCenter)
        self.qr_label.setStyleSheet(
            "background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px;"
        )
        layout.addWidget(self.qr_label, alignment=Qt.AlignCenter)

        self.refresh_overlay_button = QPushButton("Refresh", self.qr_label)
        self.refresh_overlay_button.setCursor(Qt.PointingHandCursor)
        self.refresh_overlay_button.setFixedSize(200, 200)
        self.refresh_overlay_button.move(0, 0)

        self.refresh_overlay_button.setStyleSheet(
            """
            QPushButton {
                background: rgba(245, 245, 245, 245);
                color: #007AFF;
                border: 1px solid rgba(148, 163, 184, 180);
                border-radius: 8px;
                font-size: 18px;
                font-weight: 700;
            }
            QPushButton:hover {
                background: rgba(245, 245, 245, 245);
            }
            """
        )
        self.refresh_overlay_button.clicked.connect(self._refresh_token)
        self.refresh_overlay_button.hide()

        self.set_token(token)

    def set_token(self, token: MobilePairingToken) -> None:
        self._token = token
        pixmap = _render_qr_pixmap(token.payload, size=200)
        self.qr_label.setPixmap(pixmap)
        self.update_clock(datetime.now(token.expires_at.tzinfo))

    def update_clock(self, now: datetime) -> None:
        expired = self._token.is_expired(now)
        if expired:
            self.refresh_overlay_button.show()
        else:
            self.refresh_overlay_button.hide()

    def _refresh_token(self) -> None:
        refreshed_token = self._on_refresh(self._platform)
        self.set_token(refreshed_token)


class MobileUsbPrerequisitesDialog(QDialog):
    def __init__(
        self,
        *,
        support_manager: AppleMobileDeviceSupportManager,
        initial_status: AppleMobileDeviceSupportStatus,
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self._support_manager = support_manager
        self._status = initial_status
        self.setWindowTitle("Install Apple USB Support")
        self.setModal(True)
        self.resize(700, 500)
        self.setStyleSheet("QDialog { background: #f4f4f4; }")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(12)

        title = QLabel("Install Apple USB Support")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setWeight(QFont.Weight.DemiBold)
        title.setFont(title_font)
        title.setStyleSheet("color: #1f2937;")
        layout.addWidget(title)

        subtitle = QLabel(
            "This Windows desktop is missing Apple Mobile Device Support or the Apple USB drivers "
            "needed for iPhone and iPad USB transport."
        )
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #666666; font-size: 13px;")
        layout.addWidget(subtitle)

        admin_banner = QFrame()
        admin_banner.setStyleSheet(
            "QFrame { background: #fff7ed; border: 1px solid #fed7aa; border-radius: 8px; }"
        )
        admin_banner_layout = QHBoxLayout(admin_banner)
        admin_banner_layout.setContentsMargins(12, 10, 12, 10)
        admin_banner_layout.setSpacing(8)
        admin_icon = QLabel("!")
        admin_icon.setStyleSheet("color: #9a3412; font-size: 15px; font-weight: 700;")
        admin_banner_layout.addWidget(admin_icon, alignment=Qt.AlignTop)
        admin_text = QLabel(
            "Installing Apple USB support requires Windows administrator privileges. "
            "When you click Install, Windows will show a User Account Control prompt before "
            "the bundled Apple setup and driver installers run."
        )
        admin_text.setWordWrap(True)
        admin_text.setStyleSheet("color: #9a3412; font-size: 12px; line-height: 1.5;")
        admin_banner_layout.addWidget(admin_text, stretch=1)
        layout.addWidget(admin_banner)

        self.status_label = QLabel()
        self.status_label.setWordWrap(True)
        self.status_label.setStyleSheet("font-weight: 600; color: #1f2937; font-size: 13px;")
        layout.addWidget(self.status_label)

        self.details_label = QLabel()
        self.details_label.setWordWrap(True)
        self.details_label.setStyleSheet("color: #666666; font-size: 12px;")
        self.details_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.details_label)

        self.install_feedback_label = QLabel("")
        self.install_feedback_label.setWordWrap(True)
        self.install_feedback_label.setStyleSheet("color: #1d4ed8; font-size: 12px;")
        layout.addWidget(self.install_feedback_label)

        bottom_row = QHBoxLayout()
        bottom_row.addStretch()

        self.close_button = QPushButton("Close")
        self.close_button.setCursor(Qt.PointingHandCursor)
        self.close_button.setStyleSheet(
            """
            QPushButton {
                background: #e0e0e0; border: 1px solid #c0c0c0; border-radius: 6px;
                padding: 6px 18px; font-size: 13px; font-weight: 500; color: #333333;
            }
            QPushButton:hover { background: #d4d4d4; }
            """
        )
        self.close_button.clicked.connect(self.reject)
        bottom_row.addWidget(self.close_button)

        self.check_again_button = QPushButton("Check Again")
        self.check_again_button.setCursor(Qt.PointingHandCursor)
        self.check_again_button.setStyleSheet(
            """
            QPushButton {
                background: #ffffff; border: 1px solid #c0c0c0; border-radius: 6px;
                padding: 6px 18px; font-size: 13px; font-weight: 500; color: #333333;
            }
            QPushButton:hover { background: #f7f7f7; }
            """
        )
        self.check_again_button.clicked.connect(self._refresh_status_and_maybe_continue)
        bottom_row.addWidget(self.check_again_button)

        self.install_button = QPushButton("Install as Administrator")
        self.install_button.setCursor(Qt.PointingHandCursor)
        self.install_button.setStyleSheet(
            """
            QPushButton {
                background: #007AFF; border: 1px solid #0068dd; border-radius: 6px;
                padding: 6px 18px; font-size: 13px; color: #ffffff; font-weight: 600;
            }
            QPushButton:hover { background: #0070ef; }
            QPushButton:disabled { background: #b0d4ff; border-color: #90c0ef; }
            """
        )
        self.install_button.clicked.connect(self._launch_installer)
        bottom_row.addWidget(self.install_button)
        layout.addLayout(bottom_row)

        self._apply_status(self._status)

    @classmethod
    def ensure_ready(
        cls,
        *,
        support_manager: AppleMobileDeviceSupportManager,
        parent: QWidget | None = None,
    ) -> bool:
        initial_status = support_manager.probe()
        if initial_status.is_ready:
            return True
        dialog = cls(
            support_manager=support_manager,
            initial_status=initial_status,
            parent=parent,
        )
        return dialog.exec() == QDialog.DialogCode.Accepted

    def _refresh_status_and_maybe_continue(self) -> None:
        refreshed_status = self._support_manager.probe()
        self._apply_status(refreshed_status)
        if refreshed_status.is_ready:
            self.accept()

    def _launch_installer(self) -> None:
        try:
            self._support_manager.launch_installer()
        except AppleMobileDeviceSupportInstallError as exc:
            QMessageBox.warning(
                self,
                "Install Apple USB Support",
                str(exc),
            )
            self.install_feedback_label.setText(str(exc))
            return

        self.install_feedback_label.setText(
            "Installer launched. Approve the Windows admin prompt, wait for the Apple setup "
            "and driver installation to finish, then click Check Again."
        )

    def _apply_status(self, status: AppleMobileDeviceSupportStatus) -> None:
        self._status = status
        if status.is_ready:
            self.status_label.setText("Apple Mobile Device Support and the Apple USB drivers are installed.")
            self.status_label.setStyleSheet("font-weight: 600; color: #065f46; font-size: 13px;")
            self.details_label.setText("USB pairing can continue on this desktop.")
            self.install_button.hide()
            return

        self.install_feedback_label.setText("")
        missing_component_lines = "\n".join(
            f"- {component}" for component in status.missing_system_components
        )
        if not missing_component_lines:
            missing_component_lines = "- Apple USB support could not be verified on this desktop."

        details = [
            "Missing or incomplete desktop components:",
            missing_component_lines,
            "",
            "Install uses these bundled setup files:",
            "- AppleMobileDeviceSupport64.msi",
            f"- {APPLE_USB_DRIVER_INF}",
            f"- {APPLE_NETWORK_DRIVER_INF}",
        ]
        if status.missing_bundled_assets:
            details.extend(
                [
                    "",
                    "This build is missing bundled setup files:",
                    "\n".join(f"- {asset_name}" for asset_name in status.missing_bundled_assets),
                ]
            )

        self.status_label.setText("Apple mobile support software is missing on this desktop.")
        self.status_label.setStyleSheet("font-weight: 600; color: #9A6400; font-size: 13px;")
        self.details_label.setText("\n".join(details))
        self.install_button.setVisible(True)
        self.install_button.setEnabled(status.can_install)


class MobilePairingDialog(QDialog):
    _STATUS_COLORS = {
        PairingResultState.ACCEPTED: "#065f46",
        PairingResultState.EXPIRED: "#9A6400",
        PairingResultState.REJECTED: "#991b1b",
    }

    def __init__(
        self,
        pairing_service: MobilePairingService,
        pairing_session: MobilePairingSessionDraft,
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self._pairing_service = pairing_service
        self._pairing_session = pairing_session
        self.setWindowTitle("Pair Mobile Device")
        self.setModal(True)
        self.resize(700, 590)
        self.setStyleSheet("QDialog { background: #f4f4f4; }")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(12)

        title = QLabel("Pair Mobile Device")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setWeight(QFont.Weight.DemiBold)
        title.setFont(title_font)
        title.setStyleSheet("color: #1f2937;")
        layout.addWidget(title)

        subtitle = QLabel("Scan this QR code from Album Transporter on your mobile device. The code is valid for 15 minutes.")
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #666666; font-size: 13px;")
        layout.addWidget(subtitle)

        qr_row = QHBoxLayout()
        qr_row.setSpacing(0)
        qr_row.addStretch()
        self.qr_card = PairingQrCard(
            platform=MobilePlatform.IOS,
            token=pairing_session.token_for(MobilePlatform.IOS),
            on_refresh=self._refresh_platform_token,
        )
        qr_row.addWidget(self.qr_card)
        qr_row.addStretch()
        layout.addLayout(qr_row)

        # security_note = QLabel(
        #     "🔒  Pairing uses a one-time passcode and stays entirely on the local network. "
        #     "No data leaves your devices."
        # )
        # security_note.setWordWrap(True)
        # security_note.setStyleSheet(
        #     "background: #eef5ff; border: 1px solid #c4dcff; border-radius: 8px;"
        #     " padding: 10px 12px; color: #3a5a9c; font-size: 12px;"
        # )
        # layout.addWidget(security_note)

        self.session_status_label = QLabel("Waiting for a mobile device to claim this session…")
        self.session_status_label.setWordWrap(True)
        self.session_status_label.setStyleSheet("font-weight: 600; color: #1f2937; font-size: 13px;")
        layout.addWidget(self.session_status_label)

        self.session_details_label = QLabel(_endpoint_urls_detail(pairing_service.endpoint_urls))
        self.session_details_label.setWordWrap(True)
        self.session_details_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.session_details_label.setStyleSheet("color: #666666; font-size: 12px;")
        layout.addWidget(self.session_details_label)

        bottom_row = QHBoxLayout()
        bottom_row.addStretch()
        self.close_button = QPushButton("Close")
        self.close_button.setCursor(Qt.PointingHandCursor)
        self.close_button.setStyleSheet(
            """
            QPushButton {
                background: #e0e0e0; border: 1px solid #c0c0c0; border-radius: 6px;
                padding: 6px 20px; font-size: 13px; font-weight: 500; color: #333;
            }
            QPushButton:hover { background: #d4d4d4; }
            """
        )
        self.close_button.clicked.connect(self.reject)
        bottom_row.addWidget(self.close_button)
        layout.addLayout(bottom_row)

        self._clock_timer = QTimer(self)
        self._clock_timer.setInterval(1000)
        self._clock_timer.timeout.connect(self._update_clock)
        self._auto_accept_requested = False
        self._clock_timer.start()
        self._update_clock()

    @property
    def pairing_session(self) -> MobilePairingSessionDraft:
        return self._pairing_session

    def _update_clock(self) -> None:
        now = datetime.now(self._pairing_session.created_at.tzinfo)
        self.qr_card.update_clock(now)
        self._update_pairing_result()

    def _refresh_platform_token(self, platform: MobilePlatform) -> MobilePairingToken:
        if self._pairing_service.current_result().state == PairingResultState.ACCEPTED:
            log(
                "info",
                message=(
                    "MobilePairingDialog/_refresh_platform_token: refresh ignored because pairing "
                    f"was already accepted for session {self._pairing_session.session_id}"
                ),
            )
            return self._pairing_session.token_for(platform)
        token = self._pairing_service.refresh_token(platform)
        log(
            "info",
            message=(
                f"MobilePairingDialog/_refresh_platform_token: refreshed {platform.value} token "
                f"for session {self._pairing_session.session_id}"
            ),
        )
        return token

    def _update_pairing_result(self) -> None:
        pairing_result = self._pairing_service.current_result()
        if pairing_result.state == PairingResultState.ACCEPTED:
            self.session_status_label.setText("✓  " + pairing_result.message)
            details = [
                f"Device: {pairing_result.device_name or 'Unknown'}",
                f"Transport: {pairing_result.transport or 'Unknown'}",
            ]
            if pairing_result.folder_path:
                details.append(f"Desktop folder: {pairing_result.folder_path}")
            self.session_details_label.setText("\n".join(details))
            color = self._STATUS_COLORS[PairingResultState.ACCEPTED]
            self.session_status_label.setStyleSheet(f"font-weight: 600; color: {color}; font-size: 13px;")
            self.close_button.setText("Done")
            self.close_button.setStyleSheet(
                """
                QPushButton {
                    background: #007AFF; color: white; border: none; border-radius: 6px;
                    padding: 6px 20px; font-size: 13px; font-weight: 600;
                }
                QPushButton:hover { background: #0070ef; }
                """
            )
            self.qr_card.refresh_overlay_button.setEnabled(False)
            self.qr_card.refresh_overlay_button.hide()
            if not self._auto_accept_requested:
                self._auto_accept_requested = True
                QTimer.singleShot(0, self.accept)
            return

        if pairing_result.state == PairingResultState.EXPIRED:
            self.session_status_label.setText(pairing_result.message)
            self.session_details_label.setText("Refresh the QR code on desktop, then retry the mobile pairing flow.")
            color = self._STATUS_COLORS[PairingResultState.EXPIRED]
            self.session_status_label.setStyleSheet(f"font-weight: 600; color: {color}; font-size: 13px;")
            return

        if pairing_result.state == PairingResultState.REJECTED:
            self.session_status_label.setText(pairing_result.message)
            self.session_details_label.setText("Desktop rejected the request. Generate a fresh QR code and retry pairing.")
            color = self._STATUS_COLORS[PairingResultState.REJECTED]
            self.session_status_label.setStyleSheet(f"font-weight: 600; color: {color}; font-size: 13px;")
            return

        self.session_status_label.setText("")
        self.session_details_label.setText(_endpoint_urls_detail(self._pairing_service.endpoint_urls))
        self.session_status_label.setStyleSheet("font-weight: 600; color: #1f2937; font-size: 13px;")

    def accept(self) -> None:
        self._clock_timer.stop()
        super().accept()

    def reject(self) -> None:
        if self._pairing_service.current_result().state == PairingResultState.ACCEPTED:
            self.accept()
            return
        should_close = QMessageBox.question(
            self,
            "Close Pairing",
            "Close the mobile pairing dialog? This cancels the current desktop pairing intent and you will need to start again.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if should_close != QMessageBox.StandardButton.Yes:
            return
        self._clock_timer.stop()
        super().reject()


def _render_qr_pixmap(payload: str, size: int) -> QPixmap:
    if qrcode is not None:
        try:
            qr_code = qrcode.QRCode(border=2, box_size=8)
            qr_code.add_data(payload)
            qr_code.make(fit=True)
            qr_image = qr_code.make_image(fill_color="black", back_color="white").convert("RGBA")
            qr_image = qr_image.resize((size, size), Image.Resampling.NEAREST)
            return _pil_image_to_pixmap(qr_image)
        except Exception as exc:
            log("warning", message=f"mobile_dialogs/_render_qr_pixmap: failed to render QR code: {exc}")
    return _build_placeholder_pixmap(size=size)


def _pil_image_to_pixmap(image: Image.Image) -> QPixmap:
    rgba_image = image.convert("RGBA")
    data = rgba_image.tobytes("raw", "RGBA")
    qimage = QImage(data, rgba_image.width, rgba_image.height, QImage.Format_RGBA8888).copy()
    return QPixmap.fromImage(qimage)


def _build_placeholder_pixmap(size: int) -> QPixmap:
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.white)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setPen(QColor("#d1d5db"))
    painter.drawRect(4, 4, size - 8, size - 8)
    painter.setPen(QColor("#111827"))
    font = painter.font()
    font.setPointSize(14)
    font.setBold(True)
    painter.setFont(font)
    painter.drawText(pixmap.rect(), Qt.AlignCenter, "QR\nUnavailable")
    painter.end()
    return pixmap
