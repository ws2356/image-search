import typing
from PySide6.QtGui import QStandardItemModel, QStandardItem
from PySide6.QtCore import Qt, QModelIndex, QPersistentModelIndex
from pathlib import Path
from .DefaultFolderPredicate import DefaultFolderPredicate
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_util import normalized_folder_path


class FolderTreeModel(QStandardItemModel):
    def __init__(self, parent=None, folder_predicate=DefaultFolderPredicate):
        super().__init__(parent)
        self.setHorizontalHeaderLabels(["Folders"])
        self.folder_predicate = folder_predicate

    def add_root_folder(self, path_strs: typing.List[str]):
        log("debug", message=f"FolderTreeModel/add_root_folder: adding {len(path_strs)} folders")
        for p in path_strs:
            path = Path(p).resolve()
            if not path.is_dir():
                continue
            if not self.folder_predicate(path):
                continue
            if self.find_folder_item(str(path)) is not None:
                continue

            root_item = QStandardItem(path.name)
            root_item.setData(str(path), Qt.UserRole)
            root_item.setEditable(False)
            root_item.setCheckable(False)
            root_item.setSelectable(True)

            self.appendRow(root_item)

            self._populate_subfolders(root_item, path)

    def deleteFolder(self, index: QPersistentModelIndex):
        # 1. 基础合法性校验 (使用 index 检查，不产生 item 对象)
        if not index.isValid():
            return
            
        # 检查是否有父节点（顶层节点的 parent 是 invalid 的）
        if index.parent().isValid():
            log("warning", message="FolderTreeModel/deleteFolder: item has parent, skipping")
            return

        # 2. 安全读取数据用于日志
        # 直接用 index.data，不调用 itemFromIndex(index)
        folder_path = index.data(Qt.UserRole)
        row_index = index.row()
        
        log("debug", message=f"FolderTreeModel/deleteFolder: deleting folder {folder_path} at row {row_index}")

        if not folder_path:
            return

        # 3. 执行删除
        # 注意：此时我们没有持有任何 item 对象的引用，只有 index 
        self.removeRow(row_index, QModelIndex())

        # 4. 强制处理事件循环，清理 macOS 原生引用
        from PySide6.QtCore import QCoreApplication
        QCoreApplication.processEvents()

    def expand_subfolders(self, index: QModelIndex):
        item = self.itemFromIndex(index)
        if not item:
            return
        # Iterate children of item and populate subfolders for each if not already populated
        for row in range(item.rowCount()):
            child_item = item.child(row)
            if child_item and child_item.rowCount() == 0:
                self._populate_subfolders(child_item, Path(child_item.data(Qt.UserRole)))

    def repopulate_folder_item(self, child_path: str):
        log("debug", message=f"FolderTreeModel/repopulate_folder_item: repopulating {child_path}")
        item = self.get_containing_root_folder(child_path)
        if not item:
            return
        # Clean item children and repopulate
        item.removeRows(0, item.rowCount())
        self._populate_subfolders(item, Path(item.data(Qt.UserRole)))
        self._refresh_item(item=item)
        
        # Alternative: If you want to force a complete refresh of this subtree,
        # you can emit layoutChanged signal
        # self.layoutChanged.emit()

    def get_containing_root_folder(self, child_path: str) -> QStandardItem | None:
        child_path = normalized_folder_path(child_path).replace('\\', '/')
        root_count = self.rowCount()
        for row in range(root_count):
            item = self.item(row, 0)
            if not item:
                continue
            data = item.data(Qt.UserRole)
            if not data:
                continue
            item_path = normalized_folder_path(data).replace('\\', '/')
            if item and child_path.startswith(item_path):
                return item
        return None

    def find_folder_item(self, folder_path: str) -> QStandardItem | None:
        target_path = normalized_folder_path(folder_path).replace('\\', '/')
        for row in range(self.rowCount()):
            item = self.item(row, 0)
            matched_item = self._find_folder_item(item, target_path)
            if matched_item is not None:
                return matched_item
        return None

    def _populate_subfolders(self, parent_item: QStandardItem, parent_path: Path):
        try:
            for child in sorted(parent_path.iterdir()):
                if child.is_dir() and self.folder_predicate(child):
                    child_item = QStandardItem(child.name)
                    child_item.setData(str(child.resolve()), Qt.UserRole)
                    child_item.setEditable(False)
                    parent_item.appendRow(child_item)
        except Exception as e:
            log("error", message=f"Could not read subfolders of {parent_path}: {e}")

    def _refresh_item(self, item: QStandardItem):
        """Force refresh of a specific item and its children."""
        if not item:
            return
        index = self.indexFromItem(item)
        if index.isValid():
            self.dataChanged.emit(index, index, [Qt.DisplayRole, Qt.DecorationRole])

    def _find_folder_item(self, item: QStandardItem | None, target_path: str) -> QStandardItem | None:
        if item is None:
            return None
        item_path = item.data(Qt.UserRole)
        if item_path and normalized_folder_path(item_path).replace('\\', '/') == target_path:
            return item
        for row in range(item.rowCount()):
            matched_item = self._find_folder_item(item.child(row), target_path)
            if matched_item is not None:
                return matched_item
        return None
