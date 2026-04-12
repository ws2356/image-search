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
from dt_image_search.mobile.mobile_pairing_service import MobilePairingResult, PairingResultState
from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft
from dt_image_search.model.dts_db import create_db_conn, get_config, set_config

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

    def exec(self):
        self.exec_called = True


class _FakePairingService:
    def __init__(self, session: MobilePairingSessionDraft):
        self._session = session
        self.started_with: str | None = None
        self.closed = False
        self._result = MobilePairingResult(
            state=PairingResultState.WAITING,
            message="Waiting for mobile device.",
            session_id=session.session_id,
        )

    def start_pairing_session(self, destination_parent: str) -> MobilePairingSessionDraft:
        self.started_with = destination_parent
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
        self._data_path_key = f"BM_DATA_PATH_{self._ctx.subfolder}"
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
            patch.object(mobile_folder_controller_module, "MobilePairingDialog", _FakePairingDialog),
        ):
            coordinator = mobile_folder_controller_module.MobileFolderCoordinator(self._ctx)
            with patch.object(coordinator, "_get_pairing_service", return_value=fake_pairing_service):
                result_session = coordinator.start_pairing_flow()

        self.assertIsNotNone(result_session)
        self.assertEqual(result_session.destination_parent, destination_parent_path)
        self.assertEqual(fake_pairing_service.started_with, destination_parent_path)
        self.assertTrue(fake_pairing_service.closed)

        with create_db_conn(ctx=self._ctx) as conn:
            stored_destination = get_config(conn, coordinator._LAST_DESTINATION_KEY)
        self.assertEqual(stored_destination, destination_parent_path)

    def test_choose_destination_parent_falls_back_when_stored_path_is_missing(self):
        missing_destination = (Path(self._temp_dir.name) / "does-not-exist").resolve()
        with create_db_conn(ctx=self._ctx) as conn:
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


if __name__ == "__main__":
    unittest.main()
