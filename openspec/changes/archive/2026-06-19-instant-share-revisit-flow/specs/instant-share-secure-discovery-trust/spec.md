## MODIFIED Requirements

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates. The PC SHALL include its X.509 certificate (`device_certificate_pem`) in the `/trust/confirm` encrypted response. The mobile SHALL include its X.509 certificate (`device_certificate_pem`) in the `/trust/confirm` encrypted request body. Both sides SHALL persist the exchanged X509 certificates for future mTLS-based revisit. The mobile SHALL also include `peer_device_name` in the `/trust/confirm` encrypted request body.

#### Scenario: Trust material persisted after first sharing
- **WHEN** first-share trust establishment completes successfully
- **THEN** both devices SHALL persist the exchanged X509 public certificates for future mTLS trust
- **AND** the stored material SHALL be keyed by the peer's `device_id` (derived from the certificate's CN)
- **AND** the mobile SHALL include `peer_device_name` in the encrypted `/trust/confirm` request

### Requirement: Direct mTLS for future sharing via certificate-based identity
For subsequent shares, the mobile SHALL derive the PC's `device_id` from the PC's TLS certificate CN during the mTLS handshake. If the mobile has a stored peer certificate for this `device_id`, it SHALL send the instant-share payload directly to the PC via HTTPS with mTLS using the stored X.509 certificates, skipping the trust handshake entirely. If the TLS handshake fails (the PC does not trust the mobile's client cert), the mobile SHALL fall back to the full trust handshake flow. The mDNS `signature` field is NOT used for revisit identity verification.

#### Scenario: Direct mTLS transfer for previously-trusted peer
- **WHEN** mobile connects to a PC via mTLS and extracts the PC's `device_id` from the TLS certificate CN
- **AND** the mobile has a stored X.509 peer certificate for this `device_id`
- **THEN** mobile SHALL send the instant-share payload directly to that PC via HTTPS with mTLS without repeating the trust handshake
- **AND** mobile SHALL include `X-Peer-Device-Name` header in the transfer request

#### Scenario: Trust handshake skipped for revisit
- **WHEN** mobile has a stored cert for a previously-trusted PC and the mTLS connection succeeds
- **THEN** the system SHALL skip the `/trust/handshake`, `/trust/apply`, and `/trust/confirm` steps and proceed directly to `/transfer/xxx` via mTLS

#### Scenario: TLS handshake failure falls back to full trust handshake
- **WHEN** mobile attempts an mTLS connection to a PC but the TLS handshake fails (the PC's SSL layer rejects the mobile's client certificate)
- **THEN** mobile SHALL initiate the full trust handshake flow and SHALL update stored certificates upon successful completion of the fallback

#### Scenario: No stored cert falls back to trust handshake
- **WHEN** mobile discovers a PC but has no stored X.509 peer certificate for the extracted `device_id`
- **THEN** mobile SHALL proceed directly to the full trust handshake flow without attempting mTLS transfer

#### Scenario: mDNS discovery provides connectivity only
- **WHEN** mobile discovers PCs via mDNS
- **THEN** mDNS SHALL provide connectivity information only (hostname/IP + `tls_port`)
- **AND** device identity SHALL be derived from the TLS certificate CN during the mTLS handshake, not from mDNS TXT record fields
