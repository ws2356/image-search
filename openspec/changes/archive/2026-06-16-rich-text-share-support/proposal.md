## Why

When users share rich text (formatted text from Pages, Notes, TextEdit, web pages) via the macOS Share Extension, the current implementation fails to preserve formatting. The extension only handles plain text (`UTType.plainText`) and files (`UTType.data`), causing rich text to fall through as a file and be treated as an image. This results in garbled content on the iOS side.

Users expect shared formatted text to arrive with its formatting intact — headings, bold, italic, lists, and paragraph structure should be preserved.

## What Changes

- **macOS Share Extension**: Add detection for `NSAttributedString` (rich text) via `provider.canLoadObject(ofClass: NSAttributedString.self)`. Convert rich text to HTML using `NSAttributedString.data(from:documentAttributes:)` and send as a new `"html"` payload type.

- **PC-side Handler**: Add support for `"html"` type in `QRTriggerHandler`. Store HTML content with `content_type="text/html"` and serve it on claim.

- **iOS Client**: Add new `QRClaimResult.html(String)` case to handle HTML content. Create `RichTextReceiveView` using WKWebView (JS disabled) to display formatted text. Add single "Copy to Clipboard" button that copies HTML via `UIPasteboard.general.setData(data, forType: .html)`.

- **Detection Priority**: Use `canLoadObject(ofClass: NSAttributedString.self)` as primary check, which safely covers both plain text and rich text. Image providers return `false` for this check (image types don't conform to text types in UTType hierarchy).

## Capabilities

### New Capabilities
- `html-share`: Rich text sharing via HTML — macOS converts NSAttributedString to HTML, PC stashes and serves it, iOS displays in WKWebView with clipboard copy

### Modified Capabilities
<!-- No existing capabilities modified -->

## Impact

- **macOS Share Extension**: `MacShareViewController.swift` — new NSAttributedString detection path
- **PC Handler**: `dt_image_search/instant_sharing/qr_trigger_handler.py` — new `"html"` type support
- **iOS ISFromPC Module**: `QRTriggerDownloadClient.swift` — new `.html(String)` case; new `RichTextReceiveView.swift` — WKWebView display
- **iOS AlbumTransporterKit**: `MobileAppDomain.swift` — new `QRClaimResult.html` case handling
- **Dependencies**: No new third-party dependencies (WKWebView is system framework)
