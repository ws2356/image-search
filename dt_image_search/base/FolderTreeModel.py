import typing
from PySide6.QtGui import QStandardItemModel, QStandardItem
from PySide6.QtCore import Qt, QModelIndex, QPersistentModelIndex
from pathlib import Path
from .DefaultFolderPredicate import DefaultFolderPredicate
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_util import normalized_folder_path


class FolderTreeModel(QStandardItemModel):
    SECTION_ROLE = Qt.UserRole + 100
    SECTION_KIND_ROLE = Qt.UserRole + 101
    MOBILE_TRANSFER_STATE_ROLE = Qt.UserRole + 1
    MOBILE_TRANSFERRED_COUNT_ROLE = Qt.UserRole + 2
    MOBILE_LAST_BACKUP_AT_ROLE = Qt.UserRole + 3
    _LOCAL_SECTION_KIND = "local"
    _MOBILE_SECTION_KIND = "mobile"

    def __init__(self, parent=None, folder_predicate=DefaultFolderPredicate):
        super().__init__(parent)
        # self.setHorizontalHeaderLabels(["Folders"])
        self.folder_predicate = folder_predicate
        self._mobile_transfer_states_by_path: dict[str, str] = {}
        self._mobile_folder_summaries_by_path: dict[str, dict[str, object]] = {}
        self._local_section_item: QStandardItem | None = None
        self._mobile_section_item: QStandardItem | None = None
        self._ensure_section_items()

    def add_root_folder(self, path_strs: typing.List[str]):
        log("debug", message=f"FolderTreeModel/add_root_folder: adding {len(path_strs)} folders")
        self._ensure_section_items()
        for p in path_strs:
            path = Path(p).resolve()
            if not path.is_dir():
                continue
            if not self.folder_predicate(path):
                continue
            existing_item = self.find_folder_item(str(path))
            if existing_item is not None and self.is_top_level_folder_item(existing_item):
                continue
            if existing_item is not None and existing_item.parent() is not None:
                existing_item.parent().removeRow(existing_item.row())

            root_item = QStandardItem(path.name)
            root_item.setData(str(path), Qt.UserRole)
            root_item.setEditable(False)
            root_item.setCheckable(False)
            root_item.setSelectable(True)
            self._apply_mobile_transfer_state_to_item(root_item)

            target_section = self._section_for_folder_path(str(path))
            target_section.appendRow(root_item)

            self._populate_subfolders(root_item, path)

    def deleteFolder(self, index: QPersistentModelIndex):
        # 1. 基础合法性校验 (使用 index 检查，不产生 item 对象)
        if not index.isValid():
            return

        parent_index = index.parent()
        if not parent_index.isValid():
            log("warning", message="FolderTreeModel/deleteFolder: section item deletion requested, skipping")
            return
        parent_item = self.itemFromIndex(parent_index)
        if parent_item is None or not self._is_section_item(parent_item):
            log("warning", message="FolderTreeModel/deleteFolder: item is not a top-level folder, skipping")
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
        parent_item.removeRow(row_index)

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
        matched_item: QStandardItem | None = None
        matched_path_length = -1
        for section_item in self._section_items():
            for row in range(section_item.rowCount()):
                item = section_item.child(row)
                if item is None:
                    continue
                data = item.data(Qt.UserRole)
                if not data:
                    continue
                item_path = normalized_folder_path(data).replace('\\', '/')
                if child_path.startswith(item_path) and len(item_path) > matched_path_length:
                    matched_item = item
                    matched_path_length = len(item_path)
        return matched_item

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
                    if self._is_mobile_folder_path(str(child.resolve())):
                        continue
                    child_item = QStandardItem(child.name)
                    child_item.setData(str(child.resolve()), Qt.UserRole)
                    child_item.setEditable(False)
                    self._apply_mobile_transfer_state_to_item(child_item)
                    parent_item.appendRow(child_item)
        except Exception as e:
            log("error", message=f"Could not read subfolders of {parent_path}: {e}")

    def set_mobile_transfer_states(self, states_by_path: dict[str, str]) -> None:
        self._mobile_transfer_states_by_path = {
            normalized_folder_path(path).replace('\\', '/'): state
            for path, state in states_by_path.items()
        }
        self._sync_top_level_folder_sections()
        self._apply_mobile_transfer_states_to_model()

    def set_mobile_folder_summaries(self, summaries_by_path: dict[str, dict[str, object]]) -> None:
        self._mobile_folder_summaries_by_path = {
            normalized_folder_path(path).replace('\\', '/'): summary
            for path, summary in summaries_by_path.items()
        }
        self._apply_mobile_transfer_states_to_model()

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

    def _apply_mobile_transfer_states_to_model(self) -> None:
        for row in range(self.rowCount()):
            root_item = self.item(row, 0)
            self._apply_mobile_transfer_state_recursive(root_item)

    def _apply_mobile_transfer_state_recursive(self, item: QStandardItem | None) -> None:
        if item is None:
            return
        self._apply_mobile_transfer_state_to_item(item)
        for row in range(item.rowCount()):
            self._apply_mobile_transfer_state_recursive(item.child(row))

    def _apply_mobile_transfer_state_to_item(self, item: QStandardItem) -> None:
        item_path = item.data(Qt.UserRole)
        if not item_path:
            return
        normalized_path = normalized_folder_path(item_path).replace('\\', '/')
        transfer_state = self._mobile_transfer_states_by_path.get(normalized_path)
        summary = self._mobile_folder_summaries_by_path.get(normalized_path, {})
        transferred_count = int(summary.get("transferred_count", 0))
        last_backup_at = summary.get("last_backup_at")

        item.setData(transfer_state, self.MOBILE_TRANSFER_STATE_ROLE)
        item.setData(transferred_count, self.MOBILE_TRANSFERRED_COUNT_ROLE)
        item.setData(last_backup_at, self.MOBILE_LAST_BACKUP_AT_ROLE)

        base_name = Path(item_path).name or item_path
        item.setText(base_name)

    def is_top_level_folder_item(self, item: QStandardItem | None) -> bool:
        if item is None:
            return False
        parent_item = item.parent()
        return parent_item is not None and self._is_section_item(parent_item)

    def is_mobile_folder_path(self, folder_path: str) -> bool:
        return self._is_mobile_folder_path(folder_path)

    def _ensure_section_items(self) -> None:
        if self._local_section_item is not None and self._mobile_section_item is not None:
            return

        root_item = self.invisibleRootItem()
        local_section_item = QStandardItem("Local")
        local_section_item.setEditable(False)
        local_section_item.setSelectable(False)
        local_section_item.setData(True, self.SECTION_ROLE)
        local_section_item.setData(self._LOCAL_SECTION_KIND, self.SECTION_KIND_ROLE)

        mobile_section_item = QStandardItem("Mobile")
        mobile_section_item.setEditable(False)
        mobile_section_item.setSelectable(False)
        mobile_section_item.setData(True, self.SECTION_ROLE)
        mobile_section_item.setData(self._MOBILE_SECTION_KIND, self.SECTION_KIND_ROLE)

        root_item.appendRow(local_section_item)
        root_item.appendRow(mobile_section_item)
        self._local_section_item = local_section_item
        self._mobile_section_item = mobile_section_item

    def _section_items(self) -> tuple[QStandardItem, QStandardItem]:
        self._ensure_section_items()
        assert self._local_section_item is not None
        assert self._mobile_section_item is not None
        return self._local_section_item, self._mobile_section_item

    def _section_for_folder_path(self, folder_path: str) -> QStandardItem:
        local_section_item, mobile_section_item = self._section_items()
        if self._is_mobile_folder_path(folder_path):
            return mobile_section_item
        return local_section_item

    def _is_mobile_folder_path(self, folder_path: str) -> bool:
        normalized_path = normalized_folder_path(folder_path).replace('\\', '/')
        return normalized_path in self._mobile_transfer_states_by_path

    def _is_section_item(self, item: QStandardItem) -> bool:
        return bool(item.data(self.SECTION_ROLE))

    def _sync_top_level_folder_sections(self) -> None:
        local_section_item, mobile_section_item = self._section_items()
        top_level_items: list[QStandardItem] = []
        for section_item in (local_section_item, mobile_section_item):
            for row in range(section_item.rowCount()):
                child_item = section_item.child(row)
                if child_item is not None and child_item.data(Qt.UserRole):
                    top_level_items.append(child_item)

        for folder_item in top_level_items:
            item_path = folder_item.data(Qt.UserRole)
            if not item_path:
                continue
            target_section = self._section_for_folder_path(item_path)
            current_parent = folder_item.parent()
            if current_parent is target_section or current_parent is None:
                continue
            taken_row = current_parent.takeRow(folder_item.row())
            if taken_row:
                target_section.appendRow(taken_row)
