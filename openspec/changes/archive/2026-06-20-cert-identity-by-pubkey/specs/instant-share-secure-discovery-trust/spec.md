## MODIFIED Requirements

### Requirement: X509 public certificate exchange for HTTPS trust
After successful PIN confirmation, both sides SHALL exchange X509 public certificates. The mobile (iOS) SHALL store the PC's certificate in the iOS Keychain keyed by `kSecAttrPublicKeyHash` (SHA-1 of public key). The PC side SHALL continue storing certificates using its existing API. The mobile SHALL also include `peer_device_name` in the `/trust/confirm` encrypted request body.

#### Scenario: iOS stores peer cert by pubkey hash after first sharing
- **WHEN** first-share trust establishment completes successfully on iOS
- **THEN** the iOS client SHALL store the PC's X509 certificate keyed by its public key hash (`kSecAttrPublicKeyHash`)
- **AND** the PC SHALL persist the mobile's certificate using its existing `store_peer_certificate` API

### Requirement: Direct mTLS for future sharing via certificate-based identity
For subsequent shares, the iOS client SHALL extract the server certificate's public key hash via `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → `Insecure.SHA1` during the TLS handshake, and look up the stored peer certificate by `kSecAttrPublicKeyHash`. If found, it SHALL proceed with direct mTLS transfer. If no match is found, SHALL fall back to the full trust handshake.

#### Scenario: Direct mTLS transfer via public key hash match
- **WHEN** iOS connects to a PC via TLS and extracts the server certificate's public key hash
- **AND** a stored peer certificate matches via `peerCertificate(forPubkeyHash:)`
- **THEN** iOS SHALL send the instant-share payload directly via mTLS without repeating the trust handshake

#### Scenario: No matching cert falls back to trust handshake
- **WHEN** iOS discovers a PC but has no stored peer certificate matching the server's public key hash
- **THEN** iOS SHALL proceed to the full trust handshake flow
