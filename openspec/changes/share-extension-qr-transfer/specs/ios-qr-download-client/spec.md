## ADDED Requirements

### Requirement: QR code scanning for transfer claim
AuBackup iOS app SHALL provide a QR code scanner view that, when a QR containing `ausearch://claim?` scheme is scanned, initiates the download flow.

#### Scenario: Scan valid QR
- **WHEN** the user taps "Scan QR Code" in AuBackup
- **THEN** the camera SHALL activate and scan for QR codes
- **WHEN** a QR is scanned containing `ausearch://claim?ips=<ips>&port=<port>&stash=<stash_id>&opt=<opt_code>`
- **THEN** the app SHALL extract the IP list, port, stash_id, and opt_code from the URL
- **THEN** the app SHALL begin the claim flow by calling the claim endpoint

#### Scenario: Scan non-claim QR
- **WHEN** the scanned QR code does not match the `ausearch://claim?` format
- **THEN** the app SHALL show an error: "Not a valid AuSearch share code"

#### Scenario: Camera permission denied
- **WHEN** the user has not granted camera permission
- **THEN** the scanner SHALL show a permission prompt directing the user to Settings

### Requirement: Claim HTTP request
AuBackup SHALL send `POST /api/instant-share/v1/qr-claim` to one of the IPs extracted from the QR code with the stash_id and opt_code in the request body.

#### Scenario: Successful claim of text
- **WHEN** AuBackup POSTs to `http://<ip>:<port>/api/instant-share/v1/qr-claim` with `{stash_id: "<uuid>", opt: "<code>"}` and the server returns `200` with `Content-Type: text/plain`
- **THEN** AuBackup SHALL display the received text in a view with a "Copy to Clipboard" button

#### Scenario: Successful claim of image
- **WHEN** AuBackup POSTs to `http://<ip>:<port>/api/instant-share/v1/qr-claim` and the server returns `200` with `Content-Type: image/*`
- **THEN** AuBackup SHALL display the received image in a view with a "Save to Photo Library" button

#### Scenario: Claim with network failure
- **WHEN** the request to the first IP fails (connection refused, timeout)
- **THEN** AuBackup SHALL retry with the next IP in the list (failover)
- **WHEN** all IPs in the list fail
- **THEN** AuBackup SHALL show an error: "Could not connect to your Mac. Make sure both devices are on the same Wi-Fi network."

### Requirement: Display received text
AuBackup SHALL provide a view to display received text content and allow the user to copy it to the clipboard.

#### Scenario: Copy text to clipboard
- **WHEN** the user taps "Copy to Clipboard"
- **THEN** the text SHALL be copied to the iOS system pasteboard
- **THEN** a confirmation toast SHALL appear: "Copied to clipboard"

#### Scenario: View full text
- **WHEN** the received text is longer than the visible area
- **THEN** the view SHALL be scrollable

### Requirement: Display and save received image
AuBackup SHALL provide a view to display a received image and allow the user to save it to the photo library.

#### Scenario: Save image to photo library
- **WHEN** the user taps "Save to Photo Library"
- **THEN** AuBackup SHALL request photo library write permission (if not already granted)
- **WHEN** permission is granted
- **THEN** the image SHALL be saved to the Photos app
- **THEN** a confirmation toast SHALL appear: "Saved to Photos"

#### Scenario: Photo library permission denied
- **WHEN** the user taps "Save to Photo Library" but has not granted photo library write access
- **THEN** the app SHALL show a permission prompt directing the user to Settings

### Requirement: Deep link entry
AuBackup SHALL register and handle the `aubackup://qr-claim` URL scheme as an alternative entry point to the QR download flow. The URL SHALL carry the same params as the QR code as raw query parameters, not base64-encoded.

#### Scenario: Open from deep link
- **WHEN** AuBackup is opened via `aubackup://qr-claim?ips=<ips>&port=<port>&stash=<stash_id>&opt=<opt_code>`
- **THEN** it SHALL extract the claim URL parameters from the query string
- **THEN** it SHALL proceed with the claim flow as if the QR was scanned

### Requirement: Error handling and user feedback
AuBackup SHALL handle all error cases from the claim flow with clear user-visible messages.

#### Scenario: Invalid opt-code
- **WHEN** the claim endpoint returns `401`
- **THEN** AuBackup SHALL show: "Invalid code. Make sure the code on your Mac screen is correct."

#### Scenario: Stash expired
- **WHEN** the claim endpoint returns `410`
- **THEN** AuBackup SHALL show: "This share has expired. Please share the data again from your Mac."

#### Scenario: General server error
- **WHEN** the claim endpoint returns a 5xx status
- **THEN** AuBackup SHALL show: "Something went wrong. Please try again."