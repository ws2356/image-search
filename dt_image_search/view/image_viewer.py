from PySide6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem,
    QDialog, QVBoxLayout, QSizePolicy
)
from PySide6.QtGui import QPixmap, QWheelEvent, QMouseEvent
from PySide6.QtCore import Qt, QPointF


class ImageViewerWidget(QGraphicsView):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setScene(QGraphicsScene(self))
        self.pixmap_item = QGraphicsPixmapItem()
        self.scene().addItem(self.pixmap_item)
        self.setDragMode(QGraphicsView.ScrollHandDrag)
        self.setTransformationAnchor(QGraphicsView.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.AnchorUnderMouse)

        self._zoom = 0
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
            self.scene().setSceneRect(pixmap.rect())
            self.reset_view()

    def reset_view(self):
        self._zoom = 0
        self.fitInView(self.sceneRect(), Qt.KeepAspectRatio)

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
