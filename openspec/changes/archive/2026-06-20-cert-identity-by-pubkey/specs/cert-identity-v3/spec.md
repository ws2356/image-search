## ADDED Requirements

### Requirement: Device name in CN field (iOS)
When generating a self-signed device identity certificate, the iOS system SHALL set the certificate's Common Name (CN) field to the device's human-readable name instead of the device UUID.

#### Scenario: Self-signed certificate CN is device name
- **WHEN** `initialize()` generates or regenerates the device identity certificate
- **THEN** the certificate's Subject CN SHALL be set to `UIDevice.current.name` (sanitized to ASCII)
- **AND** the device UUID SHALL NOT appear in the CN field

### Requirement: Device UUID in custom extension (iOS)
The iOS self-signed certificate SHALL contain the device UUID in a custom X.509 extension with OID `2.25.37020860436019521`, distinct from the cert version OID (`2.25.37020860436019520`).

#### Scenario: Device UUID stored in dedicated extension
- **WHEN** `initialize()` generates or regenerates the device identity certificate
- **THEN** the certificate SHALL include a custom extension with OID `2.25.37020860436019521`
- **AND** the extension value SHALL be the device UUID encoded as ASN.1 UTF8String

#### Scenario: Cert version stored in separate extension
- **WHEN** `initialize()` generates or regenerates the device identity certificate
- **THEN** the certificate SHALL include a custom extension with OID `2.25.37020860436019520`
- **AND** the extension value SHALL be `SELF_CERT_VERSION` encoded as ASN.1 INTEGER
- **AND** the version extension SHALL NOT contain the device UUID

### Requirement: Device name in CN field (PC)
When `_generate_identity()` creates a self-signed device identity certificate, the PC system SHALL set the certificate's Common Name (CN) field to the desktop computer's hostname instead of the device UUID.

#### Scenario: Self-signed certificate CN is hostname
- **WHEN** `_generate_identity(device_id, desktop_name="My Mac")` is called
- **THEN** the certificate's Subject CN SHALL be set to the desktop name (hostname fallback if not provided)
- **AND** the device UUID SHALL NOT appear in the CN field

### Requirement: Device UUID in custom extension (PC)
The PC self-signed certificate SHALL contain the device UUID in a custom X.509 extension with OID `2.25.37020860436019521`, matching the iOS extension OID.

#### Scenario: Device UUID stored in dedicated extension (PC)
- **WHEN** `_generate_identity()` creates a self-signed certificate
- **THEN** the certificate SHALL include a custom extension with OID `2.25.37020860436019521`
- **AND** the extension SHALL encode the device UUID as an ASN.1 UTF8String value

### Requirement: No PC storage/query API changes
The PC-side `device_identity.py` public APIs for peer certificate storage and query (`store_peer_certificate`, `load_peer_certificate`, `load_all_peer_certificates`, `delete_peer_certificate`) SHALL NOT change their signatures or storage mechanism. Only the self-cert content generation (`_generate_identity`) SHALL be updated.

#### Scenario: PC peer cert APIs unchanged
- **WHEN** `store_peer_certificate(peer_device_id, certificate_pem)` is called
- **THEN** it SHALL store using the same keychain service/account/label as before
- **AND** `load_peer_certificate(peer_device_id)` SHALL continue to work as before

### Requirement: iOS self-cert version bump to 3
The `SELF_CERT_VERSION` constant in `KeychainAppIdentityProvider` SHALL be updated from 2 to 3. On next launch, the migration logic SHALL detect the version mismatch (stored cert version extension value < 3) and regenerate the certificate with the new CN (device name) and new extension (device UUID in OID `2.25.37020860436019521`), preserving the same EC key pair. Old-format peer certificates SHALL be deleted during migration.

#### Scenario: Version 2 cert is migrated to version 3
- **WHEN** the app launches and the stored certificate has version < 3 in extension OID `2.25.37020860436019520`
- **AND** `SELF_CERT_VERSION` is 3
- **THEN** the migration logic SHALL regenerate the certificate with device name in CN and device UUID in OID `2.25.37020860436019521`
- **AND** the original EC key pair SHALL be reused
- **AND** all peer certs stored with the old label pattern SHALL be deleted

#### Scenario: Version 3 cert is not re-migrated
- **WHEN** the app launches and the stored certificate already has version extension value 3
- **THEN** the migration logic SHALL NOT regenerate the certificate
