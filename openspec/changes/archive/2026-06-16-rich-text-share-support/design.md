## Context

The instant sharing flow (macOS Share Extension → PC → iOS) currently handles plain text and file attachments. Rich text from apps like Pages, Notes, TextEdit, and web pages is not properly handled — it falls through to the file path and is treated as an image, resulting in garbled content on iOS.

NSAttributedString is Apple's standard type for representing styled text. It conforms to multiple UTTypes including `.text`, `.plainText`, `.rtf`, and `.html`. When loaded via `NSItemProvider.loadObject(ofClass:)`, it preserves all formatting information. The provider can then be converted to HTML using `NSAttributedString.data(from:documentAttributes:)`.

The current `canLoadObject(ofClass: Data.self)` check catches rich text providers (since Data can represent any content), but the data is then assumed to be binary (image) and passed to the image display path. The fix is to add explicit NSAttributedString detection before the Data fallback.

## Goals / Non-Goals

**Goals:**
- Detect rich text (NSAttributedString) in the macOS Share Extension before the Data fallback
- Convert NSAttributedString to HTML using `NSAttributedString.data(from:documentAttributes:)`
- Send HTML content as a new `"html"` payload type via the existing QR transfer protocol
- Display HTML on iOS using WKWebView (JS disabled, system framework)
- Allow users to copy HTML to clipboard via a single "Copy to Clipboard" button using `UIPasteboard`

**Non-Goals:**
- Editing rich text on iOS — display only
- Supporting embedded images in HTML (files will be unresolved paths — accepted limitation)
- Supporting RTF or other text formats directly — HTML is the universal interchange format
- Adding third-party editor libraries (RichEditorView, etc.)

## Decisions

### 1. Detection: NSAttributedString before Data

**Decision**: Check `provider.canLoadObject(ofClass: NSAttributedString.self)` before `provider.canLoadObject(ofClass: Data.self)`.

**Rationale**: 
- Image types (JPEG, PNG, etc.) return `false` for `canLoadObject(ofClass: NSAttributedString.self)` because image UTTypes don't conform to text UTTypes in Apple's type hierarchy
- Rich text providers (Pages, Notes, TextEdit, web) return `true`
- This is a safe discriminator — no false positives for binary content
- Alternative considered: Checking for `UTType.html` or `UTType.rtf` explicitly — rejected because it would miss plain text providers that could also be loaded as NSAttributedString, and doesn't cover all rich text sources

### 2. HTML Conversion: NSAttributedString.data(from:)

**Decision**: Use `NSAttributedString.data(from:documentAttributes:documentAttributes:)` with `.html` document type to convert to HTML.

**Rationale**:
- System-provided, no dependencies
- Preserves headings, bold, italic, lists, links, paragraph structure
- Alternative considered: Markdown conversion — rejected because HTML is the natural interchange format for rich text and can be directly rendered in WKWebView without parsing

### 3. WKWebView with JS Disabled

**Decision**: Use WKWebView with `preferences.javaScriptEnabled = false`.

**Rationale**:
- System framework, no dependencies
- Displays HTML correctly with all formatting
- Disabling JS prevents any potential script execution (security)
- Copy functionality is handled in Swift via `UIPasteboard`, not JS
- Alternative considered: RichEditorView (third-party) — rejected because it adds a dependency, is overkill for display-only, and the author mentioned it hasn't been updated recently

### 4. Copy: UIPasteboard.general.setData(data, forType: .html)

**Decision**: Single "Copy to Clipboard" button that copies HTML to the system clipboard via `UIPasteboard.general.setData(htmlData, forType: .html)`.

**Rationale**:
- Copies HTML with full formatting
- Target apps (Mail, Notes, Pages, etc.) automatically handle HTML from clipboard
- No JS needed — works with JS disabled
- Simple and reliable
- No plain text copy needed — iOS pasteboard system handles fallback automatically

## Risks / Trade-offs

- **[Risk] HTML contains embedded image file paths** → Mitigation: Accept as known limitation; embedded images from the original document will show as broken `<img src="file://...">` tags on iOS since the file is on the Mac, not the iOS device. This is acceptable for text-focused sharing use cases.

- **[Risk] Large HTML content** → Mitigation: WKWebView handles large HTML well. QR transfer protocol already handles chunked streaming for large payloads.

- **[Risk] NSAttributedString conversion may lose some formatting** → Mitigation: HTML conversion is lossy for some NSAttributeString features (e.g., custom fonts, certain paragraph styles). This is acceptable — the most important formatting (bold, italic, headings, lists) is preserved.

## Migration Plan

- No migration needed — this is additive functionality
- Existing plain text and image paths continue to work unchanged
- New `"html"` type is added alongside existing types

## Open Questions

- None — all decisions are made and align with user preferences
