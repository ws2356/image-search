## Why

The mDNS TXT record contract was originally specified to include `device_id`, `signature`, `signature_key_id`, and `timestamp_ms`. In implementation, these fields were removed to broadcast less information, produce shorter QR codes, and produce simpler mDNS advertisements. The `instant-share-secure-discovery-trust` capability was never promoted from the archived change to the project-level `openspec/specs/` directory, creating a gap between the spec and the codebase.

## What Changes

- Promote the `instant-share-secure-discovery-trust` capability spec from the archive to `openspec/specs/`
- Update the mDNS TXT record contract to match the actual implementation: only `ver`, `tls_port`, and `device_name` are advertised
- Remove `device_id`, `signature`, `signature_key_id`, and `timestamp_ms` from the TXT record contract (dropped, not deferred — the code has no provision for them)
- Document that `InstantShareDiscoveredPC` uses a synthesized `id = host:port` for Identifiable conformance, not a device identifier from mDNS
- The QR code URL contract (`launch-agent-qr-display`) already matches the implementation and requires no changes

## Capabilities

### New Capabilities
- `instant-share-secure-discovery-trust`: mDNS-based PC discovery, TXT record contract, candidate list population, and trust establishment flow for instant sharing. Promoted from archived change `2026-06-05-add-instant-share` and reconciled with the actual implementation.

### Modified Capabilities
<!-- No existing project-level specs need modification -->

## Impact

- `dt_image_search/instant_sharing/mdns.py` — `InstantShareMDNSAdvertiser._build_txt_properties()` (current source of truth)
- `mobile/ios/Sources/ISFromMobile/Services/InstantShareMDNSBrowser.swift` — `InstantShareDiscoveredPC` struct, TXT record parsing, `resolveWithEndpoint`
- Archived spec at `openspec/changes/archive/2026-06-05-add-instant-share/specs/instant-share-secure-discovery-trust/spec.md` (historical record, not modified)
