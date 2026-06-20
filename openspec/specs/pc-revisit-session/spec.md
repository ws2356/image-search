## ADDED Requirements

### Requirement: On-the-fly session creation for revisit transfers
When a transfer request arrives at `/transfer/text`, `/transfer/image`, or `/transfer/download` via mTLS and no active trust session matches the `X-Session-Id` header, the PC SHALL create a session on-the-fly if the client certificate's CN matches a previously-trusted peer certificate's device name in the keychain. The session SHALL be initialized with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`.

#### Scenario: Revisit transfer with trusted mTLS client cert
- **WHEN** a POST request arrives at a transfer endpoint via mTLS with no matching active trust session
- **AND** the TLS client certificate is valid and has been previously stored via `store_peer_certificate`
- **THEN** the PC SHALL create a new `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`

### Requirement: Client certificate CN extraction for revisit peer device name
The PC SHALL extract the client certificate's Common Name (CN) from the TLS connection scope for UI display as `peer_device_name`. Since CN now stores the human-readable device name, no separate extraction step is needed.

#### Scenario: Extract peer device name from CN
- **WHEN** a request arrives at a TLS transfer endpoint with a valid client certificate
- **THEN** the PC SHALL extract the CN from the peer certificate and use it as the `peer_device_name` for session UI display

### Requirement: peerDeviceName in transfer requests
The mobile SHALL include a human-readable device name in transfer requests. The PC SHALL use the `X-Peer-Device-Name` header if present, with fallback to the client certificate's CN value.

#### Scenario: Peer device name from header or CN
- **WHEN** a transfer request arrives with `X-Peer-Device-Name` header
- **THEN** the PC SHALL use it as the device name for UI display
- **AND** if the header is absent, the PC SHALL use the client certificate's CN value as fallback

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
The orchestrator SHALL publish lifecycle events for revisit sessions starting from state `TRANSFERRING` (skipping `BOOTSTRAPPED`, `QUEUED`, and `NEGOTIATING`). The lifecycle event SHALL include `device_name` and `session_id` for the mini-window to display. The mini-window SHALL display transfer progress for revisit sessions identically to first-share sessions.

#### Scenario: Revisit session lifecycle event published with device name
- **WHEN** an on-the-fly revisit session is created with state `TRANSFERRING`
- **THEN** the orchestrator SHALL publish a lifecycle event with `session_id`, state `TRANSFERRING`, the session details, and `device_name` populated from the peer device name
- **AND** the mini-window SHALL render the transfer progress UI showing the correct device name for the correct session

#### Scenario: Multi-session lifecycle events
- **WHEN** a revisit session and a first-share trust session are both active
- **THEN** the orchestrator SHALL publish independent lifecycle events for each session
- **AND** each event SHALL carry the correct `session_id`