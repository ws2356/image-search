## ADDED Requirements

### Requirement: Orchestrator drives multiple concurrent session lifecycles
The `InstantShareReceiverOrchestrator` SHALL support driving multiple independent session lifecycles concurrently, with each session identified by its `session_id`.

#### Scenario: Independent state transitions for each session
- **WHEN** session A receives a transfer and transitions to `TRANSFERRING`
- **AND** session B is still in `NEGOTIATING`
- **THEN** the orchestrator SHALL drive each session's lifecycle independently
- **AND** session B's state SHALL NOT be affected by session A's transition

#### Scenario: Concurrent delivery processing
- **WHEN** session A and session B both reach `DELIVERING` state at overlapping times
- **THEN** the orchestrator SHALL process both deliveries concurrently
- **AND** each session's delivery SHALL complete independently

### Requirement: Per-session lifecycle events
The orchestrator SHALL publish lifecycle events to the event bus with the `session_id` included in the payload, enabling consumers (mini-window, telemetry) to distinguish events from different sessions.

#### Scenario: Lifecycle event includes session_id
- **WHEN** the orchestrator publishes a lifecycle event for session `aaa` transitioning to `TRANSFERRING`
- **THEN** the event payload SHALL include `session_id: "aaa"`
- **AND** the event payload SHALL include the session's `device_name` and `connection_config`

#### Scenario: Concurrent lifecycle events from different sessions
- **WHEN** session A transitions to `DELIVERING` and session B transitions to `TRANSFERRING` within 100ms
- **THEN** the orchestrator SHALL publish two distinct lifecycle events
- **AND** each event SHALL carry the correct `session_id`

### Requirement: Session lifecycle timeout per session
The orchestrator SHALL maintain independent timeout tracking for each session. A timeout in session A SHALL NOT affect session B.

#### Scenario: Independent timeout per session
- **WHEN** session A times out in `NEGOTIATING` state after 120s
- **AND** session B is also in `NEGOTIATING` but started 30s later
- **THEN** session A SHALL transition to `TIMED_OUT`
- **AND** session B SHALL remain in `NEGOTIATING` until its own 120s expires

### Requirement: Session completion cleanup
When a session reaches a terminal state, the orchestrator SHALL clean up session-specific resources (timers, file handles) for that session without affecting other active sessions.

#### Scenario: Cleanup of one completed session
- **WHEN** session A completes with state `DONE`
- **AND** session B is still `TRANSFERRING`
- **THEN** the orchestrator SHALL clean up session A's resources (timers, temp files)
- **AND** session B's resources SHALL remain intact

### Requirement: Revisit session creation coexists with active trust sessions
The orchestrator's `handle_connection_config()` method SHALL create an on-the-fly session for revisit transfers even when other trust-handshake sessions are active. It SHALL NOT replace or interfere with existing sessions.

#### Scenario: Revisit during active trust handshake
- **WHEN** session A is in `NEGOTIATING` (trust handshake in progress for device X)
- **AND** a revisit transfer arrives from device Y (previously trusted)
- **THEN** the orchestrator SHALL create session B with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`
- **AND** session A SHALL continue its trust handshake unaffected
