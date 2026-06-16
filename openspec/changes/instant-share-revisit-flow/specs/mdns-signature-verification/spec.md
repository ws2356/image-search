## ADDED Requirements

### Requirement: PC Ed25519 public key exchange during first trust
During the `/trust/confirm` step of the first-share trust handshake, the PC SHALL include its Ed25519 public key (used for mDNS signature advertisements) in the encrypted response alongside its X.509 certificate. The mobile SHALL persist both the X.509 certificate and the Ed25519 public key, keyed by the PC's `device_id`.

#### Scenario: PC includes Ed25519 key in trust confirm response
- **WHEN** the PC responds to a successful `/trust/confirm` request
- **THEN** the encrypted response body SHALL contain a field `ed25519_public_key_pem` with the PC's Ed25519 public key in SubjectPublicKeyInfo PEM format

#### Scenario: Mobile stores Ed25519 key alongside X.509 cert
- **WHEN** mobile receives the `/trust/confirm` response with `ed25519_public_key_pem`
- **THEN** mobile SHALL store the Ed25519 public key keyed by `device_id` alongside the X.509 certificate for future mDNS signature verification

### Requirement: mDNS TXT signature extraction
The mobile client SHALL extract `device_id`, `signature`, `signature_key_id`, and `timestamp_ms` from the mDNS TXT records of discovered `_instantshare._tcp` services.

#### Scenario: Mobile extracts signature fields from mDNS TXT
- **WHEN** the mobile resolves an mDNS service of type `_instantshare._tcp`
- **THEN** the mobile SHALL parse `device_id`, `signature`, `signature_key_id`, and `timestamp_ms` from the TXT record properties

#### Scenario: Mobile skips device missing signature fields
- **WHEN** the mDNS TXT record does not contain `signature` or the value is empty
- **THEN** the mobile SHALL treat the device as requiring first-share trust handshake (not eligible for revisit)

### Requirement: Ed25519 signature verification against stored peer key
The mobile client SHALL verify the Ed25519 `signature` from mDNS TXT records using the previously-stored Ed25519 public key for the given `device_id`. The signed message SHALL be `"{device_id}:{timestamp_ms}"` encoded as UTF-8 bytes.

#### Scenario: Signature verification succeeds
- **WHEN** mobile reconstructs the message `"{device_id}:{timestamp_ms}"` and verifies the base64url-decoded `signature` against the stored Ed25519 public key for `device_id`
- **THEN** the verification SHALL succeed and the mobile SHALL mark the device as eligible for revisit transfer

#### Scenario: Signature verification fails due to wrong key
- **WHEN** mobile verifies the signature against the stored Ed25519 public key and verification fails
- **THEN** the mobile SHALL fall back to the full trust handshake flow for this device

#### Scenario: No stored Ed25519 key for device
- **WHEN** mobile looks up the Ed25519 public key by `device_id` and no key is found
- **THEN** the mobile SHALL fall back to the full trust handshake flow for this device

### Requirement: Signature timestamp freshness check
The mobile client SHALL reject mDNS signatures where the `timestamp_ms` differs from the mobile's current time by more than 300 seconds (5 minutes).

#### Scenario: Signature timestamp is fresh
- **WHEN** the absolute difference between mobile's current Unix timestamp in milliseconds and `timestamp_ms` from mDNS TXT is 300,000 ms or less
- **THEN** the signature SHALL be considered fresh

#### Scenario: Signature timestamp is stale
- **WHEN** the absolute difference between mobile's current Unix timestamp in milliseconds and `timestamp_ms` from mDNS TXT exceeds 300,000 ms
- **THEN** the mobile SHALL reject the signature as stale and fall back to the full trust handshake flow
