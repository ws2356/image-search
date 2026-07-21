## ADDED Requirements

### Requirement: Peer certificate storage by public key hash (iOS)
The `KeychainAppIdentityProvider` SHALL store peer certificates in the iOS Keychain using `kSecAttrPublicKeyHash` (SHA-1 of the public key's external representation) as the lookup attribute. The `kSecAttrLabel` SHALL be a constant `"AuSearch Trusted Device"` for batch query support. This matches the existing `deletePeerCertificate` pattern already in the codebase.

#### Scenario: Store peer cert with pubkey hash attribute
- **WHEN** `importPeerCertificate(_ cert: SecCertificate)` is called
- **THEN** the provider SHALL extract the public key via `SecCertificateCopyKey(cert)`
- **THEN** the provider SHALL compute the SHA-1 hash of `SecKeyCopyExternalRepresentation(publicKey, nil)` using `Insecure.SHA1`
- **THEN** the provider SHALL store the certificate in the Keychain with `kSecClass = kSecClassCertificate`, `kSecAttrLabel = "AuSearch Trusted Device"`, and `kSecAttrPublicKeyHash` set to the SHA-1 `Data`
- **AND** the `kSecAttrLabel` SHALL be a constant string regardless of the certificate identity

#### Scenario: Look up peer cert by public key hash
- **WHEN** `peerCertificate(forPubkeyHash hash: Data)` is called with SHA-1 hash `Data`
- **THEN** the provider SHALL query the Keychain with `kSecClass = kSecClassCertificate`, `kSecAttrPublicKeyHash = hash`, `kSecReturnRef = true`
- **THEN** it SHALL return the matching `SecCertificate` or `nil` via `SecItemCopyMatching`

#### Scenario: Delete peer cert by public key hash
- **WHEN** `deletePeerCertificate(forPubkeyHash hash: Data)` is called with SHA-1 hash `Data`
- **THEN** the provider SHALL delete the Keychain item with `kSecClass = kSecClassCertificate`, `kSecAttrPublicKeyHash = hash`

#### Scenario: Look up peer cert directly from SecCertificate
- **WHEN** `peerCertificate(for cert: SecCertificate)` is called
- **THEN** the provider SHALL extract the public key hash from the given cert and query by `kSecAttrPublicKeyHash`

#### Scenario: Import same cert twice is idempotent
- **WHEN** `importPeerCertificate(_:)` is called with a certificate whose public key hash already exists in the Keychain
- **THEN** the provider SHALL first delete the existing item via `kSecAttrPublicKeyHash`, then add the new one (overwrite pattern matching existing `initialize` behavior)

### Requirement: Public key hash extraction from SecCertificate (iOS)
The `CertTools` extension SHALL provide a `publicKeyHash` computed property on `SecCertificate` that returns the SHA-1 hash `Data` of the certificate's public key external representation, matching the `kSecAttrPublicKeyHash` format.

#### Scenario: Extract pubkey hash from certificate
- **WHEN** `cert.publicKeyHash` is called on a valid `SecCertificate`
- **THEN** it SHALL return `Data` produced by `Data(Insecure.SHA1.hash(data: SecKeyCopyExternalRepresentation(SecCertificateCopyKey(self), nil) as Data))`

#### Scenario: Pubkey hash is stable for same certificate
- **WHEN** `cert.publicKeyHash` is called twice on the same `SecCertificate` instance
- **THEN** both calls SHALL return identical `Data`

### Requirement: Public API without peerDeviceID parameter (iOS)
The `AppIdentityProviding` protocol SHALL no longer require `peerDeviceID` parameters in peer certificate methods. The lookup key SHALL be the public key hash `Data`.

#### Scenario: Updated protocol signatures
- **WHEN** the `AppIdentityProviding` protocol is inspected
- **THEN** it SHALL declare `importPeerCertificate(_ cert: SecCertificate) async throws`
- **AND** it SHALL declare `importPeerCertificate(pem: String) async throws`
- **AND** it SHALL declare `peerCertificate(forPubkeyHash hash: Data) throws -> SecCertificate`
- **AND** it SHALL declare `peerCertificate(for cert: SecCertificate) throws -> SecCertificate`
- **AND** it SHALL declare `deletePeerCertificate(forPubkeyHash hash: Data) throws`
- **AND** there SHALL be no `peerDeviceID` parameter in any of these signatures

### Requirement: Batch peer certificate query via constant label (iOS)
The provider SHALL support querying all stored peer certificates via a constant label query using `SecItemCopyMatching` with `kSecMatchLimit = kSecMatchLimitAll`.

#### Scenario: Load all peer certificates
- **WHEN** `loadAllPeerCertificates()` is called
- **THEN** it SHALL query the Keychain with `kSecClass = kSecClassCertificate`, `kSecAttrLabel = "AuSearch Trusted Device"`, `kSecMatchLimit = kSecMatchLimitAll`, `kSecReturnRef = true`
- **THEN** it SHALL return an array of `SecCertificate`

### Requirement: Remove old peerDeviceID-based label and lookups (iOS)
The old per-device label pattern `"AuBackup Peer Certificate \(peerDeviceID)"` SHALL be removed from the codebase. All stored peer certificates from previous versions SHALL be deleted during version migration.

#### Scenario: Cleanup of old-format peer certs on migration
- **WHEN** `SELF_CERT_VERSION` is bumped from 2 to 3 and the self cert is migrated
- **THEN** the provider SHALL delete all Keychain items with `kSecClass = kSecClassCertificate` and `kSecAttrLabel` matching the old pattern prefix `"AuBackup Peer Certificate"`
- **AND** trust relationships SHALL be re-established during the next trust handshake
