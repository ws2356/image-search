## Purpose
Secure device discovery and trust establishment for instant sharing between mobile and PC, including mDNS-based PC browsing, DH-based PIN verification, and X509 certificate exchange for mTLS reuse.
## Requirements
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
- **THEN** the Share Extension calls PC's `/api/instant-share/v1/trust/handshake` endpoint (using the IP:port from mDNS resolution) with DH key material plus bootstrap data (`mobile_port`, `mobile_ip_list`, `payload_class`, `target_intent`, `trust_mode`) embedded in the body. No separate bootstrap endpoint. **Correction**: non of above fields are useful now. The /trust/handshake endpoint is only used for DH key exchanges.

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

All requests SHALL include an `X-Session-Id` header for session routing when multiple trust sessions are active.

#### Scenario: Handshake does not carry pin code
- **WHEN** iOS calls `/trust/handshake` on PC-hosted HTTP service with `X-Session-Id` header
- **THEN** request and response contain DH and nonce material only and do not contain pin code fields
- **AND** the PC SHALL route the handshake to the correct `TrustSession` identified by `session_id`

#### Scenario: Confirm is a simple POST
- **WHEN** the user taps "Confirm" on iOS after verifying the PIN
- **THEN** the extension sends `/trust/confirm` with `X-Session-Id` as a simple POST (no long-poll) and PC returns encrypted `trust_status: "trusted"`
- **AND** the PC SHALL route the confirm to the correct session

#### Scenario: Concurrent trust handshakes
- **WHEN** mobile device X and mobile device Y both initiate trust handshakes within the same time window
- **THEN** the PC SHALL create two independent `TrustSession` instances with different `session_id` values
- **AND** each handshake SHALL proceed independently through the apply/confirm steps

### Requirement: Trust session registry supports multiple concurrent sessions
The `TrustSessionRegistry` SHALL maintain a collection of active trust sessions keyed by `session_id`. Methods `create_handshake_session()`, `get_session()`, `complete_handshake()` SHALL route by `session_id`.

#### Scenario: Multiple concurrent trust sessions
- **WHEN** two mobile devices each call `/trust/handshake`
- **THEN** the `TrustSessionRegistry` SHALL contain two independent `TrustSession` entries
- **AND** each SHALL have its own DH key material, nonces, and state

#### Scenario: Session lookup by session_id
- **WHEN** `/trust/confirm` is called with `X-Session-Id: aaa`
- **AND** sessions `aaa` and `bbb` both exist in the registry
- **THEN** the request SHALL be routed to session `aaa` only
- **AND** session `bbb` SHALL be unaffected

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates. The mobile SHALL store the PC's certificate keyed by public key hash. The PC SHALL store the mobile's certificate using its existing API. The mobile SHALL also include `peer_device_name` in the `/trust/confirm` encrypted request body. Batch image transfer metadata (image count) SHALL be communicated via HTTP headers on `/transfer/image` requests, not in the trust confirm body.

#### Scenario: Trust material persisted after first sharing (batch)
- **WHEN** first-share trust establishment completes successfully with a batch of images
- **THEN** the certificate exchange SHALL proceed identically to single-image flow
- **AND** the batch metadata SHALL be communicated via `X-Image-Count` header on subsequent `/transfer/image` requests

### Requirement: Direct mTLS for future sharing via certificate-based identity
For subsequent shares, the iOS client SHALL extract the server certificate's public key hash via `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → `Insecure.SHA1` during the TLS handshake, and look up the stored peer certificate by `kSecAttrPublicKeyHash`. If found, it SHALL proceed with direct mTLS transfer. If no match is found, SHALL fall back to the full trust handshake.

#### Scenario: Direct mTLS transfer via public key hash match
- **WHEN** iOS connects to a PC via TLS and extracts the server certificate's public key hash
- **AND** a stored peer certificate matches via `peerCertificate(forPubkeyHash:)`
- **THEN** iOS SHALL send the instant-share payload directly via mTLS without repeating the trust handshake

#### Scenario: No matching cert falls back to trust handshake
- **WHEN** iOS discovers a PC but has no stored peer certificate matching the server's public key hash
- **THEN** iOS SHALL proceed to the full trust handshake flow

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

