## ADDED Requirements

### Requirement: BLE candidate PC discovery before send
The mobile system SHALL scan BLE pairing-service broadcasts from nearby PCs and SHALL maintain a user-selectable list of candidate PCs before initiating instant-share transfer.

#### Scenario: Candidate list population
- **WHEN** the sender opens instant-share target selection
- **THEN** the mobile app presents a list of discovered candidate PCs from BLE broadcasts

### Requirement: PIN-verified DH trust establishment
For first-time sharing to a selected PC, the system SHALL perform DH key exchange and SHALL require user confirmation of matching PIN codes shown on receiver and sender before proceeding.

#### Scenario: Matching PIN confirmation succeeds
- **WHEN** receiver displays a PIN popup and sender displays a prompt with the same PIN and user confirms they match
- **THEN** both devices proceed to trust material exchange

#### Scenario: PIN mismatch or user rejection
- **WHEN** PIN values do not match or user rejects confirmation
- **THEN** trust establishment fails and no data transfer is started

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

#### Scenario: Signature verification fails
- **WHEN** mobile cannot verify PC broadcast signature for a discovered candidate
- **THEN** mobile excludes that candidate from direct-send path and does not initiate HTTPS transfer

### Requirement: PC-side implementation isolation
The desktop system SHALL implement instant-share orchestration and trust/transport flow in a dedicated PC module path and SHALL only reuse existing mobile-folder code when directly reusable without modification.

#### Scenario: Isolated PC module usage
- **WHEN** implementing instant-share receiver functionality on desktop
- **THEN** implementation resides under `dt_image_search/instant_sharing` and avoids modifying `dt_image_search/mobile/*` unless unchanged reuse is possible
