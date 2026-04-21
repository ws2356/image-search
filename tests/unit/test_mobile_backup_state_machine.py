import unittest

from dt_image_search.mobile.mobile_backup_state_machine import (
    MOBILE_TRANSFER_STATE_DISCONNECTED,
    MobileBackupEvent,
    MobileBackupState,
    MobileBackupStateMachine,
    MobileBackupStateTransitionError,
    backup_state_from_folder_transfer_state,
    folder_transfer_state_from_backup_state,
    resolve_next_backup_state,
)
from dt_image_search.mobile.mobile_pairing_store import (
    MOBILE_TRANSFER_STATE_COMPLETED,
    MOBILE_TRANSFER_STATE_FAILED,
    MOBILE_TRANSFER_STATE_PAIRED,
    MOBILE_TRANSFER_STATE_TRANSFERRING,
)


class TestMobileBackupStateMachine(unittest.TestCase):
    def test_happy_path_transitions_pairing_to_completed_transfer(self):
        machine = MobileBackupStateMachine()
        machine = machine.transition(MobileBackupEvent.PAIRING_ACCEPTED)
        self.assertEqual(machine.state, MobileBackupState.PAIRING_COMPLETED)

        machine = machine.transition(MobileBackupEvent.TRANSFER_STARTED)
        self.assertEqual(machine.state, MobileBackupState.TRANSFER_IN_PROGRESS)

        machine = machine.transition(MobileBackupEvent.TRANSFER_COMPLETED)
        self.assertEqual(machine.state, MobileBackupState.TRANSFER_COMPLETED)

    def test_mismatch_path_resolves_back_to_pairing_completed(self):
        machine = MobileBackupStateMachine()
        machine = machine.transition(MobileBackupEvent.PAIRING_MISMATCH_DETECTED)
        self.assertEqual(machine.state, MobileBackupState.PAIRING_MISMATCHED)

        machine = machine.transition(MobileBackupEvent.PAIRING_MISMATCH_RESOLVED)
        self.assertEqual(machine.state, MobileBackupState.PAIRING_COMPLETED)

    def test_mismatch_path_can_transition_to_pairing_stopped(self):
        machine = MobileBackupStateMachine()
        machine = machine.transition(MobileBackupEvent.PAIRING_MISMATCH_DETECTED)
        machine = machine.transition(MobileBackupEvent.PAIRING_STOPPED)
        self.assertEqual(machine.state, MobileBackupState.PAIRING_STOPPED)

    def test_pending_pairing_can_transition_to_pairing_expired(self):
        machine = MobileBackupStateMachine()
        machine = machine.transition(MobileBackupEvent.PAIRING_EXPIRED)
        self.assertEqual(machine.state, MobileBackupState.PAIRING_EXPIRED)

    def test_transfer_stopped_state_maps_to_paired_folder_state(self):
        self.assertEqual(
            folder_transfer_state_from_backup_state(MobileBackupState.TRANSFER_STOPPED),
            MOBILE_TRANSFER_STATE_PAIRED,
        )

    def test_folder_transfer_state_mapping_supports_phase2_disconnected(self):
        self.assertEqual(
            backup_state_from_folder_transfer_state(MOBILE_TRANSFER_STATE_PAIRED),
            MobileBackupState.PAIRING_COMPLETED,
        )
        self.assertEqual(
            backup_state_from_folder_transfer_state(MOBILE_TRANSFER_STATE_TRANSFERRING),
            MobileBackupState.TRANSFER_IN_PROGRESS,
        )
        self.assertEqual(
            backup_state_from_folder_transfer_state(MOBILE_TRANSFER_STATE_COMPLETED),
            MobileBackupState.TRANSFER_COMPLETED,
        )
        self.assertEqual(
            backup_state_from_folder_transfer_state(MOBILE_TRANSFER_STATE_FAILED),
            MobileBackupState.TRANSFER_FAILED,
        )
        self.assertEqual(
            backup_state_from_folder_transfer_state(MOBILE_TRANSFER_STATE_DISCONNECTED),
            MobileBackupState.TRANSFER_STOPPED,
        )

    def test_invalid_transition_raises_state_transition_error(self):
        machine = MobileBackupStateMachine()
        with self.assertRaises(MobileBackupStateTransitionError):
            machine.transition(MobileBackupEvent.TRANSFER_COMPLETED)

    def test_resolve_next_backup_state_uses_fallback_when_current_state_disallows_event(self):
        next_state = resolve_next_backup_state(
            current_folder_transfer_state=MOBILE_TRANSFER_STATE_COMPLETED,
            event=MobileBackupEvent.TRANSFER_FAILED,
            fallback_state=MobileBackupState.TRANSFER_IN_PROGRESS,
        )
        self.assertEqual(next_state, MobileBackupState.TRANSFER_FAILED)


if __name__ == "__main__":
    unittest.main()
