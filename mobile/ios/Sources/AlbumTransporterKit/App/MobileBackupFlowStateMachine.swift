import Foundation

enum MobileBackupFlowState: String, Equatable, Sendable, Codable {
    case pendingPairing
    case pairingMismatched
    case pairingCompleted
    case pairingExpired
    case pairingStopped
    case transferInProgress
    case transferStopped
    case transferCompleted
    case transferFailed
}

enum MobileBackupFlowEvent: String, Equatable, Sendable {
    case pairingStarted
    case pairingAccepted
    case pairingFailed
    case pairingMismatchDetected
    case pairingMismatchResolved
    case pairingExpired
    case pairingStopped
    case transferStarted
    case transferStopped
    case transferCompleted
    case transferFailed
    case resetToPendingPairing
}

struct MobileBackupFlowStateMachine: Equatable, Sendable {
    private(set) var state: MobileBackupFlowState

    init(state: MobileBackupFlowState = .pendingPairing) {
        self.state = state
    }

    mutating func transition(_ event: MobileBackupFlowEvent) {
        state = Self.nextState(from: state, event: event)
    }

    static func nextState(from state: MobileBackupFlowState, event: MobileBackupFlowEvent) -> MobileBackupFlowState {
        switch (state, event) {
        case (_, .resetToPendingPairing):
            return .pendingPairing

        case (.pendingPairing, .pairingStarted):
            return .pendingPairing
        case (.pendingPairing, .pairingAccepted):
            return .pairingCompleted
        case (.pendingPairing, .pairingFailed):
            return .pendingPairing
        case (.pendingPairing, .pairingMismatchDetected):
            return .pairingMismatched
        case (.pendingPairing, .pairingExpired):
            return .pairingExpired
        case (.pendingPairing, .pairingStopped):
            return .pairingStopped

        case (.pairingMismatched, .pairingMismatchDetected):
            return .pairingMismatched
        case (.pairingMismatched, .pairingMismatchResolved):
            return .pairingCompleted
        case (.pairingMismatched, .pairingExpired):
            return .pairingExpired
        case (.pairingMismatched, .pairingStopped):
            return .pairingStopped
        case (.pairingMismatched, .pairingFailed), (.pairingMismatched, .pairingStarted):
            return .pendingPairing

        case (.pairingCompleted, .pairingAccepted):
            return .pairingCompleted
        case (.pairingCompleted, .pairingStopped):
            return .pairingStopped
        case (.pairingCompleted, .transferStarted):
            return .transferInProgress
        case (.pairingCompleted, .pairingFailed):
            return .pendingPairing

        case (.pairingExpired, .pairingExpired):
            return .pairingExpired
        case (.pairingExpired, .pairingAccepted):
            return .pairingCompleted
        case (.pairingExpired, .pairingMismatchDetected):
            return .pairingMismatched
        case (.pairingExpired, .pairingStopped):
            return .pairingStopped
        case (.pairingExpired, .pairingStarted), (.pairingExpired, .pairingFailed):
            return .pendingPairing

        case (.pairingStopped, .pairingStopped):
            return .pairingStopped
        case (.pairingStopped, .pairingAccepted):
            return .pairingCompleted
        case (.pairingStopped, .pairingStarted), (.pairingStopped, .pairingFailed):
            return .pendingPairing

        case (.transferInProgress, .transferStarted):
            return .transferInProgress
        case (.transferInProgress, .transferStopped):
            return .transferStopped
        case (.transferInProgress, .transferCompleted):
            return .transferCompleted
        case (.transferInProgress, .transferFailed):
            return .transferFailed

        case (.transferStopped, .transferStarted),
             (.transferCompleted, .transferStarted),
             (.transferFailed, .transferStarted):
            return .transferInProgress

        case (.transferStopped, .pairingAccepted),
             (.transferCompleted, .pairingAccepted),
             (.transferFailed, .pairingAccepted):
            return .pairingCompleted

        case (.transferStopped, .pairingStarted),
             (.transferCompleted, .pairingStarted),
             (.transferFailed, .pairingStarted):
            return .pendingPairing

        default:
            return state
        }
    }
}
