## ADDED Requirements

### Requirement: Payload extractor collects all matching images
The `InstantSharePayloadExtractor` SHALL collect ALL image attachments from the iOS Share Extension instead of returning after the first match. The return type SHALL change from a single `InstantSharePayloadEnvelope` to an array `[InstantSharePayloadEnvelope]`.

#### Scenario: Multiple images selected in Photos app
- **WHEN** the user selects 5 images in the Photos app and taps "Share" → "AuBackup"
- **THEN** `extract(from:)` SHALL iterate all attachments from all extension items
- **AND** return an array of 5 `InstantSharePayloadEnvelope` entries, each with `payloadType: .image`, a `fileURL`, `filename`, and `contentType`

#### Scenario: Single image still works
- **WHEN** the user selects 1 image
- **THEN** `extract(from:)` SHALL return an array containing exactly 1 `InstantSharePayloadEnvelope`

#### Scenario: No supported items
- **WHEN** no supported attachments are present
- **THEN** `extract(from:)` SHALL throw `InstantSharePayloadExtractorError.noSupportedItems`

### Requirement: ViewModel manages multiple payloads
`InstantShareExtensionViewModel` SHALL store a list of `[InstantSharePayloadEnvelope]` instead of a single optional envelope. The `send()` method SHALL iterate over all image payloads and upload each one sequentially within the same session.

#### Scenario: Send multiple images
- **WHEN** the user taps "Send" with 3 images loaded
- **THEN** the ViewModel SHALL call `uploadImage` for each image in sequence
- **AND** the upload progress SHALL reflect the overall batch progress (e.g., "Sending image 2 of 3")

#### Scenario: Send fails mid-batch
- **WHEN** the second of 5 images fails to upload
- **THEN** the ViewModel SHALL report an error and stop the batch
- **AND** already-uploaded images SHALL remain on the PC

### Requirement: Upload client supports batch image transfer
`InstantShareUploadClient` SHALL provide a `uploadImages(_ urls: [(URL, String, String)]) async throws` method that uploads multiple images sequentially within the same session. Per-image progress SHALL be aggregated.

#### Scenario: Sequential image upload
- **WHEN** `uploadImages` is called with 4 image URLs
- **THEN** it SHALL call `/transfer/image` for each URL sequentially with the same `X-Session-Id`
- **AND** return after all uploads complete or fail

#### Scenario: Session reused across images
- **WHEN** multiple images are uploaded
- **THEN** all uploads SHALL use the same `X-Session-Id` header
- **AND** the PC SHALL process each image within the same session context

### Requirement: Transfer request includes image count header
The first `/transfer/image` request in a batch SHALL include an `X-Image-Count` header so the PC knows the total expected images. Ordering is not guaranteed for user-selected images, so no index header is needed.

#### Scenario: First image transfer declares batch size
- **WHEN** the first image is uploaded via `/transfer/image`
- **THEN** the request SHALL include header `X-Image-Count: 5`
- **AND** the PC SHALL store `image_count: 5` for the session and `received_count: 1`

#### Scenario: Subsequent images update received count
- **WHEN** each subsequent image is uploaded
- **THEN** the PC SHALL increment the session's `received_count`

#### Scenario: Last image triggers delivery completion
- **WHEN** the final image is uploaded (`received_count == image_count`)
- **THEN** the PC SHALL transition the session to `DELIVERING` after processing the image

#### Scenario: Single image — no batch header needed
- **WHEN** only 1 image is shared
- **THEN** the `X-Image-Count` header MAY be omitted (PC defaults to 1)
