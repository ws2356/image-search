import importlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from dt_image_search.bm_context import BMContext
from dt_image_search.model.dts_fs import get_app_private_name
from dt_image_search.mobile.mobile_pairing_service import (
    MobileBackupAgainDecision,
    MobileBackupAgainMismatchContext,
    MobilePairingResult,
    PairingResultState,
)
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft
from dt_image_search.model.dts_db import create_db_conn, get_config, insert_folder, set_config

mobile_folder_controller_module = importlib.import_module("dt_image_search.mobile.mobile_folder_controller")


class _DummySubscription:
    def dispose(self):
        return None


class _FakePairingDialog:
    def __init__(self, *, pairing_service, pairing_session, parent=None):
        self.pairing_service = pairing_service
        self.pairing_session = pairing_session
        self.parent = parent
        self.exec_called = False
        self.accept_called = False

    def exec(self):
        self.exec_called = True

    def accept(self):
        self.accept_called = True


class _FakePairingService:
    def __init__(self, session: MobilePairingSessionDraft):
        self._session = session
        self.started_with: str | None = None
        self.backup_again_context = None
        self.closed = False
        self._result = MobilePairingResult(
            state=PairingResultState.WAITING,
            message="Waiting for mobile device.",
            session_id=session.session_id,
        )

    def start_pairing_session(
        self,
        destination_parent: str,
        backup_again_context=None,
    ) -> MobilePairingSessionDraft:
        self.started_with = destination_parent
        self.backup_again_context = backup_again_context
        self._session.set_destination_parent(destination_parent)
        return self._session

    def current_result(self) -> MobilePairingResult:
        return self._result

    def close_active_session(self) -> None:
        self.closed = True


class TestMobileFolderCoordinator(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self._ctx = BMContext(
            version=1,
            subfolder=f"mobile-folder-controller-tests-{uuid.uuid4().hex}",
            model_name="test-model",
            pretrained_model="test-pretrained",
            offline_mode=True,
            model_file_info_url="https://example.invalid/model.json",
        )
        self._data_path_key = f"BM_DATA_PATH_{get_app_private_name()}"
        os.environ[self._data_path_key] = self._temp_dir.name
        self.addCleanup(os.environ.pop, self._data_path_key, None)

    def test_start_pairing_flow_returns_none_when_parent_folder_selection_is_cancelled(self):
        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.ParentFolderSelectionDialog,
                "select_destination_parent",
                return_value=None,
            ),
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service") as get_pairing_service_mock:
                pairing_session = coordinator.start_pairing_flow()

        self.assertIsNone(pairing_session)
        get_pairing_service_mock.assert_not_called()

    def test_start_pairing_flow_uses_selected_parent_and_persists_last_destination(self):
        destination_parent = (Path(self._temp_dir.name) / "Mobile Backups").resolve()
        destination_parent.mkdir(parents=True, exist_ok=True)
        destination_parent_path = destination_parent.as_posix()
        pairing_session = MobilePairingSessionDraft.create(
            destination_parent=destination_parent_path,
            desktop_endpoint_url="http://127.0.0.1:54921/api/mobile/pairing/claim",
        )
        fake_pairing_service = _FakePairingService(pairing_session)

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.ParentFolderSelectionDialog,
                "select_destination_parent",
                return_value=destination_parent_path,
            ),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_ensure_usb_prerequisites",
                return_value=True,
            ),
            patch.object(mobile_folder_controller_module, "MobilePairingDialog", _FakePairingDialog),
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service", return_value=fake_pairing_service):
                result_session = coordinator.start_pairing_flow()

        self.assertIsNotNone(result_session)
        self.assertEqual(result_session.destination_parent, destination_parent_path)
        self.assertEqual(fake_pairing_service.started_with, destination_parent_path)
        self.assertTrue(fake_pairing_service.closed)

        with create_db_conn() as conn:
            stored_destination = get_config(conn, coordinator._LAST_DESTINATION_KEY)
        self.assertEqual(stored_destination, destination_parent_path)

    def test_choose_destination_parent_falls_back_when_stored_path_is_missing(self):
        missing_destination = (Path(self._temp_dir.name) / "does-not-exist").resolve()
        with create_db_conn() as conn:
            set_config(conn, mobile_folder_controller_module.MobileFolderCoordinator._LAST_DESTINATION_KEY, missing_destination.as_posix())

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.ParentFolderSelectionDialog,
                "select_destination_parent",
                return_value=None,
            ) as select_destination_parent_mock,
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            coordinator._choose_destination_parent()

        self.assertEqual(
            select_destination_parent_mock.call_args.kwargs["initial_directory"],
            coordinator._default_destination_parent(),
        )

    def test_start_pairing_flow_returns_none_when_user_cancels_usb_prerequisites_dialog(self):
        destination_parent = Path(self._temp_dir.name).resolve().as_posix()
        pairing_session = MobilePairingSessionDraft.create(
            destination_parent=destination_parent,
            desktop_endpoint_url="http://127.0.0.1:54921/api/mobile/pairing/claim",
        )
        fake_pairing_service = _FakePairingService(pairing_session)

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.ParentFolderSelectionDialog,
                "select_destination_parent",
                return_value=destination_parent,
            ),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_ensure_usb_prerequisites",
                return_value=False,
            ),
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service", return_value=fake_pairing_service):
                result_session = coordinator.start_pairing_flow()

        self.assertIsNone(result_session)
        self.assertIsNone(fake_pairing_service.started_with)
        self.assertFalse(fake_pairing_service.closed)

    def test_start_pairing_flow_blocks_when_another_backup_is_transferring(self):
        destination_parent = Path(self._temp_dir.name).resolve()
        destination_parent.mkdir(parents=True, exist_ok=True)
        active_mobile_folder = (destination_parent / "Alice iPhone").resolve()
        active_mobile_folder.mkdir(parents=True, exist_ok=True)

        with create_db_conn() as conn:
            folder = insert_folder(conn, active_mobile_folder.as_posix())
            self.assertIsNotNone(folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    "ios-device-transfer-001",
                    "ios",
                    "Alice iPhone",
                    "trust-transfer",
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (
                    int(folder.id),
                    "ios-device-transfer-001",
                    "transferring",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_backup_sessions (
                    session_id,
                    device_uuid,
                    folder_id,
                    status,
                    transferred_count,
                    failed_count,
                    started_at,
                    paired_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "active-transfer-session",
                    "ios-device-transfer-001",
                    int(folder.id),
                    "transferring",
                    12,
                    0,
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.commit()

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_prompt_stop_active_backup_and_restart",
                return_value=False,
            ) as prompt_stop_mock,
            patch.object(
                mobile_folder_controller_module.ParentFolderSelectionDialog,
                "select_destination_parent",
            ) as select_destination_parent_mock,
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service") as get_pairing_service_mock:
                result_session = coordinator.start_pairing_flow()

        self.assertIsNone(result_session)
        get_pairing_service_mock.assert_not_called()
        select_destination_parent_mock.assert_not_called()
        prompt_stop_mock.assert_called_once()

    def test_start_backup_again_flow_starts_pairing_from_selected_mobile_folder_parent(self):
        destination_parent = (Path(self._temp_dir.name) / "Mobile Backups").resolve()
        destination_parent.mkdir(parents=True, exist_ok=True)
        mobile_folder = (destination_parent / "Alice iPhone").resolve()
        mobile_folder.mkdir(parents=True, exist_ok=True)

        pairing_session = MobilePairingSessionDraft.create(
            destination_parent=destination_parent.as_posix(),
            desktop_endpoint_url="http://127.0.0.1:54921/api/mobile/pairing/claim",
        )
        fake_pairing_service = _FakePairingService(pairing_session)
        with create_db_conn() as conn:
            folder = insert_folder(conn, mobile_folder.as_posix())
            self.assertIsNotNone(folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    "ios-device-old-001",
                    "ios",
                    "Alice iPhone",
                    "trust-old",
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (
                    int(folder.id),
                    "ios-device-old-001",
                    "paired",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.commit()

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_ensure_usb_prerequisites",
                return_value=True,
            ),
            patch.object(mobile_folder_controller_module, "MobilePairingDialog", _FakePairingDialog),
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service", return_value=fake_pairing_service):
                result_session = coordinator.start_backup_again_flow(mobile_folder.as_posix())

        self.assertIsNotNone(result_session)
        self.assertEqual(fake_pairing_service.started_with, destination_parent.as_posix())
        self.assertIsNotNone(fake_pairing_service.backup_again_context)
        self.assertEqual(fake_pairing_service.backup_again_context.selected_folder_path, mobile_folder.as_posix())
        self.assertEqual(fake_pairing_service.backup_again_context.expected_device_uuid, "ios-device-old-001")

    def test_start_backup_again_flow_blocks_when_another_backup_is_transferring(self):
        destination_parent = (Path(self._temp_dir.name) / "Mobile Backups").resolve()
        destination_parent.mkdir(parents=True, exist_ok=True)
        selected_mobile_folder = (destination_parent / "Selected iPhone").resolve()
        selected_mobile_folder.mkdir(parents=True, exist_ok=True)
        active_mobile_folder = (destination_parent / "Active iPhone").resolve()
        active_mobile_folder.mkdir(parents=True, exist_ok=True)

        with create_db_conn() as conn:
            selected_folder = insert_folder(conn, selected_mobile_folder.as_posix())
            active_folder = insert_folder(conn, active_mobile_folder.as_posix())
            self.assertIsNotNone(selected_folder)
            self.assertIsNotNone(active_folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)
                """,
                (
                    "ios-device-selected-001",
                    "ios",
                    "Selected iPhone",
                    "trust-selected",
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                    "ios-device-active-001",
                    "ios",
                    "Active iPhone",
                    "trust-active",
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?), (?, ?, ?, ?)
                """,
                (
                    int(selected_folder.id),
                    "ios-device-selected-001",
                    "paired",
                    "2026-04-10T00:00:00+00:00",
                    int(active_folder.id),
                    "ios-device-active-001",
                    "transferring",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_backup_sessions (
                    session_id,
                    device_uuid,
                    folder_id,
                    status,
                    transferred_count,
                    failed_count,
                    started_at,
                    paired_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "active-transfer-session",
                    "ios-device-active-001",
                    int(active_folder.id),
                    "transferring",
                    7,
                    0,
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.commit()

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_prompt_stop_active_backup_and_restart",
                return_value=False,
            ) as prompt_stop_mock,
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service") as get_pairing_service_mock:
                result_session = coordinator.start_backup_again_flow(selected_mobile_folder.as_posix())

        self.assertIsNone(result_session)
        get_pairing_service_mock.assert_not_called()
        prompt_stop_mock.assert_called_once()

    def test_start_pairing_flow_stops_active_session_and_continues_when_user_confirms(self):
        destination_parent = Path(self._temp_dir.name).resolve()
        destination_parent.mkdir(parents=True, exist_ok=True)
        active_mobile_folder = (destination_parent / "Alice iPhone").resolve()
        active_mobile_folder.mkdir(parents=True, exist_ok=True)

        pairing_session = MobilePairingSessionDraft.create(
            destination_parent=destination_parent.as_posix(),
            desktop_endpoint_url="http://127.0.0.1:54921/api/mobile/pairing/claim",
        )
        fake_pairing_service = _FakePairingService(pairing_session)

        with create_db_conn() as conn:
            folder = insert_folder(conn, active_mobile_folder.as_posix())
            self.assertIsNotNone(folder)
            conn.execute(
                """
                INSERT INTO mobile_devices (
                    device_uuid,
                    platform,
                    device_name,
                    trust_key_b64,
                    paired_at,
                    last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    "ios-device-transfer-001",
                    "ios",
                    "Alice iPhone",
                    "trust-transfer",
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_folders (folder_id, device_uuid, transfer_state, transfer_state_updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (
                    int(folder.id),
                    "ios-device-transfer-001",
                    "transferring",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.execute(
                """
                INSERT INTO mobile_backup_sessions (
                    session_id,
                    device_uuid,
                    folder_id,
                    status,
                    transferred_count,
                    failed_count,
                    started_at,
                    paired_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "active-transfer-session",
                    "ios-device-transfer-001",
                    int(folder.id),
                    "transferring",
                    12,
                    0,
                    "2026-04-10T00:00:00+00:00",
                    "2026-04-10T00:00:00+00:00",
                ),
            )
            conn.commit()

        with (
            patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_prompt_stop_active_backup_and_restart",
                return_value=True,
            ),
            patch.object(
                mobile_folder_controller_module.MobileFolderCoordinator,
                "_ensure_usb_prerequisites",
                return_value=True,
            ),
            patch.object(
                mobile_folder_controller_module.ParentFolderSelectionDialog,
                "select_destination_parent",
                return_value=destination_parent.as_posix(),
            ),
            patch.object(mobile_folder_controller_module, "MobilePairingDialog", _FakePairingDialog),
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service", return_value=fake_pairing_service):
                result_session = coordinator.start_pairing_flow()

        self.assertIsNotNone(result_session)
        self.assertEqual(fake_pairing_service.started_with, destination_parent.as_posix())

        with create_db_conn() as conn:
            stopped_row = conn.execute(
                """
                SELECT status, ended_at
                FROM mobile_backup_sessions
                WHERE session_id = ?
                """,
                ("active-transfer-session",),
            ).fetchone()
        self.assertIsNotNone(stopped_row)
        self.assertEqual(stopped_row["status"], "stopped_by_mobile")
        self.assertIsNotNone(stopped_row["ended_at"])

    def test_resolve_backup_again_mismatch_uses_prompt_result_on_main_thread(self):
        with patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)

        mismatch_context = MobileBackupAgainMismatchContext(
            selected_folder_path="/tmp/mobile-folder",
            previous_device_uuid="old-device",
            replacement_device_uuid="new-device",
            replacement_device_name="Replacement iPhone",
        )
        with patch.object(
            coordinator,
            "_prompt_backup_again_mismatch",
            return_value=MobileBackupAgainDecision.CONTINUE_IN_SELECTED_FOLDER,
        ), patch(
            "dt_image_search.mobile.mobile_folder_controller.QThread.isMainThread",
            return_value=True,
        ):
            decision = coordinator._resolve_backup_again_mismatch(mismatch_context)

        self.assertEqual(decision, MobileBackupAgainDecision.CONTINUE_IN_SELECTED_FOLDER)

    def test_transfer_started_closes_active_dialog_after_pairing_accepts(self):
        destination_parent = Path(self._temp_dir.name).resolve().as_posix()
        pairing_session = MobilePairingSessionDraft.create(
            destination_parent=destination_parent,
            desktop_endpoint_url="http://127.0.0.1:54921/api/mobile/pairing/claim",
        )
        fake_pairing_service = _FakePairingService(pairing_session)
        fake_pairing_service._result = MobilePairingResult(
            state=PairingResultState.ACCEPTED,
            message="Paired successfully.",
            session_id=pairing_session.session_id,
        )
        fake_dialog = _FakePairingDialog(pairing_service=fake_pairing_service, pairing_session=pairing_session)

        with patch.object(mobile_folder_controller_module.default_bus, "subscribe", return_value=_DummySubscription()):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)

        coordinator._pairing_service = fake_pairing_service
        coordinator._active_dialog = fake_dialog

        coordinator._handle_transfer_started_on_main_thread(
            pairing_session.session_id,
            pairing_session.destination_parent,
        )

        self.assertTrue(fake_dialog.accept_called)


if __name__ == "__main__":
    unittest.main()
