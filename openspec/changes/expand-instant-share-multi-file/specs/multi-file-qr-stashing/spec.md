## ADDED Requirements

### Requirement: Batch stash creation from multiple files
The QR trigger handler SHALL support creating a batch stash from a list of files. When the `/api/instant-share/v1/qr-trigger` endpoint receives a request body with `type: "image"` and a `files` array, it SHALL create a single `StashEntry` containing all file references.

#### Scenario: Stash multiple image files
- **WHEN** the macOS Share Extension POSTs to `/qr-trigger` with `{type: "image", files: [{file_path: "/path/a.jpg", filename: "a.jpg"}, {file_path: "/path/b.png", filename: "b.png"}]}`
- **THEN** the handler SHALL create a single stash entry with `content_type: "multi/image"` and `files: [FileEntry(file_path="/path/a.jpg", filename="a.jpg", ...), FileEntry(file_path="/path/b.png", filename="b.png", ...)]`
- **AND** the response SHALL include `status: "stashed"`, `stash_id`, and `file_count: 2`

#### Scenario: Backward compatible single-file stash
- **WHEN** the macOS Share Extension POSTs to `/qr-trigger` with `{type: "image", file_path: "/path/photo.jpg", filename: "photo.jpg"}` (legacy format)
- **THEN** the handler SHALL create a stash entry with a single file in the `files` list (wrapping the legacy payload internally)
- **AND** the response SHALL still work as before with `status: "stashed"` and `stash_id`

#### Scenario: Mixed file types in batch are accepted
- **WHEN** the batch includes files of different image formats (e.g., JPEG, PNG, HEIC)
- **THEN** the handler SHALL accept all files and detect MIME types individually per file

### Requirement: StashEntry tracks per-file metadata
The `StashEntry` dataclass SHALL include a `files` list of `FileEntry` objects, each holding `file_path`, `filename`, `content_type`, and `size_bytes`. The legacy `file_path` and `filename` attributes SHALL be deprecated in favor of `files`.

#### Scenario: FileEntry captures metadata
- **WHEN** a file at `/path/photo.jpg` with size 204800 bytes is added to a stash
- **THEN** the `FileEntry` SHALL have `file_path="/path/photo.jpg"`, `filename="photo.jpg"`, `content_type="image/jpeg"`, `size_bytes=204800`

#### Scenario: Single-file stash has files list with one entry
- **WHEN** a single file is stashed via the legacy `file_path` format
- **THEN** `stash_entry.files` SHALL be a list of length 1
- **AND** `stash_entry.files[0].file_path` SHALL equal the original `file_path` value

### Requirement: Batch stash size limit
The QR trigger handler SHALL enforce a maximum batch file count. Exceeding the limit SHALL reject the request with a clear error.

#### Scenario: Reject oversized batch
- **WHEN** the request contains 51 files and the configured max is 50
- **THEN** the handler SHALL return `{_status: 400, status: "error", error: "Too many files. Maximum is 50."}`

#### Scenario: Max batch count is configurable
- **WHEN** the configuration key `instant_share.max_batch_file_count` is set to `20`
- **THEN** the handler SHALL use 20 as the maximum batch file count

### Requirement: Transfer manifest endpoint returns file listing
The `/api/instant-share/v1/transfer/manifest` endpoint SHALL always return a JSON manifest listing all files in the stash with their indices, filenames, content types, and sizes. This endpoint replaces the old `/transfer/download` and SHALL be used by the iOS client to discover what files are available before downloading them individually.

#### Scenario: Manifest for multi-file stash
- **WHEN** an iOS client calls `/transfer/manifest` with a valid `X-Session-Id` for a 3-file batch stash
- **THEN** the response SHALL be JSON `{file_count: 3, files: [{index: 0, filename: "a.jpg", content_type: "image/jpeg", size_bytes: 102400}, {index: 1, filename: "b.png", content_type: "image/png", size_bytes: 204800}, {index: 2, filename: "c.heic", content_type: "image/heic", size_bytes: 51200}]}`
- **AND** the HTTP status SHALL be 200

#### Scenario: Manifest for single-file stash
- **WHEN** an iOS client calls `/transfer/manifest` for a stash containing exactly 1 file
- **THEN** the response SHALL be JSON `{file_count: 1, files: [{index: 0, filename: "photo.jpg", content_type: "image/jpeg", size_bytes: 102400}]}`
- **AND** the HTTP status SHALL be 200

### Requirement: Per-file download endpoint
The `/api/instant-share/v1/transfer/download/<file_index>` endpoint SHALL serve individual file bytes for any stash (single or multi-file). The `file_index` is 0-based and validated against the stash's file count. This is the universal download endpoint; the iOS client discovers available files via `/transfer/manifest` first.

#### Scenario: Download file at valid index
- **WHEN** an iOS client calls `/transfer/download/0` for a 3-file stash
- **THEN** the response SHALL contain the file bytes of the first file with correct `Content-Type` and `X-Original-Filename` headers
- **AND** HTTP status SHALL be 200

#### Scenario: Invalid file index returns error
- **WHEN** an iOS client calls `/transfer/download/5` for a 3-file stash
- **THEN** the response SHALL be `{error_code: "INVALID_REQUEST", message: "File index 5 out of range (0–2)"}`
- **AND** HTTP status SHALL be 400

#### Scenario: Stash file no longer exists returns error
- **WHEN** the file at the requested index has been deleted from disk since stash creation
- **THEN** the response SHALL be `{error_code: "PAYLOAD_UNREADABLE", message: "Source file no longer available"}`
- **AND** HTTP status SHALL be 410
