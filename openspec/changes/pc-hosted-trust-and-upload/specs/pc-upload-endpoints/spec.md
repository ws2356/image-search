# PC Upload Endpoints

## ADDED Requirements

### Requirement: PC hosts text upload endpoint
The PC SHALL expose `POST /api/instant-share/v1/transfer/text` on the bootstrap HTTP server (port 9527). The endpoint SHALL accept a JSON body with `text_utf8` (the shared text content) and optional `metadata` object. The endpoint SHALL store the received text for local delivery (clipboard or file).

#### Scenario: Successful text upload
- **WHEN** iOS sends POST to `/transfer/text` with `{"text_utf8": "Hello world"}` after trust is established
- **THEN** PC returns 200 with `{"state": "delivered"}` and the text is available for local delivery

#### Scenario: Text upload without trust
- **WHEN** iOS sends POST to `/transfer/text` without completing trust handshake
- **THEN** PC returns 403 with error code `TRUST_REQUIRED`

### Requirement: PC hosts image upload endpoint
The PC SHALL expose `POST /api/instant-share/v1/transfer/image` on the bootstrap HTTP server. The endpoint SHALL accept a binary body with `Content-Type` header indicating the image format and `X-Instant-Share-Filename` header providing the original filename. The endpoint SHALL store the received image for local delivery.

#### Scenario: Successful image upload
- **WHEN** iOS sends POST to `/transfer/image` with binary JPEG data and `Content-Type: image/jpeg` header
- **THEN** PC returns 200 with `{"state": "delivered"}` and the image is saved to disk

#### Scenario: Image upload without trust
- **WHEN** iOS sends POST to `/transfer/image` without completing trust handshake
- **THEN** PC returns 403 with error code `TRUST_REQUIRED`

### Requirement: PC upload session validation
The PC SHALL validate that the upload request corresponds to an active, trusted session. The session SHALL be identified by the `X-Session-Id` header in the request.

#### Scenario: Upload with valid session
- **WHEN** iOS sends upload request with `X-Session-Id` header matching an active trusted session
- **THEN** PC accepts the upload and processes the payload

#### Scenario: Upload with invalid session
- **WHEN** iOS sends upload request with `X-Session-Id` header that does not match any active session
- **THEN** PC returns 404 with error code `SESSION_NOT_FOUND`

#### Scenario: Upload with untrusted session
- **WHEN** iOS sends upload request with `X-Session-Id` header matching a session that has not completed trust
- **THEN** PC returns 403 with error code `TRUST_REQUIRED`
