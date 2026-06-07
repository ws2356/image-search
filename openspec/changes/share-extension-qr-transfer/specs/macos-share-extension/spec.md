## ADDED Requirements

### Requirement: macOS Share Extension registration
The macOS Share Extension SHALL register as an NSExtension with `NSExtensionPointIdentifier` = `com.apple.share-services` and appear in the system Share menu.

#### Scenario: Extension appears in share menu
- **WHEN** user right-clicks a file in Finder or selects text in any app and opens the Share menu
- **THEN** "AuSearch" SHALL appear as a share target in the menu

#### Scenario: Extension activation for text
- **WHEN** user selects "AuSearch" from the Share menu with text selected
- **THEN** the extension SHALL receive the selected text as `NSPasteboard` content with type `NSPasteboardTypeString`

#### Scenario: Extension activation for file
- **WHEN** user selects "AuSearch" from the Share menu with a file selected in Finder
- **THEN** the extension SHALL receive the file URL as an `NSItemProvider` with type `public.file-url`

### Requirement: Payload stashing to Launch Agent
The Share Extension SHALL send the received payload to the Launch Agent via HTTP POST to `http://127.0.0.1:9527/api/qr-transfer/v1/stash`.

#### Scenario: Stash text payload
- **WHEN** the extension receives a text payload from the Share menu
- **THEN** it SHALL POST the UTF-8 encoded text with `Content-Type: text/plain` to the stash endpoint
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>"}`

#### Scenario: Stash image payload
- **WHEN** the extension receives an image file from the Share menu
- **THEN** it SHALL POST the raw image bytes with `Content-Type: image/png` (or the detected MIME type) and `X-Original-Filename` header to the stash endpoint
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>"}`

#### Scenario: Stash failure handling
- **WHEN** the stash endpoint returns a non-200 response or the Launch Agent is unreachable
- **THEN** the extension SHALL display an error message: "Could not connect to AuSearch. Make sure AuSearch is running."

### Requirement: Share Extension confirmation UI
The Share Extension SHALL show a confirmation UI after stashing, displaying the QR code (fetched from Launch Agent) or a success message with instructions to scan with AuBackup.

#### Scenario: Show confirmation after stash
- **WHEN** the payload is successfully stashed
- **THEN** the extension SHALL display a confirmation message: "Data sent. Open AuBackup on your iPhone and scan the QR code on your Mac to receive it."
- **THEN** the extension SHALL provide a "Close" button to dismiss

### Requirement: Extension sandbox entitlements
The macOS Share Extension SHALL declare the following sandbox entitlements in its `Info.plist` and `ShareExtension.entitlements`:
- `com.apple.security.network.local` — for localhost HTTP communication
- `com.apple.security.network.client` — for outbound network access to Launch Agent

#### Scenario: Entitlements present
- **WHEN** the extension is built and codesigned
- **THEN** the entitlements file SHALL contain both `com.apple.security.network.local` and `com.apple.security.network.client` set to `true`

### Requirement: Activation rule scoping
The Share Extension SHALL define an `NSExtensionActivationRule` that limits activation to text and file content types.

#### Scenario: Activation rule limits
- **WHEN** the extension is activated with text content
- **THEN** the activation rule SHALL match string type (`NSPasteboardTypeString`)
- **WHEN** the extension is activated with a single file
- **THEN** the activation rule SHALL match file URL type (`public.file-url`)
- **WHEN** the extension is activated with unsupported types (URLs, multiple files, contact, calendar)
- **THEN** the activation rule SHALL NOT match
