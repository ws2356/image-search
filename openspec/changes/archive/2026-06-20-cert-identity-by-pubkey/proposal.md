## Why

Peer certificates on iOS are currently stored and looked up by `peerDeviceID` (the device UUID string from the CN field). This requires callers to know and pass the peer's device ID, creating an unnecessary indirection during server trust evaluation. The public key is a self-contained identity extracted directly from the certificate at handshake time. Additionally, the CN field should convey the human-readable device name (for UI display) rather than the opaque device UUID, with the UUID moved to a custom X.509 extension.

## What Changes

- **BREAKING (iOS only)**: Remove `peerDeviceID` parameter from `importPeerCertificate`, `peerCertificate`, `deletePeerCertificate` on iOS `KeychainAppIdentityProvider` public APIs
- Store and look up peer certificates by public key hash instead of `peerDeviceID` on iOS
- Make iOS keychain label a constant string `"AuSearch Trusted Device"` so all peer certs can be batch-queried
- During server trust evaluation on iOS, extract the server cert's public key and query the stored peer cert by that hash
- Store the human-readable device name in the certificate CN field (was device UUID) on both iOS and PC
- Store the device UUID in a separate custom X.509 extension OID on both iOS and PC (distinct from cert version OID)
- Bump iOS `SELF_CERT_VERSION` from 2 to 3 to trigger auto-migration on next launch
- **PC side self-cert content only**: CN changed to device name, device ID added to custom extension. No storage/query API changes on PC.

## Capabilities

### New Capabilities
- `cert-pubkey-peer-lookup-ios`: iOS peer certificates stored and looked up by public key hash via keychain-compatible query attributes. Constant keychain label enables batch queries.
- `cert-identity-v3`: Certificate identity v3 scheme — device name in CN field, device UUID in custom extension. iOS version bump from 2 to 3 triggers auto-migration. PC self-cert updated to match.

### Modified Capabilities
- `instant-share-secure-discovery-trust`: iOS server trust evaluation delegates extract public key from server cert, query stored peer cert by pubkey hash instead of CN+deviceID combination.
- `pc-revisit-session`: Peer device name derived from CN field (now carries human-readable name). No cert lookup changes on PC side.
- `revisit-transfer-skip-trust`: Mobile-side peer certificate lookup during revisit transfers uses public key hash from server cert instead of device_id.

## Impact

- **iOS code**: `KeychainAppIdentityProvider.swift` (public API signatures, storage, lookup, migration logic), `CertTools.swift` (pubkey hash extraction), `QRTriggerDownloadClient.swift` (trust delegate), `InstantShareUploadClient.swift` (trust delegate), `InstantShareExtensionViewModel.swift` (cert import)
- **PC code**: `dt_image_search/identity/device_identity.py` (cert generation: CN + custom extension only — no storage/query API changes), callers unchanged
- **Specs updated**: `instant-share-secure-discovery-trust`, `pc-revisit-session`, `revisit-transfer-skip-trust`
- **New specs**: `cert-pubkey-peer-lookup-ios`, `cert-identity-v3`
