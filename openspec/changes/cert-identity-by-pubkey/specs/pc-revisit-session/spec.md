## MODIFIED Requirements

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
