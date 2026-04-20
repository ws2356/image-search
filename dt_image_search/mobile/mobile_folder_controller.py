from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import threading
from typing import Callable

from PySide6.QtCore import QObject, QThread, Signal
from PySide6.QtWidgets import QMessageBox, QWidget

from dt_image_search.base.status_bar_messenger import status_bar_messenger
from dt_image_search.bm_context import BMContext
from dt_image_search.mobile.apple_mobile_device_support import AppleMobileDeviceSupportManager
from dt_image_search.mobile.mobile_dialogs import (
    MobilePairingDialog,
    MobileUsbPrerequisitesDialog,
    ParentFolderSelectionDialog,
    SourceSelectionDialog,
)
from dt_image_search.mobile.mobile_pairing_service import (
    MobileBackupAgainDecision,
    MobileBackupAgainMismatchContext,
    MobileBackupAgainSessionContext,
    MobilePairingService,
    PairingResultState,
)
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobileSourceType
from dt_image_search.mobile.mobile_pairing_store import get_mobile_folder_binding_by_path
from dt_image_search.mobile.mobile_transfer_service import MOBILE_TRANSFER_STARTED_EVENT
from dt_image_search.model.dts_db import create_db_conn, get_config, set_config
from dt_image_search.telemetry.telemetry_client import log
from dt_image_search.tools.dts_event_bus import default_bus


@dataclass
class _BackupAgainPromptRequest:
    context: MobileBackupAgainMismatchContext
    decision: MobileBackupAgainDecision | None = None
    completed: threading.Event = field(default_factory=threading.Event)


class MobileFolderCoordinator(QObject):
    transfer_started = Signal(str, str)
    backup_again_mismatch_requested = Signal(object)
    _LAST_DESTINATION_KEY = "mobile_backup_parent_path"

    def __init__(self, ctx: BMContext, *, on_folder_ready: Callable[[str], None] | None = None):
        super().__init__()
        self.ctx = ctx
        self._on_folder_ready = on_folder_ready
        self._pairing_service: MobilePairingService | None = None
        self._active_dialog: MobilePairingDialog | None = None
        self._backup_again_parent: QWidget | None = None
        self.transfer_started.connect(self._handle_transfer_started_on_main_thread)
        self.backup_again_mismatch_requested.connect(self._on_backup_again_prompt_request)
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
        return self._run_pairing_flow(destination_parent=destination_parent, parent=parent)

    def start_backup_again_flow(
        self,
        selected_folder_path: str,
        parent: QWidget | None = None,
    ) -> MobilePairingSessionDraft | None:
        normalized_folder_path = Path(selected_folder_path).expanduser().resolve().as_posix()
        with create_db_conn(ctx=self.ctx) as conn:
            folder_binding = get_mobile_folder_binding_by_path(conn, folder_path=normalized_folder_path)
        if folder_binding is None:
            status_bar_messenger.show_status_message.emit("Mobile folder pairing data is missing for this folder.")
            log(
                "warning",
                message=(
                    "MobileFolderCoordinator/start_backup_again_flow: no mobile folder binding for "
                    f"{normalized_folder_path}"
                ),
            )
            return None

        destination_parent = Path(folder_binding.folder_path).parent.as_posix()
        backup_again_context = MobileBackupAgainSessionContext(
            selected_folder_id=folder_binding.folder_id,
            selected_folder_path=folder_binding.folder_path,
            expected_device_uuid=folder_binding.device_uuid,
            mismatch_resolver=self._resolve_backup_again_mismatch,
        )
        return self._run_pairing_flow(
            destination_parent=destination_parent,
            parent=parent,
            backup_again_context=backup_again_context,
        )

    def _run_pairing_flow(
        self,
        *,
        destination_parent: str,
        parent: QWidget | None = None,
        backup_again_context: MobileBackupAgainSessionContext | None = None,
    ) -> MobilePairingSessionDraft | None:
        try:
            self._backup_again_parent = parent if backup_again_context is not None else None

            if not self._ensure_usb_prerequisites(parent):
                return None

            pairing_service = self._get_pairing_service()
            pairing_session = pairing_service.start_pairing_session(
                destination_parent,
                backup_again_context=backup_again_context,
            )
            log(
                "info",
                message=(
                    "MobileFolderCoordinator/_run_pairing_flow: created pairing session "
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
        finally:
            self._backup_again_parent = None

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

    def _resolve_backup_again_mismatch(
        self,
        context: MobileBackupAgainMismatchContext,
    ) -> MobileBackupAgainDecision:
        if QThread.isMainThread():
            return self._prompt_backup_again_mismatch(context)

        prompt_request = _BackupAgainPromptRequest(context=context)
        self.backup_again_mismatch_requested.emit(prompt_request)
        if not prompt_request.completed.wait(timeout=300):
            log(
                "warning",
                message=(
                    "MobileFolderCoordinator/_resolve_backup_again_mismatch: "
                    "timed out waiting for user decision, canceling backup-again request."
                ),
            )
            return MobileBackupAgainDecision.CANCEL
        return prompt_request.decision or MobileBackupAgainDecision.CANCEL

    def _on_backup_again_prompt_request(self, prompt_request: object) -> None:
        if not isinstance(prompt_request, _BackupAgainPromptRequest):
            return
        try:
            prompt_request.decision = self._prompt_backup_again_mismatch(prompt_request.context)
        finally:
            prompt_request.completed.set()

    def _prompt_backup_again_mismatch(
        self,
        context: MobileBackupAgainMismatchContext,
    ) -> MobileBackupAgainDecision:
        dialog = QMessageBox(self._backup_again_parent)
        dialog.setIcon(QMessageBox.Icon.Warning)
        dialog.setWindowTitle("Mobile Device Not Paired")
        dialog.setText("This mobile app is no longer paired with the selected mobile folder.")
        dialog.setInformativeText(
            "You can continue in this folder and repair the pairing, or back up in a new folder."
        )
        continue_button = dialog.addButton("Continue in This Folder", QMessageBox.ButtonRole.AcceptRole)
        backup_new_folder_button = dialog.addButton("Back Up in New Folder", QMessageBox.ButtonRole.ActionRole)
        dialog.setDefaultButton(backup_new_folder_button)
        dialog.exec()
        clicked_button = dialog.clickedButton()
        if clicked_button is continue_button:
            return MobileBackupAgainDecision.CONTINUE_IN_SELECTED_FOLDER
        if clicked_button is backup_new_folder_button:
            log(
                "info",
                message=(
                    "MobileFolderCoordinator/_prompt_backup_again_mismatch: "
                    f"using new folder for replacement device {context.replacement_device_uuid}"
                ),
            )
            return MobileBackupAgainDecision.BACKUP_IN_NEW_FOLDER
        log(
            "info",
            message=(
                "MobileFolderCoordinator/_prompt_backup_again_mismatch: "
                f"user canceled mismatch resolution for replacement device {context.replacement_device_uuid}"
            ),
        )
        return MobileBackupAgainDecision.CANCEL
