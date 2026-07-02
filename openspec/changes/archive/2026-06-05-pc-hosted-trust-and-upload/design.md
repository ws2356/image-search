## Context

The instant-share protocol currently has iOS hosting 6 HTTP server endpoints (trust handshake, trust apply, trust confirm, payload text, payload image, delivery result) while the PC acts as the HTTP client. This architecture was originally designed around BLE characteristics where the mobile was the peripheral (server) and the desktop was the central (client).

With the migration to mDNS + HTTP, this server-on-mobile pattern creates problems:
- iOS Share Extensions have limited execution time (~30 seconds for foreground, up to ~5 minutes with background tasks)
- The extension must keep a NWListener running while the PC drives the timing of trust and transfer operations
- Network sandboxing on iOS can block inbound connections more easily than outbound

The new architecture inverts the client-server relationship: **PC hosts the HTTP endpoints, iOS extension calls them**.

## Goals / Non-Goals

**Goals:**
- PC hosts all trust and upload HTTP endpoints
- iOS extension acts as a pure HTTP client (no server)
- Extension flow is sequential: discover → handshake (includes bootstrap) → apply → confirm → upload → done
- Same security guarantees (DH key exchange, AES-GCM trust envelopes, PIN verification)
- Same mDNS discovery mechanism
- Trust confirmation is mobile-side only (user taps Confirm on iOS, not PC)

**Non-Goals:**
- Change the DH/HKDF key derivation protocol
- Change the trust envelope format
- Change the mDNS advertisement format
- Support bidirectional data transfer (only iOS→PC in this change)
- Bootstrap endpoint removed (iOS drives trust directly via /trust/handshake)

## Decisions

### Decision 1: Bootstrap endpoint removed

**Choice**: The bootstrap endpoint (`POST /api/instant-share/v1/sessions/bootstrap`) is removed. The `InstantShareHTTPServer` (port 9527) now serves only trust and transfer endpoints. Trust sessions are created on-demand by the `/trust/handshake` endpoint when iOS initiates the trust flow.

**Rationale**: iOS drives the trust establishment directly via `/trust/handshake`, `/trust/apply`, and `/trust/confirm` endpoints. The separate bootstrap step is no longer necessary.

**Alternative considered**: Keeping the bootstrap endpoint — rejected because iOS now works as a client-only and initiates trust without a bootstrap step.

### Decision 2: Trust flow inversion details

**Current flow** (PC drives):
```
PC → iOS: /trust/handshake  (DH exchange)
PC → iOS: /trust/apply      (send encrypted PIN)
PC → iOS: /trust/confirm    (long-poll, wait for user)
PC → iOS: /payload/text     (download payload)
```

**New flow** (iOS drives):
```
iOS → PC: /trust/handshake  (plain DH key exchange, both sides derive session key)
iOS → PC: /trust/apply      (encrypted request+response, PC returns PIN; both sides display)
iOS → PC: /trust/confirm    (encrypted request+response, mobile-side confirmation)
iOS → PC: /transfer/text    (upload payload to PC)
```

### Decision 3: Three-step trust with clear semantics

The trust flow has three distinct steps with clear boundaries:

1. **`/trust/handshake`** — Plain-text DH key exchange.
   - iOS sends its X25519 DH public key and a 32-byte nonce.
   - PC stores the iOS DH public key, generates its own nonce + kdf_context, returns them.
   - Both sides derive the AES-GCM session key using HKDF-SHA256.
   - **No encryption** — the session key is needed for encryption in the next step.
   - **No PIN** — the PIN is generated only after the key is established.

2. **`/trust/apply`** — Encrypted PIN retrieval.
   - iOS sends a request envelope (encrypted with the session key) — body is `{"action": "request_pin"}`.
   - PC generates a 6-digit PIN, encrypts it in a trust envelope, returns the envelope.
   - iOS decrypts the envelope and displays the PIN.
   - PC also displays the PIN on its mini window.
   - Both request and response are encrypted — this proves both sides have derived the same session key.

3. **`/trust/confirm`** — Encrypted confirmation.
   - iOS sends an encrypted request — body is `{"action": "confirm", "pin_verified": true}`.
   - PC decrypts, marks the trust session as `trusted`, returns encrypted `{"trust_status": "trusted"}`.
   - **No long-polling** — iOS sends the confirmation after the user taps Confirm in the iOS UI.
   - **Mobile-side only** — PC does not require a separate user action; iOS user is the trust authority.

### Decision 4: PIN generation location

**Choice**: PC generates the PIN in response to `/trust/apply`.

**Rationale**: The PIN is a shared secret that both sides need to agree on. PC generates it once and returns it encrypted to iOS. PC also displays the same PIN on its mini window.

### Decision 5: Upload endpoint design

**Choice**: New `/transfer/text` and `/transfer/image` endpoints on PC.

**Rationale**: These replace the current `/payload/text` and `/payload/image` endpoints on iOS, but with reversed direction — iOS POSTs data TO PC instead of PC downloading FROM iOS.

**Endpoint specifications:**
- `POST /transfer/text`: JSON body `{"text_utf8": "...", "metadata": {...}}`
- `POST /transfer/image`: Binary body with `Content-Type` and `X-Instant-Share-Filename` headers

### Decision 6: Extension flow simplification

**Choice**: Remove `InstantShareHTTPServer` from iOS entirely. Extension becomes a pure client.

**Rationale**: With no server, the extension's execution path is linear:
1. Load payload
2. mDNS browse → select PC
3. Bootstrap to PC
4. Call `/trust/handshake` (plain DH exchange)
5. Call `/trust/apply` (encrypted) → get PIN → display PIN
6. User taps Confirm on iOS
7. Call `/trust/confirm` (encrypted) → trust established
8. Upload payload via `/transfer/text` or `/transfer/image`
9. Done

No NWListener, no connection handling, no continuation-based long-poll.

## Risks / Trade-offs

- **[Risk] PC firewall blocks inbound connections on port 9527** → Mitigation: Same risk as current bootstrap server. Document firewall requirements.
- **[Risk] User has to look at two devices to verify PIN** → Mitigation: Both sides show the same 6-digit PIN. Standard pairing UX (like Bluetooth pairing).
- **[Risk] Breaking change for existing installations** → Mitigation: Both PC and iOS must be updated together. No backward compatibility with old protocol.
- **[Trade-off] PC must be reachable from iOS** → Same as current bootstrap flow. No new network requirements.

## Migration Plan

1. Implement PC-side trust/transfer endpoints (Python)
2. Implement iOS-side trust/upload clients (Swift)
3. Remove iOS HTTP server code
4. Update extension ViewModel to use sequential client flow
5. Test end-to-end on local network
6. Update OpenSpec specs and tasks

## Open Questions

- Should the PC's trust handler run on the same thread as the bootstrap server, or use a separate thread pool?
- Should the iOS client retry on transient network errors during handshake/apply/confirm?
