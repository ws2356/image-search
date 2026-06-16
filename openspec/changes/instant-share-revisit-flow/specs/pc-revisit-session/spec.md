## ADDED Requirements

### Requirement: On-the-fly session creation for revisit transfers
When a transfer request arrives at `/transfer/text`, `/transfer/image`, or `/transfer/download` via mTLS and no active session matches the `X-Session-Id` header, the PC SHALL create a session on-the-fly if the client certificate matches a previously-trusted peer. The session SHALL be initialized with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`.

#### Scenario: Revisit transfer with trusted mTLS client cert
- **WHEN** a POST request arrives at `/transfer/text` or `/transfer/image` via mTLS with no matching active session
- **AND** the TLS client certificate's CN matches a stored peer certificate in the keychain
- **THEN** the PC SHALL create a new `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`, and the payload metadata from request headers
- **AND** the PC SHALL process the transfer and deliver the payload normally

#### Scenario: Revisit transfer from unknown mTLS client cert
- **WHEN** a POST request arrives at `/transfer/xxx` via mTLS with no matching active session
- **AND** the TLS client certificate's CN does not match any stored peer certificate
- **THEN** the PC SHALL return HTTP 403 with error code `TRUST_REQUIRED`

#### Scenario: Revisit transfer when another session is active
- **WHEN** a revisit transfer request arrives and an active session already exists for a different device
- **THEN** the PC SHALL return HTTP 409 with error code `RECEIVER_BUSY_SINGLE_SESSION`

### Requirement: Session metadata extraction from revisit request headers
For on-the-fly sessions created during revisit, the PC SHALL derive the session metadata (`payload_class`, `target_intent`) from the transfer request rather than from a prior bootstrap message. The `flow_id` SHALL be `instant_share` and `trust_mode` SHALL be `trusted_direct`.

#### Scenario: Text transfer revisit session metadata
- **WHEN** a revisit transfer request arrives at `/transfer/text`
- **THEN** the on-the-fly session SHALL have `payload_class=TEXT` and `target_intent=CLIPBOARD_ONLY`

#### Scenario: Image transfer revisit session metadata
- **WHEN** a revisit transfer request arrives at `/transfer/image`
- **THEN** the on-the-fly session SHALL have `payload_class=IMAGE` and `target_intent=CLIPBOARD_OR_FILE`

### Requirement: Client certificate CN extraction for revisit identity
The PC SHALL extract the client certificate's Common Name (CN) from the TLS connection and SHALL use it as the mobile `device_id` for peer certificate lookup and session identification.

#### Scenario: Extract device_id from TLS client cert CN
- **WHEN** a request arrives at a TLS transfer endpoint
- **THEN** the PC SHALL extract the CN from the peer certificate presented during the TLS handshake
- **AND** the PC SHALL use this CN value as the mobile's `device_id` to look up the stored peer certificate in the keychain

### Requirement: Revisit session lifecycle events
The orchestrator SHALL publish lifecycle events for revisit sessions starting from state `TRANSFERRING` (skipping `BOOTSTRAPPED`, `QUEUED`, and `NEGOTIATING`). The mini-window SHALL display transfer progress for revisit sessions identically to first-share sessions.

#### Scenario: Revisit session lifecycle event published
- **WHEN** an on-the-fly revisit session is created with state `TRANSFERRING`
- **THEN** the orchestrator SHALL publish a lifecycle event with state `TRANSFERRING` and the session details
- **AND** the mini-window SHALL render the transfer progress UI
