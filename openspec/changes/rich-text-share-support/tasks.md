## 1. macOS Share Extension — Rich Text Detection

- [x] 1.1 Add NSAttributedString detection before Data fallback in `MacShareViewController.swift`
- [x] 1.2 Convert NSAttributedString to HTML using `NSAttributedString.data(from:documentAttributes:)`
- [x] 1.3 Send HTML payload with `type: "html"` via QR transfer

## 2. PC-side Handler — HTML Support

- [x] 2.1 Add `"html"` type to `QRTriggerHandler._resolve_payload_type()`
- [x] 2.2 Store HTML content with `content_type: "text/html"` in stash
- [x] 2.3 Serve HTML content in claim response

## 3. iOS Client — HTML Case Handling

- [x] 3.1 Add `.html(String)` case to `QRClaimResult` enum in `QRTriggerDownloadClient.swift`
- [x] 3.2 Update `parseClaimResponse` to handle `"html"` type
- [x] 3.3 Update `QRClaimResultBox` equality for `.html` case

## 4. iOS Client — RichTextReceiveView

- [x] 4.1 Create `RichTextReceiveView.swift` in ISFromPC module
- [x] 4.2 Implement WKWebView with `preferences.javaScriptEnabled = false`
- [x] 4.3 Load HTML via `loadHTMLString(_:baseURL:)`
- [x] 4.4 Add "Copy to Clipboard" button using `UIPasteboard.general.setData(data, forPasteboardType: "public.html")`
- [x] 4.5 Add toast notification "Copied to clipboard" with auto-dismiss

## 5. Integration & Navigation

- [x] 5.1 Update `MobileAppModel` to navigate to `RichTextReceiveView` for `.html` case
- [x] 5.2 Verify end-to-end flow: macOS Share → PC → iOS HTML display + copy
