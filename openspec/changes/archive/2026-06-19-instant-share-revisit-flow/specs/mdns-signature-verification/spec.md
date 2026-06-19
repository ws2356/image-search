## REMOVED Requirements

This capability (`mdns-signature-verification`) has been removed from the revisit flow design. The Ed25519 signature verification over mDNS TXT records is no longer needed because:

1. **mTLS already proves identity.** The TLS handshake verifies both the server's certificate (mobile authenticates the PC) and the client's certificate (PC authenticates the mobile). No additional cryptographic proof is needed.
2. **Device identity comes from the TLS cert CN.** The mobile extracts the PC's `device_id` from the certificate CN during the TLS handshake (already implemented in `CertTools.swift`).
3. **Trust evaluation failure manifests as TLS handshake failure.** When the PC doesn't trust the mobile's cert, the connection is refused at the SSL layer — no separate signature check is needed.

See `revisit-transfer-skip-trust` and `instant-share-secure-discovery-trust` for the updated flow.
