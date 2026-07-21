# Text File Card Preview

## Summary

Extend the iOS InstantShare file card UI so that text-based files (`contentType` starting with `text/`) render a readable text preview, regardless of whether the text was sent inline or as a downloadable file.

## Context

The current `ISFromPC` receive flow distinguishes between inline entries (`entryType == "text"`, `"html"`, `"link"`) and downloadable files (`entryType == "file"`).

- `TextFileCard` previews inline text.
- `ImageFileCard` previews image files.
- All other files fall back to `GenericFileCard`, which shows only filename, size, and a Share button.

This means a shared `.txt`, `.json`, `.csv`, or `.md` file is shown as a generic row even though its contents are human-readable. The goal is to give text files the same preview treatment as inline text.

## Requirements

1. Any downloaded file whose `contentType` starts with `text/` must be rendered with a text preview instead of `GenericFileCard`.
2. Inline text entries (`entryType == "text"`) continue to render as they do today.
3. Preview limits:
   - Maximum 5 lines.
   - Maximum 500 characters.
   - Apply whichever limit is reached first.
4. File-size safety cap: do not read files larger than 1 MB for preview; fall back to a placeholder message.
5. Font: use the existing monospaced font (`DesignSystem.Typography.monoBody`).
6. Downloading state: use the existing `FileCardContainer` spinner overlay.
7. Failed state: show an expanded card with a "Failed to load preview" placeholder.
8. Keep Copy and Share actions available on the card footer.

## Design

### Architecture

No new components are introduced. The change extends existing routing and preview logic:

- `FileCard.swift` decides which card type to render.
- `TextFileCard.swift` becomes the single component for text previews, handling both inline text and downloaded text files.
- `MultiFileReceiveViewModel.FileDownloadState` gains a computed property that resolves the preview string from either `inlineContent` or the downloaded file URL.

Existing layouts, spinners, and footer actions remain unchanged.

### Component Changes

#### `FileCard.swift`

Update the `"file"` branch to check for text content before falling back to image or generic handling:

```swift
case "file":
    let lowercasedContentType = state.contentType.lowercased()
    if lowercasedContentType.hasPrefix("text/") {
        TextFileCard(state: state, shareAction: shareAction)
    } else if lowercasedContentType.hasPrefix("image/") {
        ImageFileCard(state: state, shareAction: shareAction)
    } else {
        GenericFileCard(state: state, shareAction: shareAction)
    }
```

#### `MultiFileReceiveViewModel.FileDownloadState`

Add a helper that resolves the text to preview:

```swift
var textPreviewContent: String? {
    let source: String? = {
        if let inlineContent, !inlineContent.isEmpty {
            return inlineContent
        }
        guard let result else { return nil }
        switch result {
        case .file(let url, let contentType, _):
            guard contentType.lowercased().hasPrefix("text/") else { return nil }
            return Self.readPreviewText(from: url)
        default:
            return nil
        }
    }()
    guard let source else { return nil }
    return String(source.prefix(Self.maxPreviewCharacterCount))
}

private static let maxPreviewCharacterCount = 500
private static let maxPreviewFileSize = 1_048_576 // 1 MB

private static func readPreviewText(from url: URL) -> String? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? UInt64,
          size <= maxPreviewFileSize else {
        return nil
    }
    return try? String(contentsOf: url, encoding: .utf8)
}
```

#### `TextFileCard.swift`

Use the new helper and apply the monospaced font and truncation limits:

```swift
var body: some View {
    let preview = state.textPreviewContent
    FileCardContainer(isDownloading: state.status == .downloading) {
        ExpandedFileCardLayout(state: state) {
            if let preview {
                Text(preview)
                    .font(DesignSystem.Typography.monoBody)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                    .lineLimit(5)
                    .truncationMode(.tail)
                    .frame(height: 120, alignment: .topLeading)
            } else {
                placeholder
            }
        } footer: {
            HStack(spacing: DesignSystem.Spacing.md) {
                CardActionButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {
                    UIPasteboard.general.string = state.textPreviewContent ?? ""
                    withAnimation { showCopiedToast = true }
                }

                CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                    shareAction()
                }
            }
        }
    }
    .overlay(alignment: .bottom) {
        ToastView(message: "Copied to clipboard", isShowing: $showCopiedToast)
    }
}

private var placeholder: some View {
    VStack(spacing: DesignSystem.Spacing.sm) {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 28))
            .foregroundStyle(DesignSystem.Colors.secondaryText)
        Text(state.status == .failed ? "Failed to load preview" : "Preview not available")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .frame(height: 120)
}
```

The 500-character limit is enforced inside `textPreviewContent` by truncating the resolved source string before it is rendered. The 5-line limit is enforced by SwiftUI's `.lineLimit(5)` in `TextFileCard`.

### Data Flow

1. A manifest entry arrives with `type: "file"` and `contentType: "text/plain"`.
2. `FileDownloadState` is initialized with `inlineContent: nil` and status `.pending`.
3. `FileCard` routes to `TextFileCard` because the content type starts with `text/`.
4. While downloading, `FileCardContainer` overlays a spinner.
5. On successful download, `result` becomes `.file(url, contentType, filename)`.
6. `textPreviewContent` reads the file lazily, subject to the 1 MB cap, and returns the string.
7. `TextFileCard` renders the string with monospaced font, truncated to 500 characters and 5 lines.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Download in progress | `FileCardContainer` spinner overlay |
| Download failed | Expanded card body shows "Failed to load preview" placeholder |
| File larger than 1 MB | `textPreviewContent` returns `nil`; body shows "Preview not available" placeholder |
| Non-UTF-8 or unreadable file | Treated as unreadable; same placeholder as above |
| Inline text (`entryType == "text"`) | Works exactly as today |

### Testing

- Unit tests for `FileDownloadState.textPreviewContent`:
  - Inline text returns the inline content.
  - Small UTF-8 text file returns file contents.
  - File larger than 1 MB returns `nil`.
  - Non-text content type returns `nil`.
- UI previews in `TextFileCard.swift` for:
  - Inline text.
  - Downloaded text file.
  - Failed / unavailable preview state.

## Decisions

- **Approach A chosen:** Route text files into `TextFileCard` and teach it to read from disk. This is the smallest change that satisfies the requirement while keeping all text previews in one place.
- **Rejected Approach B:** Creating a separate `TextPreviewFileCard` would add a near-duplicate component without a clear future divergence need.
- **Rejected Approach C:** Adding the preview to `GenericFileCard` would mix compact-row responsibility with expanded-preview responsibility.

## Open Questions

None. All scope decisions were confirmed with the requester.
