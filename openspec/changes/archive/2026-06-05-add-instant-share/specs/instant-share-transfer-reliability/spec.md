## ADDED Requirements

### Requirement: Authenticated instant-share negotiation
The system SHALL negotiate instant-share sessions only over authenticated paired-device channels and SHALL reject unauthenticated session attempts.

#### Scenario: Reject unpaired sender
- **WHEN** a sender without valid pairing credentials initiates an instant-share request
- **THEN** the receiver rejects negotiation and returns an authentication failure result

### Requirement: Bounded retry and timeout policy
The system SHALL apply bounded retry with exponential backoff for transient negotiation/transfer failures and SHALL terminate with timeout status after configured retry limits are exhausted.

#### Scenario: Recover from transient connection failure
- **WHEN** initial transfer connection attempt fails due to a transient network error
- **THEN** the system retries within configured limits and completes transfer if a retry succeeds

#### Scenario: Exhaust retries
- **WHEN** all configured retries are exhausted without successful transfer
- **THEN** the system marks the session as timed-out or failed and shows a clear failure state to the user

### Requirement: Single active instant-share session
The system SHALL support only one active instant-share session at a time on the receiver side and SHALL reject or defer additional incoming session requests while a session is in progress.

#### Scenario: Reject concurrent incoming session
- **WHEN** a second instant-share request arrives while an active instant-share session is transferring or delivering
- **THEN** the receiver returns a busy/deferred response and does not start a concurrent session

### Requirement: No size-based rejection and user-controlled abort
The system SHALL NOT reject instant-share transfers based on payload file size and SHALL provide the sender user with explicit controls to keep waiting or abort long-running transfers.

#### Scenario: Large file keeps transferring
- **WHEN** a large payload transfer takes longer than typical transfer duration
- **THEN** the system continues transfer and shows user controls to keep waiting or abort

#### Scenario: User aborts long transfer
- **WHEN** the sender chooses to abort an in-progress transfer
- **THEN** the system terminates the active session and reports a user-aborted outcome on both sides

### Requirement: Correlated end-to-end status reporting
The system SHALL assign a correlation identifier per instant-share session and SHALL include it across negotiation, transfer, delivery, and telemetry events.

#### Scenario: Correlation across lifecycle
- **WHEN** an instant-share session progresses from queued to completion
- **THEN** all lifecycle records and telemetry events include the same correlation identifier
