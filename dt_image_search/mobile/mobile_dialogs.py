from __future__ import annotations

from datetime import datetime
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
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from dt_image_search.mobile.mobile_pairing_service import MobilePairingService, PairingResultState
from dt_image_search.mobile.mobile_pairing_session import (
    MobilePairingSessionDraft,
    MobilePairingToken,
    MobilePlatform,
    MobileSourceType,
    platform_display_name,
)
from dt_image_search.telemetry.telemetry_client import log

try:
    import qrcode
except Exception:
    qrcode = None


def _endpoint_target_summary(endpoint_targets: tuple[str, ...]) -> str:
    primary_target = endpoint_targets[0]
    if len(endpoint_targets) == 1:
        return primary_target
    return f"{primary_target} +{len(endpoint_targets) - 1} more"


def _endpoint_urls_detail(endpoint_urls: tuple[str, ...]) -> str:
    if len(endpoint_urls) == 1:
        endpoint_heading = f"Desktop endpoint: {endpoint_urls[0]}"
    else:
        endpoint_heading = "Desktop endpoints:\n" + "\n".join(endpoint_urls)
    return (
        f"{endpoint_heading}\n"
        "Destination folder will be resolved after the mobile device identity is accepted."
    )


class SourceSelectionDialog(QDialog):
    _ICON_LOCAL = "🖥"
    _ICON_MOBILE = "📱"

    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        self._selected_source: MobileSourceType | None = None
        self._source_buttons: list[QPushButton] = []
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
            "Local Device keeps the existing folder-indexing flow.\n"
            "Mobile Device starts a paired backup flow over USB or Wi-Fi LAN."
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
                description="Pair a phone or tablet for local backup transfer.",
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
        card.setStyleSheet(self._card_style(selected=False))

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

        card.mousePressEvent = lambda _event, s=source, c=card, t=title_label: self._select_card(s, c, t)
        card.mouseDoubleClickEvent = lambda _event, s=source: self._confirm_source(s)
        self._source_buttons.append(card)
        card._title_label = title_label  # type: ignore[attr-defined]
        return card

    @staticmethod
    def _card_style(selected: bool) -> str:
        if selected:
            return (
                "QFrame { background: #ffffff; border: 2px solid #007AFF;"
                " border-radius: 12px; }"
            )
        return (
            "QFrame { background: #ffffff; border: 1.5px solid #d8d8d8;"
            " border-radius: 12px; }"
            "QFrame:hover { border-color: #90b8ff; }"
        )

    def _select_card(self, source: MobileSourceType, card: QFrame, title_label: QLabel) -> None:
        self._selected_source = source
        for btn in self._source_buttons:
            btn.setStyleSheet(self._card_style(selected=False))
            lbl = getattr(btn, "_title_label", None)
            if lbl is not None:
                lbl.setStyleSheet(
                    "font-size: 14px; font-weight: 600; color: #1f2937; border: none; background: transparent;"
                )
        card.setStyleSheet(self._card_style(selected=True))
        title_label.setStyleSheet(
            "font-size: 14px; font-weight: 600; color: #007AFF; border: none; background: transparent;"
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


class PairingQrCard(QFrame):
    _TIMER_GREEN = "#22c55e"
    _TIMER_ORANGE = "#f59e0b"
    _TIMER_RED = "#ef4444"
    _WARNING_SECONDS = 120

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

        badge_row = QHBoxLayout()
        badge_icon = "🍎" if platform == MobilePlatform.IOS else "🤖"
        badge_label = QLabel(f" {badge_icon}  {platform_display_name(platform)}")
        badge_label.setStyleSheet(
            "font-size: 13px; font-weight: 600; color: #333; border: none; background: transparent;"
        )
        badge_row.addWidget(badge_label)
        badge_row.addStretch()
        layout.addLayout(badge_row)

        self.qr_label = QLabel()
        self.qr_label.setFixedSize(200, 200)
        self.qr_label.setAlignment(Qt.AlignCenter)
        self.qr_label.setStyleSheet(
            "background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px;"
        )
        layout.addWidget(self.qr_label, alignment=Qt.AlignCenter)

        timer_row = QHBoxLayout()
        timer_row.setSpacing(6)
        self._timer_dot = QLabel("●")
        self._timer_dot.setStyleSheet(f"color: {self._TIMER_GREEN}; font-size: 10px; border: none; background: transparent;")
        timer_row.addWidget(self._timer_dot)
        self.status_label = QLabel()
        self.status_label.setStyleSheet(
            "font-size: 13px; color: #1f2937; font-variant-numeric: tabular-nums; border: none; background: transparent;"
        )
        timer_row.addWidget(self.status_label)
        timer_row.addStretch()
        layout.addLayout(timer_row)

        self.refresh_button = QPushButton("↻  Refresh QR")
        self.refresh_button.setCursor(Qt.PointingHandCursor)
        self.refresh_button.setStyleSheet(
            """
            QPushButton {
                background: #007AFF; color: white; border: none; border-radius: 6px;
                padding: 6px 14px; font-size: 13px; font-weight: 600;
            }
            QPushButton:hover { background: #0070ef; }
            """
        )
        self.refresh_button.clicked.connect(self._refresh_token)
        self.refresh_button.hide()
        layout.addWidget(self.refresh_button, alignment=Qt.AlignLeft)

        instructions = QLabel(self._instructions_text(platform))
        instructions.setWordWrap(True)
        instructions.setStyleSheet("color: #666666; font-size: 12px; border: none; background: transparent;")
        layout.addWidget(instructions)

        self.set_token(token)

    def _instructions_text(self, platform: MobilePlatform) -> str:
        if platform == MobilePlatform.ANDROID:
            return "Scan from Album Transporter on Android.\nUSB preferred · Wi-Fi LAN fallback"
        return "Scan from Album Transporter on iPhone / iPad.\nUSB preferred · Wi-Fi LAN fallback"

    def set_token(self, token: MobilePairingToken) -> None:
        self._token = token
        pixmap = _render_qr_pixmap(token.payload, size=200)
        self.qr_label.setPixmap(pixmap)
        self.update_clock(datetime.now(token.expires_at.tzinfo))

    def update_clock(self, now: datetime) -> None:
        expired = self._token.is_expired(now)
        if expired:
            self.status_label.setText("Expired — refresh to generate a new code")
            self.status_label.setStyleSheet(
                f"color: {self._TIMER_RED}; font-size: 13px; font-weight: 600; border: none; background: transparent;"
            )
            self._timer_dot.setStyleSheet(f"color: {self._TIMER_RED}; font-size: 10px; border: none; background: transparent;")
            self.refresh_button.show()
            self.qr_label.setStyleSheet(
                "background: #f3f4f6; border: 1px solid #e5e7eb; border-radius: 8px; opacity: 0.45;"
            )
        else:
            seconds_remaining = self._token.seconds_remaining(now)
            minutes = seconds_remaining // 60
            seconds = seconds_remaining % 60
            self.status_label.setText(f"Expires in {minutes:02d}:{seconds:02d}")
            self.refresh_button.hide()
            self.qr_label.setStyleSheet(
                "background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px;"
            )
            if seconds_remaining <= self._WARNING_SECONDS:
                color = self._TIMER_ORANGE
                self.status_label.setStyleSheet(
                    f"color: {color}; font-size: 13px; font-weight: 600; border: none; background: transparent;"
                )
            else:
                color = self._TIMER_GREEN
                self.status_label.setStyleSheet(
                    f"color: #1f2937; font-size: 13px; border: none; background: transparent;"
                )
            self._timer_dot.setStyleSheet(f"color: {color}; font-size: 10px; border: none; background: transparent;")

    def _refresh_token(self) -> None:
        refreshed_token = self._on_refresh(self._platform)
        self.set_token(refreshed_token)


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
        self.resize(700, 620)
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

        subtitle = QLabel(
            "Keep this window open while the mobile app scans and claims the session."
        )
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("color: #666666; font-size: 13px;")
        layout.addWidget(subtitle)

        destination_row = QHBoxLayout()
        destination_row.setSpacing(8)
        destination_caption = QLabel("📂 Destination")
        destination_caption.setStyleSheet("font-weight: 600; font-size: 13px; color: #1f2937;")
        destination_row.addWidget(destination_caption)

        self.destination_label = QLabel(pairing_session.destination_parent)
        self.destination_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.destination_label.setWordWrap(True)
        self.destination_label.setStyleSheet("color: #666666; font-size: 13px;")
        destination_row.addWidget(self.destination_label, stretch=1)

        self.change_button = QPushButton("Change")
        self.change_button.setCursor(Qt.PointingHandCursor)
        self.change_button.setStyleSheet(
            """
            QPushButton {
                background: #e0e0e0; border: 1px solid #c0c0c0; border-radius: 5px;
                padding: 4px 12px; font-size: 12px; color: #333;
            }
            QPushButton:hover { background: #d4d4d4; }
            """
        )
        self.change_button.clicked.connect(self._change_destination)
        destination_row.addWidget(self.change_button)
        layout.addLayout(destination_row)

        qr_row = QHBoxLayout()
        qr_row.setSpacing(14)
        self.android_card = PairingQrCard(
            platform=MobilePlatform.ANDROID,
            token=pairing_session.token_for(MobilePlatform.ANDROID),
            on_refresh=self._refresh_platform_token,
        )
        self.ios_card = PairingQrCard(
            platform=MobilePlatform.IOS,
            token=pairing_session.token_for(MobilePlatform.IOS),
            on_refresh=self._refresh_platform_token,
        )
        qr_row.addWidget(self.android_card)
        qr_row.addWidget(self.ios_card)
        layout.addLayout(qr_row)

        security_note = QLabel(
            "🔒  Pairing uses a one-time passcode and stays entirely on the local network. "
            "No data leaves your devices."
        )
        security_note.setWordWrap(True)
        security_note.setStyleSheet(
            "background: #eef5ff; border: 1px solid #c4dcff; border-radius: 8px;"
            " padding: 10px 12px; color: #3a5a9c; font-size: 12px;"
        )
        layout.addWidget(security_note)

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
        self._clock_timer.start()
        self._update_clock()

    @property
    def pairing_session(self) -> MobilePairingSessionDraft:
        return self._pairing_session

    def _update_clock(self) -> None:
        now = datetime.now(self._pairing_session.created_at.tzinfo)
        self.android_card.update_clock(now)
        self.ios_card.update_clock(now)
        self._update_pairing_result()

    def _refresh_platform_token(self, platform: MobilePlatform) -> MobilePairingToken:
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
            self.change_button.setEnabled(False)
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

        self.session_status_label.setText(pairing_result.message)
        self.session_details_label.setText(_endpoint_urls_detail(self._pairing_service.endpoint_urls))
        self.session_status_label.setStyleSheet("font-weight: 600; color: #1f2937; font-size: 13px;")
        self.change_button.setEnabled(True)

    def _change_destination(self) -> None:
        selected_directory = QFileDialog.getExistingDirectory(
            self,
            "Select Mobile Backup Parent Folder",
            self._pairing_session.destination_parent,
        )
        if not selected_directory:
            return
        self._pairing_session.set_destination_parent(selected_directory)
        self.destination_label.setText(self._pairing_session.destination_parent)
        log(
            "info",
            message=(
                "MobilePairingDialog/_change_destination: updated destination parent "
                f"for session {self._pairing_session.session_id}"
            ),
        )

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
