## ADDED Requirements

### Requirement: Multi-session registry with session-id-keyed collection
The `InstantShareSessionRegistry` SHALL maintain a collection of active sessions keyed by `session_id` instead of a single `_active_session` slot. All existing methods SHALL route operations by `session_id`.

#### Scenario: Concurrent sessions created independently
- **WHEN** session A is in state `TRANSFERRING` with `session_id` `aaa`
- **AND** a new `bootstrap()` call arrives for a different mobile device
- **THEN** the registry SHALL create session B with a new `session_id` `bbb`
- **AND** session A SHALL remain unchanged with state `TRANSFERRING`

#### Scenario: Same session_id re-bootstrap is idempotent
- **WHEN** `bootstrap()` is called with a `connection_config` whose `session_id` already exists in the registry
- **THEN** the registry SHALL return the existing session without raising an error
- **AND** the existing session's state SHALL NOT be changed

#### Scenario: Terminal session pruned on next bootstrap
- **WHEN** session A is in terminal state `DONE`
- **AND** `bootstrap()` is called for a new session B
- **THEN** session A SHALL remain in the registry until a TTL-based cleanup removes it
- **AND** session B SHALL be created independently

### Requirement: Thread-safe concurrent session access
The registry SHALL use `threading.RLock()` to protect all methods and SHALL support concurrent reads and writes across different `session_id` values.

#### Scenario: Concurrent transitions on different sessions
- **WHEN** thread 1 calls `transition(session_a_id, DELIVERING)` and thread 2 calls `transition(session_b_id, TRANSFERRING)` concurrently
- **THEN** both transitions SHALL succeed without race conditions
- **AND** each session's state SHALL be correctly updated

#### Scenario: Concurrent operations on same session
- **WHEN** two threads call `transition()` on the same `session_id` concurrently
- **THEN** exactly one SHALL succeed and the other SHALL raise an appropriate error (invalid transition or session not found)

### Requirement: Configurable session capacity limit
The registry SHALL enforce a maximum number of concurrent active (non-terminal) sessions, configurable via a parameter with a default of 8. Attempting to `bootstrap()` beyond capacity SHALL raise a retryable error with code `RECEIVER_BUSY_MAX_SESSIONS`.

#### Scenario: Session limit reached
- **WHEN** 8 sessions are already in active (non-terminal) states
- **AND** a new `bootstrap()` call arrives
- **THEN** the registry SHALL raise `InstantShareError` with `ErrorCode.RECEIVER_BUSY_MAX_SESSIONS` and a retryable flag
- **THEN** the HTTP layer SHALL return `503` to the client

#### Scenario: Session limit frees on terminal state
- **WHEN** 8 sessions are active and one transitions to `DONE`
- **AND** a new `bootstrap()` call arrives
- **THEN** the registry SHALL allow the new session

### Requirement: Session lookup by session_id
The registry SHALL provide a `get_active_sessions()` method that returns all sessions currently in non-terminal states, and a `get_session(session_id)` method for direct lookup.

#### Scenario: List active sessions
- **WHEN** `get_active_sessions()` is called with 3 sessions in `TRANSFERRING`, `DONE`, and `BOOTSTRAPPED`
- **THEN** the result SHALL include only the `TRANSFERRING` and `BOOTSTRAPPED` sessions
- **THE** `DONE` session SHALL be excluded

#### Scenario: Lookup non-existent session
- **WHEN** `get_session(nonexistent_id)` is called
- **THEN** it SHALL return `None`

### Requirement: Remove RECEIVER_BUSY_SINGLE_SESSION error
The `ErrorCode.RECEIVER_BUSY_SINGLE_SESSION` SHALL be removed from the `ErrorCode` enum. All code paths that raised it SHALL be updated to instead create new sessions or route to existing ones.

#### Scenario: No single-session rejection on bootstrap
- **WHEN** `bootstrap()` is called while another session is `TRANSFERRING`
- **THEN** the registry SHALL NOT raise `RECEIVER_BUSY_SINGLE_SESSION`
- **AND** a new session SHALL be created

### Requirement: Stale terminal session cleanup
The registry SHALL remove sessions in terminal states (`DONE`, `FAILED`, `TIMED_OUT`, `ABORTED`) after a configurable TTL (default 60 seconds) to prevent memory leaks.

#### Scenario: Terminal session cleaned up after TTL
- **WHEN** session A transitions to `DONE`
- **THEN** after 60 seconds the session SHALL be removed from the registry
- **AND** memory SHALL be freed

#### Scenario: Non-terminal session not cleaned
- **WHEN** a session is in state `TRANSFERRING` for over 60 seconds
- **THEN** the session SHALL NOT be removed by the cleanup mechanism
