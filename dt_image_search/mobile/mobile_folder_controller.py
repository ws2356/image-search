from __future__ import annotations

from pathlib import Path
from typing import Callable

from PySide6.QtCore import QObject, Signal
from PySide6.QtWidgets import QWidget

from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.apple_mobile_device_support import AppleMobileDeviceSupportManager
from dt_image_search.mobile.mobile_dialogs import (
    MobilePairingDialog,
    MobileUsbPrerequisitesDialog,
    ParentFolderSelectionDialog,
    SourceSelectionDialog,
)
from dt_image_search.mobile.mobile_pairing_service import MobilePairingService, PairingResultState
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobileSourceType
from dt_image_search.mobile.mobile_transfer_service import MOBILE_TRANSFER_STARTED_EVENT
from dt_image_search.model.dts_db import create_db_conn, get_config, set_config
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_event_bus import default_bus


class MobileFolderCoordinator(QObject):
    transfer_started = Signal(str, str)
    _LAST_DESTINATION_KEY = "mobile_backup_parent_path"

    def __init__(self, ctx: BMContext, *, on_folder_ready: Callable[[str], None] | None = None):
        super().__init__()
        self.ctx = ctx
        self._on_folder_ready = on_folder_ready
        self._pairing_service: MobilePairingService | None = None
        self._active_dialog: MobilePairingDialog | None = None
        self.transfer_started.connect(self._handle_transfer_started_on_main_thread)
        self._transfer_started_subscription = default_bus.subscribe(
            MOBILE_TRANSFER_STARTED_EVENT,
            self._on_transfer_started,
        )

    def choose_source(self, parent: QWidget | None = None) -> MobileSourceType | None:
        source = SourceSelectionDialog.select_source(parent)
        if source is not None:
            log("info", message=f"MobileFolderCoordinator/choose_source: selected {source.value}")
        return source

    def start_pairing_flow(self, parent: QWidget | None = None) -> MobilePairingSessionDraft | None:
        destination_parent = self._choose_destination_parent(parent)
        if not destination_parent:
            return None

        if not self._ensure_usb_prerequisites(parent):
            return None

        pairing_service = self._get_pairing_service()
        pairing_session = pairing_service.start_pairing_session(destination_parent)
        log(
            "info",
            message=(
                "MobileFolderCoordinator/start_pairing_flow: created pairing session "
                f"{pairing_session.session_id}"
            ),
        )
        status_bar_messenger.show_status_message.emit("Opened mobile pairing flow.")

        dialog = MobilePairingDialog(pairing_service=pairing_service, pairing_session=pairing_session, parent=parent)
        self._active_dialog = dialog
        try:
            dialog.exec()
        finally:
            if self._active_dialog is dialog:
                self._active_dialog = None
        self._store_last_destination(pairing_session.destination_parent)
        pairing_result = pairing_service.current_result()
        if pairing_result.state == PairingResultState.ACCEPTED and pairing_result.device_name:
            status_bar_messenger.show_status_message.emit(f"Paired {pairing_result.device_name} for mobile backup.")
        pairing_service.close_active_session()
        return pairing_session

    def _choose_destination_parent(self, parent: QWidget | None = None) -> str | None:
        initial_directory = self._last_destination_parent()
        if not initial_directory or not Path(initial_directory).is_dir():
            initial_directory = self._default_destination_parent()
        return ParentFolderSelectionDialog.select_destination_parent(initial_directory=initial_directory, parent=parent)

    @staticmethod
    def _default_destination_parent() -> str:
        pictures_path = (Path.home() / "Pictures").resolve()
        if pictures_path.is_dir():
            return pictures_path.as_posix()
        return Path.home().resolve().as_posix()

    def _last_destination_parent(self) -> str | None:
        with create_db_conn(ctx=self.ctx) as conn:
            stored_value = get_config(conn, self._LAST_DESTINATION_KEY)
        if not stored_value:
            return None
        return Path(stored_value).expanduser().resolve().as_posix()

    def _store_last_destination(self, destination_parent: str) -> None:
        with create_db_conn(ctx=self.ctx) as conn:
            set_config(conn, self._LAST_DESTINATION_KEY, destination_parent)

    def _get_pairing_service(self) -> MobilePairingService:
        if self._pairing_service is None:
            self._pairing_service = MobilePairingService(self.ctx)
        return self._pairing_service

    @staticmethod
    def _ensure_usb_prerequisites(parent: QWidget | None = None) -> bool:
        support_manager = AppleMobileDeviceSupportManager()
        return MobileUsbPrerequisitesDialog.ensure_ready(
            support_manager=support_manager,
            parent=parent,
        )

    def _on_transfer_started(self, *, session_id: str, folder_path: str, **_: object) -> None:
        self.transfer_started.emit(session_id, folder_path)

    def _handle_transfer_started_on_main_thread(self, session_id: str, folder_path: str) -> None:
        if self._on_folder_ready is not None:
            self._on_folder_ready(folder_path)

        dialog = self._active_dialog
        if dialog is None:
            return
        if dialog.pairing_session.session_id != session_id:
            return

        log(
            "info",
            message=(
                "MobileFolderCoordinator/_handle_transfer_started_on_main_thread: "
                f"closing pairing dialog for session {session_id}"
            ),
        )
        dialog.accept()
