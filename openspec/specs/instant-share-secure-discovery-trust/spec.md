## ADDED Requirements

### Requirement: mDNS candidate PC discovery before send
The mobile system SHALL discover PCs via mDNS (Bonjour) on the local network and SHALL maintain a user-selectable list of candidate PCs in the iOS Share Extension. No AuBackup handoff — extension handles the full flow natively.

#### Scenario: Candidate list population
- **WHEN** the sender opens instant-share target selection
- **THEN** the Share Extension presents a production device selector card populated with discovered candidate PCs from mDNS `_instantshare._tcp` service advertisements

### Requirement: mDNS TXT record contract
The desktop mDNS service SHALL advertise with service type `_instantshare._tcp` and SHALL include the following TXT records:
- `ver` (protocol version string, e.g. `1`)
- `device_name` (human-readable PC display name)
- `tls_port` (integer port number for TLS/HTTPS connections)

The advertised TCP port SHALL be the PC's instant-share HTTP API port. `tls_port` SHALL be the PC's instant-share HTTPS API port. No persistent device identifier SHALL be included in the advertisement.

#### Scenario: Mobile builds device list from mDNS TXT
- **WHEN** mobile resolves discovered mDNS services
- **THEN** the Share Extension uses `device_name` TXT values to render the candidate PC list and stores resolved IP, port, and `tls_port` for the trust flow

#### Scenario: Mobile calls trust handshake with bootstrap data
- **WHEN** the user has selected a PC and taps "Send" in the Share Extension
- **THEN** the Share Extension calls PC's `/api/instant-share/v1/trust/handshake` endpoint (using the IP:port from mDNS resolution) with DH key material plus bootstrap data (`mobile_port`, `mobile_ip_list`, `payload_class`, `target_intent`, `trust_mode`) embedded in the body. No separate bootstrap endpoint. No local HTTP server.

### Requirement: Discovered PC identity
The mobile system SHALL synthesize a unique identity for each discovered PC using the resolved `host:port` tuple. This identity SHALL be used for SwiftUI `Identifiable` conformance, list deduplication, and equality checks.

#### Scenario: PC identity from host:port
- **WHEN** mobile resolves an mDNS service to IP `192.168.1.5` and port `9527`
- **THEN** the discovered PC's identity SHALL be `"192.168.1.5:9527"`
- **THEN** this identity SHALL be stable for the duration of the browsing session
- **THEN** two resolved services at the same `host:port` SHALL be treated as the same PC

#### Scenario: PC identity changes on network change
- **WHEN** the same physical PC reappears on a different IP or port
- **THEN** it SHALL be treated as a new discovery entry with a new `host:port` identity

### Requirement: Desktop mDNS advertisement daemon
The desktop system SHALL run a background daemon process that continuously advertises the instant-sharing mDNS service for mobile discovery and access.

#### Scenario: Discoverable without active backup session
- **WHEN** backup session is not active and instant-sharing feature is enabled
- **THEN** mobile discovery still finds the PC through the daemon-advertised mDNS service

### Requirement: PIN-verified DH trust establishment
For first-time sharing to a selected PC, the system SHALL perform DH key exchange and SHALL require user confirmation of matching PIN codes shown on receiver and sender before proceeding.

#### Scenario: Matching PIN confirmation succeeds
- **WHEN** receiver displays a PIN popup and sender displays a prompt with the same PIN and user confirms they match
- **THEN** both devices proceed to trust material exchange

#### Scenario: PIN mismatch or user rejection
- **WHEN** PIN values do not match or user rejects confirmation
- **THEN** trust establishment fails and no data transfer is started

### Requirement: Handshake/apply/confirm trust API flow
The trust flow SHALL use three HTTP APIs:
- `/trust/handshake` for DH exchange (includes bootstrap data)
- `/trust/apply` to receive PIN encrypted with symmetric key derived from handshake
- `/trust/confirm` sent after user taps Confirm (not in parallel, no long-poll)

#### Scenario: Handshake does not carry pin code
- **WHEN** iOS calls `/trust/handshake` on PC-hosted HTTP service
- **THEN** request and response contain DH and nonce material only and do not contain pin code fields

#### Scenario: Confirm is a simple POST
- **WHEN** the user taps "Confirm" on iOS after verifying the PIN
- **THEN** the extension sends `/trust/confirm` as a simple POST (no long-poll) and PC returns encrypted `trust_status: "trusted"`

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates. The PC SHALL include its X509 certificate (`device_certificate_pem`) in the `/trust/confirm` encrypted response. The mobile SHALL include its X509 certificate (`device_certificate_pem`) in the `/trust/confirm` encrypted request body. Both sides SHALL persist the exchanged X509 certificates for future mTLS-based revisit. The mobile SHALL also include `peer_device_name` in the `/trust/confirm` encrypted request body.

#### Scenario: Trust material persisted after first sharing
- **WHEN** first-share trust establishment completes successfully
- **THEN** both devices SHALL persist the exchanged X509 public certificates for future mTLS trust
- **AND** the stored material SHALL be keyed by the peer's `device_id` (derived from the certificate's CN)
- **AND** the mobile SHALL include `peer_device_name` in the encrypted `/trust/confirm` request

### Requirement: Direct mTLS for future sharing via certificate-based identity
For subsequent shares, the mobile SHALL derive the PC's `device_id` from the PC's TLS certificate CN during the mTLS handshake. If the mobile has a stored peer certificate for this `device_id`, it SHALL send the instant-share payload directly to the PC via HTTPS with mTLS using the stored X509 certificates, skipping the trust handshake entirely. If the TLS handshake fails (the PC does not trust the mobile's client cert), the mobile SHALL fall back to the full trust handshake flow. The mDNS `signature` field is NOT used for revisit identity verification.

#### Scenario: Direct mTLS transfer for previously-trusted peer
- **WHEN** mobile connects to a PC via mTLS and extracts the PC's `device_id` from the TLS certificate CN
- **AND** the mobile has a stored X509 peer certificate for this `device_id`
- **THEN** mobile SHALL send the instant-share payload directly to that PC via HTTPS with mTLS without repeating the trust handshake
- **AND** mobile SHALL include `X-Peer-Device-Name` header in the transfer request

#### Scenario: Trust handshake skipped for revisit
- **WHEN** mobile has a stored cert for a previously-trusted PC and the mTLS connection succeeds
- **THEN** the system SHALL skip the `/trust/handshake`, `/trust/apply`, and `/trust/confirm` steps and proceed directly to `/transfer/xxx` via mTLS

#### Scenario: TLS handshake failure falls back to full trust handshake
- **WHEN** mobile attempts an mTLS connection to a PC but the TLS handshake fails (the PC's SSL layer rejects the mobile's client certificate)
- **THEN** mobile SHALL initiate the full trust handshake flow and SHALL update stored certificates upon successful completion of the fallback

#### Scenario: No stored cert falls back to trust handshake
- **WHEN** mobile discovers a PC but has no stored X509 peer certificate for the extracted `device_id`
- **THEN** mobile SHALL proceed directly to the full trust handshake flow without attempting mTLS transfer

#### Scenario: mDNS discovery provides connectivity only
- **WHEN** mobile discovers PCs via mDNS
- **THEN** mDNS SHALL provide connectivity information only (hostname/IP + `tls_port`)
- **AND** device identity SHALL be derived from the TLS certificate CN during the mTLS handshake, not from mDNS TXT record fields

### Requirement: PC-side implementation isolation
The desktop system SHALL implement instant-share orchestration, trust/transport flow, and the standalone mini window UI in a dedicated PC module path and SHALL NOT modify desktop code in `dt_image_search/mobile/*`. The mini window SHALL be independent from the main AuSearch application window.

#### Scenario: Isolated PC module usage
- **WHEN** implementing instant-share receiver functionality on desktop
- **THEN** implementation resides under `dt_image_search/instant_sharing` and no desktop implementation changes are made under `dt_image_search/mobile/*`

#### Scenario: Mini window is independent from main app
- **WHEN** the instant-share mini window is created or destroyed
- **THEN** the main AuSearch window state, navigation, and tab layout remain unchanged

### Requirement: No dependency on QR backup pairing/session capability exchange
The instant-share flow SHALL NOT depend on existing QR backup pairing/session infrastructure, including backup-session capability exchange endpoints.

#### Scenario: Instant-share starts without backup session
- **WHEN** sender initiates instant-share from Share Extension without an active QR backup session
- **THEN** the system completes discovery, trust establishment, and transfer using instant-share-specific protocol endpoints only

### Requirement: No dedicated bootstrap endpoint
Instant-sharing SHALL NOT require a dedicated `/sessions/bootstrap` endpoint. Session is created on the PC when iOS calls `/trust/handshake` with bootstrap data (`mobile_port`, `mobile_ip_list`, `payload_class`, `target_intent`, `trust_mode`) embedded in the request body.

#### Scenario: Session created from trust handshake
- **WHEN** iOS sends `/trust/handshake` with bootstrap metadata
- **THEN** PC creates a session from the embedded bootstrap data and subsequent requests are matched by `X-Session-Id`

## REMOVED Requirements

### Requirement: Signed mDNS advertisement verification and pinned direct HTTPS for future sharing
**Reason**: The TXT fields supporting this feature (`device_id`, `signature`, `signature_key_id`, `timestamp_ms`) were removed from the mDNS advertisement to reduce broadcast data and simplify the QR code. The code has no provision for signed mDNS advertisement verification or pinned HTTPS.
**Migration**: If signature-verified direct shares are implemented in the future, a new TXT record version should be defined under `ver` and the relevant fields reintroduced as a new capability spec.
