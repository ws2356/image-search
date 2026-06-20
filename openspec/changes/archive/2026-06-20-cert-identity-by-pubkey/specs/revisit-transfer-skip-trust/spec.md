## MODIFIED Requirements

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
