"""
Reusable progress indicators and spinners for the instant-share PC mini-window.
"""

from PySide6.QtCore import Qt, QTimer, Property
from PySide6.QtGui import QColor, QPainter, QPen, QRadialGradient
from PySide6.QtWidgets import QProgressBar, QWidget

from dt_image_search.instant_sharing.mobile_to_pc.design_system import (
    Colors,
    Spacing,
)


class SpinnerWidget(QWidget):
    """Custom spinner widget with blue arc animation."""

    def __init__(self, size: int = 56, parent=None) -> None:
        super().__init__(parent)
        self._size = size
        self._angle = 0
        self.setFixedSize(size, size)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._rotate)
        self._timer.start(50)

    def _rotate(self) -> None:
        self._angle = (self._angle + 10) % 360
        self.update()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Draw track circle
        track_pen = QPen(QColor(Colors.PROGRESS_TRACK), 4, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap)
        painter.setPen(track_pen)
        margin = 4
        rect = self.rect().adjusted(margin, margin, -margin, -margin)
        painter.drawArc(rect, 0, 360 * 16)

        # Draw spinning arc
        spinner_pen = QPen(QColor(Colors.PRIMARY_BLUE), 4, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap)
        painter.setPen(spinner_pen)
        painter.drawArc(rect, self._angle * 16, 90 * 16)

    def stop(self) -> None:
        self._timer.stop()

    def start(self) -> None:
        self._timer.start(50)


class StatusProgressBar(QProgressBar):
    """Thin progress bar with design system colors."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setRange(0, 100)
        self.setValue(0)
        self.setTextVisible(False)
        self.setFixedHeight(4)
        self.setStyleSheet(f"""
            QProgressBar {{
                background-color: {Colors.PROGRESS_TRACK};
                border: none;
                border-radius: 2px;
            }}
            QProgressBar::chunk {{
                background-color: {Colors.PRIMARY_BLUE};
                border-radius: 2px;
            }}
        """)
