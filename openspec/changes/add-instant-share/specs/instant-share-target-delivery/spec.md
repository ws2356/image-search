## ADDED Requirements

### Requirement: Text clipboard-only delivery
The system SHALL deliver instant-share text payloads to the desktop clipboard only and SHALL surface delivery completion status to the user.

#### Scenario: Successful clipboard delivery
- **WHEN** a text instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the exact text payload to clipboard and marks the session as delivered successfully

#### Scenario: Text-to-file is blocked
- **WHEN** a text instant-share payload is requested for local file target
- **THEN** the system rejects the target selection and enforces clipboard-only behavior for text payloads

### Requirement: Image dual-target delivery
The system SHALL support delivering image payloads to either clipboard or local file target and SHALL report delivery status for the selected target.

#### Scenario: Successful image clipboard delivery
- **WHEN** an image instant-share payload is configured for clipboard target and reaches the desktop delivery stage
- **THEN** the system writes the image payload to clipboard and marks clipboard delivery as successful

#### Scenario: Successful image file delivery
- **WHEN** an image instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the image file to the configured directory using a sanitized unique filename and marks delivery as successful

### Requirement: Video and other files local-file-only delivery
The system SHALL deliver video and non-media file payloads to local files only using sanitized deterministic filenames that avoid collisions.

#### Scenario: Successful video file delivery
- **WHEN** a video instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the video file to the configured directory using a sanitized unique filename and marks delivery as successful

#### Scenario: Successful other-file delivery
- **WHEN** a non-media file instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the file to the configured directory using a sanitized unique filename and marks delivery as successful

### Requirement: Default local-file target path
The system SHALL default instant-share local-file output path to the user's Downloads folder unless user configuration overrides it.

#### Scenario: Use Downloads as default path
- **WHEN** no explicit local-file target directory is configured
- **THEN** the system writes image/video/file payloads to the user's Downloads folder

### Requirement: Delivery path safety
The system SHALL validate that all output file writes remain inside the configured receive directory and SHALL reject traversal or invalid-path attempts.

#### Scenario: Reject unsafe output path
- **WHEN** resolved output naming would escape the configured receive directory boundary
- **THEN** the system aborts delivery, reports a path-safety error, and records a failed session outcome
