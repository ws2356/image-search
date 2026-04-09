from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QFileDialog, QWidget

from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.mobile_dialogs import MobilePairingDialog, SourceSelectionDialog
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobileSourceType
from dt_image_search.model.dts_db import create_db_conn, get_config, set_config
from dt_image_search.telemetry.telemetry_client import log


class MobileFolderCoordinator:
    _LAST_DESTINATION_KEY = "mobile_backup_parent_path"

    def __init__(self, ctx: BMContext):
        self.ctx = ctx

    def choose_source(self, parent: QWidget | None = None) -> MobileSourceType | None:
        source = SourceSelectionDialog.select_source(parent)
        if source is not None:
            log("info", message=f"MobileFolderCoordinator/choose_source: selected {source.value}")
        return source

    def start_pairing_flow(self, parent: QWidget | None = None) -> MobilePairingSessionDraft | None:
        destination_parent = self._choose_destination_parent(parent)
        if not destination_parent:
            return None

        pairing_session = MobilePairingSessionDraft.create(destination_parent)
        log(
            "info",
            message=(
                "MobileFolderCoordinator/start_pairing_flow: created pairing session "
                f"{pairing_session.session_id}"
            ),
        )
        status_bar_messenger.show_status_message.emit("Opened mobile pairing flow.")

        dialog = MobilePairingDialog(pairing_session=pairing_session, parent=parent)
        dialog.exec()
        self._store_last_destination(pairing_session.destination_parent)
        return pairing_session

    def _choose_destination_parent(self, parent: QWidget | None = None) -> str | None:
        initial_directory = self._last_destination_parent() or Path.home().as_posix()
        selected_directory = QFileDialog.getExistingDirectory(
            parent,
            "Select Mobile Backup Parent Folder",
            initial_directory,
        )
        if not selected_directory:
            return None
        return Path(selected_directory).expanduser().resolve().as_posix()

    def _last_destination_parent(self) -> str | None:
        with create_db_conn(ctx=self.ctx) as conn:
            stored_value = get_config(conn, self._LAST_DESTINATION_KEY)
        if not stored_value:
            return None
        return Path(stored_value).expanduser().resolve().as_posix()

    def _store_last_destination(self, destination_parent: str) -> None:
        with create_db_conn(ctx=self.ctx) as conn:
            set_config(conn, self._LAST_DESTINATION_KEY, destination_parent)