# PC Trust Endpoints

## ADDED Requirements

### Requirement: PC hosts trust handshake endpoint
The PC SHALL expose `POST /api/instant-share/v1/trust/handshake` on the bootstrap HTTP server (port 9527). The endpoint SHALL accept a JSON body with `pc_dh_public_key` (base64url-encoded X25519 public key) and `pc_nonce` (base64url-encoded 32-byte nonce). The endpoint SHALL perform X25519 ECDH key agreement, generate a mobile nonce and kdf_context, derive a 256-bit AES-GCM session key via HKDF-SHA256, and return the mobile's DH public key, nonce, and kdf_context in the response.

#### Scenario: Successful handshake
- **WHEN** iOS sends POST to `/trust/handshake` with valid `pc_dh_public_key` and `pc_nonce`
- **THEN** PC returns 200 with `mobile_dh_public_key`, `mobile_nonce`, `kdf_context`, and both sides derive the same session key

#### Scenario: Missing required fields
- **WHEN** iOS sends POST to `/trust/handshake` without `pc_dh_public_key` or `pc_nonce`
- **THEN** PC returns 400 with error code `INVALID_REQUEST`

### Requirement: PC hosts trust apply endpoint
The PC SHALL expose `POST /api/instant-share/v1/trust/apply` on the bootstrap HTTP server. The endpoint SHALL generate a 6-digit PIN code, encrypt it in an AES-GCM trust envelope using the session key, and return the envelope to the iOS client. The PC SHALL store the PIN for subsequent verification.

#### Scenario: Successful PIN generation and return
- **WHEN** iOS sends POST to `/trust/apply` after a successful handshake
- **THEN** PC generates a 6-digit PIN, encrypts it in a trust envelope, returns 202 with `apply_status: "accepted"` and the encrypted PIN in the response body

#### Scenario: Handshake not completed
- **WHEN** iOS sends POST to `/trust/apply` without completing handshake
- **THEN** PC returns 400 with error code `HANDSHAKE_REQUIRED`

### Requirement: PC hosts trust confirm endpoint
The PC SHALL expose `POST /api/instant-share/v1/trust/confirm` on the bootstrap HTTP server. The endpoint SHALL long-poll, waiting for the iOS client to confirm that the user has verified the PIN. The PC SHALL wait up to 300 seconds for confirmation.

#### Scenario: User confirms PIN on iOS
- **WHEN** iOS sends POST to `/trust/confirm` with confirmation that user verified the PIN
- **THEN** PC returns 200 with `trust_status: "trusted"` in an encrypted trust envelope

#### Scenario: User rejects PIN on iOS
- **WHEN** iOS sends POST to `/trust/confirm` with rejection
- **THEN** PC returns 409 with error code `PIN_MISMATCH_OR_REJECTED`

#### Scenario: Confirmation timeout
- **WHEN** iOS does not send confirmation within 300 seconds
- **THEN** PC returns 408 with error code `CONFIRM_TIMEOUT`

### Requirement: PC trust session management
The PC SHALL maintain a trust session for each active instant-share session, tracking the DH-derived session key, PIN code, and confirmation state. The session SHALL be identified by the session ID from the bootstrap request.

#### Scenario: Session lifecycle
- **WHEN** iOS bootstraps a new session
- **THEN** PC creates a new trust session with a unique session ID
- **WHEN** trust handshake completes
- **THEN** session stores the derived session key
- **WHEN** trust confirm completes successfully
- **THEN** session transitions to `trusted` state
