import typing
from PySide6.QtGui import QStandardItemModel, QStandardItem
from PySide6.QtCore import Qt, QModelIndex
from pathlib import Path
from .DefaultFolderPredicate import DefaultFolderPredicate
from dt_image_search.telemetry.telemetry_client import log


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
