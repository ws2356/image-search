## 1. iOS: CertTools Extensions

- [ ] 1.1 Add `publicKeyHash` computed property to `SecCertificate` extension in `CertTools.swift` — returns `Data` via `Insecure.SHA1.hash(data: SecKeyCopyExternalRepresentation(SecCertificateCopyKey(self), nil))`, matching existing `deletePeerCertificate` pattern
- [ ] 1.2 Add `deviceUUIDFromExtension` method to parse OID `2.25.37020860436019521` (UTF8String) from certificate
- [ ] 1.3 Add `certVersionFromExtension` method to parse OID `2.25.37020860436019520` (INTEGER) from certificate
- [ ] 1.4 Add unit tests for `publicKeyHash`, `deviceUUIDFromExtension`, `certVersionFromExtension`

## 2. iOS: KeychainAppIdentityProvider — Pubkey-Based Storage

- [ ] 2.1 Change peer cert label from `"AuBackup Peer Certificate \(peerDeviceID)"` to constant `"AuSearch Trusted Device"`
- [ ] 2.2 Update `importPeerCertificate(_ cert: SecCertificate)` — compute SHA-1 of public key external representation, store with `kSecClass = kSecClassCertificate`, `kSecAttrLabel = "AuSearch Trusted Device"`, `kSecAttrPublicKeyHash = hashData`, no `peerDeviceID` param
- [ ] 2.3 Add `importPeerCertificate(pem: String)` — parse PEM, delegate to `importPeerCertificate(_:)`
- [ ] 2.4 Replace `peerCertificate(for peerDeviceID:)` with `peerCertificate(forPubkeyHash hash: Data)` — query via `SecItemCopyMatching` with `kSecAttrPublicKeyHash`
- [ ] 2.5 Add `peerCertificate(for cert: SecCertificate)` — extract pubkey hash from cert, delegate to `peerCertificate(forPubkeyHash:)`
- [ ] 2.6 Replace `deletePeerCertificate(for:cert:)` with `deletePeerCertificate(forPubkeyHash hash: Data)` — delete by `kSecAttrPublicKeyHash` only (remove the old label-based fallback)
- [ ] 2.7 Add `loadAllPeerCertificates() -> [SecCertificate]` — batch query by constant label with `kSecMatchLimitAll`
- [ ] 2.8 Update `AppIdentityProviding` protocol: remove `peerDeviceID` from all peer cert method signatures
- [ ] 2.9 Remove old helper `getPeerCertLabel(_:)` and all `peerDeviceID`-based code paths

## 3. iOS: Certificate Identity v3

- [ ] 3.1 Bump `SELF_CERT_VERSION` from 2 to 3
- [ ] 3.2 Add constant `_DEVICE_ID_OID = "2.25.37020860436019521"` for device UUID extension (separate from version OID `2.25.37020860436019520`)
- [ ] 3.3 Update cert generation: set CN to `UIDevice.current.name` (sanitized), add device UUID in OID `2.25.37020860436019521` extension
- [ ] 3.4 Update migration logic: detect stored version < 3 → regenerate cert with new CN + device UUID extension, preserving EC key pair
- [ ] 3.5 Sanitize device name for X.509 CN (ASCII-only, trim whitespace, fallback to "iPhone")

## 4. iOS: Trust Delegates — Pubkey-Based Validation

- [ ] 4.1 Update `ISPCServerTrustDelegate.handleServerTrustChallenge()` — extract server cert's `publicKeyHash`, query `peerCertificate(forPubkeyHash:)` instead of CN+deviceID fallback
- [ ] 4.2 Update `InstantShareServerTrustDelegate.handleServerTrustChallenge()` — same pubkey approach
- [ ] 4.3 Update cert import in `QRTriggerDownloadClient` and `InstantShareExtensionViewModel` — call `importPeerCertificate(pem:)` without `peerDeviceID`

## 5. iOS: Unit Tests

- [ ] 5.1 Update existing tests for new API signatures (remove `peerDeviceID` params)
- [ ] 5.2 Add tests for pubkey-based store/query/delete cycle
- [ ] 5.3 Add tests for `loadAllPeerCertificates()` batch query
- [ ] 5.4 Add tests for v2→v3 cert migration (name in CN, UUID in extension, old peer cert cleanup)
- [ ] 5.5 Run `xcodebuild test` to verify all tests pass

## 6. PC: device_identity.py — Self-Cert Content Only

- [ ] 6.1 Add `_DEVICE_ID_OID = ObjectIdentifier("2.25.37020860436019521")` constant
- [ ] 6.2 Update `_generate_identity()`: add `desktop_name` parameter, set CN to `desktop_name` (fallback to hostname), add device UUID in extension OID `2.25.37020860436019521`
- [ ] 6.3 Add `extract_device_name(cert: x509.Certificate) -> str` utility from CN
- [ ] 6.4 Add `extract_device_id(cert: x509.Certificate) -> str | None` utility from custom extension
- [ ] 6.5 Update `__init__.py` re-exports for new utilities; NO changes to existing `store_peer_certificate`, `load_peer_certificate`, etc.

## 7. PC: Caller Updates for CN Change

- [ ] 7.1 Update `https_bootstrap.py:_do_trust_confirm()` — where `peer_device_name` is extracted from certificate CN, confirm it now correctly extracts the device name (was UUID)
- [ ] 7.2 Update `https_tls_server.py` — any code extracting CN for device name should now get human-readable name
- [ ] 7.3 Verify `load_all_peer_certificates()` works unchanged (still returns `(device_id, pem)` tuples)
- [ ] 7.4 Verify `runtime.py` passes desktop name to identity generation if available

## 8. PC: Unit Tests

- [ ] 8.1 Add tests for cert generation with name-in-CN and UUID-in-extension
- [ ] 8.2 Add tests for `extract_device_name` and `extract_device_id` utilities
- [ ] 8.3 Verify existing peer cert storage tests still pass (APIs unchanged)
- [ ] 8.4 Run `python -m pytest` on identity and instant_sharing tests
