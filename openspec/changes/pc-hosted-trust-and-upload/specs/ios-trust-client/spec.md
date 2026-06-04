# iOS Trust Client

## ADDED Requirements

### Requirement: iOS extension calls PC trust handshake
The iOS extension SHALL call `POST /api/instant-share/v1/trust/handshake` on the PC's bootstrap server. The request SHALL contain the extension's X25519 DH public key and a 32-byte nonce. The extension SHALL derive the same AES-GCM session key as the PC using the HKDF-SHA256 formula.

#### Scenario: Successful handshake
- **WHEN** extension sends handshake request to PC
- **THEN** extension receives PC's DH public key, nonce, and kdf_context
- **AND** extension derives the same session key as PC

#### Scenario: Handshake failure
- **WHEN** PC returns an error (e.g., 400 INVALID_REQUEST)
- **THEN** extension shows error state and allows retry

### Requirement: iOS extension calls PC trust apply
The iOS extension SHALL call `POST /api/instant-share/v1/trust/apply` on the PC's bootstrap server. The extension SHALL receive the encrypted PIN from the PC, decrypt it using the session key, and display the 6-digit PIN to the user.

#### Scenario: Successful PIN retrieval
- **WHEN** extension sends apply request to PC after handshake
- **THEN** extension receives encrypted PIN, decrypts it, and displays 6-digit PIN to user

#### Scenario: Apply before handshake
- **WHEN** extension sends apply request before completing handshake
- **THEN** extension receives error and retries handshake

### Requirement: iOS extension calls PC trust confirm
The iOS extension SHALL call `POST /api/instant-share/v1/trust/confirm` on the PC's bootstrap server. The request SHALL long-poll until the user confirms or rejects the PIN on the extension UI. The extension SHALL send confirmation or rejection to the PC.

#### Scenario: User confirms PIN
- **WHEN** user taps "Confirm" on extension UI
- **THEN** extension sends confirmation to PC
- **AND** PC returns `trust_status: "trusted"` in encrypted envelope
- **AND** extension transitions to success state

#### Scenario: User rejects PIN
- **WHEN** user taps "Reject" on extension UI
- **THEN** extension sends rejection to PC
- **AND** PC returns 409 PIN_MISMATCH_OR_REJECTED
- **AND** extension transitions to failed state

#### Scenario: Confirm timeout
- **WHEN** user does not act within 300 seconds
- **THEN** PC returns timeout error
- **AND** extension shows timeout state

### Requirement: iOS extension trust flow sequence
The extension SHALL execute the trust flow in sequence: handshake → apply → confirm. Each step SHALL wait for the previous step to complete before proceeding.

#### Scenario: Complete trust flow
- **WHEN** extension starts trust flow
- **THEN** extension calls handshake first
- **AND** after handshake succeeds, extension calls apply
- **AND** after apply succeeds, extension calls confirm
- **AND** after confirm succeeds, extension transitions to transfer state

#### Scenario: Trust flow with error at any step
- **WHEN** any trust step fails
- **THEN** extension shows error state with retry option
- **AND** extension does not proceed to next step
