import XCTest
@testable import AlbumTransporterKit

final class MobileBackupFlowStateMachineTests: XCTestCase {
    func test_happy_path_transitions_to_transfer_completed() {
        var machine = MobileBackupFlowStateMachine()
        XCTAssertEqual(machine.state, .pendingPairing)

        machine.transition(.pairingAccepted)
        XCTAssertEqual(machine.state, .pairingCompleted)

        machine.transition(.transferStarted)
        XCTAssertEqual(machine.state, .transferInProgress)

        machine.transition(.transferCompleted)
        XCTAssertEqual(machine.state, .transferCompleted)
    }

    func test_mismatch_path_resolves_to_pairing_completed() {
        var machine = MobileBackupFlowStateMachine()

        machine.transition(.pairingMismatchDetected)
        XCTAssertEqual(machine.state, .pairingMismatched)

        machine.transition(.pairingMismatchResolved)
        XCTAssertEqual(machine.state, .pairingCompleted)
    }

    func test_pairing_stopped_state_is_reachable_from_mismatch() {
        var machine = MobileBackupFlowStateMachine()

        machine.transition(.pairingMismatchDetected)
        machine.transition(.pairingStopped)

        XCTAssertEqual(machine.state, .pairingStopped)
    }

    func test_pairing_expired_state_is_reachable_from_pending() {
        var machine = MobileBackupFlowStateMachine()
        machine.transition(.pairingExpired)
        XCTAssertEqual(machine.state, .pairingExpired)
    }

    func test_transfer_resume_from_non_active_states_returns_to_in_progress() {
        var stoppedMachine = MobileBackupFlowStateMachine(state: .transferStopped)
        stoppedMachine.transition(.transferStarted)
        XCTAssertEqual(stoppedMachine.state, .transferInProgress)

        var completedMachine = MobileBackupFlowStateMachine(state: .transferCompleted)
        completedMachine.transition(.transferStarted)
        XCTAssertEqual(completedMachine.state, .transferInProgress)

        var failedMachine = MobileBackupFlowStateMachine(state: .transferFailed)
        failedMachine.transition(.transferStarted)
        XCTAssertEqual(failedMachine.state, .transferInProgress)
    }

    func test_reset_event_returns_pending_pairing() {
        var machine = MobileBackupFlowStateMachine(state: .transferCompleted)
        machine.transition(.resetToPendingPairing)
        XCTAssertEqual(machine.state, .pendingPairing)
    }

    func test_unsupported_transition_keeps_state() {
        var machine = MobileBackupFlowStateMachine(state: .pendingPairing)
        machine.transition(.transferCompleted)
        XCTAssertEqual(machine.state, .pendingPairing)
    }
}
