## Context

The archived change `2026-06-05-add-instant-share` specified an mDNS TXT record contract that included `device_id`, `signature`, `signature_key_id`, and `timestamp_ms`. During implementation, these fields were removed for simplicity and privacy. The capability spec was never promoted to `openspec/specs/`, so the project-level spec directory has no record of the mDNS discovery contract. This design reconciles the spec with the code.

## Goals / Non-Goals

**Goals:**
- Promote `instant-share-secure-discovery-trust` to project-level specs
- Align the mDNS TXT record contract with the actual implementation (`ver`, `tls_port`, `device_name`)
- Document that `device_id` and signature fields are **dropped** (not deferred)
- Document that `InstantShareDiscoveredPC.id` is synthesized from `host:port`

**Non-Goals:**
- No code changes — the implementation already reflects the desired behavior
- No modification to the archived spec (historical record remains intact)
- No changes to other project-level specs (`launch-agent-qr-display`, `ios-qr-download-client`, etc.) — they already match the implementation

## Decisions

### 1. Drop `device_id` from mDNS TXT records

**Rationale:** Broadcasting a persistent device identifier over LAN adds unnecessary exposure. The `host:port` tuple is sufficient to uniquely identify a PC on the local network for the duration of a browsing session. The iOS `InstantShareDiscoveredPC.id` is synthesized as `"\(host):\(port)"` and used only for SwiftUI `Identifiable` conformance and list deduplication — it does not need a persistent identity.

**Alternatives considered:**
- *Keep device_id in TXT but don't use it* — adds bytes to the advertisement with no functional benefit
- *Use device_id for pinned trust later* — the pinned trust path (X509 exchange, signed advertisements) is deferred; if implemented later, it can be added to TXT at that time as a new version

### 2. Add `tls_port` to mDNS TXT records

**Rationale:** The PC advertises both an HTTP port and an HTTPS (TLS) port. The mobile client needs to know which TLS port to connect to for secure sessions. This was added during implementation but was absent from the original spec.

### 3. Drop `signature`, `signature_key_id`, `timestamp_ms` from TXT

**Rationale:** These fields were originally intended for a deferred feature: signature-verified mDNS advertisements enabling direct trusted shares without repeating the PIN handshake. This feature was never implemented and has no code provision. Dropping them cleanly rather than deferring keeps the spec accurate. If the signature verification path is implemented in the future, these fields can be reintroduced under the protocol version `ver` field's versioning scheme.

### 4. Preserve archive as historical record

**Rationale:** The archived spec at `openspec/changes/archive/2026-06-05-add-instant-share/specs/instant-share-secure-discovery-trust/spec.md` represents the original design intent. Modifying it would erase history. Instead, this change creates a new project-level spec that supersedes it.

## Risks / Trade-offs

- **mDNS TXT size**: Minimal. Only `ver`, `tls_port`, `device_name` — roughly 50-100 bytes total. Well within mDNS limits.
- **Future direct-trust path**: If signature-verified mDNS advertisements are implemented later, the TXT contract will need to be extended. The `ver` field provides forward compatibility for this.
- **No persistent PC identity in mDNS**: If a PC changes its IP or port, the iOS browser will see it as a new entry (different `host:port`). This is acceptable — the browser re-resolves on network changes anyway, and the user sees PC names, not IDs.

## Open Questions

- Should `ver` be bumped (e.g., to `"2"`) to signal the changed TXT contract? Currently `ver` is `"1"` in code. The mobile side does not enforce a version check — it only reads the fields it knows about. Keeping `ver` at `"1"` is acceptable since no mobile client ever relied on the removed fields.
