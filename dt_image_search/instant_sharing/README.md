# Instant Share

Instant Share enables low-friction "share and forget" content transfer from iPhone to PC via the iOS Share Extension.

## Architecture

```
iOS Share Extension          AuBackup Main App              PC (AuSearch)
┌──────────────┐          ┌──────────────────┐          ┌─────────────────┐
│ BLE Scanner  │          │ Trust + Transfer │          │ BLE Daemon      │
│ Selector Card│──handoff─▶│ HTTP Server     │◀──HTTPS──│ Orchestrator    │
│ Payload Norm │          │ PIN Confirm UI   │          │ Delivery Service│
└──────────────┘          └──────────────────┘          └─────────────────┘
```

### Components

| Component | Location | Role |
|-----------|----------|------|
| BLE Daemon | `dt_image_search/instant_sharing/ble.py` | Always-on GATT service broadcasting PC identity via `bless` |
| Orchestrator | `dt_image_search/instant_sharing/orchestrator.py` | Session lifecycle, trust, payload receive |
| HTTP Client | `dt_image_search/instant_sharing/http_client.py` | PC-side HTTPS caller with TLS pinning |
| Delivery Service | `dt_image_search/instant_sharing/delivery.py` | Routes payloads to clipboard or files |
| Sender Identity | `dt_image_search/instant_sharing/sender_validation.py` | Ed25519 signing identity management |
| Trust Crypto | `dt_image_search/instant_sharing/trust_crypto.py` | AES-GCM trust session envelope |
| Security | `dt_image_search/instant_sharing/security.py` | X25519 DH + Ed25519 session signing |
| Runtime | `dt_image_search/instant_sharing/runtime.py` | Composition root wiring all components |
| iOS BLE Scanner | `mobile/ios/.../InstantShareBLEScanner.swift` | CBCentralManager wrapper |
| iOS HTTP Server | `mobile/ios/.../InstantShareHTTPServer.swift` | NWListener with TLS 1.3 |
| iOS Trust Manager | `mobile/ios/.../InstantShareTrustSessionManager.swift` | X25519 ECDH + HKDF |

## Setup

### Feature Flag

Instant Share is gated behind a feature flag. Check `dt_image_search/model/feature_flags.py`:

```python
from dt_image_search.model.feature_flags import is_instant_share_enabled
```

Default: **off**. Enable via remote config payload with `instant_share: true`.

### PC-Side Requirements

- Python 3.10+ with `cryptography` package
- BLE hardware (daemon polls for ConnectionConfig writes)
- Network access to mobile device IP (same LAN)

### iOS-Side Requirements

- iOS 16+ with Bluetooth permission (`NSBluetoothAlwaysUsageDescription`)
- TLS identity generated at runtime (EC P-256 keypair in iOS Keychain)
- App Group configured for Share Extension handoff (pending implementation)

## Protocol Flow

### First Share (Trust Establishment)

```
1. iOS scans BLE → discovers PC
2. User taps PC in selector card
3. Share Extension hands off to AuBackup
4. AuBackup writes ConnectionConfig via BLE
5. PC calls /trust/handshake (DH exchange)
6. PC calls /trust/apply (encrypted PIN) + /trust/confirm (parallel)
7. Both devices show PIN → user confirms match
8. X509 public keys exchanged
9. PC downloads payload via HTTPS with TLS pinning
10. PC delivers to clipboard/file
```

### Trusted Revisit (Skip Trust)

```
1. iOS scans BLE → verifies DeviceSignature
2. User taps trusted PC
3. AuBackup writes ConnectionConfig via BLE
4. PC downloads payload directly (signed requests + TLS pin)
5. PC delivers to clipboard/file
```

## Delivery Rules

| Payload | Target | Behavior |
|---------|--------|----------|
| Text | Clipboard only | Exact UTF-8 text written to clipboard |
| Image | Clipboard or file | File mode: saved to ~/Downloads with collision resolution |
| Video | Local file only | Deferred to follow-up iteration |
| Other files | Local file only | Deferred to follow-up iteration |

## Rollout

### Staged Enablement Checklist

1. **Internal testing** (current): Feature flag off by default. Enable manually for dev machines.
2. **Dogfooding**: Enable for internal team via remote config. Monitor telemetry for error rates.
3. **Beta**: Enable for beta users. Watch for BLE reliability issues and trust flow failures.
4. **GA**: Enable for all users. Monitor `instant_share.*` telemetry attributes.

### Rollback Procedure

1. Set `instant_share: false` in remote config
2. BLE daemon stops broadcasting on next poll cycle
3. Existing sessions complete or timeout naturally
4. No data loss: payloads remain on iOS until successful delivery

## Troubleshooting

### Common Issues

| Symptom | Cause | Resolution |
|---------|-------|------------|
| No PCs discovered | BLE permission denied or hardware off | Check iOS Bluetooth settings; verify `NSBluetoothAlwaysUsageDescription` |
| Trust handshake fails | Network unreachable | Ensure devices on same LAN; check firewall rules |
| PIN mismatch | User error or clock skew | Retry trust flow; verify device clocks are synchronized |
| TLS pin validation failed | Certificate changed | Re-establish trust (delete cached public key) |
| Transfer timeout | Large payload or slow network | User can wait or abort; no size-based rejection |
| Session busy | Concurrent share attempt | Wait for active session to complete; single-session model |

### Telemetry Attributes

All instant-share events include:
- `instant_share.session_id`
- `instant_share.correlation_id`
- `instant_share.payload_class`
- `instant_share.target_intent`
- `instant_share.trust_mode`
- `instant_share.state`
- `instant_share.error_code` (if error)

### Manual Testing

Use the PC CLI script:
```bash
python dt_image_search/scripts/instant_share_agent_main.py
```

Use the iOS debug view (HomeView → Instant Share Debug) for full discovery → select → connect → trust → transfer flow.

## Known Limits

- **Single active session**: Only one instant-share transfer at a time per receiver
- **No concurrent transfers**: Additional attempts return `RECEIVER_BUSY_SINGLE_SESSION`
- **No size-based rejection**: User controls wait/abort for large payloads
- **Text-to-file not supported**: Text payloads go to clipboard only
- **Video/other files deferred**: Only text and image in current slice
- **No mTLS**: Session-id signature verification only (can add mTLS later)
- **BLE GATT server via `bless`**: PC uses the [`bless`](https://github.com/kevincar/bless) library to advertise the `4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b` GATT service with DeviceName (read), DeviceSignature (read), and ConnectionConfig (write) characteristics. Requires Bluetooth permission on first run.
