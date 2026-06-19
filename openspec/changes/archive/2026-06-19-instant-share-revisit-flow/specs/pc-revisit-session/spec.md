## ADDED Requirements

### Requirement: On-the-fly session creation for revisit transfers
When a transfer request arrives at `/transfer/text`, `/transfer/image`, or `/transfer/download` via mTLS and no active trust session matches the `X-Session-Id` header, the PC SHALL create a session on-the-fly if the client certificate's CN matches a previously-trusted peer certificate in the keychain. The session SHALL be initialized with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`.

#### Scenario: Revisit transfer with trusted mTLS client cert
- **WHEN** a POST request arrives at `/transfer/text` or `/transfer/image` via mTLS with no matching active trust session
- **AND** the TLS client certificate's CN matches a stored peer certificate in the keychain (verified via `load_peer_certificate()`)
- **THEN** the PC SHALL create a new `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`, and the payload metadata derived from the endpoint
- **AND** the PC SHALL process the transfer and deliver the payload normally

#### Scenario: Revisit transfer from unknown mTLS client cert
- **WHEN** a TLS handshake is attempted but the client's certificate is not in the trusted CA bundle
- **THEN** the TLS handshake SHALL fail at the SSL layer — the PC SHALL NOT receive an HTTP request and SHALL NOT return an HTTP error

#### Scenario: Revisit transfer when another session is active
- **WHEN** a revisit transfer request arrives and an active session already exists for a different device
- **THEN** the PC SHALL return HTTP 409 with error code `RECEIVER_BUSY_SINGLE_SESSION`
- **AND** the mobile SHALL fall back to the trust handshake or retry

### Requirement: Client certificate CN extraction for revisit identity
The PC SHALL extract the client certificate's Common Name (CN) from the TLS connection scope and SHALL use it as the mobile `device_id` for peer certificate lookup and session identification. The TLS layer's existing certificate validation (signature, public key, expiry) SHALL remain intact.

#### Scenario: Extract device_id from TLS client cert CN
- **WHEN** a request arrives at a TLS transfer endpoint
- **THEN** the PC SHALL extract the CN from the peer certificate presented during the TLS handshake via the request scope
- **AND** the PC SHALL use this CN value as the mobile's `device_id` to look up the stored peer certificate in the keychain via `load_peer_certificate()`
- **AND** the TLS layer's existing cert validation (CA bundle verification, public key comparison) SHALL remain unchanged

### Requirement: Session metadata extraction from revisit request
For on-the-fly sessions created during revisit, the PC SHALL derive the session metadata (`payload_class`, `target_intent`) from the transfer endpoint being called. The `flow_id` SHALL be `instant_share` and `trust_mode` SHALL be `trusted_direct`. The `peer_device_name` SHALL be extracted from the `X-Peer-Device-Name` header.

#### Scenario: Text transfer revisit session metadata
- **WHEN** a revisit transfer request arrives at `/transfer/text`
- **THEN** the on-the-fly session SHALL have `payload_class=TEXT` and `target_intent=CLIPBOARD_ONLY`

#### Scenario: Image transfer revisit session metadata
- **WHEN** a revisit transfer request arrives at `/transfer/image`
- **THEN** the on-the-fly session SHALL have `payload_class=IMAGE` and `target_intent=CLIPBOARD_OR_FILE`

#### Scenario: peerDeviceName extracted from revisit request
- **WHEN** a revisit transfer request arrives with `X-Peer-Device-Name` header
- **THEN** the PC SHALL extract the device name and include it in the session for UI display

### Requirement: peerDeviceName in trust confirm for first visit
During the first-share trust handshake, the mobile SHALL include a human-readable device name in the `/trust/confirm` encrypted request body.

#### Scenario: First visit trust confirm includes peer device name
- **WHEN** mobile sends the encrypted `/trust/confirm` request
- **THEN** the decrypted body SHALL contain a `peer_device_name` field with a human-readable device name
- **AND** the PC SHALL store this name for UI display during the current session

### Requirement: Revisit session lifecycle events
The orchestrator SHALL publish lifecycle events for revisit sessions starting from state `TRANSFERRING` (skipping `BOOTSTRAPPED`, `QUEUED`, and `NEGOTIATING`). The lifecycle event SHALL include `device_name` for the mini-window to display. The mini-window SHALL display transfer progress for revisit sessions identically to first-share sessions.

#### Scenario: Revisit session lifecycle event published with device name
- **WHEN** an on-the-fly revisit session is created with state `TRANSFERRING`
- **THEN** the orchestrator SHALL publish a lifecycle event with state `TRANSFERRING`, the session details, and `device_name` populated from the peer device name
- **AND** the mini-window SHALL render the transfer progress UI showing the correct device name

#### Scenario: Mini-window displays peer device name for revisit
- **WHEN** the mini-window receives a lifecycle event for a revisit session
- **THEN** the mini-window SHALL display the `device_name` from the event (e.g., "Receiving shared item from John's iPhone...")
- **AND** if no device name is provided, the mini-window SHALL fall back to "your phone"
