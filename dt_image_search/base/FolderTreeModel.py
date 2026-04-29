from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import typing

from PySide6.QtCore import QAbstractItemModel, QDir, QIdentityProxyModel, QModelIndex, QPersistentModelIndex, Qt
from PySide6.QtGui import QStandardItem, QStandardItemModel
from PySide6.QtWidgets import QFileSystemModel

from .DefaultFolderPredicate import DefaultFolderPredicate
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_util import normalized_folder_path


@dataclass(frozen=True)
class _FolderTreeNode:
    kind: str
    key: str


class FolderTreeItemRef:
    def __init__(self, model: "FolderTreeModel", node: _FolderTreeNode):
        self._model = model
        self._node = node

    def data(self, role: int):
        return self._model._data_for_node(self._node, role)

    def text(self) -> str:
        return str(self.data(Qt.DisplayRole) or "")

    def parent(self) -> "FolderTreeItemRef | None":
        parent_node = self._model._parent_node_for(self._node)
        if parent_node is None:
            return None
        return FolderTreeItemRef(self._model, parent_node)

    def row(self) -> int:
        return self._model.indexFromItem(self).row()


class FolderTreeFsProxyModel(QIdentityProxyModel):
    def _source_model(self) -> QFileSystemModel:
        source_model = self.sourceModel()
        assert isinstance(source_model, QFileSystemModel)
        return source_model

    def index_for_path(self, path: str) -> QModelIndex:
        normalized_path = normalized_folder_path(path).replace("\\", "/")
        return self.mapFromSource(self._source_model().index(normalized_path))

    def file_path(self, index: QModelIndex) -> str:
        if not index.isValid():
            return ""
        return normalized_folder_path(self._source_model().filePath(self.mapToSource(index))).replace("\\", "/")

    def is_dir(self, index: QModelIndex) -> bool:
        if not index.isValid():
            return False
        return self._source_model().isDir(self.mapToSource(index))

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole):
        if role == Qt.UserRole and index.isValid():
            return self.file_path(index)
        return super().data(index, role)


class FolderTreeModel(QAbstractItemModel):
    SECTION_ROLE = Qt.UserRole + 100
    SECTION_KIND_ROLE = Qt.UserRole + 101
    MOBILE_TRANSFER_STATE_ROLE = Qt.UserRole + 1
    MOBILE_TRANSFERRED_COUNT_ROLE = Qt.UserRole + 2
    MOBILE_LAST_BACKUP_AT_ROLE = Qt.UserRole + 3
    MOBILE_PLATFORM_ROLE = Qt.UserRole + 4
    MOBILE_LAST_TRANSFER_STATUS_ROLE = Qt.UserRole + 5
    MOBILE_LAST_TRANSFER_AT_ROLE = Qt.UserRole + 6
    _LOCAL_SECTION_KIND = "local"
    _MOBILE_SECTION_KIND = "mobile"
    _SECTION_NODE_KIND = "section"
    _ROOT_NODE_KIND = "root"
    _FS_NODE_KIND = "fs"

    def __init__(
        self,
        parent=None,
        folder_predicate=DefaultFolderPredicate,
        *,
        sectioned_view: bool = True,
    ):
        super().__init__(parent)
        self.folder_predicate = folder_predicate
        self._sectioned_view = sectioned_view
        self._mobile_folder_paths: set[str] = set()
        self._mobile_transfer_states_by_path: dict[str, str] = {}
        self._mobile_folder_summaries_by_path: dict[str, dict[str, object]] = {}
        self._node_cache: dict[tuple[str, str], _FolderTreeNode] = {}
        self._root_registry_model = QStandardItemModel(self)
        self._local_section_item: QStandardItem | None = None
        self._mobile_section_item: QStandardItem | None = None
        self._fs_source_model = QFileSystemModel(self)
        self._fs_source_model.setFilter(QDir.AllDirs | QDir.NoDotAndDotDot)
        self._fs_source_model.setRootPath(self._filesystem_root_path())
        self._fs_proxy_model = FolderTreeFsProxyModel(self)
        self._fs_proxy_model.setSourceModel(self._fs_source_model)
        if self._sectioned_view:
            self._ensure_section_items()

    def add_root_folder(self, path_strs: typing.List[str]):
        log("debug", message=f"FolderTreeModel/add_root_folder: adding {len(path_strs)} folders")
        if self._sectioned_view:
            self._ensure_section_items()
        for path_str in path_strs:
            path = Path(path_str).resolve()
            resolved_path = normalized_folder_path(path.as_posix()).replace("\\", "/")
            if not path.is_dir():
                continue
            if not self.folder_predicate(path):
                continue
            if self._has_root_folder(resolved_path):
                continue

            target_section_kind = self._section_kind_for_folder_path(resolved_path)
            parent_index = (
                self._section_index_for_kind(target_section_kind)
                if self._sectioned_view
                else QModelIndex()
            )
            insert_row = self._root_insert_row(target_section_kind, resolved_path)
            target_parent_item = self._registry_parent_for_section(target_section_kind)
            root_item = QStandardItem(path.name or resolved_path)
            root_item.setData(resolved_path, Qt.UserRole)
            root_item.setEditable(False)
            root_item.setCheckable(False)
            root_item.setSelectable(True)

            self.beginInsertRows(parent_index, insert_row, insert_row)
            target_parent_item.insertRow(insert_row, [root_item])
            self.endInsertRows()

    def deleteFolder(self, index: QPersistentModelIndex):
        if not index.isValid():
            return
        item = self.itemFromIndex(index)
        if item is None or not self.is_top_level_folder_item(item):
            log("warning", message="FolderTreeModel/deleteFolder: item is not a top-level folder, skipping")
            return

        parent_index = index.parent()
        parent_item = item.parent()
        if parent_item is None:
            return
        row_index = index.row()
        folder_path = item.data(Qt.UserRole)
        log("debug", message=f"FolderTreeModel/deleteFolder: deleting folder {folder_path} at row {row_index}")

        registry_parent_item = self._registry_item_for_ref(parent_item)
        if registry_parent_item is None:
            return
        self.beginRemoveRows(parent_index, row_index, row_index)
        registry_parent_item.removeRow(row_index)
        self.endRemoveRows()

    def expand_subfolders(self, index: QModelIndex):
        if self.canFetchMore(index):
            self.fetchMore(index)

    def repopulate_folder_item(self, child_path: str):
        if self.get_containing_root_folder(child_path) is None:
            return
        log("debug", message=f"FolderTreeModel/repopulate_folder_item: refreshing {child_path}")
        self.beginResetModel()
        self.endResetModel()

    def get_containing_root_folder(self, child_path: str) -> FolderTreeItemRef | None:
        normalized_path = normalized_folder_path(child_path).replace("\\", "/")
        matched_root_path: str | None = None
        matched_path_length = -1
        for root_path in self._all_root_paths():
            if normalized_path.startswith(root_path) and len(root_path) > matched_path_length:
                matched_root_path = root_path
                matched_path_length = len(root_path)
        if matched_root_path is None:
            return None
        return FolderTreeItemRef(self, self._node(self._ROOT_NODE_KIND, matched_root_path))

    def find_folder_item(self, folder_path: str) -> FolderTreeItemRef | None:
        normalized_path = normalized_folder_path(folder_path).replace("\\", "/")
        if self._has_root_folder(normalized_path):
            return FolderTreeItemRef(self, self._node(self._ROOT_NODE_KIND, normalized_path))

        containing_root = self.get_containing_root_folder(normalized_path)
        if containing_root is None:
            return None

        folder_proxy_index = self._fs_proxy_model.index_for_path(normalized_path)
        if not folder_proxy_index.isValid() or not self._fs_proxy_model.is_dir(folder_proxy_index):
            return None
        if self._is_mobile_folder_path(normalized_path):
            return None
        return FolderTreeItemRef(self, self._node(self._FS_NODE_KIND, normalized_path))

    def set_mobile_transfer_states(self, states_by_path: dict[str, str]) -> None:
        self._mobile_transfer_states_by_path = {
            normalized_folder_path(path).replace("\\", "/"): state
            for path, state in states_by_path.items()
        }
        self._emit_root_data_changed(
            [self.MOBILE_TRANSFER_STATE_ROLE, self.MOBILE_TRANSFERRED_COUNT_ROLE]
        )

    def set_mobile_folder_paths(self, folder_paths: typing.Iterable[str]) -> None:
        self._mobile_folder_paths = {
            normalized_folder_path(path).replace("\\", "/")
            for path in folder_paths
        }
        self._sync_root_sections()
        self.beginResetModel()
        self.endResetModel()

    def set_mobile_folder_summaries(self, summaries_by_path: dict[str, dict[str, object]]) -> None:
        self._mobile_folder_summaries_by_path = {
            normalized_folder_path(path).replace("\\", "/"): summary
            for path, summary in summaries_by_path.items()
        }
        self._emit_root_data_changed(
            [
                self.MOBILE_TRANSFERRED_COUNT_ROLE,
                self.MOBILE_LAST_BACKUP_AT_ROLE,
                self.MOBILE_PLATFORM_ROLE,
                self.MOBILE_LAST_TRANSFER_STATUS_ROLE,
                self.MOBILE_LAST_TRANSFER_AT_ROLE,
            ]
        )

    def itemFromIndex(self, index: QModelIndex) -> FolderTreeItemRef | None:
        node = self._node_from_index(index)
        if node is None:
            return None
        return FolderTreeItemRef(self, node)

    def item(self, row: int, column: int = 0) -> FolderTreeItemRef | None:
        return self.itemFromIndex(self.index(row, column))

    def indexFromItem(self, item: FolderTreeItemRef | None) -> QModelIndex:
        if item is None or item._model is not self:
            return QModelIndex()
        return self._index_for_node(item._node)

    def is_top_level_folder_item(self, item: FolderTreeItemRef | None) -> bool:
        return item is not None and item._node.kind == self._ROOT_NODE_KIND

    def is_mobile_folder_path(self, folder_path: str) -> bool:
        return self._is_mobile_folder_path(folder_path)

    def index(self, row: int, column: int, parent: QModelIndex = QModelIndex()) -> QModelIndex:
        if column != 0 or row < 0:
            return QModelIndex()

        parent_node = self._node_from_index(parent)
        if parent_node is None:
            if self._sectioned_view:
                section_nodes = self._section_nodes()
                if row >= len(section_nodes):
                    return QModelIndex()
                return self.createIndex(row, column, section_nodes[row])
            root_paths = self._all_root_paths()
            if row >= len(root_paths):
                return QModelIndex()
            return self.createIndex(row, column, self._node(self._ROOT_NODE_KIND, root_paths[row]))

        if parent_node.kind == self._SECTION_NODE_KIND:
            root_paths = self._root_paths_for_section(parent_node.key)
            if row >= len(root_paths):
                return QModelIndex()
            return self.createIndex(row, column, self._node(self._ROOT_NODE_KIND, root_paths[row]))

        if parent_node.kind in (self._ROOT_NODE_KIND, self._FS_NODE_KIND):
            child_paths = self._child_directory_paths(parent_node.key)
            if row >= len(child_paths):
                return QModelIndex()
            return self.createIndex(row, column, self._node(self._FS_NODE_KIND, child_paths[row]))

        return QModelIndex()

    def parent(self, index: QModelIndex) -> QModelIndex:
        node = self._node_from_index(index)
        if node is None:
            return QModelIndex()
        parent_node = self._parent_node_for(node)
        if parent_node is None:
            return QModelIndex()
        return self._index_for_node(parent_node)

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.column() > 0:
            return 0

        node = self._node_from_index(parent)
        if node is None:
            return len(self._section_nodes()) if self._sectioned_view else len(self._all_root_paths())
        if node.kind == self._SECTION_NODE_KIND:
            return len(self._root_paths_for_section(node.key))
        if node.kind in (self._ROOT_NODE_KIND, self._FS_NODE_KIND):
            return len(self._child_directory_paths(node.key))
        return 0

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 1

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole):
        node = self._node_from_index(index)
        if node is None:
            return None
        return self._data_for_node(node, role)

    def flags(self, index: QModelIndex) -> Qt.ItemFlags:
        if not index.isValid():
            return Qt.NoItemFlags
        node = self._node_from_index(index)
        if node is None:
            return Qt.NoItemFlags
        if node.kind == self._SECTION_NODE_KIND:
            return Qt.ItemIsEnabled
        return Qt.ItemIsEnabled | Qt.ItemIsSelectable

    def hasChildren(self, parent: QModelIndex = QModelIndex()) -> bool:
        return self.rowCount(parent) > 0

    def canFetchMore(self, parent: QModelIndex) -> bool:
        node = self._node_from_index(parent)
        if node is None or node.kind not in (self._ROOT_NODE_KIND, self._FS_NODE_KIND):
            return False
        proxy_index = self._fs_proxy_model.index_for_path(node.key)
        return proxy_index.isValid() and self._fs_proxy_model.canFetchMore(proxy_index)

    def fetchMore(self, parent: QModelIndex) -> None:
        node = self._node_from_index(parent)
        if node is None or node.kind not in (self._ROOT_NODE_KIND, self._FS_NODE_KIND):
            return
        proxy_index = self._fs_proxy_model.index_for_path(node.key)
        if proxy_index.isValid() and self._fs_proxy_model.canFetchMore(proxy_index):
            self._fs_proxy_model.fetchMore(proxy_index)

    def _data_for_node(self, node: _FolderTreeNode, role: int):
        if node.kind == self._SECTION_NODE_KIND:
            section_item = self._section_item_for_kind(node.key)
            if section_item is None:
                return None
            if role == Qt.DisplayRole:
                return section_item.text()
            if role == self.SECTION_ROLE:
                return True
            if role == self.SECTION_KIND_ROLE:
                return node.key
            return None

        item_path = normalized_folder_path(node.key).replace("\\", "/")
        summary = self._mobile_folder_summaries_by_path.get(item_path, {})
        transfer_state = self._mobile_transfer_states_by_path.get(item_path)

        if role == Qt.DisplayRole:
            return Path(item_path).name or item_path
        if role == Qt.UserRole:
            return self._public_path(item_path)
        if role == self.MOBILE_TRANSFER_STATE_ROLE:
            return transfer_state
        if role == self.MOBILE_TRANSFERRED_COUNT_ROLE:
            return int(summary.get("transferred_count", 0))
        if role == self.MOBILE_LAST_BACKUP_AT_ROLE:
            return summary.get("last_backup_at")
        if role == self.MOBILE_PLATFORM_ROLE:
            return summary.get("platform")
        if role == self.MOBILE_LAST_TRANSFER_STATUS_ROLE:
            return summary.get("last_transfer_status")
        if role == self.MOBILE_LAST_TRANSFER_AT_ROLE:
            return summary.get("last_transfer_at")
        return None

    def _node(self, kind: str, key: str) -> _FolderTreeNode:
        cache_key = (kind, key)
        cached_node = self._node_cache.get(cache_key)
        if cached_node is None:
            cached_node = _FolderTreeNode(kind, key)
            self._node_cache[cache_key] = cached_node
        return cached_node

    def _node_from_index(self, index: QModelIndex) -> _FolderTreeNode | None:
        if not index.isValid():
            return None
        internal_pointer = index.internalPointer()
        if isinstance(internal_pointer, _FolderTreeNode):
            return internal_pointer
        return None

    def _parent_node_for(self, node: _FolderTreeNode) -> _FolderTreeNode | None:
        if node.kind == self._SECTION_NODE_KIND:
            return None
        if node.kind == self._ROOT_NODE_KIND:
            if not self._sectioned_view:
                return None
            return self._node(
                self._SECTION_NODE_KIND,
                self._section_kind_for_folder_path(node.key),
            )
        if node.kind != self._FS_NODE_KIND:
            return None

        containing_root = self.get_containing_root_folder(node.key)
        if containing_root is None:
            return None
        root_path = containing_root._node.key
        parent_path = normalized_folder_path(Path(node.key).parent.as_posix()).replace("\\", "/")
        if parent_path == root_path:
            return self._node(self._ROOT_NODE_KIND, root_path)
        return self._node(self._FS_NODE_KIND, parent_path)

    def _index_for_node(self, node: _FolderTreeNode) -> QModelIndex:
        if node.kind == self._SECTION_NODE_KIND:
            for row, section_node in enumerate(self._section_nodes()):
                if section_node.key == node.key:
                    return self.createIndex(row, 0, section_node)
            return QModelIndex()

        if node.kind == self._ROOT_NODE_KIND:
            parent_node = self._parent_node_for(node)
            if parent_node is None:
                root_paths = self._all_root_paths()
                try:
                    row = root_paths.index(node.key)
                except ValueError:
                    return QModelIndex()
                return self.createIndex(row, 0, node)
            parent_index = self._index_for_node(parent_node)
            root_paths = self._root_paths_for_section(parent_node.key)
            try:
                row = root_paths.index(node.key)
            except ValueError:
                return QModelIndex()
            return self.createIndex(row, 0, node) if parent_index.isValid() else QModelIndex()

        if node.kind == self._FS_NODE_KIND:
            parent_node = self._parent_node_for(node)
            if parent_node is None:
                return QModelIndex()
            child_paths = self._child_directory_paths(parent_node.key)
            try:
                row = child_paths.index(node.key)
            except ValueError:
                return QModelIndex()
            return self.createIndex(row, 0, node)

        return QModelIndex()

    def _child_directory_paths(self, parent_path: str) -> list[str]:
        parent_proxy_index = self._fs_proxy_model.index_for_path(parent_path)
        if not parent_proxy_index.isValid():
            return []
        if self._fs_proxy_model.canFetchMore(parent_proxy_index):
            self._fs_proxy_model.fetchMore(parent_proxy_index)

        child_paths: list[str] = []
        for row in range(self._fs_proxy_model.rowCount(parent_proxy_index)):
            child_index = self._fs_proxy_model.index(row, 0, parent_proxy_index)
            if not child_index.isValid() or not self._fs_proxy_model.is_dir(child_index):
                continue
            child_path = self._fs_proxy_model.file_path(child_index)
            if not child_path:
                continue
            child_dir = Path(child_path)
            if not self.folder_predicate(child_dir):
                continue
            if self._is_mobile_folder_path(child_path):
                continue
            child_paths.append(child_path)
        child_paths.sort(key=str.casefold)
        return child_paths

    def _ensure_section_items(self) -> None:
        if not self._sectioned_view:
            return
        if self._local_section_item is not None and self._mobile_section_item is not None:
            return
        root_item = self._root_registry_model.invisibleRootItem()
        local_section_item = QStandardItem("LOCAL")
        local_section_item.setEditable(False)
        local_section_item.setSelectable(False)
        local_section_item.setData(True, self.SECTION_ROLE)
        local_section_item.setData(self._LOCAL_SECTION_KIND, self.SECTION_KIND_ROLE)

        mobile_section_item = QStandardItem("MOBILE")
        mobile_section_item.setEditable(False)
        mobile_section_item.setSelectable(False)
        mobile_section_item.setData(True, self.SECTION_ROLE)
        mobile_section_item.setData(self._MOBILE_SECTION_KIND, self.SECTION_KIND_ROLE)

        root_item.appendRow(local_section_item)
        root_item.appendRow(mobile_section_item)
        self._local_section_item = local_section_item
        self._mobile_section_item = mobile_section_item

    def _section_nodes(self) -> list[_FolderTreeNode]:
        if not self._sectioned_view:
            return []
        return [
            self._node(self._SECTION_NODE_KIND, self._LOCAL_SECTION_KIND),
            self._node(self._SECTION_NODE_KIND, self._MOBILE_SECTION_KIND),
        ]

    def _section_kind_for_folder_path(self, folder_path: str) -> str:
        return self._MOBILE_SECTION_KIND if self._is_mobile_folder_path(folder_path) else self._LOCAL_SECTION_KIND

    def _section_item_for_kind(self, section_kind: str) -> QStandardItem | None:
        if not self._sectioned_view:
            return None
        self._ensure_section_items()
        if section_kind == self._LOCAL_SECTION_KIND:
            return self._local_section_item
        if section_kind == self._MOBILE_SECTION_KIND:
            return self._mobile_section_item
        return None

    def _section_index_for_kind(self, section_kind: str) -> QModelIndex:
        for row, section_node in enumerate(self._section_nodes()):
            if section_node.key == section_kind:
                return self.createIndex(row, 0, section_node)
        return QModelIndex()

    def _registry_parent_for_section(self, section_kind: str) -> QStandardItem:
        section_item = self._section_item_for_kind(section_kind)
        if section_item is not None:
            return section_item
        return self._root_registry_model.invisibleRootItem()

    def _root_insert_row(self, section_kind: str, folder_path: str) -> int:
        root_paths = self._root_paths_for_section(section_kind)
        root_paths.append(folder_path)
        root_paths.sort(key=str.casefold)
        return root_paths.index(folder_path)

    def _root_paths_for_section(self, section_kind: str) -> list[str]:
        parent_item = self._registry_parent_for_section(section_kind)
        root_paths = []
        for row in range(parent_item.rowCount()):
            child_item = parent_item.child(row)
            if child_item is None:
                continue
            child_path = child_item.data(Qt.UserRole)
            if not child_path:
                continue
            normalized_path = normalized_folder_path(child_path).replace("\\", "/")
            if self._section_kind_for_folder_path(normalized_path) != section_kind:
                continue
            root_paths.append(normalized_path)
        root_paths.sort(key=str.casefold)
        return root_paths

    def _all_root_paths(self) -> list[str]:
        if self._sectioned_view:
            return self._root_paths_for_section(self._LOCAL_SECTION_KIND) + self._root_paths_for_section(self._MOBILE_SECTION_KIND)
        paths = []
        for row in range(self._root_registry_model.rowCount()):
            child_item = self._root_registry_model.item(row, 0)
            if child_item is not None and child_item.data(Qt.UserRole):
                paths.append(normalized_folder_path(child_item.data(Qt.UserRole)).replace("\\", "/"))
        paths.sort(key=str.casefold)
        return paths

    def _has_root_folder(self, folder_path: str) -> bool:
        normalized_path = normalized_folder_path(folder_path).replace("\\", "/")
        return normalized_path in self._all_root_paths()

    def _is_mobile_folder_path(self, folder_path: str) -> bool:
        normalized_path = normalized_folder_path(folder_path).replace("\\", "/")
        return normalized_path in self._mobile_folder_paths

    def _sync_root_sections(self) -> None:
        if not self._sectioned_view:
            return
        self._ensure_section_items()
        assert self._local_section_item is not None
        assert self._mobile_section_item is not None

        for section_item in (self._local_section_item, self._mobile_section_item):
            row = 0
            while row < section_item.rowCount():
                child_item = section_item.child(row)
                if child_item is None:
                    row += 1
                    continue
                child_path = child_item.data(Qt.UserRole)
                if not child_path:
                    row += 1
                    continue
                normalized_path = normalized_folder_path(child_path).replace("\\", "/")
                target_parent = self._registry_parent_for_section(self._section_kind_for_folder_path(normalized_path))
                if target_parent is section_item:
                    row += 1
                    continue
                taken_row = section_item.takeRow(row)
                if not taken_row:
                    continue
                insert_row = self._root_insert_row(self._section_kind_for_folder_path(normalized_path), normalized_path)
                target_parent.insertRow(insert_row, taken_row)

    def _registry_item_for_ref(self, item: FolderTreeItemRef) -> QStandardItem | None:
        if item._node.kind == self._SECTION_NODE_KIND:
            return self._section_item_for_kind(item._node.key)
        if item._node.kind == self._ROOT_NODE_KIND:
            parent_item = self._registry_parent_for_section(self._section_kind_for_folder_path(item._node.key))
            for row in range(parent_item.rowCount()):
                child_item = parent_item.child(row)
                if child_item is None:
                    continue
                child_path = child_item.data(Qt.UserRole)
                if normalized_folder_path(child_path).replace("\\", "/") == item._node.key:
                    return child_item
        return None

    def _emit_root_data_changed(self, roles: list[int]) -> None:
        for root_path in self._all_root_paths():
            root_index = self._index_for_node(self._node(self._ROOT_NODE_KIND, root_path))
            if root_index.isValid():
                self.dataChanged.emit(root_index, root_index, roles)

    @staticmethod
    def _public_path(normalized_path: str) -> str:
        if normalized_path.endswith("/") and len(normalized_path) > 1:
            return normalized_path[:-1]
        return normalized_path

    @staticmethod
    def _filesystem_root_path() -> str:
        anchor = Path.home().anchor or QDir.rootPath()
        if anchor:
            return normalized_folder_path(anchor).replace("\\", "/")
        return QDir.rootPath()
