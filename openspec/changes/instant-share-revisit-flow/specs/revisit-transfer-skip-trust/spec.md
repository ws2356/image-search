## ADDED Requirements

### Requirement: Revisit transfer skips trust handshake on verified signature
When the mobile verifies a PC's mDNS Ed25519 signature successfully, the mobile SHALL skip the trust handshake (`/trust/handshake`, `/trust/apply`, `/trust/confirm`) and SHALL send the instant-share payload directly via HTTPS with mTLS to the PC's TLS port (from mDNS `tls_port`).

#### Scenario: Direct transfer after successful signature verification
- **WHEN** mobile successfully verifies the mDNS signature for a previously-trusted PC
- **THEN** mobile SHALL connect directly to the PC's `tls_port` via HTTPS with its own X.509 client certificate and POST the payload to `/transfer/text` or `/transfer/image`
- **AND** mobile SHALL NOT call `/trust/handshake`, `/trust/apply`, or `/trust/confirm`

#### Scenario: Revisit transfer generates fresh session ID
- **WHEN** mobile initiates a revisit transfer to a verified PC
- **THEN** mobile SHALL generate a new UUID v4 `X-Session-Id` header and SHALL set `X-Device-Id` to its own device_id

### Requirement: Fallback to full trust handshake on mTLS failure
If the mTLS connection or transfer request fails during a revisit attempt, the mobile SHALL fall back to the existing full trust handshake flow. On completion of the fallback trust handshake, the mobile SHALL update its stored X.509 certificate and Ed25519 public key for the PC.

#### Scenario: mTLS connection fails during revisit
- **WHEN** mobile attempts to connect to the PC's TLS server for a revisit transfer and the TLS handshake fails (e.g., cert verification error, connection refused)
- **THEN** mobile SHALL initiate the full trust handshake flow: `/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`

#### Scenario: Transfer endpoint returns error during revisit
- **WHEN** mobile successfully establishes an mTLS connection but the `/transfer/xxx` endpoint returns an HTTP error (4xx or 5xx)
- **THEN** mobile SHALL fall back to the full trust handshake flow

#### Scenario: Certificates refreshed after fallback trust
- **WHEN** mobile completes the fallback trust handshake successfully
- **THEN** mobile SHALL replace the stored X.509 certificate and Ed25519 public key for the PC's `device_id` with the newly exchanged values

### Requirement: Revisit attempt on mDNS candidate selection
When the user selects a candidate PC from the mDNS-discovered device list, the mobile SHALL first attempt the revisit flow (signature verification + direct mTLS transfer) before falling back to the trust handshake.

#### Scenario: User taps a previously-trusted PC
- **WHEN** user selects a PC from the device list that has a stored Ed25519 public key and X.509 certificate
- **THEN** mobile SHALL attempt the revisit flow and only show the PIN entry UI if the revisit fails and the fallback trust handshake reaches the `/trust/apply` step

#### Scenario: User taps a new PC
- **WHEN** user selects a PC from the device list that has no stored Ed25519 public key
- **THEN** mobile SHALL proceed directly to the full trust handshake flow without attempting revisit
