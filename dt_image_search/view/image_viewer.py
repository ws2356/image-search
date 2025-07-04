from PySide6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem,
    QDialog, QVBoxLayout, QSizePolicy
)
from PySide6.QtGui import QPixmap, QWheelEvent, QMouseEvent
from PySide6.QtCore import Qt, QPointF
import math

class ImageViewerWidget(QGraphicsView):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setScene(QGraphicsScene(self))
        self.pixmap_item = QGraphicsPixmapItem()
        self.scene().addItem(self.pixmap_item)

        self.setDragMode(QGraphicsView.NoDrag)  # We'll handle dragging manually
        self.setTransformationAnchor(QGraphicsView.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.AnchorViewCenter)

        self._zoom = 0
        self._angle = 0
        self._dragging = False
        self._last_pos = None
        self._empty = True

        self.setBackgroundBrush(Qt.black)

    def set_image(self, image_path):
        pixmap = QPixmap(image_path)
        if pixmap.isNull():
            self.pixmap_item.setPixmap(QPixmap())
            self._empty = True
        else:
            self._empty = False
            self.pixmap_item.setPixmap(pixmap)
            self.pixmap_item.setTransformOriginPoint(pixmap.rect().center())
            self.scene().setSceneRect(pixmap.rect())
            self.reset_view()

    def reset_view(self):
        self._zoom = 0
        self._angle = 0
        self.pixmap_item.setRotation(0)
        self.fitInView(self.sceneRect(), Qt.KeepAspectRatio)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton and not self._empty:
            self._dragging = True
            self._last_pos = event.pos()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self._dragging and self._last_pos:
            # Get scene position of image center and mouse points
            center = self.pixmap_item.boundingRect().center()
            center_in_scene = self.pixmap_item.mapToScene(center)
            prev_scene_pos = self.mapToScene(self._last_pos)
            curr_scene_pos = self.mapToScene(event.pos())

            # Compute vectors from center to previous and current mouse positions
            v1 = prev_scene_pos - center_in_scene
            v2 = curr_scene_pos - center_in_scene

            # Compute angle between v1 and v2
            angle1 = math.atan2(v1.y(), v1.x())
            angle2 = math.atan2(v2.y(), v2.x())
            raw_angle_delta = math.degrees(angle2 - angle1)

            # Normalize to [-180, 180] range
            angle_delta = (raw_angle_delta + 180) % 360 - 180

            # Sensitivity multiplier
            sensitivity = 1.0  # You can tweak this
            self._angle += angle_delta * sensitivity
            self.pixmap_item.setRotation(self._angle)

            self._last_pos = event.pos()

        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._dragging = False
            self._last_pos = None
        super().mouseReleaseEvent(event)

    def wheelEvent(self, event: QWheelEvent):
        if self._empty:
            return
        zoom_in = event.angleDelta().y() > 0
        factor = 1.25 if zoom_in else 0.8
        self._zoom += 1 if zoom_in else -1
        if self._zoom < -10:
            self._zoom = -10
        elif self._zoom > 20:
            self._zoom = 20
        else:
            self.scale(factor, factor)

    def mouseDoubleClickEvent(self, event: QMouseEvent):
        if not self._empty:
            self.reset_view()

class ImageViewerDialog(QDialog):
    def __init__(self, image_path, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Image Viewer")
        self.viewer = ImageViewerWidget()
        self.viewer.set_image(image_path)

        layout = QVBoxLayout(self)
        layout.addWidget(self.viewer)

        self.resize(1000, 700)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
