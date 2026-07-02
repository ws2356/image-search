## ADDED Requirements

### Requirement: macOS Share Extension detects rich text providers

The macOS Share Extension SHALL detect rich text (NSAttributedString) providers before falling back to Data.

#### Scenario: Rich text from Pages document

- **WHEN** user shares selected text from a Pages document via the Share Extension
- **THEN** the extension SHALL load the content as NSAttributedString via `provider.canLoadObject(ofClass: NSAttributedString.self)`

#### Scenario: Rich text from Notes app

- **WHEN** user shares a note with formatted text (bold, italic, lists) via the Share Extension
- **THEN** the extension SHALL detect the NSAttributedString provider and load it

#### Scenario: Image provider returns false for NSAttributedString

- **WHEN** user shares a JPEG image via the Share Extension
- **THEN** `provider.canLoadObject(ofClass: NSAttributedString.self)` SHALL return false
- **AND** the extension SHALL fall through to the Data/image path

### Requirement: NSAttributedString converts to HTML

The macOS Share Extension SHALL convert loaded NSAttributedString to HTML using `NSAttributedString.data(from:documentAttributes:)` with `.html` document type.

#### Scenario: Convert rich text to HTML

- **WHEN** an NSAttributedString is successfully loaded from the provider
- **THEN** the extension SHALL call `attributedString.data(from:documentAttributes:documentAttributes: [.documentType: NSAttributedString.DocumentType.html])`
- **AND** the resulting HTML data SHALL be converted to a UTF-8 string

#### Scenario: Send HTML payload via QR transfer

- **WHEN** HTML content is generated from NSAttributedString
- **THEN** the extension SHALL send a payload with `type: "html"` containing the HTML string
- **AND** the PC-side handler SHALL store the content with `content_type: "text/html"`

### Requirement: PC-side handler serves HTML content

The PC-side `QRTriggerHandler` SHALL support the `"html"` type and serve HTML content on claim.

#### Scenario: Store HTML in stash

- **WHEN** the PC receives a QR claim request with `type: "html"`
- **THEN** the handler SHALL create a stash entry with `content_type: "text/html"`
- **AND** the HTML content SHALL be stored as a UTF-8 string

#### Scenario: Serve HTML on claim

- **WHEN** an iOS device claims a stash entry with `type: "html"`
- **THEN** the handler SHALL return the HTML content in the response payload
- **AND** the response SHALL include `"type": "html"`

### Requirement: iOS client handles HTML content

The iOS client SHALL add a new `QRClaimResult.html(String)` case to handle HTML content.

#### Scenario: Parse HTML claim response

- **WHEN** the iOS client receives a claim response with `type: "html"`
- **THEN** `parseClaimResponse` SHALL create a `QRClaimResult.html(htmlString)` case
- **AND** the `claimID` SHALL be extracted from the response

#### Scenario: Navigate to RichTextReceiveView

- **WHEN** `QRClaimResult.html` is received
- **THEN** `QRClaimResultBox` SHALL be set with the HTML content
- **AND** the view SHALL navigate to `RichTextReceiveView`

### Requirement: RichTextReceiveView displays HTML

The `RichTextReceiveView` SHALL display HTML content using WKWebView with JavaScript disabled.

#### Scenario: Display formatted text

- **WHEN** `RichTextReceiveView` receives an HTML string
- **THEN** it SHALL create a WKWebView with `preferences.javaScriptEnabled = false`
- **AND** the WKWebView SHALL load the HTML string via `loadHTMLString(_:baseURL:)`
- **AND** all formatting (headings, bold, italic, lists, links) SHALL be displayed correctly

#### Scenario: Navigation bar with Done button

- **WHEN** the view is displayed
- **THEN** it SHALL show a NavigationView with title "Received"
- **AND** a "Done" button in the top-right corner SHALL dismiss the view

### Requirement: Copy to clipboard

The `RichTextReceiveView` SHALL provide a single "Copy to Clipboard" button that copies HTML to the system clipboard.

#### Scenario: User taps Copy button

- **WHEN** user taps the "Copy to Clipboard" button
- **THEN** the HTML content SHALL be copied to `UIPasteboard.general` using `setData(htmlData, forType: .html)`
- **AND** a toast notification SHALL appear saying "Copied to clipboard"
- **AND** the toast SHALL auto-dismiss after 2 seconds

#### Scenario: Pasting rich text into another app

- **WHEN** user copies HTML from RichTextReceiveView
- **AND** pastes into Mail, Notes, Pages, or other rich text apps
- **THEN** the pasted content SHALL retain all formatting (headings, bold, italic, lists)

### Requirement: HTML does not contain script execution

The WKWebView in RichTextReceiveView SHALL not execute JavaScript.

#### Scenario: JavaScript is disabled

- **WHEN** the WKWebView loads HTML content
- **THEN** `preferences.javaScriptEnabled` SHALL be false
- **AND** any `<script>` tags in the HTML SHALL NOT execute
