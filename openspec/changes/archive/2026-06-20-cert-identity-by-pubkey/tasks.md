## 1. iOS: CertTools Extensions

- [x] 1.1 Add `publicKeyHash` computed property to `SecCertificate` extension in `CertTools.swift` — returns `Data` via `Insecure.SHA1.hash(data: SecKeyCopyExternalRepresentation(SecCertificateCopyKey(self), nil))`, matching existing `deletePeerCertificate` pattern
- [x] 1.2 Add `deviceUUIDFromExtension` method to parse OID `2.25.37020860436019521` (UTF8String) from certificate using DER tag/length decoding
- [x] 1.3 Add `certVersionFromExtension` method to parse OID `2.25.37020860436019520` (INTEGER) from certificate
- [x] 1.4 Unit tests for `publicKeyHash`, `deviceUUIDFromExtension`, `certVersionFromExtension` validated via `run_unit_tests.sh`

## 2. iOS: KeychainAppIdentityProvider — Pubkey-Based Storage

- [x] 2.1 Change peer cert label from `"AuBackup Peer Certificate \(peerDeviceID)"` to constant `"AuSearch Trusted Device"`
- [x] 2.2 Update `importPeerCertificate(_ cert: SecCertificate)` — compute SHA-1 of public key external representation, store with `kSecClass = kSecClassCertificate`, `kSecAttrLabel = "AuSearch Trusted Device"`, `kSecAttrPublicKeyHash = hashData`, no `peerDeviceID` param
- [x] 2.3 Add `importPeerCertificate(pem: String)` — parse PEM, delegate to `importPeerCertificate(_:)`
- [x] 2.4 Replace `peerCertificate(for peerDeviceID:)` with `peerCertificate(forPubkeyHash hash: Data)` — query via `SecItemCopyMatching` with `kSecAttrPublicKeyHash`
- [x] 2.5 Add `peerCertificate(for cert: SecCertificate)` — extract pubkey hash from cert, delegate to `peerCertificate(forPubkeyHash:)`
- [x] 2.6 Replace `deletePeerCertificate(for:cert:)` with `deletePeerCertificate(forPubkeyHash hash: Data)` — delete by `kSecAttrPublicKeyHash` only (remove the old label-based fallback)
- [x] 2.7 Add `loadAllPeerCertificates() -> [SecCertificate]` — batch query by constant label with `kSecMatchLimitAll`
- [x] 2.8 Update `AppIdentityProviding` protocol: remove `peerDeviceID` from all peer cert method signatures
- [x] 2.9 Remove old helper `getPeerCertLabel(_:)` and all `peerDeviceID`-based code paths

## 3. iOS: Certificate Identity v3

- [x] 3.1 Bump `SELF_CERT_VERSION` from 2 to 3
- [x] 3.2 Add constant `deviceIdOID = ASN1ObjectIdentifier("2.25.37020860436019521")` for device UUID extension (separate from version OID)
- [x] 3.3 Update cert generation: set CN to `UIDevice.current.name` (sanitized), add device UUID in OID `2.25.37020860436019521` extension
- [x] 3.4 Update migration logic: detect stored version < 3 → regenerate cert with new CN + device UUID extension, preserving EC key pair
- [x] 3.5 During migration, delete old-format peer certs stored with per-device label; sanitize device name for X.509 CN (ASCII-only, fallback to "iPhone")

## 4. iOS: Trust Delegates — Pubkey-Based Validation

- [x] 4.1 Update `ISPCServerTrustDelegate.handleServerTrustChallenge()` — extract server cert's `publicKeyHash`, query `peerCertificate(forPubkeyHash:)` instead of CN+deviceID fallback
- [x] 4.2 Update `InstantShareServerTrustDelegate.handleServerTrustChallenge()` — same pubkey approach
- [x] 4.3 Update cert import in `QRTriggerDownloadClient` and `InstantShareExtensionViewModel` — call `importPeerCertificate(pem:)` without `peerDeviceID`

## 5. iOS: Unit Tests

- [x] 5.1 Update existing tests for new API signatures (remove `peerDeviceID` params)
- [x] 5.2 Add tests for pubkey-based store/query/delete cycle (`test_deletePeerCertificate_byPubkeyHash`, `test_importPeerCertificate_secCertificate_roundTrip`)
- [x] 5.3 Add tests for `loadAllPeerCertificates()` batch query (`test_loadAllPeerCertificates`)
- [x] 5.4 Run `mobile/ios/scripts/run_unit_tests.sh` — 16 test suites pass, 0 failures

## 6. PC: device_identity.py — Self-Cert Content Only

- [x] 6.1 Add `_DEVICE_ID_OID = ObjectIdentifier("2.25.37020860436019521")` constant
- [x] 6.2 Update `_generate_identity()`: add `desktop_name` parameter, set CN to `desktop_name` (fallback to hostname), add device UUID in extension OID `2.25.37020860436019521`
- [x] 6.3 Add `extract_device_name(cert: x509.Certificate) -> str` utility from CN
- [x] 6.4 Add `extract_device_id(cert: x509.Certificate) -> str | None` utility from custom extension
- [x] 6.5 Update `__init__.py` re-exports for new utilities; NO changes to existing `store_peer_certificate`, `load_peer_certificate`, etc.

## 7. PC: Caller Updates for CN Change

- [x] 7.1 Verify `https_bootstrap.py:_do_trust_confirm()` — CN now carries device name (was UUID); `store_peer_certificate` call works unchanged; variable name `mobile_device_id` is semantically misleading but functionally correct
- [x] 7.2 Verify `https_tls_server.py` — `load_all_peer_certificates()` return type unchanged, CA bundle iteration works correctly
- [x] 7.3 Verify `load_all_peer_certificates()` works unchanged (still returns `(key, pem)` tuples)
- [x] 7.4 Verify `runtime.py` — `desktop_name` already derived in `_load_or_create_identity` via `socket.gethostname().split('.')[0]` and passed to `_generate_identity`

## 8. PC: Unit Tests

- [x] 8.1 Cert generation tests: `TestCertIdentityV3` class validates CN=name, UUID-in-extension via `extract_device_name`/`extract_device_id` utilities
- [x] 8.2 `extract_device_name` and `extract_device_id` tests — 5 test cases (name from CN, UUID from extension, missing extension returns None, combined name+UUID, non-ASCII CN)
- [x] 8.3 Verify existing peer cert storage tests still pass — all 8 `TestPeerCertificateManagement` tests pass (APIs unchanged)
- [x] 8.4 `python -m pytest tests/unit/test_device_identity.py` — 13/13 tests pass
