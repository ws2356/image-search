## MODIFIED Requirements

### Requirement: On-the-fly session creation for revisit transfers
When a transfer request arrives at `/transfer/text`, `/transfer/image`, or `/transfer/download` via mTLS and no active trust session matches the `X-Session-Id` header, the PC SHALL create a session on-the-fly if the client certificate's CN matches a previously-trusted peer certificate in the keychain. The session SHALL be initialized with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`. This session SHALL coexist with any other active sessions.

#### Scenario: Revisit transfer with trusted mTLS client cert
- **WHEN** a POST request arrives at `/transfer/text` or `/transfer/image` via mTLS with no matching active trust session
- **AND** the TLS client certificate's CN matches a stored peer certificate in the keychain (verified via `load_peer_certificate()`)
- **THEN** the PC SHALL create a new `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`, and the payload metadata derived from the endpoint
- **AND** the PC SHALL process the transfer and deliver the payload normally

#### Scenario: Revisit transfer from unknown mTLS client cert
- **WHEN** a TLS handshake is attempted but the client's certificate is not in the trusted CA bundle
- **THEN** the TLS handshake SHALL fail at the SSL layer — the PC SHALL NOT receive an HTTP request and SHALL NOT return an HTTP error

#### Scenario: Revisit transfer when another session is active
- **WHEN** a revisit transfer request arrives and another active session already exists for a different device
- **THEN** the PC SHALL create a new session for the revisit transfer and process it normally
- **AND** the existing session SHALL continue unaffected

### Requirement: Revisit session lifecycle events
The orchestrator SHALL publish lifecycle events for revisit sessions starting from state `TRANSFERRING` (skipping `BOOTSTRAPPED`, `QUEUED`, and `NEGOTIATING`). The lifecycle event SHALL include `device_name` and `session_id` for the mini-window to display. The mini-window SHALL display transfer progress for revisit sessions identically to first-share sessions.

#### Scenario: Revisit session lifecycle event published with device name
- **WHEN** an on-the-fly revisit session is created with state `TRANSFERRING`
- **THEN** the orchestrator SHALL publish a lifecycle event with `session_id`, state `TRANSFERRING`, the session details, and `device_name` populated from the peer device name
- **AND** the mini-window SHALL render the transfer progress UI showing the correct device name for the correct session

#### Scenario: Multi-session lifecycle events
- **WHEN** a revisit session and a first-share trust session are both active
- **THEN** the orchestrator SHALL publish independent lifecycle events for each session
- **AND** each event SHALL carry the correct `session_id`
