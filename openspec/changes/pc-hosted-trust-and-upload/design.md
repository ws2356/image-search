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
- Extension flow is sequential: discover → bootstrap → handshake → apply → confirm → upload → done
- Same security guarantees (DH key exchange, AES-GCM trust envelopes, PIN verification)
- Same mDNS discovery mechanism

**Non-Goals:**
- Change the DH/HKDF key derivation protocol
- Change the trust envelope format
- Change the mDNS advertisement format
- Support bidirectional data transfer (only iOS→PC in this change)
- Change the bootstrap flow (iOS still bootstraps to PC first)

## Decisions

### Decision 1: Extend existing bootstrap server vs. new server

**Choice**: Extend the existing `InstantShareBootstrapServer` (port 9527) to also serve trust and upload endpoints.

**Rationale**: The PC already has an HTTP server on port 9527 for bootstrap. Adding trust/transfer endpoints to the same server avoids port management complexity and keeps all instant-share traffic on one port.

**Alternative considered**: Separate server on a different port — rejected because it adds complexity with no benefit (all traffic is from the same iOS device).

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
iOS → PC: /trust/handshake  (DH exchange, iOS sends its DH public key)
iOS → PC: /trust/apply      (PC generates PIN, encrypts, returns to iOS)
iOS → PC: /trust/confirm    (long-poll, PC waits for iOS to confirm user action)
iOS → PC: /transfer/text    (upload payload to PC)
```

**Key change in `/trust/apply`**: Currently PC generates the PIN, encrypts it, and sends it to iOS. In the new flow, iOS calls PC's `/trust/apply` endpoint, and the PC generates the PIN, encrypts it with the session key, and returns it in the response. iOS decrypts and displays it.

**Key change in `/trust/confirm`**: Currently PC long-polls iOS's `/trust/confirm`. In the new flow, iOS calls PC's `/trust/confirm` which long-polls internally. When the iOS UI calls `confirmTrust()`, the iOS client sends a confirmation request to PC, which resumes the long-poll.

### Decision 3: PIN generation location

**Choice**: PC generates the PIN (unchanged from current behavior).

**Rationale**: The PIN is a shared secret that both sides need to agree on. Having PC generate it (as it does now) keeps the protocol consistent. The encrypted PIN is returned to iOS via `/trust/apply` response.

### Decision 4: Upload endpoint design

**Choice**: New `/transfer/text` and `/transfer/image` endpoints on PC.

**Rationale**: These replace the current `/payload/text` and `/payload/image` endpoints on iOS, but with reversed direction — iOS POSTs data TO PC instead of PC downloading FROM iOS.

**Endpoint specifications:**
- `POST /transfer/text`: JSON body `{"text_utf8": "...", "metadata": {...}}`
- `POST /transfer/image`: Binary body with `Content-Type` and `X-Instant-Share-Filename` headers

### Decision 5: Extension flow simplification

**Choice**: Remove `InstantShareHTTPServer` from iOS entirely. Extension becomes a pure client.

**Rationale**: With no server, the extension's execution path is linear:
1. Load payload
2. mDNS browse → select PC
3. Bootstrap to PC
4. Call `/trust/handshake`
5. Call `/trust/apply` → get encrypted PIN → display PIN
6. Call `/trust/confirm` (long-poll) → wait for user confirmation
7. Upload payload via `/transfer/text` or `/transfer/image`
8. Done

No NWListener, no connection handling, no continuation-based user confirmation flow.

## Risks / Trade-offs

- **[Risk] PC firewall blocks inbound connections on port 9527** → Mitigation: Same risk as current bootstrap server. Document firewall requirements.
- **[Risk] Long-poll timeout on `/trust/confirm`** → Mitigation: PC uses same 300-second timeout as current iOS implementation. iOS extension uses `performExpiringActivity` for additional time.
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
- Should `/trust/confirm` use Server-Sent Events (SSE) instead of plain long-poll for better timeout handling?
