## ADDED Requirements

### Requirement: Unix domain socket listener (inside extension sandbox)
The Launch Agent SHALL determine the macOS Share Extension's sandbox container path from its bundle ID and create a Unix domain socket inside it (e.g., `~/Library/Containers/<bundle-id>/Data/Library/Application Support/au-search/qr-transfer.sock`). This socket SHALL be created before accepting any stash requests. The extension is sandboxed and can only connect to sockets within its own container.

#### Scenario: Socket creation at startup
- **WHEN** the Launch Agent starts and the QR transfer feature is enabled
- **THEN** it SHALL determine the extension's sandbox container path from its bundle ID
- **THEN** it SHALL create the parent directory inside the container (which may not exist yet)
- **THEN** it SHALL remove any stale socket file before creating a new one
- **THEN** it SHALL create the Unix domain socket at that path and listen for HTTP connections

#### Scenario: Extension connects via socket
- **WHEN** the macOS Share Extension connects to the Unix socket
- **THEN** the agent SHALL accept the connection and process HTTP requests

### Requirement: Stash endpoint
The Launch Agent SHALL expose `POST /api/instant-share/v1/qr-trigger/stash` on the Unix domain socket to receive payloads from the macOS Share Extension.

#### Scenario: Stash text payload
- **WHEN** a POST request arrives at `/api/instant-share/v1/qr-trigger/stash` with JSON body `{type: "text", content: "<text>"}`
- **THEN** the server SHALL store the text in memory with a generated UUID `stash_id`
- **THEN** it SHALL return `201` with JSON `{status: "stashed", stash_id: "<uuid>", content_type: "text/plain"}`

#### Scenario: Stash image payload (file path)
- **WHEN** a POST request arrives with JSON body `{type: "image", file_path: "<absolute-path>", filename: "<name>"}`
- **THEN** the server SHALL verify the file exists at the given path
- **THEN** it SHALL store the file path and filename with a generated UUID `stash_id`
- **THEN** it SHALL return `201` with JSON `{status: "stashed", stash_id: "<uuid>", content_type: "<detected-mime>"}`

#### Scenario: Stash with non-existent file path
- **WHEN** a POST request arrives with a `file_path` that does not exist
- **THEN** the server SHALL return `400` with JSON `{status: "error", error: "File not found"}`

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
- **THEN** the QR code SHALL encode a URL in the format: `ausearch://claim?ips=<comma-separated-ips>&port=<port>&stash=<stash_id>&opt=<opt-code>`
- **THEN** the window SHALL display the QR code prominently, along with the opt-code as fallback text, PC name (and port), and "Scan with AuBackup" instructions

#### Scenario: QR window lifecycle
- **WHEN** the user clicks "Cancel" on the QR window
- **THEN** the stash SHALL be invalidated and the window SHALL close
- **WHEN** the opt-code expires (5-minute TTL)
- **THEN** the stash SHALL be invalidated and the window SHALL show "Expired" and auto-close after 10 seconds
- **WHEN** the stash is successfully claimed
- **THEN** the window SHALL show "Delivered" and auto-close after 4 seconds

### Requirement: QR claim endpoint (TCP)
The Launch Agent HTTP server SHALL expose `POST /api/instant-share/v1/qr-trigger/claim` on the TCP listener (port 9527) for the iOS app to download the stashed payload. This endpoint SHALL accept connections from any LAN IP.

#### Scenario: Claim text payload
- **WHEN** a POST request arrives at `/api/instant-share/v1/qr-trigger/claim` with JSON body `{stash_id: "<uuid>", opt: "<6-digit-code>"}` and the stash exists with matching opt-code not expired
- **THEN** the server SHALL return `200` with headers `Content-Type: text/plain` and body containing the stashed UTF-8 text
- **THEN** the stash SHALL be marked as claimed

#### Scenario: Claim image payload
- **WHEN** a POST request arrives at `/api/instant-share/v1/qr-trigger/claim` with matching stash_id and opt-code for an image payload
- **THEN** the server SHALL open the file at the stored file path and stream it as the response body
- **THEN** it SHALL return `200` with headers `Content-Type: <detected-mime>` and `X-Original-Filename: <filename>`
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

#### Scenario: Claim image with deleted source file
- **WHEN** a POST request arrives for an image stash whose file_path no longer exists
- **THEN** the server SHALL return `410` with JSON `{status: "expired", error: "Source file no longer available"}`

### Requirement: Stash expiry cleanup
The Launch Agent SHALL use a oneshot timer per stash (set to the opt-code TTL of 5 minutes) to invalidate expired stashes instead of a periodic cleanup loop.

#### Scenario: Oneshot timer cleanup
- **WHEN** a stash is created
- **THEN** a oneshot timer SHALL be scheduled for 5 minutes
- **WHEN** the timer fires
- **THEN** the stash SHALL be marked as expired if not already claimed
- **THEN** the QR window SHALL show "Expired" and auto-close

#### Scenario: Timer cancelled on claim
- **WHEN** a stash is successfully claimed before the timer fires
- **THEN** the oneshot timer SHALL be cancelled
