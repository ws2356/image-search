## MODIFIED Requirements

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates and Ed25519 public keys. The PC SHALL include its Ed25519 public key (`ed25519_public_key_pem`) in the `/trust/confirm` encrypted response alongside its X.509 certificate (`device_certificate_pem`). Both sides SHALL persist the exchanged X509 certificates and Ed25519 public keys for future TLS trust decisions and mDNS signature verification.

#### Scenario: Trust material persisted after first sharing
- **WHEN** first-share trust establishment completes successfully
- **THEN** both devices SHALL persist the exchanged X509 public certificates and Ed25519 public keys for future TLS trust and mDNS signature verification
- **AND** the stored material SHALL be keyed by the peer's `device_id`

### Requirement: Signed mDNS advertisement verification and pinned direct HTTPS for future sharing
For subsequent shares, the mobile SHALL verify the Ed25519 `signature` in the PC's mDNS TXT record against the previously-stored Ed25519 public key for that `device_id`. The signed message SHALL be `"{device_id}:{timestamp_ms}"` encoded as UTF-8. If verification succeeds, the mobile SHALL send the instant-share payload directly to the PC via HTTPS with mTLS using the stored X.509 certificates, skipping the trust handshake entirely. If verification or mTLS fails, the mobile SHALL fall back to the full trust handshake flow.

#### Scenario: Verified signed advertisement enables direct share
- **WHEN** mobile verifies the Ed25519 `signature` from the PC's mDNS TXT record against the stored Ed25519 public key for that `device_id`
- **AND** the signature timestamp is within 300 seconds of the mobile's current time
- **THEN** mobile SHALL send the instant-share payload directly to that PC via HTTPS with mTLS without repeating the trust handshake

#### Scenario: Trust handshake skipped for verified revisit
- **WHEN** mobile verifies the PC's mDNS signature for an existing trust relationship
- **THEN** the system SHALL skip the `/trust/handshake`, `/trust/apply`, and `/trust/confirm` steps and proceed directly to `/transfer/xxx` via mTLS

#### Scenario: mTLS failure falls back to full trust handshake
- **WHEN** mobile verifies the mDNS signature successfully but the subsequent mTLS connection or transfer request fails
- **THEN** mobile SHALL initiate the full trust handshake flow and SHALL update stored certificates and keys upon successful completion of the fallback

#### Scenario: Signature verification fails falls back to trust handshake
- **WHEN** mobile cannot verify the PC's mDNS TXT `signature` (no stored Ed25519 key, wrong key, or stale timestamp)
- **THEN** mobile SHALL fall back to the full trust handshake flow for that PC
