# PC Trust Endpoints

## ADDED Requirements

### Requirement: PC hosts trust handshake endpoint (plain DH exchange)
The PC SHALL expose `POST /api/instant-share/v1/trust/handshake` on the bootstrap HTTP server (port 9527). The endpoint SHALL accept a JSON body with the iOS extension's X25519 DH public key (`mobile_dh_public_key`, base64url-encoded, 32 bytes) and a 32-byte nonce (`mobile_nonce`, base64url-encoded). The endpoint SHALL generate a PC-side nonce and kdf_context, and return the PC's DH public key, nonce, and kdf_context in the response. The session key SHALL be derived on both sides using HKDF-SHA256 with salt = `pc_nonce || mobile_nonce` and info = `"dtis.instant-share.trust-session.v1" || kdf_context`.

**The handshake request and response are plain text (not encrypted).** Encryption is only used in `/trust/apply` and `/trust/confirm`.

#### Scenario: Successful handshake
- **WHEN** iOS sends POST to `/trust/handshake` with valid `mobile_dh_public_key` and `mobile_nonce`
- **THEN** PC returns 200 with `pc_dh_public_key`, `pc_nonce`, `kdf_context`, and both sides derive the same session key

#### Scenario: Missing required fields
- **WHEN** iOS sends POST to `/trust/handshake` without `mobile_dh_public_key` or `mobile_nonce`
- **THEN** PC returns 400 with error code `INVALID_REQUEST`

#### Scenario: Malformed DH public key
- **WHEN** iOS sends POST to `/trust/handshake` with a `mobile_dh_public_key` that is not 32 bytes after base64url decoding
- **THEN** PC returns 400 with error code `HANDSHAKE_REQUIRED`

### Requirement: PC hosts trust apply endpoint (encrypted PIN retrieval)
The PC SHALL expose `POST /api/instant-share/v1/trust/apply` on the bootstrap HTTP server. The endpoint SHALL require a valid trust session (handshake completed). The request body SHALL be a trust envelope encrypted with the session key (AES-256-GCM), with plaintext `{"action": "request_pin"}`. The PC SHALL decrypt the request, generate a 6-digit PIN, encrypt the PIN in a trust envelope with the same session key, and return the envelope to iOS. The PC SHALL also display the same PIN on its mini window.

#### Scenario: Successful PIN retrieval
- **WHEN** iOS sends POST to `/trust/apply` with an encrypted request after a successful handshake
- **THEN** PC generates a 6-digit PIN, encrypts it in a trust envelope, returns 202 with `apply_status: "accepted"` and the encrypted PIN in the response body
- **AND** the PC mini window displays the same 6-digit PIN

#### Scenario: Handshake not completed
- **WHEN** iOS sends POST to `/trust/apply` without completing handshake
- **THEN** PC returns 400 with error code `HANDSHAKE_REQUIRED`

#### Scenario: Decryption failure
- **WHEN** iOS sends POST to `/trust/apply` with an envelope that cannot be decrypted
- **THEN** PC returns 400 with error code `PAYLOAD_UNREADABLE`

### Requirement: PC hosts trust confirm endpoint (encrypted finalization)
The PC SHALL expose `POST /api/instant-share/v1/trust/confirm` on the bootstrap HTTP server. The endpoint SHALL require a valid trust session (handshake completed). The request body SHALL be a trust envelope encrypted with the session key, with plaintext `{"action": "confirm", "pin_verified": true}`. The PC SHALL decrypt the request, mark the trust session as `trusted`, and return an encrypted `{"trust_status": "trusted"}` response. This endpoint is a simple POST — no long-polling. The user confirms only on the iOS side; the PC does not require a separate user action.

#### Scenario: Successful confirmation
- **WHEN** iOS sends POST to `/trust/confirm` with an encrypted confirmation request
- **THEN** PC returns 200 with `trust_status: "trusted"` in an encrypted trust envelope
- **AND** the trust session transitions to `trusted` state

#### Scenario: Handshake not completed
- **WHEN** iOS sends POST to `/trust/confirm` without completing handshake
- **THEN** PC returns 400 with error code `HANDSHAKE_REQUIRED`

#### Scenario: Decryption failure
- **WHEN** iOS sends POST to `/trust/confirm` with an envelope that cannot be decrypted
- **THEN** PC returns 400 with error code `PAYLOAD_UNREADABLE`

### Requirement: PC trust session management
The PC SHALL maintain a trust session for each active instant-share session, tracking the DH-derived session key, PIN code, and confirmation state. The session SHALL be identified by the session ID from the bootstrap request. The session SHALL be cleared when the iOS client disconnects or the transfer completes.

#### Scenario: Session lifecycle
- **WHEN** iOS bootstraps a new session
- **THEN** PC creates a new trust session with a unique session ID
- **WHEN** trust handshake completes
- **THEN** session stores the derived session key
- **WHEN** trust apply completes successfully
- **THEN** session stores the generated PIN code
- **WHEN** trust confirm completes successfully
- **THEN** session transitions to `trusted` state
