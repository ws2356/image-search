## ADDED Requirements

### Requirement: iOS client uses manifest-first download flow
The iOS client SHALL always call `POST /api/instant-share/v1/transfer/manifest` to discover available files before downloading. The manifest response is a JSON object with `file_count` and `files` array. This pattern applies uniformly to both single-file and multi-file stashes.

#### Scenario: Manifest returns 4 files → show batch receive view
- **WHEN** the iOS client calls `/transfer/manifest` and receives `{file_count: 4, files: [{index: 0, filename: "a.jpg", content_type: "image/jpeg", size_bytes: 102400}, ...]}`
- **THEN** the client SHALL navigate to `MultiFileReceiveView` displaying "4 files ready to download"

#### Scenario: Manifest returns 1 file → show single file receive view
- **WHEN** the iOS client calls `/transfer/manifest` and receives `{file_count: 1, files: [{index: 0, filename: "photo.jpg", content_type: "image/jpeg", size_bytes: 102400}]}`
- **THEN** the client SHALL navigate to a single-file receive view (or the multi-file view with a single entry) showing "photo.jpg" with a "Save" button

### Requirement: Sequential file download with aggregated progress
The iOS client SHALL download files sequentially (one at a time), showing aggregated progress. Each file SHALL be downloaded via `GET /api/instant-share/v1/transfer/download/<index>` using the same `X-Session-Id`. For single-file stashes, there is only one download at index 0.

#### Scenario: Download all files successfully
- **WHEN** the user taps "Download All" in `MultiFileReceiveView` for a 3-file batch
- **THEN** the client SHALL call `/transfer/download/0`, `/transfer/download/1`, `/transfer/download/2` sequentially
- **AND** the progress SHALL show "Downloading file 1 of 3..." → "...2 of 3..." → "...3 of 3..."
- **AND** after completion, display "3 files saved" with success state

#### Scenario: Network failure mid-batch resumes at next file
- **WHEN** the download of file index 1 fails with a network error
- **THEN** the client SHALL skip file 1 and proceed to file index 2
- **AND** at the end, display "2 of 3 files saved. 1 file failed."
- **AND** failed files SHALL be shown with a retry option

#### Scenario: Stash expires during batch download
- **WHEN** the download of file index 2 returns HTTP 410 (stash expired)
- **THEN** the client SHALL stop the batch immediately
- **AND** display "This share has expired. 2 of 5 files saved. Please share the remaining files again from your Mac."

### Requirement: MultiFileReceiveView displays file list with save options
The `MultiFileReceiveView` SHALL display a scrollable list of files with filename, type icon, and size. Each file SHALL have a "Save" button. A "Save All" button SHALL download and save all files.

#### Scenario: View renders file list
- **WHEN** `MultiFileReceiveView` receives a manifest with 4 files
- **THEN** a `List` SHALL display each file with its filename, MIME-type-based SF Symbol icon, and formatted size (e.g., "2.3 MB")
- **AND** each row SHALL have a "Save" button

#### Scenario: Save individual file
- **WHEN** user taps "Save" on the second file row
- **THEN** the client SHALL download only file index 1
- **AND** after download, save to Photos (for images) or Files app
- **AND** show checkmark on that row upon success

#### Scenario: Save All downloads and saves all files
- **WHEN** user taps "Save All" button
- **THEN** the client SHALL sequentially download all files
- **AND** save each file to the appropriate destination (Photos for images, Files app for other types)
- **AND** show checkmarks on all successfully saved rows
- **AND** show error indicators on any that failed

### Requirement: Per-file save destination
For each downloaded file, the iOS client SHALL save images to the Photos library and non-image files to the Files app. The user SHALL be prompted for Photo Library permission on first save.

#### Scenario: Save JPEG to Photos
- **WHEN** a file with `content_type: "image/jpeg"` is downloaded
- **THEN** the client SHALL save it to the Photos library using `PHPhotoLibrary`

#### Scenario: Save unsupported file type to Files
- **WHEN** a file with `content_type: "application/pdf"` is downloaded
- **THEN** the client SHALL open a document picker or save to the Files app

#### Scenario: Batch save requesting Photos permission
- **WHEN** "Save All" is tapped and Photos permission has not been granted
- **THEN** the client SHALL request permission
- **THEN** on grant, proceed with saving; on denial, skip image files and save only non-image files
