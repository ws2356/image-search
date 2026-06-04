## Why

The current instant-share protocol has iOS hosting 6 HTTP server endpoints while the PC acts as the HTTP client. This creates problems for the iOS Share Extension:

1. **Extension execution time pressure**: The Share Extension runs the NWListener-based HTTP server, handles incoming PC requests, and waits for long-poll `/trust/confirm` — all within the extension's limited execution window. The extension must keep running while the PC drives the flow.

2. **Complex extension-side state machine**: The extension must manage PIN display, await user confirmation via `CheckedContinuation`, serve payload bytes on demand, and handle delivery results — all while the PC controls the timing.

3. **Unreliable connection direction**: The PC connects TO the iOS device, which can fail due to iOS network sandboxing, NAT, or firewall issues. Having iOS initiate outbound HTTP requests to the PC is more reliable on constrained networks.

By inverting the architecture so the **PC hosts the trust and upload endpoints** and the **iOS extension acts as the HTTP client**, the extension becomes a simple sequential caller: discover PC → call handshake → call apply → call confirm → upload data → done. No server, no long-polls, no waiting for the PC to connect.

## What Changes

- **BREAKING**: PC adds new HTTP endpoints: `/trust/handshake`, `/trust/apply`, `/trust/confirm`, `/transfer/text`, `/transfer/image`
- **BREAKING**: iOS removes `InstantShareHTTPServer` NWListener-based server and all 6 endpoint handlers
- **BREAKING**: iOS extension becomes an HTTP client that calls PC endpoints sequentially
- **BREAKING**: Trust flow direction inverts: iOS calls PC's `/trust/handshake` (not PC calling iOS)
- **BREAKING**: PIN generation moves to PC side (PC generates, encrypts, returns to iOS via `/trust/apply`)
- **BREAKING**: Data transfer inverts: iOS uploads to PC (not PC downloading from iOS)
- Bootstrap flow unchanged: iOS still sends bootstrap to PC first
- mDNS discovery unchanged: PC advertises `_instantshare._tcp`, iOS browses
- DH session key derivation unchanged: same X25519 + HKDF-SHA256 protocol
- Trust envelope format unchanged: same AES-256-GCM envelope schema

## Capabilities

### New Capabilities
- `pc-trust-endpoints`: PC-side HTTP endpoints for trust handshake, PIN apply, and confirmation long-poll
- `pc-upload-endpoints`: PC-side HTTP endpoints for receiving text and image payloads from iOS
- `ios-trust-client`: iOS extension HTTP client that calls PC's trust endpoints sequentially
- `ios-upload-client`: iOS extension HTTP client that uploads text/image to PC

### Modified Capabilities
- (none — this is a full architectural inversion, not a modification of existing behavior)

## Impact

- **PC Python code**: `http_client.py` replaces `InstantShareHttpClient` (outbound calls to iOS) with `InstantShareTrustHandler` + `InstantShareUploadHandler` (inbound HTTP handlers). `orchestrator.py` changes from driving outbound calls to receiving inbound requests. `https_bootstrap.py` extends to also serve trust/transfer endpoints (or a new server is created).
- **iOS Swift code**: `InstantShareHTTPServer.swift` removed. New `InstantShareTrustClient.swift` and `InstantShareUploadClient.swift` replace it. `InstantShareService.swift` simplified to sequential client flow. `InstantShareExtensionViewModel.swift` drives the sequential flow.
- **Protocol contracts**: Endpoint paths change from iOS-hosted to PC-hosted. Request/response bodies remain the same but direction flips.
- **No dependency changes**: Same `zeroconf`, `Network.framework`, `CryptoKit` usage.
