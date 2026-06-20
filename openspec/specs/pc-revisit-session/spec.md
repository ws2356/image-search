## Purpose
Enable previously-trusted mobile devices to skip the PIN-based trust handshake and transfer data directly via mTLS, with on-the-fly session creation for unsolicited transfers from known devices.
## Requirements
### Requirement: On-the-fly session creation for revisit transfers
When a transfer request arrives via mTLS and no active trust session matches the `X-Session-Id` header, the PC SHALL create a session on-the-fly. For batch transfers, the first image's request creates the session; subsequent images reuse it.

#### Scenario: Revisit batch transfer session created on first image
- **WHEN** the first `/transfer/image` request of a revisit batch arrives
- **THEN** the PC SHALL create an on-the-fly session with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`
- **AND** subsequent `/transfer/image` requests with the same `X-Session-Id` SHALL reuse the session

#### Scenario: Revisit batch delivery complete after all images
- **WHEN** the final image of a revisit batch arrives
- **THEN** the PC SHALL transition to `DELIVERING` → `DONE`
- **AND** `handle_delivery_complete()` SHALL only be called after the last image

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
The orchestrator SHALL publish lifecycle events for revisit sessions. For batch transfers, lifecycle events SHALL include `image_count` and `received_count`.

#### Scenario: Batch revisit lifecycle event
- **WHEN** a revisit batch session has 3 expected images and 2 received
- **THEN** the lifecycle event SHALL include `image_count: 3` and `received_count: 2`
- **AND** the mini-window SHALL display appropriate batch progress

