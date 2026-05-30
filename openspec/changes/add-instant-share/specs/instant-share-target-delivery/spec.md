## ADDED Requirements

### Requirement: Clipboard delivery for text and images
The system SHALL support delivering instant-share text and image payloads to the desktop clipboard and SHALL surface delivery completion status to the user.

#### Scenario: Successful clipboard delivery
- **WHEN** a text instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the exact text payload to clipboard and marks the session as delivered successfully

#### Scenario: Successful image clipboard delivery
- **WHEN** an image instant-share payload is configured for clipboard target and reaches the desktop delivery stage
- **THEN** the system writes the image payload to clipboard and marks clipboard delivery as successful

### Requirement: Media to local file delivery
The system SHALL deliver image and video payloads to a configured local directory using sanitized deterministic filenames that avoid collisions.

#### Scenario: Successful image file delivery
- **WHEN** an image instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the image file to the configured directory using a sanitized unique filename and marks delivery as successful

#### Scenario: Successful video file delivery
- **WHEN** a video instant-share payload reaches the desktop delivery stage
- **THEN** the system writes the video file to the configured directory using a sanitized unique filename and marks delivery as successful

### Requirement: Delivery path safety
The system SHALL validate that all output file writes remain inside the configured receive directory and SHALL reject traversal or invalid-path attempts.

#### Scenario: Reject unsafe output path
- **WHEN** resolved output naming would escape the configured receive directory boundary
- **THEN** the system aborts delivery, reports a path-safety error, and records a failed session outcome
