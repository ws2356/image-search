## ADDED Requirements

### Requirement: Independent mini-window per session
Each active instant share session SHALL run in its own independent mini-window. A session SHALL be either pc-to-mobile (QR stash) or mobile-to-pc (trust handshake + mTLS transfer). Each mini-window SHALL display exactly one session's details and progress.

#### Scenario: Single session gets its own window
- **WHEN** a mobile-to-pc session is bootstrapped (trust handshake begins)
- **THEN** a new mini-window SHALL open displaying that session's device name and state
- **AND** no other mini-window is affected

#### Scenario: Multiple sessions get independent windows
- **WHEN** session A (mobile-to-pc) is transferring and session B (pc-to-mobile QR stash) is created
- **THEN** session A's mini-window SHALL continue showing transfer progress
- **AND** a separate new mini-window SHALL open for session B showing the QR code and opt-code
- **AND** the two windows SHALL be draggable and positionable independently

#### Scenario: Same-direction concurrent sessions
- **WHEN** two mobile devices each initiate trust handshakes
- **THEN** two independent mini-windows SHALL open, one per device
- **AND** each window SHALL display the correct device name and state

### Requirement: Session status indicators per window
Each mini-window SHALL display a status indicator reflecting its session's current state: spinner (connecting), lock icon (negotiating), progress bar (transferring), checkmark (delivered), red X (error). The window title SHALL indicate the session direction and device name.

#### Scenario: Connecting state (mobile-to-pc)
- **WHEN** a mobile-to-pc session is in `BOOTSTRAPPED` or `QUEUED` state
- **THEN** its mini-window SHALL show a spinning indicator with text "Connecting..." and the peer device name
- **AND** the window title SHALL be formatted as "Receiving from <device_name>"

#### Scenario: Transferring state (mobile-to-pc)
- **WHEN** a mobile-to-pc session is in `TRANSFERRING` state
- **THEN** its mini-window SHALL show a progress bar with transfer percentage and the peer device name

#### Scenario: QR stash state (pc-to-mobile)
- **WHEN** a pc-to-mobile session (QR stash) is active
- **THEN** its mini-window SHALL display the QR code prominently, the opt-code as fallback text, and "Scan with AuBackup" instructions
- **AND** the window title SHALL be formatted as "Sending to Phone"

#### Scenario: Completed state
- **WHEN** a session reaches `DONE` state
- **THEN** its mini-window SHALL show a green checkmark with text "Delivered" and the device name
- **AND** the window SHALL auto-close after 4 seconds

#### Scenario: Error state
- **WHEN** a session reaches `FAILED` state
- **THEN** its mini-window SHALL show a red X with the error description and the device name
- **AND** the window SHALL auto-close after 10 seconds

#### Scenario: Cancelled state (pc-to-mobile)
- **WHEN** the user clicks "Cancel" on a QR stash mini-window
- **THEN** the stash SHALL be invalidated and the window SHALL close immediately

### Requirement: Per-window lifecycle
Each mini-window's lifecycle SHALL be tied to its session: the window opens when the session is created and closes when the session reaches a terminal state.

#### Scenario: Window opens on session creation
- **WHEN** a new session is bootstrapped (either pc-to-mobile or mobile-to-pc)
- **THEN** a corresponding mini-window SHALL be created and displayed

#### Scenario: Window closes on terminal state
- **WHEN** a session reaches `DONE`, `FAILED`, `TIMED_OUT`, or `ABORTED`
- **THEN** its mini-window SHALL show the terminal state briefly and auto-close (4s for success, 10s for error)
- **AND** other sessions' mini-windows SHALL be unaffected

#### Scenario: Window closes on user cancel (pc-to-mobile)
- **WHEN** the user clicks "Cancel" on a pc-to-mobile (QR stash) mini-window
- **THEN** the window SHALL close immediately
- **AND** the underlying stash SHALL be invalidated

### Requirement: Lifecycle event routing to correct window
The orchestrator SHALL publish lifecycle events with `session_id`, and each mini-window SHALL subscribe to events and update only when the event's `session_id` matches its own.

#### Scenario: Event routed to correct window
- **WHEN** session A transitions to `TRANSFERRING` and the orchestrator publishes an event with `session_id: aaa`
- **THEN** only the mini-window associated with `session_id: aaa` SHALL update its display
- **AND** session B's mini-window SHALL remain unchanged

#### Scenario: Window ignores events from other sessions
- **WHEN** a mini-window for session B receives a lifecycle event with `session_id: aaa`
- **THEN** the mini-window SHALL ignore the event
