## Requirements

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

### Requirement: MultiFileReceiveView displays a selectable file list for resharing
The `MultiFileReceiveView` SHALL display a scrollable, selectable list of files with filename, type icon, and formatted size. The user SHALL select one or more files via built-in SwiftUI `List` selection. A "Share N selected" button SHALL download the selected files and present the iOS system share sheet.

#### Scenario: View renders selectable file list
- **WHEN** `MultiFileReceiveView` receives a manifest with 4 files
- **THEN** a `List` with selection binding SHALL display each file with its filename, MIME-type-based SF Symbol icon, and formatted size (e.g., "2.3 MB")
- **AND** each row SHALL show a selection circle indicator
- **AND** inline text/html entries SHALL show their content preview and a green checkmark (already delivered)

#### Scenario: Select multiple files
- **WHEN** user taps 3 of 4 file rows
- **THEN** the selection count SHALL update to "3 selected"
- **AND** the share button SHALL read "Share (3 selected)"

#### Scenario: Share selected files
- **WHEN** user taps "Share (3 selected)"
- **THEN** the client SHALL download any selected files that are not yet downloaded (skipping already-downloaded and inline items)
- **AND** show a "Downloading..." progress indicator during downloads
- **AND** upon completion, present the iOS system share sheet with the downloaded file URLs and inline text content
- **AND** failed downloads SHALL be skipped and shown with a red error indicator

#### Scenario: Inline text entries are shareable without download
- **WHEN** a selected entry has `type: "text"` or `type: "html"`
- **THEN** the text content SHALL be included in the share sheet items directly (no download needed)

### Requirement: No saving to Photos or Files for multi-file receive
The `MultiFileReceiveView` SHALL NOT save downloaded files to the Photos library or Files app. The only action available after downloading is sharing via the system share sheet. This keeps the receive flow simple and avoids polluting the user's library.

#### Scenario: File downloaded but not saved to Photos
- **WHEN** a JPEG file is downloaded in `MultiFileReceiveView`
- **THEN** the file SHALL NOT be saved to `PHPhotoLibrary`
- **AND** the file URL SHALL only be used as a share sheet item

### Requirement: Cleanup of downloaded temporary files
The `MultiFileReceiveView` SHALL clean up downloaded file URLs when the view disappears, removing temporary files from the `QRDownloads` directory.
