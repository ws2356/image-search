## Requirements

### Requirement: Mini window displays multi-file batch count and filenames
The `QRTriggerMiniWindow` SHALL display batch file count and a list of filenames when the stash contains multiple files. The UI SHALL remain compact and scrollable.

#### Scenario: Display batch with 3 files
- **WHEN** a batch stash with 3 files (`a.jpg`, `b.png`, `c.heic`) is created
- **THEN** the mini window SHALL display "Sharing 3 files from Mac" as the main message
- **AND** a scrollable list SHALL show the filenames: `a.jpg`, `b.png`, `c.heic`

#### Scenario: Single file retains existing display
- **WHEN** a stash has exactly 1 file
- **THEN** the mini window SHALL display the existing single-file UI without batch indicators ("Sharing file from Mac")

#### Scenario: Truncated filename list for large batches
- **WHEN** a batch stash has more than 10 files
- **THEN** the mini window SHALL show the first 10 filenames followed by "+N more files..." at the bottom
- **AND** the full list SHALL be scrollable to reveal all entries

### Requirement: Mini window shows download progress per file
The `QRTriggerMiniWindow` SHALL update to show per-file download progress when the iOS client is downloading from a batch stash. The progress SHALL reflect how many files have been downloaded out of the total.

#### Scenario: Download in progress for batch
- **WHEN** iOS client is downloading file 2 of 5 from a batch stash
- **THEN** the mini window SHALL display "Downloading file 2 of 5..."
- **AND** the progress bar SHALL show 40% completion

#### Scenario: Download completes
- **WHEN** all 5 files have been downloaded
- **THEN** the mini window SHALL display "All 5 files sent successfully."
- **AND** the progress bar SHALL show 100%

#### Scenario: Partial download failure
- **WHEN** 3 of 5 files downloaded successfully and 2 failed
- **THEN** the mini window SHALL display "3 of 5 files sent. 2 files failed."
- **AND** the error label SHALL show which files failed

### Requirement: QR code display is unchanged for multi-file
The QR code SHALL continue to encode a single `ausearch://claim?` URL with `stash_id` and `opt_code`. No additional parameters are needed — the iOS client discovers the file count from the download manifest.

#### Scenario: QR code encodes only stash identity
- **WHEN** a batch stash with 5 files is created
- **THEN** the QR code SHALL contain `ausearch://claim?ips=<ips>&port=<port>&stash=<stash_id>&opt=<opt_code>`
- **AND** SHALL NOT contain file count or filenames (discovered via manifest)
