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

### Requirement: Payload stashing to Launch Agent via Unix socket
The Share Extension SHALL send the received payload to the Launch Agent via HTTP POST over a Unix domain socket inside the extension's own sandbox container. The socket path SHALL be derived from the extension's container directory (e.g., `~/Library/Containers/<bundle-id>/Data/Library/Application Support/au-search/qr-transfer.sock`). The stash endpoint is `POST /api/instant-share/v1/qr-trigger/stash`.

#### Scenario: Stash text payload
- **WHEN** the extension receives a text payload from the Share menu
- **THEN** it SHALL POST a JSON body `{type: "text", content: "<text>"}` with `Content-Type: application/json` to the stash endpoint over the Unix socket
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>"}`

#### Scenario: Stash image payload (file path)
- **WHEN** the extension receives an image file from the Share menu
- **THEN** it SHALL POST a JSON body `{type: "image", file_path: "<absolute-path-to-file>", filename: "<original-filename>"}` with `Content-Type: application/json` to the stash endpoint over the Unix socket
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>"}`

#### Scenario: Stash failure handling
- **WHEN** the stash endpoint returns a non-200 response or the agent is unreachable
- **THEN** the extension SHALL exit silently (no user-facing error from the extension; the agent shows any errors)

### Requirement: Activation rule scoping
The Share Extension SHALL define an `NSExtensionActivationRule` that limits activation to text and file content types.

#### Scenario: Activation rule limits
- **WHEN** the extension is activated with text content
- **THEN** the activation rule SHALL match string type (`NSPasteboardTypeString`)
- **WHEN** the extension is activated with a single file
- **THEN** the activation rule SHALL match file URL type (`public.file-url`)
- **WHEN** the extension is activated with unsupported types (URLs, multiple files, contact, calendar)
- **THEN** the activation rule SHALL NOT match