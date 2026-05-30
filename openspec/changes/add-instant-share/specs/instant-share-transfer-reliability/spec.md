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

### Requirement: Correlated end-to-end status reporting
The system SHALL assign a correlation identifier per instant-share session and SHALL include it across negotiation, transfer, delivery, and telemetry events.

#### Scenario: Correlation across lifecycle
- **WHEN** an instant-share session progresses from queued to completion
- **THEN** all lifecycle records and telemetry events include the same correlation identifier
