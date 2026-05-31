## ADDED Requirements

### Requirement: BLE candidate PC discovery before send
The mobile system SHALL scan BLE pairing-service broadcasts from nearby PCs and SHALL maintain a user-selectable list of candidate PCs before initiating instant-share transfer.

#### Scenario: Candidate list population
- **WHEN** the sender opens instant-share target selection
- **THEN** the mobile app presents a list of discovered candidate PCs from BLE broadcasts

### Requirement: BLE service characteristics contract
The desktop BLE service SHALL expose exactly three characteristics for instant-sharing bootstrap:
- `DeviceName` read-only for PC display name
- `DeviceSignature` read-only for trust/signature verification
- `ConnectionConfig` write-only for mobile IP list, mobile port, and session ID bootstrap

#### Scenario: Mobile builds device list from DeviceName
- **WHEN** mobile reads discovered device characteristics
- **THEN** mobile uses `DeviceName` values to render candidate PC list

#### Scenario: Mobile writes connection bootstrap to ConnectionConfig
- **WHEN** user selects a target PC from the discovered list
- **THEN** mobile writes session ID, mobile port, and mobile IP list to `ConnectionConfig` before HTTP trust/transfer calls

### Requirement: Desktop BLE broadcast daemon
The desktop system SHALL run a background daemon process that continuously broadcasts the instant-sharing BLE service for mobile discovery and access.

#### Scenario: Discoverable without active backup session
- **WHEN** backup session is not active and instant-sharing feature is enabled
- **THEN** mobile discovery still finds the PC through the daemon-broadcast instant-sharing BLE service

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
- `/trust/handshake` for DH exchange only
- `/trust/apply` to carry PIN encrypted with symmetric key derived from handshake
- `/trust/confirm` sent in parallel with `/trust/apply`, carrying PC public key and waiting for mobile confirmation before responding with mobile public key

#### Scenario: Handshake does not carry pin code
- **WHEN** PC calls `/trust/handshake` on mobile-hosted HTTP service
- **THEN** request and response contain DH and nonce material only and do not contain pin code fields

#### Scenario: Confirm waits for mobile user action
- **WHEN** `/trust/confirm` is in-flight during trust apply phase
- **THEN** endpoint blocks until mobile confirms matching PIN and returns mobile public key on success

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates and SHALL use that trust material for subsequent HTTPS connections with self-signed certificates.

#### Scenario: Trust material persisted after first sharing
- **WHEN** first-share trust establishment completes successfully
- **THEN** both devices persist exchanged X509 public certificates for future TLS trust decisions

### Requirement: Signed broadcast verification and pinned direct HTTPS for future sharing
For subsequent shares, the PC SHALL include a cryptographic signature in its broadcast and mobile SHALL verify the signature; if verification succeeds and pinned trust exists, mobile SHALL send directly to PC via HTTPS using pinned public key trust.

#### Scenario: Verified signed broadcast enables direct share
- **WHEN** mobile verifies PC broadcast signature and finds a matching pinned public certificate from prior trust establishment
- **THEN** mobile sends instant-share payload directly to that PC over HTTPS without repeating first-time trust handshake

#### Scenario: Negotiating state skipped for trusted-direct share
- **WHEN** mobile verifies PC `DeviceSignature` for an existing trust relationship
- **THEN** the session skips negotiating/trust-handshake steps and proceeds directly to transfer

#### Scenario: Signature verification fails
- **WHEN** mobile cannot verify PC broadcast signature for a discovered candidate
- **THEN** mobile excludes that candidate from direct-send path and does not initiate HTTPS transfer

### Requirement: PC-side implementation isolation
The desktop system SHALL implement instant-share orchestration and trust/transport flow in a dedicated PC module path and SHALL NOT modify desktop code in `dt_image_search/mobile/*`.

#### Scenario: Isolated PC module usage
- **WHEN** implementing instant-share receiver functionality on desktop
- **THEN** implementation resides under `dt_image_search/instant_sharing` and no desktop implementation changes are made under `dt_image_search/mobile/*`

### Requirement: No dependency on QR backup pairing/session capability exchange
The instant-share flow SHALL NOT depend on existing QR backup pairing/session infrastructure, including backup-session capability exchange endpoints.

#### Scenario: Instant-share starts without backup session
- **WHEN** sender initiates instant-share from Share Extension without an active QR backup session
- **THEN** the system completes discovery, trust establishment, and transfer using instant-share-specific protocol endpoints only

### Requirement: No `/sessions` endpoint dependency
Instant-sharing SHALL NOT require an HTTP `/sessions` endpoint because session is created on mobile at device selection time and bootstrapped through BLE `ConnectionConfig`.

#### Scenario: Session verified from BLE bootstrap
- **WHEN** PC performs instant-sharing HTTP calls
- **THEN** each request includes the session ID from BLE bootstrap and mobile verifies it against the selected-device session
