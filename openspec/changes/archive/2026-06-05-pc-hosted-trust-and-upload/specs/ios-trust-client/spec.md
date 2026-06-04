# iOS Trust Client

## ADDED Requirements

### Requirement: iOS extension calls PC trust handshake (plain DH exchange)
The iOS extension SHALL call `POST /api/instant-share/v1/trust/handshake` on the PC's bootstrap server. The request SHALL contain the extension's X25519 DH public key (`mobile_dh_public_key`, base64url-encoded 32 bytes) and a 32-byte nonce (`mobile_nonce`, base64url-encoded). The request and response are plain text (not encrypted). The extension SHALL derive the AES-GCM session key using HKDF-SHA256 with salt = `pc_nonce || mobile_nonce` and info = `"dtis.instant-share.trust-session.v1" || kdf_context`.

#### Scenario: Successful handshake
- **WHEN** extension sends handshake request to PC
- **THEN** extension receives PC's DH public key, nonce, and kdf_context
- **AND** extension derives the same session key as PC

#### Scenario: Handshake failure
- **WHEN** PC returns an error (e.g., 400 INVALID_REQUEST)
- **THEN** extension shows error state and allows retry

### Requirement: iOS extension calls PC trust apply (encrypted PIN retrieval)
The iOS extension SHALL call `POST /api/instant-share/v1/trust/apply` on the PC's bootstrap server. The extension SHALL encrypt the request body `{"action": "request_pin"}` with the session key (AES-256-GCM trust envelope). The extension SHALL decrypt the response envelope using the session key and display the 6-digit PIN to the user.

#### Scenario: Successful PIN retrieval
- **WHEN** extension sends apply request to PC after handshake
- **THEN** extension receives encrypted PIN, decrypts it, and displays 6-digit PIN to user

#### Scenario: Apply before handshake
- **WHEN** extension sends apply request before completing handshake
- **THEN** extension receives error and retries handshake

#### Scenario: Decryption failure
- **WHEN** PC returns an envelope that cannot be decrypted
- **THEN** extension shows error state

### Requirement: iOS extension calls PC trust confirm (encrypted finalization)
The iOS extension SHALL call `POST /api/instant-share/v1/trust/confirm` on the PC's bootstrap server after the user taps "Confirm" in the iOS UI. The extension SHALL encrypt the request body `{"action": "confirm", "pin_verified": true}` with the session key. The extension SHALL decrypt the response envelope and verify `trust_status == "trusted"`. This is a simple POST — no long-polling. The user confirms only on the iOS side; the PC does not require a separate user action.

#### Scenario: User confirms PIN
- **WHEN** user taps "Confirm" on extension UI
- **THEN** extension sends encrypted confirmation to PC
- **AND** PC returns `trust_status: "trusted"` in encrypted envelope
- **AND** extension transitions to transfer state

#### Scenario: User rejects PIN
- **WHEN** user taps "Reject" on extension UI
- **THEN** extension aborts the session and transitions to failed state
- **AND** extension does NOT call /trust/confirm

#### Scenario: Confirmation request fails
- **WHEN** PC returns an error from `/trust/confirm`
- **THEN** extension shows error state with retry option

### Requirement: iOS extension trust flow sequence
The extension SHALL execute the trust flow in sequence: handshake → apply → confirm. Each step SHALL wait for the previous step to complete before proceeding. After all three steps complete, the extension transitions to the transfer state.

#### Scenario: Complete trust flow
- **WHEN** extension starts trust flow
- **THEN** extension calls handshake first
- **AND** after handshake succeeds, extension calls apply
- **AND** after apply succeeds, extension displays PIN to user
- **AND** after user confirms, extension calls confirm
- **AND** after confirm succeeds, extension transitions to transfer state

#### Scenario: Trust flow with error at any step
- **WHEN** any trust step fails
- **THEN** extension shows error state with retry option
- **AND** extension does not proceed to next step
