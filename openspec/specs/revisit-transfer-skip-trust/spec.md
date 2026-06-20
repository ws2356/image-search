## ADDED Requirements

### Requirement: Revisit transfer skips trust handshake via direct mTLS
When the mobile (iOS) has a stored X.509 peer certificate for a discovered PC (matched by the PC's certificate public key hash extracted during the TLS handshake), the mobile SHALL skip the trust handshake and SHALL send the instant-share payload directly via HTTPS with mTLS. The peer certificate lookup SHALL be by public key hash, not by `device_id`.

#### Scenario: Direct transfer when stored peer cert exists by pubkey hash match
- **WHEN** iOS has a stored X.509 peer certificate whose public key hash matches the server certificate's public key hash
- **THEN** iOS SHALL connect directly to the PC's `tls_port` via HTTPS with mTLS and POST the payload
- **AND** iOS SHALL NOT call `/trust/handshake`, `/trust/apply`, or `/trust/confirm`

#### Scenario: No stored cert for pubkey hash falls back to trust handshake
- **WHEN** iOS discovers a PC but has no stored peer certificate matching the server's public key hash
- **THEN** iOS SHALL proceed to the full trust handshake flow

#### Scenario: Revisit attempt on device selection uses pubkey hash lookup
- **WHEN** user selects a PC from the device list
- **THEN** iOS SHALL extract the server certificate during TLS handshake, compute its public key hash
- **AND** iOS SHALL query `peerCertificate(forPubkeyHash:)` with that hash
- **AND** if a match is found, iOS SHALL attempt the revisit flow

### Requirement: Fallback to full trust handshake on TLS failure
If the mTLS connection fails during a revisit attempt (TLS handshake failure because the PC doesn't trust the mobile's client cert), the mobile SHALL fall back to the existing full trust handshake flow. On completion of the fallback trust handshake, the mobile SHALL update its stored X.509 certificate for the PC.

#### Scenario: TLS handshake fails during revisit
- **WHEN** mobile attempts an mTLS connection to the PC's TLS server for a revisit transfer and the TLS handshake fails (the PC's SSL layer rejects the mobile's client cert because it is not in the trusted CA bundle)
- **THEN** mobile SHALL initiate the full trust handshake flow: `/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`
- **AND** mobile SHALL NOT treat this as a fatal error

#### Scenario: Transfer endpoint returns busy during revisit
- **WHEN** mobile successfully establishes an mTLS connection but the PC returns HTTP 409 (RECEIVER_BUSY — another session is active)
- **THEN** mobile SHALL fall back to the full trust handshake flow or retry after a delay

#### Scenario: Certificates refreshed after fallback trust
- **WHEN** mobile completes the fallback trust handshake successfully
- **THEN** mobile SHALL replace the stored X.509 certificate for the PC's `device_id` with the newly exchanged value

### Requirement: Revisit attempt on device selection
When the user selects a PC from the discovered device list, the mobile SHALL first attempt the revisit flow (direct mTLS transfer) if a stored peer cert exists, before falling back to the trust handshake.

#### Scenario: User taps a previously-trusted PC
- **WHEN** user selects a PC from the device list for which the mobile has a stored X.509 certificate
- **THEN** mobile SHALL attempt the revisit flow and only show the PIN entry UI if the revisit fails and the fallback trust handshake reaches the `/trust/apply` step

#### Scenario: User taps a new PC
- **WHEN** user selects a PC from the device list for which the mobile has no stored X.509 certificate
- **THEN** mobile SHALL proceed directly to the full trust handshake flow without attempting revisit

### Requirement: peerDeviceName in transfer requests
The mobile SHALL include a human-readable device name in revisit transfer requests so the PC can display which device is sharing.

#### Scenario: Revisit transfer includes peer device name
- **WHEN** mobile initiates a revisit transfer
- **THEN** mobile SHALL include the `X-Peer-Device-Name` header with a human-readable device name in the HTTP request