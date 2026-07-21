## Requirements

### Requirement: macOS Share Extension registration
The macOS Share Extension SHALL register as an NSExtension with `NSExtensionPointIdentifier` = `com.apple.share-services` and appear in the system Share menu.

#### Scenario: Extension appears in share menu
- **WHEN** user right-clicks a file in Finder or selects text in any app and opens the Share menu
- **THEN** "AuSearch" SHALL appear as a share target in the menu

#### Scenario: Extension activation for text
- **WHEN** user selects "AuSearch" from the Share menu with text selected
- **THEN** the extension SHALL receive the selected text as `NSPasteboard` content with type `NSPasteboardTypeString`

#### Scenario: Extension activation for single file
- **WHEN** user selects "AuSearch" from the Share menu with a single file selected in Finder
- **THEN** the extension SHALL receive the file URL as an `NSItemProvider` with type `public.file-url`

#### Scenario: Extension activation for multiple files
- **WHEN** user selects "AuSearch" from the Share menu with 3 files selected in Finder
- **THEN** the extension SHALL receive all 3 file URLs as `NSItemProvider` instances with type `public.file-url`
- **AND** the extension SHALL iterate over all received file URLs for stashing

### Requirement: Payload stashing to Launch Agent via Unix socket
The Share Extension SHALL send the received payload to the Launch Agent via HTTP POST over a Unix domain socket inside the extension's own sandbox container. The socket path SHALL be derived from the extension's container directory (e.g., `~/Library/Containers/<bundle-id>/Data/Library/Application Support/au-search/qr-transfer.sock`). The endpoint is `POST /api/instant-share/v1/qr-trigger`.

#### Scenario: Stash text payload
- **WHEN** the extension receives a text payload from the Share menu
- **THEN** it SHALL POST a JSON body `{type: "text", content: "<text>"}` with `Content-Type: application/json` to `/api/instant-share/v1/qr-trigger` over the Unix socket
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>"}`

#### Scenario: Stash image payload (file path)
- **WHEN** the extension receives an image file from the Share menu
- **THEN** it SHALL POST a JSON body `{type: "image", file_path: "<absolute-path-to-file>", filename: "<original-filename>"}` with `Content-Type: application/json` to `/api/instant-share/v1/qr-trigger` over the Unix socket
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>"}`

#### Scenario: Stash multiple image payloads (batch file paths)
- **WHEN** the extension receives 3 image files from the Share menu
- **THEN** it SHALL POST a JSON body `{type: "image", files: [{file_path: "<path1>", filename: "<name1>"}, {file_path: "<path2>", filename: "<name2>"}, {file_path: "<path3>", filename: "<name3>"}]}` with `Content-Type: application/json` to `/api/instant-share/v1/qr-trigger` over the Unix socket
- **THEN** it SHALL receive a JSON response with `{status: "stashed", stash_id: "<uuid>", file_count: 3}`

#### Scenario: Stash failure handling
- **WHEN** the stash endpoint returns a non-200 response or the agent is unreachable
- **THEN** the extension SHALL exit silently (no user-facing error from the extension; the agent shows any errors)

### Requirement: Activation rule scoping
The Share Extension SHALL define an `NSExtensionActivationRule` that limits activation to text and file content types. For file URLs, the extension SHALL accept up to a configurable maximum number of files.

#### Scenario: Activation rule matches string type
- **WHEN** the extension is activated with text content
- **THEN** the activation rule SHALL match string type (`NSPasteboardTypeString`)

#### Scenario: Activation rule matches single or multiple file URLs
- **WHEN** the extension is activated with one or more files (up to the maximum allowed count)
- **THEN** the activation rule SHALL match file URL type (`public.file-url`) with `NSExtensionActivationSupportsFileWithMaxCount` set to a value greater than 1

#### Scenario: Activation rule rejects unsupported types
- **WHEN** the extension is activated with unsupported types (URLs, contact, calendar)
- **THEN** the activation rule SHALL NOT match