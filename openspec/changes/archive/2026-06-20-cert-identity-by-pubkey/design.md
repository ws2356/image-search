## Context

Peer certificates on iOS are currently stored and looked up by `peerDeviceID` — the device UUID string from the CN field. This requires callers to know and pass the peer's UUID, creating an unnecessary indirection during server trust evaluation. The public key hash is a self-contained identity extracted directly from the certificate at handshake time — no string parsing or CN extraction needed.

Additionally, the CN field currently stores the opaque device UUID on both iOS and PC, which is not human-readable. The device name belongs in CN (for UI display); the device UUID belongs in a custom X.509 extension.

This design is **iOS-focused** for the storage/query changes. The PC side only receives a certificate content update (name in CN, UUID in extension) — no storage or query API changes on PC.

## Goals / Non-Goals

**Goals:**
- iOS: Store/lookup/delete peer certificates by public key hash instead of `peerDeviceID`
- iOS: Constant keychain label `"AuSearch Trusted Device"` for batch query support
- iOS: Remove `peerDeviceID` parameter from `AppIdentityProviding` protocol
- iOS + PC: Device name in certificate CN field (was device UUID)
- iOS + PC: Device UUID in dedicated custom X.509 extension (OID `2.25.37020860436019521`)
- iOS: `SELF_CERT_VERSION` bumped to 3 with auto-migration preserving the EC key pair
- iOS: Migration also deletes old-format peer certs

**Non-Goals:**
- Changing PC-side peer cert storage/query APIs (NO changes to `store_peer_certificate`, `load_peer_certificate`, etc.)
- Changing cryptographic algorithms (P-256 ECDSA, SHA-256)
- Changing the trust handshake protocol flow
- Android/Rn support

## Decisions

### Decision 1: SHA-1 of public key external representation via kSecAttrPublicKeyHash
**Choice**: Use `kSecAttrPublicKeyHash` (a standard iOS Keychain certificate attribute) with SHA-1 hash of `SecKeyCopyExternalRepresentation(publicKey)` as the lookup key.

**Rationale**: This is the pattern already proven in the existing `deletePeerCertificate` code: `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → `Insecure.SHA1.hash` → `kSecAttrPublicKeyHash`. iOS Keychain natively supports `SecItemCopyMatching` and `SecItemDelete` queries by `kSecAttrPublicKeyHash`. No custom hash-to-string encoding needed — it works directly with `Data`. The existing codebase already has this exact pattern for deletion; extending it to queries is trivial.

### Decision 2: Separate OIDs for version and device UUID
**Choice**: 
- `2.25.37020860436019520` — cert version (existing OID, ASN.1 INTEGER)
- `2.25.37020860436019521` — device UUID (new OID, ASN.1 UTF8String)

**Rationale**: These are semantically different attributes (integer version vs string UUID). Using the same OID for both would require a compound encoding (e.g., SEQUENCE of INTEGER + UTF8String), which adds unnecessary parsing complexity and is fragile. Separate extensions are self-describing and simple.

### Decision 3: iOS migration deletes old peer certs
**Choice**: When migrating from v2 to v3 self-cert, delete all peer certs stored with the old label pattern `"AuBackup Peer Certificate *"`.

**Rationale**: The old peer certs are keyed by `peerDeviceID` embedded in the label string. After migration, the lookup mechanism changes to pubkey hash via `kSecAttrAccount`. Old peer certs stored with the old pattern become orphans — they can't be found via the new query method. Deleting them is simpler than attempting a migration of unknown peer certs. Trust relationships will be re-established during the next trust handshake.

### Decision 4: No PC storage/query API changes
**Choice**: PC-side `store_peer_certificate(peer_device_id, cert_pem)`, `load_peer_certificate(peer_device_id)`, etc. retain their current signatures and storage mechanism.

**Rationale**: The PC storage already works. The peer lookup on PC uses `peer_device_id` derived from the TLS certificate identity — this is sufficient for the existing revisit flow. Changing it would require coordination with the TLS server's cert injection logic. The iOS side benefits from pubkey-based lookup because iOS trust delegates need to extract the identity from `SecTrust` directly during the TLS handshake callback, where the public key is the most natural identity.

### Decision 5: Constant keychain label on iOS
**Choice**: Use `kSecAttrLabel = "AuSearch Trusted Device"` for all peer certificates, matching the PC side's existing label constant.

**Rationale**: Enables batch queries via `SecItemCopyMatching` with `kSecMatchLimit = kSecMatchLimitAll` and a label predicate. The PC side already uses this pattern. The account attribute carries the differentiating pubkey hash.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| iOS migration deletes all existing trust relationships | Trust is re-established during next handshake; this is acceptable since self-cert migration is a one-time event |
| SHA-256 hash collision on P-256 keys | Cryptographically infeasible |
| Device name contains characters invalid for X.509 CN | Sanitize to ASCII; fall back to "iPhone" / hostname |
| PC callers of `store_peer_certificate` expecting new signature | No changes — PC APIs are unchanged |
| iOS Keychain query by `kSecAttrAccount` returns wrong cert if hash collision | Not possible with SHA-256 |

## Open Questions

- **Q1**: Should old peer certs be migrated (re-stored with new pubkey hash key) instead of deleted? → Deleted for simplicity. Re-establishing trust is a one-time UX cost per peer device.
