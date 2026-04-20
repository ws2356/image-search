from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from dt_image_search.mobile.mobile_pairing_store import (
    MOBILE_TRANSFER_STATE_COMPLETED,
    MOBILE_TRANSFER_STATE_FAILED,
    MOBILE_TRANSFER_STATE_PAIRED,
    MOBILE_TRANSFER_STATE_TRANSFERRING,
)

MOBILE_TRANSFER_STATE_DISCONNECTED = "disconnected"


class MobileBackupState(str, Enum):
    PENDING_PAIRING = "pending_pairing"
    PAIRING_MISMATCHED = "pairing_mismatched"
    PAIRING_COMPLETED = "pairing_completed"
    TRANSFER_IN_PROGRESS = "transfer_in_progress"
    TRANSFER_STOPPED = "transfer_stopped"
    TRANSFER_COMPLETED = "transfer_completed"
    TRANSFER_FAILED = "transfer_failed"


class MobileBackupEvent(str, Enum):
    PAIRING_ACCEPTED = "pairing_accepted"
    PAIRING_MISMATCH_DETECTED = "pairing_mismatch_detected"
    PAIRING_MISMATCH_RESOLVED = "pairing_mismatch_resolved"
    TRANSFER_STARTED = "transfer_started"
    TRANSFER_STOPPED = "transfer_stopped"
    TRANSFER_COMPLETED = "transfer_completed"
    TRANSFER_FAILED = "transfer_failed"


class MobileBackupStateTransitionError(RuntimeError):
    pass


_STATE_TRANSITIONS: dict[tuple[MobileBackupState, MobileBackupEvent], MobileBackupState] = {
    (MobileBackupState.PENDING_PAIRING, MobileBackupEvent.PAIRING_ACCEPTED): MobileBackupState.PAIRING_COMPLETED,
    (MobileBackupState.PENDING_PAIRING, MobileBackupEvent.PAIRING_MISMATCH_DETECTED): MobileBackupState.PAIRING_MISMATCHED,
    (MobileBackupState.PAIRING_MISMATCHED, MobileBackupEvent.PAIRING_MISMATCH_DETECTED): MobileBackupState.PAIRING_MISMATCHED,
    (MobileBackupState.PAIRING_MISMATCHED, MobileBackupEvent.PAIRING_MISMATCH_RESOLVED): MobileBackupState.PAIRING_COMPLETED,
    (MobileBackupState.PAIRING_COMPLETED, MobileBackupEvent.PAIRING_ACCEPTED): MobileBackupState.PAIRING_COMPLETED,
    (MobileBackupState.PAIRING_COMPLETED, MobileBackupEvent.TRANSFER_STARTED): MobileBackupState.TRANSFER_IN_PROGRESS,
    (MobileBackupState.TRANSFER_IN_PROGRESS, MobileBackupEvent.TRANSFER_STARTED): MobileBackupState.TRANSFER_IN_PROGRESS,
    (MobileBackupState.TRANSFER_IN_PROGRESS, MobileBackupEvent.TRANSFER_STOPPED): MobileBackupState.TRANSFER_STOPPED,
    (MobileBackupState.TRANSFER_IN_PROGRESS, MobileBackupEvent.TRANSFER_COMPLETED): MobileBackupState.TRANSFER_COMPLETED,
    (MobileBackupState.TRANSFER_IN_PROGRESS, MobileBackupEvent.TRANSFER_FAILED): MobileBackupState.TRANSFER_FAILED,
    (MobileBackupState.TRANSFER_STOPPED, MobileBackupEvent.TRANSFER_STARTED): MobileBackupState.TRANSFER_IN_PROGRESS,
    (MobileBackupState.TRANSFER_COMPLETED, MobileBackupEvent.TRANSFER_STARTED): MobileBackupState.TRANSFER_IN_PROGRESS,
    (MobileBackupState.TRANSFER_FAILED, MobileBackupEvent.TRANSFER_STARTED): MobileBackupState.TRANSFER_IN_PROGRESS,
}


@dataclass(frozen=True)
class MobileBackupStateMachine:
    state: MobileBackupState = MobileBackupState.PENDING_PAIRING

    def transition(self, event: MobileBackupEvent) -> MobileBackupStateMachine:
        next_state = _STATE_TRANSITIONS.get((self.state, event))
        if next_state is None:
            raise MobileBackupStateTransitionError(
                f"Unsupported mobile backup transition: {self.state.value} -> {event.value}"
            )
        return MobileBackupStateMachine(state=next_state)

    @classmethod
    def from_folder_transfer_state(
        cls,
        folder_transfer_state: str | None,
        *,
        default_state: MobileBackupState = MobileBackupState.PAIRING_COMPLETED,
    ) -> MobileBackupStateMachine:
        return cls(
            state=backup_state_from_folder_transfer_state(
                folder_transfer_state,
                default_state=default_state,
            )
        )

    @property
    def folder_transfer_state(self) -> str:
        return folder_transfer_state_from_backup_state(self.state)


def backup_state_from_folder_transfer_state(
    folder_transfer_state: str | None,
    *,
    default_state: MobileBackupState = MobileBackupState.PAIRING_COMPLETED,
) -> MobileBackupState:
    if folder_transfer_state == MOBILE_TRANSFER_STATE_TRANSFERRING:
        return MobileBackupState.TRANSFER_IN_PROGRESS
    if folder_transfer_state == MOBILE_TRANSFER_STATE_COMPLETED:
        return MobileBackupState.TRANSFER_COMPLETED
    if folder_transfer_state == MOBILE_TRANSFER_STATE_FAILED:
        return MobileBackupState.TRANSFER_FAILED
    if folder_transfer_state == MOBILE_TRANSFER_STATE_DISCONNECTED:
        return MobileBackupState.TRANSFER_STOPPED
    if folder_transfer_state == MOBILE_TRANSFER_STATE_PAIRED:
        return MobileBackupState.PAIRING_COMPLETED
    return default_state


def folder_transfer_state_from_backup_state(state: MobileBackupState) -> str:
    if state == MobileBackupState.TRANSFER_IN_PROGRESS:
        return MOBILE_TRANSFER_STATE_TRANSFERRING
    if state == MobileBackupState.TRANSFER_COMPLETED:
        return MOBILE_TRANSFER_STATE_COMPLETED
    if state == MobileBackupState.TRANSFER_FAILED:
        return MOBILE_TRANSFER_STATE_FAILED
    return MOBILE_TRANSFER_STATE_PAIRED


def resolve_next_backup_state(
    *,
    current_folder_transfer_state: str | None,
    event: MobileBackupEvent,
    fallback_state: MobileBackupState,
) -> MobileBackupState:
    current_state_machine = MobileBackupStateMachine.from_folder_transfer_state(
        current_folder_transfer_state,
        default_state=fallback_state,
    )
    try:
        return current_state_machine.transition(event).state
    except MobileBackupStateTransitionError:
        return MobileBackupStateMachine(state=fallback_state).transition(event).state
