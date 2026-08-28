# Design: Android AOA USB Backup Transport

Date: 2026-07-28
Status: Approved

## Goal

Implement end-to-end USB backup transport for the Android AuBackup React Native app using Android Open Accessory (AOA). The mobile app must be able to pair with, and transfer media to, the desktop AuSearch app over a USB cable, while transparently falling back to LAN when USB is unavailable.

## Decisions captured from design review

| Topic | Decision |
| --- | --- |
| Scope | Full end-to-end: native Android AOA runtime, RN bridge, TypeScript transport strategy, adaptive transport selection, and a production desktop AOA adapter. |
| Protocol | Reuse the existing `dtis.mobile-transport.v1` envelope protocol and `dtis.mobile-pairing.v1` auth handshake used by iOS USB/WebSocket. Replace only the wire framing with an AOA length-prefixed frame. |
| Pairing | Full USB pairing + transfer: after QR scan, mobile prepares AOA bootstrap and the desktop connects via AOA for `pairing.claim` / `pairing.state` as well as transfer operations. |
| Encryption | Match the LAN path: capability exchange, trust-proof signing, and `MobilePayloadEncryption` for JSON envelopes and binary asset chunks. |
| Transport selection | Automatic prefer-USB with LAN fallback, similar to the iOS `AdaptiveMobileTransferClient`. |
| Host validation | macOS first. Windows driver work follows once the macOS implementation is stable. |
| Auth challenge | Computed inside native `AoaClient` using `opt` passed via `prepareBootstrap`; no JavaScript callback or two-round correlation is used. |
| End-to-end tests | No automated end-to-end tests required. The implementation will be unit-tested and manually smoke-tested on a real Android device. |

## Architecture

```text
+-----------------------------------------+        AOA bulk endpoints          +---------------------------+
|  AuBackup Android (React Native)        | <================================> |  AuSearch Desktop (PyQt)  |
|                                         |                                    |                           |
|  UI / hooks  ->  AdaptiveTransportStrategy -> AoaTransportStrategy         |  MobileTransportManager    |
|                          |                                        |         |       |                   |
|           (LAN fallback) |                                        |         |  LanHttpTransportAdapter  |
|                          v                                        v         |       |                   |
|            LanTransportStrategy  <---------------------------->  LAN HTTP  |  UsbAoaTransportAdapter   |
|                          |                                                   |                           |
|  NativeModules.AoaTransportModule                                  |         |  MobileTransportRouter    |
|                          |                                       |          |       |                   |
|  AoaClient (Kotlin) <----> AOA frame codec / auth responder        |          |  pairing + transfer handlers |
+-----------------------------------------+                          |          +---------------------------+
```

## Wire protocol

### AOA frame format

Every message sent over the AOA bulk endpoints is wrapped in a length-prefixed binary frame. The header is intentionally identical to the iOS USB binary asset-chunk header and the Phase-0 AOA POC header so existing framing logic can be reused.

```text
0        1        37       41       42
| version | request_id | length | flags | payload |
```

- `version` (1 byte): `0x01`.
- `request_id` (36 bytes): exactly 36 ASCII bytes. For text envelopes the frame `request_id` may be zero-filled because the envelope carries its own `request_id`; for binary asset-chunk frames it must be the active streaming request UUID.
- `length` (4 bytes, big-endian): length of the payload that follows.
- `flags` (1 byte): frame type.
  - `0x00` — text envelope.
  - `0x01` — binary asset chunk.
- `payload`: the enclosed message.

Two payload types travel over this frame:

1. **Text envelope** — `flags = 0x00`; payload is a UTF-8 JSON string containing a `dtis.mobile-transport.v1` envelope.
2. **Binary chunk** — `flags = 0x01`; payload is raw bytes of an encrypted asset chunk. The `request_id` ties the chunk to the active streaming request.

### Auth handshake

1. Desktop opens the AOA accessory and sends a text envelope:

```json
{
  "schema": "dtis.mobile-transport.v1",
  "operation": "transport.auth.challenge",
  "request_id": "auth-challenge",
  "body_schema": "dtis.mobile-pairing.v1",
  "body": {
    "schema": "dtis.mobile-pairing.v1",
    "sid": "<session_id from QR>",
    "rand": "<desktop random nonce>"
  }
}
```

2. Mobile validates that `sid` matches the prepared bootstrap session. It computes:

```text
proof = SHA256(opt + rand)
```

where `opt` is the one-time passcode from the QR payload.

3. Mobile responds with a text envelope:

```json
{
  "schema": "dtis.mobile-transport.v1",
  "request_id": "auth-challenge",
  "status_code": 200,
  "body": {
    "schema": "dtis.mobile-pairing.v1",
    "status": "accepted",
    "proof": "<hex digest>"
  }
}
```

4. Desktop verifies the proof and marks the connection authenticated.

### Application envelopes

After authentication, the mobile and desktop exchange the same envelopes used by LAN and iOS USB:

- `pairing.claim`
- `pairing.state`
- `capabilities.exchange`
- `transfer.start`
- `transfer.existence`
- `transfer.asset`
- `transfer.complete`
- `update.prompt`

Each request envelope includes `schema`, `operation`, `request_id`, `body_schema`, and `body`. Each response envelope echoes `request_id`, includes `status_code`, and a `body`.

### Encrypted asset streaming

For `transfer.asset`:

1. Mobile sends a text envelope with `stream_state: "start"`, metadata, and optional `chunk_size`.
2. Mobile sends one or more binary frames containing encrypted asset chunks.
3. Mobile sends a text envelope with `stream_state: "complete"`.
4. Desktop responds with the asset result envelope.

The encryption is the same `MobilePayloadEncryption` used on LAN; the capability exchange determines whether it is enabled.

## Native Android AOA runtime

### Files

- `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaClient.kt`
- `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaFrameCodec.kt`
- `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportModule.kt`
- `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportError.kt`
- `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportState.kt`

### Components

**AoaClient**

- Owns the AOA state machine (`idle`, `preparing`, `authenticating`, `connected`, `disconnected`, `failed`).
- Registers for `UsbManager.ACTION_USB_ACCESSORY_ATTACHED` / `DETACHED`.
- Requests accessory permission via `UsbManager.requestPermission()`.
- Opens the accessory `ParcelFileDescriptor` and starts a reader thread plus a writer thread.
- Handles the incoming `transport.auth.challenge` as a special response path: it validates `sid`, computes the `SHA256(opt + rand)` proof, and sends the auth response envelope back to the desktop. The one-time passcode `opt` is stored in native memory after `prepareBootstrap` and is never exposed to the JavaScript layer, matching the iOS USB implementation. The name `AoaClient` is kept because this class is the mobile-side peer that both sends requests and handles desktop-initiated challenge responses.
- Correlates request/response envelopes by `request_id` and resolves pending JS promises.
- Manages streaming asset requests: allows binary chunks to be sent for an active `request_id` until the completion envelope is sent.
- On detach, rejects all pending promises with `connectionUnavailable`.

**AoaFrameCodec**

- Encodes and decodes the AOA frame header.
- Provides a streaming decoder that can accumulate partial reads from the accessory.

**AoaTransportModule**

React Native bridge module exposing typed methods:

```typescript
prepareBootstrap(sessionId: string, oneTimePasscode: string, suggestedPort: number): Promise<void>
reset(): Promise<void>
isConnected(): boolean
sendRequest(envelopeJson: string): Promise<string>
beginStreamingRequest(envelopeJson: string): Promise<string>
sendBinaryChunk(requestId: string, chunk: Uint8Array): Promise<void>
finishStreamingRequest(requestId: string): Promise<string>
addListener(eventName: string): void
removeListeners(count: number): void
```

The module emits a single event `AoaTransportStateChanged` with state objects (`connected`, `disconnected`, `error`, `errorMessage`).

### Lifecycle

- `MainApplication.onCreate` initializes `AoaClient` and registers the broadcast receiver. It does not yet open the accessory; it only prepares for attachment events.
- When the user scans a QR code, TypeScript calls `prepareBootstrap(sessionId, opt, usp)`.
- If a USB accessory is already attached, the runtime opens it immediately. If not, it waits for the next `ACTION_USB_ACCESSORY_ATTACHED`.
- The desktop negotiates AOA mode and opens the accessory. The mobile runtime receives the auth challenge, validates it, and the connection becomes `connected`.
- During transfer, the runtime remains connected. If the user stops the session or the screen unmounts, TypeScript calls `reset()`.
- If the cable is detached, the runtime transitions to `disconnected`, rejects pending promises, and the adaptive transport layer falls back to LAN.

### Concurrency

- A dedicated background thread reads from the accessory `FileInputStream` and pushes decoded frames into a thread-safe queue.
- A second background thread serializes writes to the accessory `FileOutputStream` so frames never interleave.
- JS promises are resolved on the React Native bridge thread pool.

## React Native / TypeScript transport layer

### Files

- `mobile/rn/infrastructure/transport/aoa/aoa-transport-strategy.ts`
- `mobile/rn/infrastructure/transport/aoa/aoa-bridge.ts`
- `mobile/rn/infrastructure/transport/adaptive-transport-strategy.ts`
- `mobile/rn/infrastructure/di/app-services-provider.tsx`

### AoaTransportStrategy

Implements `TransportStrategy` from `infrastructure/transport/transport-strategy.ts`.

- `claim_pairing`, `get_pairing_state`, `start_transfer`, `check_transfer_existence`, and `complete_transfer` build the `dtis.mobile-transport.v1` envelope, call `AoaBridge.sendRequest`, and return the parsed response body.
- `upload_transfer_asset` begins a streaming request, then iterates over the asset source in chunks, encrypts each chunk if encryption is enabled, and sends binary frames via `AoaBridge.sendBinaryChunk`. It finishes with `finishStreamingRequest`.
- Uses `TrustProofSigner` and `PayloadCipher` for encryption so the behavior is identical to LAN.

### AoaBridge

A thin wrapper around `NativeModules.AoaTransportModule` that:

- Converts TypeScript objects to envelope JSON strings.
- Parses response JSON.
- Wraps native errors in a typed `AoaTransportError`.
- Emits state-change events to subscribers.

### AdaptiveTransportStrategy

Wraps `AoaTransportStrategy` and `LanTransportStrategy`. For every operation:

1. If `AoaBridge.isConnected()` is true, try AOA.
2. If AOA fails, mark AOA unavailable for a short cooldown (e.g., 500 ms) and retry the same operation over LAN.
3. If LAN succeeds, the next operation attempts AOA again after the cooldown.
4. If the desktop signals an old version (no `aoa_transfer` capability), the strategy falls back to LAN and may trigger the update prompt.

### DI and wiring

`AppServicesProvider` becomes the composition root for backup services:

```typescript
const services = {
  runtimeMode: 'native-capable',
  aoaBridge: new NativeAoaBridge(),
  lanTransportStrategy: new LanTransportStrategy(...),
  aoaTransportStrategy: new AoaTransportStrategy(aoaBridge, ...),
  adaptiveTransportStrategy: new AdaptiveTransportStrategy(aoaTransportStrategy, lanTransportStrategy),
};
```

Existing hooks (`useTransferScreenController`, `startTransfer`) are updated to accept an injected transport strategy instead of constructing the LAN-only `TransferService` internally.

## Desktop Python AOA adapter

### File

- `dt_image_search/mobile/transport/usb_aoa_adapter.py`

### Responsibilities

`UsbAoaTransportAdapter` in `usb_aoa_adapter.py` provides the same external contract as `UsbWebSocketTransportAdapter` so `MobileTransportManager` can own it without changing its shape:

- `configure_bootstrap(config: UsbBootstrapConfig)` stores `session_id`, `one_time_passcode`, and `suggested_port`.
- `start()` launches a daemon probe thread.
- `stop()` stops the thread and closes the accessory connection.
- `state`, `bootstrap_config`, `last_probe_error` properties.

### Probe thread

1. Lists USB devices via PyUSB.
2. Detects AOA-capable devices and devices already in accessory mode.
3. If a device is not in accessory mode, sends the AOA string descriptors and starts accessory mode (reusing `android_aoa_poc.py` logic).
4. Opens the accessory interface and locates the bulk IN and OUT endpoints.
5. Sends the `transport.auth.challenge` envelope and waits for the mobile proof.
6. Once authenticated, reads framed envelopes and dispatches them through `MobileTransportRouter`.
7. For `transfer.asset`, reuses `TransferAssetUploadStream` to accumulate binary chunks, decrypts if needed, computes SHA1, and routes the payload to the existing transfer handler.
8. Writes response envelopes back as text frames.

### Simulated host driver

The existing `AoaHostDriver` Protocol from `android_aoa_poc.py` is extracted into a reusable interface. A `SimulatedAoaHostDriver` implementation creates a local in-memory AOA endpoint for unit tests, so `UsbAoaTransportAdapter` can be tested without a real device.

## Update prompt for old desktop versions

The mobile app advertises `aoa_transfer: 1` during the capability exchange.

- If the desktop does not include `aoa_transfer: 1` in its accepted capabilities, the mobile app marks the desktop as not supporting AOA.
- The adaptive transport strategy falls back to LAN.
- If the user previously expected USB, the app triggers the existing `update.prompt` flow to show a message such as "Please update AuSearch on your computer to use USB backup."
- The same path is used if the desktop rejects the AOA auth challenge with an unsupported operation.

## Error handling

Native AOA errors are typed and mapped to TypeScript:

- `invalidBootstrap` — bad QR material.
- `connectionUnavailable` — accessory not connected or permission denied.
- `sendFailed` — write error.
- `responseTimedOut` — response not received within the configured timeout.
- `invalidEnvelope` — malformed frame or envelope.
- `authRejected` — sid/opt mismatch or bad proof.

All of these cause the adaptive strategy to fall back to LAN. `connectionUnavailable` also updates the observable transport state so the UI can show the active transport.

## Security

- `opt` never leaves the mobile device; only `SHA256(opt + rand)` is sent back to the desktop.
- Large asset bytes are encrypted via the existing trust key when the capability exchange enables it.
- The AOA frame header contains only `length`, `request_id`, and `flags`; no filenames or metadata leak into framing.
- The accessory filter XML is kept restrictive; only the AuSearch desktop host can negotiate the AOA accessory mode.

## Testing

### Desktop

- Unit tests for `UsbAoaTransportAdapter` using `SimulatedAoaHostDriver`.
- Tests cover: auth handshake, request/response correlation, `transfer.asset` streaming, decryption, error envelopes, and stop/cleanup.

### Mobile native

- Kotlin unit tests for `AoaFrameCodec` with full and partial frames.
- Kotlin unit tests for `AoaClient` using a pipe-based fake `ParcelFileDescriptor`.
- Tests cover: auth response, request/response correlation, streaming chunk lifecycle, and detach cleanup.

### Mobile TypeScript

- Unit tests for `AoaTransportStrategy` with a mock `AoaBridge`.
- Unit tests for `AdaptiveTransportStrategy` verifying USB preference, LAN fallback, and cooldown.
- Tests for the DI provider wiring to ensure the AOA bridge is registered.

### Manual

- Real-device smoke test on macOS first: scan QR, pair over AOA, transfer a small number of assets, verify LAN fallback when the cable is unplugged.
- Windows host validation and driver notes follow after macOS is stable.

## macOS-first rollout

- The AOA probe and accessory negotiation are implemented and validated on macOS first.
- Windows-specific driver configuration (Zadig / WinUSB) is documented and tested once the macOS path is stable.
- The `UsbAoaTransportAdapter` is written so that the Windows-specific differences are isolated to the PyUSB backend interaction and do not affect the message framing or routing logic.

### macOS USB permission requirement

macOS gates USB device access behind a privacy (TCC) permission; when it is missing, `IOUSBHostInterfaceOpen` returns `kIOReturnNotPermitted`, which libusb reports as `LIBUSB_ERROR_ACCESS` (`[Errno 13] Access denied (insufficient permissions)`).

- When running from source, grant USB access to the terminal/IDE that launches `python dt_image_search/main.py`.
- When running the packaged `.app`, grant USB access to `AuSearch` (and add `com.apple.security.device.usb` if the app is ever sandboxed).
- Grant under **System Settings → Privacy & Security → USB** (or approve the one-time prompt on first USB access).

### macOS misleading `LIBUSB_ERROR_ACCESS` on re-claim

**Do not assume `LIBUSB_ERROR_ACCESS` means a TCC permission denial.** libusb on macOS also maps `kIOReturnExclusiveAccess` (the interface is already held by this same process) to `LIBUSB_ERROR_ACCESS`. The probe loop used to leak the claimed interface: after a session ended it closed the streams but never released the interface or disposed the device handle, so the next probe pass failed at `claim_interface` with this misleading "Access denied" error. Fixes:

- `PyUsbAoaHostDriver.open_stream` releases any previously-held device handle before opening a new one.
- `UsbAoaTransportAdapter._run_transport_loop` calls `driver.stop()` in the session teardown `finally` to release the interface after every session.

## Risks

- AOA bulk endpoint performance depends on the Android device and host driver. The implementation should keep chunk sizes configurable.
- Android may kill the foreground service if the cable is unplugged while the app is in the background; the LAN fallback path must be robust.
- Some Android devices require the user to accept the USB accessory permission dialog; the UI must explain this.

## Appendix: constants

- Frame version: `1`
- Request ID length: `36` bytes
- Frame header size: `42` bytes
- Frame flag text: `0x00`
- Frame flag binary: `0x01`
- Envelope schema: `dtis.mobile-transport.v1`
- Auth body schema: `dtis.mobile-pairing.v1`
- Auth operation: `transport.auth.challenge`
- AOA capability flag: `aoa_transfer`
