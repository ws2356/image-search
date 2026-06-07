## ADDED Requirements

### Requirement: Stash endpoint
The Launch Agent HTTP server SHALL expose `POST /api/qr-transfer/v1/stash` to receive payloads from the macOS Share Extension. This endpoint SHALL only accept connections from `127.0.0.1`.

#### Scenario: Accept text stash
- **WHEN** a POST request arrives at `/api/qr-transfer/v1/stash` from `127.0.0.1` with `Content-Type: text/plain` and UTF-8 body
- **THEN** the server SHALL store the text in memory with a generated UUID `stash_id`
- **THEN** it SHALL return `201` with JSON `{status: "stashed", stash_id: "<uuid>", content_type: "text/plain"}`

#### Scenario: Accept image stash
- **WHEN** a POST request arrives at `/api/qr-transfer/v1/stash` from `127.0.0.1` with `Content-Type: image/*` and raw image bytes
- **THEN** the server SHALL store the image bytes, filename, and content type in memory with a generated UUID `stash_id`
- **THEN** it SHALL return `201` with JSON `{status: "stashed", stash_id: "<uuid>", content_type: "<mime>"}`

#### Scenario: Reject non-localhost stash
- **WHEN** a POST request arrives at `/api/qr-transfer/v1/stash` from any IP other than `127.0.0.1`
- **THEN** the server SHALL return `403` with JSON `{status: "forbidden", error: "Only localhost allowed"}`

### Requirement: Opt-code generation
Upon successful stash, the Launch Agent SHALL generate a 6-digit opt-code and associate it with the stash. The opt-code SHALL have a 5-minute TTL.

#### Scenario: Generate opt-code
- **WHEN** a payload is stashed
- **THEN** a 6-digit opt-code SHALL be generated using a CSPRNG
- **THEN** the opt-code SHALL be stored alongside the stash_id with a 5-minute expiry timestamp
- **THEN** the opt-code SHALL be single-use (invalidated after a successful or 3 failed claim attempts)

### Requirement: QR code display
After generating the opt-code, the Launch Agent SHALL display a mini-window with a QR code encoding the PC's LAN IP addresses, port, stash_id, and opt-code.

#### Scenario: Show QR mini-window
- **WHEN** a payload is stashed and opt-code generated
- **THEN** the Launch Agent SHALL create a mini-window (similar to `InstantShareMiniWindow` but for QR display)
- **THEN** the QR code SHALL encode a URL in the format: `ausearch://claim?ips=<comma-separated-ips>&port=9527&stash=<stash_id>&opt=<opt-code>`
- **THEN** the window SHALL display the QR code prominently, along with the opt-code as fallback text, PC name, and "Scan with AuBackup" instructions

#### Scenario: QR window lifecycle
- **WHEN** the user clicks "Cancel" on the QR window
- **THEN** the stash SHALL be invalidated and the window SHALL close
- **WHEN** the opt-code expires (5-minute TTL)
- **THEN** the stash SHALL be invalidated and the window SHALL show "Expired" and auto-close after 10 seconds
- **WHEN** the stash is successfully claimed
- **THEN** the window SHALL show "Delivered" and auto-close after 4 seconds

### Requirement: QR claim endpoint
The Launch Agent HTTP server SHALL expose `POST /api/qr-transfer/v1/claim` for the iOS app to download the stashed payload. This endpoint SHALL accept connections from any LAN IP.

#### Scenario: Claim text payload
- **WHEN** a POST request arrives at `/api/qr-transfer/v1/claim` with JSON body `{stash_id: "<uuid>", opt: "<6-digit-code>"}` and the stash exists with matching opt-code not expired
- **THEN** the server SHALL return `200` with headers `Content-Type: text/plain` and body containing the stashed UTF-8 text
- **THEN** the stash SHALL be marked as claimed

#### Scenario: Claim image payload
- **WHEN** a POST request arrives at `/api/qr-transfer/v1/claim` with matching stash_id and opt-code for an image payload
- **THEN** the server SHALL return `200` with headers `Content-Type: <original-mime>` and `X-Original-Filename: <filename>` and body containing the raw image bytes
- **THEN** the stash SHALL be marked as claimed

#### Scenario: Claim with invalid opt-code
- **WHEN** a POST request arrives with a valid stash_id but incorrect opt-code
- **THEN** the server SHALL return `401` with JSON `{status: "unauthorized", error: "Invalid opt-code"}`
- **THEN** the attempt counter SHALL increment; after 3 failures the stash SHALL be invalidated

#### Scenario: Claim expired stash
- **WHEN** a POST request arrives with a valid stash_id and opt-code but the TTL has expired
- **THEN** the server SHALL return `410` with JSON `{status: "expired", error: "Stash has expired"}`

#### Scenario: Claim non-existent stash
- **WHEN** a POST request arrives with a stash_id that does not exist
- **THEN** the server SHALL return `404` with JSON `{status: "not_found", error: "Stash not found"}`

### Requirement: Background cleanup
The Launch Agent SHALL periodically clean up expired stashed payloads from memory.

#### Scenario: Expired stash cleanup
- **WHEN** a stash has been expired for more than 1 minute beyond its TTL
- **THEN** the Launch Agent SHALL remove it from memory to free resources

### Requirement: Payload size limit
The stash endpoint SHALL reject payloads larger than 50 MB.

#### Scenario: Over-size rejection
- **WHEN** a POST request arrives with `Content-Length` exceeding 50 MB (52,428,800 bytes)
- **THEN** the server SHALL return `413` with JSON `{status: "too_large", error: "Payload exceeds 50 MB limit"}`
