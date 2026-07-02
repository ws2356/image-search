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
- `device_id` (persistent unique device identifier)
- `signature` (base64 cryptographic signature for trusted-direct verification)
- `signature_key_id` (key identifier for signature verification)
- `timestamp_ms` (Unix millisecond timestamp for signature freshness)

The advertised TCP port SHALL be the PC's instant-share HTTP API port.

#### Scenario: Mobile builds device list from mDNS TXT
- **WHEN** mobile resolves discovered mDNS services
- **THEN** the Share Extension uses `device_name` TXT values to render the candidate PC list and stores `device_id`, `signature`, `signature_key_id`, `timestamp_ms`, and resolved IP:port for the trust flow

#### Scenario: Mobile calls trust handshake with bootstrap data
- **WHEN** the user has selected a PC and taps "Send" in the Share Extension
- **THEN** the Share Extension calls PC's `/api/instant-share/v1/trust/handshake` endpoint (using the IP:port from mDNS resolution) with DH key material plus bootstrap data (mobile_port, mobile_ip_list, payload_class, target_intent, trust_mode) embedded in the body. No separate bootstrap endpoint. No local HTTP server.

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

### Requirement: X509 public certificate exchange for HTTPS trust — **DEFERRED**
After successful PIN confirmation, both sides SHALL exchange X509 public certificates and SHALL use that trust material for subsequent HTTPS connections with self-signed certificates.

#### Scenario: Trust material persisted after first sharing
- **WHEN** first-share trust establishment completes successfully
- **THEN** both devices persist exchanged X509 public certificates for future TLS trust decisions
- **CURRENT STATUS**: Not implemented. Trust is session-key-only (AES-GCM trust envelopes over plain HTTP). X509 exchange, signed mDNS advertisements, and cert-pinned HTTPS are deferred.

### Requirement: Signed mDNS advertisement verification and pinned direct HTTPS for future sharing — **DEFERRED**
For subsequent shares, the PC SHALL include a cryptographic signature in its mDNS TXT record and mobile SHALL verify the signature; if verification succeeds and pinned trust exists, mobile SHALL send directly to PC via HTTPS using pinned public key trust.

#### Scenario: Verified signed advertisement enables direct share
- **WHEN** mobile verifies PC mDNS TXT `signature` and finds a matching pinned public certificate from prior trust establishment
- **THEN** mobile sends instant-share payload directly to that PC over HTTPS without repeating first-time trust handshake
- **CURRENT STATUS**: Deferred. Every share currently goes through the full DH handshake + PIN verification flow.

#### Scenario: Negotiating state skipped for trusted-direct share
- **WHEN** mobile verifies PC `signature` from mDNS TXT record for an existing trust relationship
- **THEN** the session skips negotiating/trust-handshake steps and proceeds directly to transfer
- **CURRENT STATUS**: Not implemented.

#### Scenario: Signature verification fails
- **WHEN** mobile cannot verify PC mDNS TXT `signature` for a discovered candidate
- **THEN** mobile excludes that candidate from direct-send path and does not initiate HTTPS transfer
- **CURRENT STATUS**: Not implemented.

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
Instant-sharing SHALL NOT require a dedicated `/sessions/bootstrap` endpoint. Session is created on the PC when iOS calls `/trust/handshake` with bootstrap data (mobile_port, mobile_ip_list, payload_class, target_intent, trust_mode) embedded in the request body.

#### Scenario: Session created from trust handshake
- **WHEN** iOS sends `/trust/handshake` with bootstrap metadata
- **THEN** PC creates a session from the embedded bootstrap data and subsequent requests are matched by `X-Session-Id`
