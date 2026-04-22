import os
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication, QDialog, QMessageBox

from dt_image_search.mobile.mobile_dialogs import MobilePairingDialog
from dt_image_search.mobile.mobile_pairing_service import (
    MobilePairingResult,
    PairingResultState,
)
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobilePlatform

_APP = QApplication.instance() or QApplication([])


class _FakePairingService:
    def __init__(self, pairing_session: MobilePairingSessionDraft):
        self.endpoint_urls = pairing_session.desktop_endpoint_urls
        self._pairing_session = pairing_session
        self._result = MobilePairingResult(
            state=PairingResultState.WAITING,
            message="Scan the QR code from the mobile app to begin pairing.",
            session_id=pairing_session.session_id,
        )

    def current_result(self) -> MobilePairingResult:
        return self._result

    def refresh_token(self, platform: MobilePlatform):
        return self._pairing_session.refresh_token(platform)


class TestMobilePairingDialog(unittest.TestCase):
    def setUp(self) -> None:
        self._destination_parent = Path.cwd().as_posix()
        self._pairing_session = MobilePairingSessionDraft.create(
            destination_parent=self._destination_parent,
            desktop_endpoint_url="http://127.0.0.1:54921/api/mobile/pairing/claim",
        )
        self._pairing_service = _FakePairingService(self._pairing_session)
        self._dialog = MobilePairingDialog(
            pairing_service=self._pairing_service,
            pairing_session=self._pairing_session,
        )
        self.addCleanup(self._dialog.close)

    def test_accepted_state_shows_transfer_waiting_ui_and_keeps_dialog_open(self):
        accepted_result = replace(
            self._pairing_service.current_result(),
            state=PairingResultState.ACCEPTED,
            message="Mobile app claimed this pairing session.",
            device_name="Alice iPhone",
            transport="usb",
            folder_path="/tmp/mobile-backup",
        )
        self._pairing_service._result = accepted_result

        self._dialog._update_pairing_result()

        self.assertEqual(self._dialog.session_status_label.text(), "Pairing complete. Waiting for transfer to start…")
        self.assertFalse(self._dialog.transfer_wait_spinner.isHidden())
        self.assertFalse(self._dialog.transfer_wait_message_label.isHidden())
        self.assertTrue(self._dialog.qr_card.isHidden())
        self.assertEqual(self._dialog.close_button.text(), "Close")
        self.assertEqual(self._dialog.result(), 0)

    def test_reject_confirmed_after_acceptance_rejects_dialog(self):
        accepted_result = replace(
            self._pairing_service.current_result(),
            state=PairingResultState.ACCEPTED,
            message="Mobile app claimed this pairing session.",
        )
        self._pairing_service._result = accepted_result
        self._dialog._update_pairing_result()

        with patch(
            "dt_image_search.mobile.mobile_dialogs.QMessageBox.question",
            return_value=QMessageBox.StandardButton.Yes,
        ):
            self._dialog.reject()

        self.assertEqual(self._dialog.result(), int(QDialog.DialogCode.Rejected))


if __name__ == "__main__":
    unittest.main()
