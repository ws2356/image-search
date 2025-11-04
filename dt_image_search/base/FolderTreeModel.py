import typing
from PySide6.QtGui import QStandardItemModel, QStandardItem
from PySide6.QtCore import Qt, QModelIndex
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
        for p in path_strs:
            path = Path(p).resolve()
            if not path.is_dir():
                continue
            if not self.folder_predicate(path):
                continue

            root_item = QStandardItem(path.name)
            root_item.setData(str(path), Qt.UserRole)
            root_item.setEditable(False)
            root_item.setCheckable(False)
            root_item.setSelectable(True)

            self.appendRow(root_item)

            self._populate_subfolders(root_item, path)

    def deleteFolder(self, index: QModelIndex):
        item = self.itemFromIndex(index)
        if not item or item.parent():
            return
        folder_path = item.data(Qt.UserRole)
        if not folder_path:
            return
        self.removeRow(item.row(), QModelIndex())

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
            item_path = normalized_folder_path(item.data(Qt.UserRole)).replace('\\', '/')
            if item and child_path.startswith(item_path):
                return item
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
