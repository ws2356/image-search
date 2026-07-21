## ADDED Requirements

### Requirement: Share Extension payload normalization
The system SHALL accept Share Extension payloads of type text, image, video, and other files, and normalize them into a common instant-share transfer envelope containing content type, payload metadata, and source app context.

#### Scenario: Ingest shared text
- **WHEN** the user shares plain text from an iOS app to AuSearch/AuBackup Share Extension
- **THEN** the extension creates an instant-share envelope with content type `text` and the exact UTF-8 text body

#### Scenario: Ingest shared photo
- **WHEN** the user shares a photo from iOS Photos to AuSearch/AuBackup Share Extension
- **THEN** the extension creates an instant-share envelope with content type `image`, media metadata, and a resolvable media source handle

#### Scenario: Ingest shared video
- **WHEN** the user shares a video from iOS Photos to AuSearch/AuBackup Share Extension
- **THEN** the extension creates an instant-share envelope with content type `video`, duration/size metadata, and a resolvable media source handle

#### Scenario: Ingest shared other file
- **WHEN** the user shares a non-media file type (for example PDF or ZIP) to AuSearch/AuBackup Share Extension
- **THEN** the extension creates an instant-share envelope with content type `file`, filename metadata, and a resolvable file source handle

### Requirement: Unsupported payload rejection
The system SHALL reject only payloads that cannot be read or represented as text/image/video/file transfer content with a user-visible unsupported-type error and SHALL NOT start transfer negotiation.

#### Scenario: Reject unsupported file type
- **WHEN** the user attempts to share an attachment whose content provider cannot be represented as text/image/video/file transfer content
- **THEN** the extension shows an unsupported-type message and no instant-share session is created

### Requirement: Extension-safe preflight checks
The system SHALL perform preflight validation for payload readability and required metadata before opening an instant-share session.

#### Scenario: Fail preflight for unreadable payload
- **WHEN** the shared media handle cannot be opened by the extension sandbox
- **THEN** the extension reports a preflight failure and terminates the instant-share attempt before session negotiation

### Requirement: Large-media optimization deferred
The system SHALL treat advanced optimization for very large media payloads as out of scope for this iteration and SHALL not require chunk-level or adaptive optimization logic for acceptance.

#### Scenario: Accept baseline media transfer behavior
- **WHEN** a valid media payload is shared in this iteration
- **THEN** the system uses baseline transfer behavior without requiring large-media optimization features

### Requirement: Share Extension device selector card
The iOS Share Extension SHALL present a production-quality device selector card that lists discovered mDNS PCs and lets the user choose the target receiver. No main-app handoff — the extension handles the full trust + upload flow natively.

#### Scenario: Display discovered receivers in extension
- **WHEN** the Share Extension discovers one or more eligible PCs over mDNS (Bonjour)
- **THEN** it renders those PCs in the device selector card with recognizable receiver identity and current availability state

#### Scenario: Full flow in extension after device selection
- **WHEN** the user taps a device in the selector card
- **THEN** the Share Extension initiates the complete trust + upload flow: calls PC's `/trust/handshake` with bootstrap data, receives encrypted PIN from `/trust/apply`, sends confirmation via `/trust/confirm`, and uploads payload via `/transfer/text` or `/transfer/image`. No AuBackup handoff, no URL navigation, no local HTTP server.
