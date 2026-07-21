# iOS File Card Receive UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current row-based file list in `MultiFileReceiveView` with type-specific cards (text, HTML, image, generic file, web link), route every receive result through `MultiFileReceiveView`, and switch the bulk action from Save All to Share All.

**Architecture:** Introduce a `Views/Components/FileCards/` package of small, focused SwiftUI views: shared card chrome (`FileCardBackground`, `ExpandedFileCardLayout`, `CompactFileCardLayout`, `FileCardContainer`), a new `CardActionButton`, one view per card type, and a `FileCard` dispatcher. Update `MultiFileReceiveViewModel` to preserve inline HTML/link results, support a single-result wrapper for all `QRClaimResult` types, and expose `shareAll()`. Update `MultiFileReceiveView` to render the card list and a Share All button. Finally, update `ISQRRootView` so every successful claim pushes `MultiFileReceiveView`.

**Tech Stack:** Swift, SwiftUI, UIKit (`UIActivityViewController`, `UIPasteboard`, `WKWebView`), iOS 15+ (matching existing `#if os(iOS)` guards).

## Global Constraints

- Target platform: iOS (`#if os(iOS)`).
- Use the existing `DesignSystem` colors, typography, spacing, and corner radii.
- All file paths use forward slashes and are relative to `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/` unless otherwise noted.
- Preserve the existing `MultiFileReceiveViewModel` public interface used by `ISQRRootView` and snapshot tests.
- Do not change `QRTriggerDownloadClient` networking logic.
- Use `git commit` after each task with `[LLM: <name>]` prefix.

---

## File map

| File | Responsibility |
| :-- | :-- |
| `Views/Components/FileCards/FileCardBackground.swift` | Shared white rounded card border/background. |
| `Views/Components/FileCards/ExpandedFileCardLayout.swift` | Header + fixed-height body + footer layout. |
| `Views/Components/FileCards/CompactFileCardLayout.swift` | Horizontal badge/info + trailing buttons layout. |
| `Views/Components/FileCards/FileCardContainer.swift` | Applies `FileCardBackground` + dimmed download overlay. |
| `Views/Components/CardActionButton.swift` | Pill-style action buttons used inside cards. |
| `Views/Components/FileCards/TextFileCard.swift` | Text preview card. |
| `Views/Components/FileCards/HTMLFileCard.swift` | Rich-text preview card. |
| `Views/Components/FileCards/ImageFileCard.swift` | Image thumbnail card. |
| `Views/Components/FileCards/GenericFileCard.swift` | Compact generic file card. |
| `Views/Components/FileCards/WebLinkCard.swift` | Web link preview card. |
| `Views/Components/FileCards/FileCard.swift` | Type dispatcher. |
| `ViewModels/MultiFileReceiveViewModel.swift` | Refactored view model (split from the view file). |
| `Views/MultiFileReceiveView.swift` | Updated list view using `FileCard`. |
| `Views/ISQRRootView.swift` | Updated routing for all result types. |
| `Tests/AlbumTransporterAppSnapshotTests/InstantShareSnapshotTests.swift` | New snapshot tests for cards and mixed list. |
| `Tests/AlbumTransporterKitTests/MultiFileReceiveViewModelTests.swift` | New unit tests for the view model. |

---

### Task 1: Create shared card chrome — `FileCardBackground`

**Files:**
- Create: `Views/Components/FileCards/FileCardBackground.swift`
- Test: run the app preview / build target

**Interfaces:**
- Produces: `FileCardBackground<Content: View>` — reusable card background.

- [ ] **Step 1: Create the directory and file**

Create `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileCardBackground.swift`:

```swift
import SwiftUI

#if os(iOS)
struct FileCardBackground<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
}

#Preview {
    FileCardBackground {
        Text("Card content")
    }
    .padding()
    .background(Color.white)
}
#endif
```

- [ ] **Step 2: Build the iOS target**

Run:

```bash
xcodebuild build -project mobile/ios/AlbumTransporterApp.xcodeproj -scheme AlbumTransporterApp -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -skip-testing
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileCardBackground.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add FileCardBackground component"
```

---

### Task 2: Create `FileTypeBadge` helper

**Files:**
- Create: `Views/Components/FileCards/FileTypeBadge.swift`
- Test: build target

**Interfaces:**
- Produces: `FileTypeBadge` view used by `ExpandedFileCardLayout` and `CompactFileCardLayout`.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct FileTypeBadge: View {
    let entryType: String
    let filename: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.chip)
                .fill(backgroundColor)
                .frame(width: 40, height: 40)

            Text(badgeText)
                .font(.system(size: 9, weight: .black))
                .tracking(0.5)
                .foregroundStyle(foregroundColor)
        }
    }

    private var badgeText: String {
        switch entryType.lowercased() {
        case "text": return "TXT"
        case "html": return "HTML"
        case "link": return "LINK"
        default:
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".png") { return "PNG" }
            if lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") { return "JPG" }
            if lowercased.hasSuffix(".pdf") { return "PDF" }
            if lowercased.hasSuffix(".zip") { return "ZIP" }
            if lowercased.hasSuffix(".txt") { return "TXT" }
            if lowercased.hasSuffix(".doc") || lowercased.hasSuffix(".docx") { return "DOC" }
            if lowercased.hasSuffix(".xls") || lowercased.hasSuffix(".xlsx") { return "XLS" }
            return "FILE"
        }
    }

    private var backgroundColor: Color {
        switch entryType.lowercased() {
        case "text", "html": return DesignSystem.Colors.primary.opacity(0.1)
        case "link": return DesignSystem.Colors.success.opacity(0.1)
        default:
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") {
                return DesignSystem.Colors.success.opacity(0.2)
            }
            if lowercased.hasSuffix(".pdf") {
                return DesignSystem.Colors.primary.opacity(0.2)
            }
            return DesignSystem.Colors.secondaryText.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch entryType.lowercased() {
        case "text", "html": return DesignSystem.Colors.primary
        case "link": return DesignSystem.Colors.success
        default:
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") {
                return DesignSystem.Colors.success
            }
            if lowercased.hasSuffix(".pdf") {
                return DesignSystem.Colors.primary
            }
            return DesignSystem.Colors.secondaryText
        }
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileTypeBadge.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add FileTypeBadge component"
```

---

### Task 3: Create `ExpandedFileCardLayout`

**Files:**
- Create: `Views/Components/FileCards/ExpandedFileCardLayout.swift`
- Test: run the app preview / build target

**Interfaces:**
- Consumes: `MultiFileReceiveViewModel.FileDownloadState`
- Produces: `ExpandedFileCardLayout<Body: View, Footer: View>`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct ExpandedFileCardLayout<Body: View, Footer: View>: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    @ViewBuilder let bodyContent: () -> Body
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            header
            bodyContent()
                .frame(maxWidth: .infinity)
            footer()
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            FileTypeBadge(entryType: state.entryType, filename: state.filename)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(state.filename.isEmpty ? "File \(state.index + 1)" : state.filename)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                    .lineLimit(1)

                Text(formatBytes(state.sizeBytes))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Text(typeLabel(for: state.entryType))
                .font(DesignSystem.Typography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
    }

    private func typeLabel(for entryType: String) -> String {
        switch entryType.lowercased() {
        case "text": return "TEXT"
        case "html": return "HTML"
        case "link": return "LINK"
        case "file": return fileTypeLabel(for: state.filename)
        default: return "FILE"
        }
    }

    private func fileTypeLabel(for filename: String) -> String {
        let lowercased = filename.lowercased()
        if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") { return "IMAGE" }
        if lowercased.hasSuffix(".pdf") { return "PDF" }
        if lowercased.hasSuffix(".zip") { return "ZIP" }
        return "FILE"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

#Preview {
    ExpandedFileCardLayout(
        state: MultiFileReceiveViewModel.FileDownloadState(
            index: 0,
            entryType: "text",
            filename: "notes.txt",
            contentType: "text/plain",
            sizeBytes: 1234,
            inlineContent: "Hello",
            status: .downloaded,
            result: .text("Hello")
        ),
        bodyContent: {
            Text("Preview body")
                .frame(height: 120, alignment: .topLeading)
        },
        footer: {
            Text("Footer")
        }
    )
    .padding()
    .background(Color.white)
}
#endif
```

- [ ] **Step 2: Build**

Run the same `xcodebuild build` command as Task 1.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/ExpandedFileCardLayout.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add ExpandedFileCardLayout component"
```

---

### Task 4: Create `CompactFileCardLayout`

**Files:**
- Create: `Views/Components/FileCards/CompactFileCardLayout.swift`
- Test: build target

**Interfaces:**
- Consumes: `MultiFileReceiveViewModel.FileDownloadState`
- Produces: `CompactFileCardLayout<Trailing: View>`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct CompactFileCardLayout<Trailing: View>: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            FileTypeBadge(entryType: state.entryType, filename: state.filename)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(state.filename.isEmpty ? "File \(state.index + 1)" : state.filename)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                    .lineLimit(1)

                Text(formatBytes(state.sizeBytes))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            trailing()
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

#Preview {
    CompactFileCardLayout(
        state: MultiFileReceiveViewModel.FileDownloadState(
            index: 0,
            entryType: "file",
            filename: "design_assets.zip",
            contentType: "application/zip",
            sizeBytes: 24_700_000,
            inlineContent: nil,
            status: .downloaded,
            result: nil
        )
    ) {
        Text("Trailing")
    }
    .padding()
    .background(Color.white)
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/CompactFileCardLayout.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add CompactFileCardLayout component"
```

---

### Task 5: Create `FileCardContainer`

**Files:**
- Create: `Views/Components/FileCards/FileCardContainer.swift`
- Test: build target

**Interfaces:**
- Consumes: `isDownloading: Bool`
- Produces: `FileCardContainer<Content: View>`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct FileCardContainer<Content: View>: View {
    let isDownloading: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        FileCardBackground {
            content()
        }
        .overlay(
            Group {
                if isDownloading {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                        .fill(DesignSystem.Colors.foreground.opacity(0.08))
                        .overlay(
                            ProgressView()
                                .controlSize(.regular)
                                .tint(DesignSystem.Colors.primary)
                        )
                }
            }
        )
        .disabled(isDownloading)
    }
}

#Preview {
    VStack(spacing: 16) {
        FileCardContainer(isDownloading: false) {
            Text("Idle card")
        }
        FileCardContainer(isDownloading: true) {
            Text("Downloading card")
        }
    }
    .padding()
    .background(Color.white)
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileCardContainer.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add FileCardContainer with download overlay"
```

---

### Task 6: Create `CardActionButton`

**Files:**
- Create: `Views/Components/CardActionButton.swift`
- Test: build target

**Interfaces:**
- Produces: `CardActionButton` — pill-style buttons for card footers.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct CardActionButton: View {
    let title: String
    var icon: String? = nil
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(DesignSystem.Typography.captionMedium)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return DesignSystem.Colors.primary
        case .secondary: return DesignSystem.Colors.foreground
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return DesignSystem.Colors.primary.opacity(0.1)
        case .secondary: return DesignSystem.Colors.cardBackground.opacity(0.8)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        CardActionButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {}
        CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {}
    }
    .padding()
    .background(Color.white)
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/CardActionButton.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add CardActionButton component"
```

---

### Task 7: Create `TextFileCard`

**Files:**
- Create: `Views/Components/FileCards/TextFileCard.swift`
- Test: build target + snapshot test (Task 13)

**Interfaces:**
- Consumes: `state: MultiFileReceiveViewModel.FileDownloadState`, `shareAction: () -> Void`
- Produces: `TextFileCard` view

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct TextFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                Text(state.inlineContent ?? "")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                    .lineLimit(5)
                    .frame(height: 120, alignment: .topLeading)
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {
                        UIPasteboard.general.string = state.inlineContent ?? ""
                    }

                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/TextFileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add TextFileCard component"
```

---

### Task 8: Create `HTMLFileCard`

**Files:**
- Create: `Views/Components/FileCards/HTMLFileCard.swift`
- Modify: `Views/RichTextReceiveView.swift` — ensure `RichTextWebView` is internal (not private).
- Test: build target

**Interfaces:**
- Consumes: `state: MultiFileReceiveViewModel.FileDownloadState`, `shareAction: () -> Void`
- Produces: `HTMLFileCard` view

- [ ] **Step 1: Make `RichTextWebView` internal**

In `Views/RichTextReceiveView.swift`, change:

```swift
struct RichTextWebView: UIViewRepresentable {
```

to:

```swift
struct RichTextWebView: UIViewRepresentable {
```

If it is already internal, no change is needed. It must not be `private`.

- [ ] **Step 2: Create `HTMLFileCard.swift`**

```swift
import SwiftUI

#if os(iOS)
struct HTMLFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        let html = state.downloadedTextContent ?? state.inlineContent ?? ""
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                RichTextWebView(html: html)
                    .frame(height: 120)
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {
                        guard let data = html.data(using: .utf8) else { return }
                        UIPasteboard.general.setData(data, forPasteboardType: "public.html")
                    }

                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 3: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/RichTextReceiveView.swift \
        mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/HTMLFileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add HTMLFileCard component"
```

---

### Task 9: Create `ImageFileCard`

**Files:**
- Create: `Views/Components/FileCards/ImageFileCard.swift`
- Test: build target

**Interfaces:**
- Consumes: `state: MultiFileReceiveViewModel.FileDownloadState`, `shareAction: () -> Void`
- Produces: `ImageFileCard` view

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct ImageFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                imagePreview
                    .frame(height: 160)
                    .clipped()
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let fileURL = state.result?.imageFileURL,
           let uiImage = UIImage(contentsOfFile: fileURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color(DesignSystem.Colors.secondaryText.opacity(0.1))
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            )
    }
}

private extension QRClaimResult {
    var imageFileURL: URL? {
        switch self {
        case .image(let fileURL, _, _): return fileURL
        default: return nil
        }
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/ImageFileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add ImageFileCard component"
```

---

### Task 10: Create `GenericFileCard`

**Files:**
- Create: `Views/Components/FileCards/GenericFileCard.swift`
- Test: build target

**Interfaces:**
- Consumes: `state: MultiFileReceiveViewModel.FileDownloadState`, `shareAction: () -> Void`
- Produces: `GenericFileCard` view

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct GenericFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            CompactFileCardLayout(state: state) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
        .frame(height: 72)
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/GenericFileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add GenericFileCard component"
```

---

### Task 11: Create `WebLinkCard`

**Files:**
- Create: `Views/Components/FileCards/WebLinkCard.swift`
- Test: build target

**Interfaces:**
- Consumes: `state: MultiFileReceiveViewModel.FileDownloadState`, `shareAction: () -> Void`
- Produces: `WebLinkCard` view

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct WebLinkCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        let urlString = state.downloadedTextContent ?? state.inlineContent ?? ""
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "link")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignSystem.Colors.primary)

                    Text(urlString)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 120)
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: "Copy Link", icon: "doc.on.doc", style: .secondary) {
                        UIPasteboard.general.string = urlString
                    }

                    if let url = URL(string: urlString) {
                        Link(destination: url) {
                            CardActionButton(title: "Open", icon: "safari", style: .secondary) {}
                        }
                    }

                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/WebLinkCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add WebLinkCard component"
```

---

### Task 12: Create `FileCard` dispatcher

**Files:**
- Create: `Views/Components/FileCards/FileCard.swift`
- Test: build target

**Interfaces:**
- Consumes: `state: MultiFileReceiveViewModel.FileDownloadState`, `shareAction: () -> Void`
- Produces: `FileCard` view

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

#if os(iOS)
struct FileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        switch state.entryType.lowercased() {
        case "text":
            TextFileCard(state: state, shareAction: shareAction)
        case "html":
            HTMLFileCard(state: state, shareAction: shareAction)
        case "link":
            WebLinkCard(state: state, shareAction: shareAction)
        case "file":
            if state.contentType.lowercased().hasPrefix("image/") {
                ImageFileCard(state: state, shareAction: shareAction)
            } else {
                GenericFileCard(state: state, shareAction: shareAction)
            }
        default:
            GenericFileCard(state: state, shareAction: shareAction)
        }
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add FileCard dispatcher"
```

---

### Task 13: Extract and update `MultiFileReceiveViewModel`

**Files:**
- Create: `ViewModels/MultiFileReceiveViewModel.swift`
- Modify: `Views/MultiFileReceiveView.swift` — remove the view model class, keep only the view.
- Test: build target + new unit tests (Task 15)

**Interfaces:**
- Consumes: `MultiFileManifest`, `QRClaimResult`
- Produces: `MultiFileReceiveViewModel` with `shareAll()`, `shareState(_:)`, updated inline result mapping, and single-result wrapper for all types.

- [ ] **Step 1: Create `ViewModels/MultiFileReceiveViewModel.swift`**

1. Create `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/MultiFileReceiveViewModel.swift`.
2. Add imports at the top:
   ```swift
   import SwiftUI
   import Factory
   import Common
   ```
3. Copy the entire `@MainActor public class MultiFileReceiveViewModel` (and its nested `FileDownloadState` struct/enums) from `Views/MultiFileReceiveView.swift` into the new file.
4. Apply the changes in Steps 2–4 below.

- [ ] **Step 2: Update inline result mapping**

In the manifest initializer, replace:

```swift
let result: QRClaimResult? = entry.isInline
    ? .text(entry.content ?? "")
    : nil
```

with:

```swift
let result: QRClaimResult? = {
    guard let content = entry.content else { return nil }
    switch entry.type {
    case "text": return .text(content)
    case "html": return .html(content)
    case "link": return .link(content)
    default: return nil
    }
}()
```

- [ ] **Step 3: Extend `singleResult` initializer for all types**

Replace the existing `init(singleResult:delegate:)` switch with:

```swift
public init(
    singleResult: QRClaimResult,
    delegate: ISQRDeliverDelegate
) {
    self.manifest = MultiFileManifest(fileCount: 1, files: [])
    self.host = ""
    self.tlsPort = 0
    self.sessionId = ""
    self.correlationID = ""
    self.delegate = delegate

    switch singleResult {
    case .text(let text):
        self.fileStates = [FileDownloadState(
            index: 0, entryType: "text", filename: "Shared Text",
            contentType: "text/plain", sizeBytes: text.utf8.count,
            inlineContent: text, status: .downloaded, result: singleResult
        )]
    case .html(let html):
        self.fileStates = [FileDownloadState(
            index: 0, entryType: "html", filename: "Shared Note",
            contentType: "text/html", sizeBytes: html.utf8.count,
            inlineContent: html, status: .downloaded, result: singleResult
        )]
    case .link(let urlString):
        self.fileStates = [FileDownloadState(
            index: 0, entryType: "link", filename: "Web Link",
            contentType: "text/uri-list", sizeBytes: urlString.utf8.count,
            inlineContent: urlString, status: .downloaded, result: singleResult
        )]
    case .image(let fileURL, let contentType, let filename):
        let displayName = filename ?? fileURL.lastPathComponent
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
        self.fileStates = [FileDownloadState(
            index: 0, entryType: "file", filename: displayName,
            contentType: contentType, sizeBytes: sizeBytes,
            inlineContent: nil, status: .downloaded, result: singleResult
        )]
    case .file(let fileURL, let contentType, let filename):
        let displayName = filename ?? fileURL.lastPathComponent
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
        self.fileStates = [FileDownloadState(
            index: 0, entryType: "file", filename: displayName,
            contentType: contentType, sizeBytes: sizeBytes,
            inlineContent: nil, status: .downloaded, result: singleResult
        )]
    case .multiFile:
        self.fileStates = []
    }
}
```

- [ ] **Step 4: Add `shareAll()` and `shareState(_:)`**

Add these methods and refactor `presentShareSheetForSelected()` to use a shared helper:

```swift
public func shareAll() {
    let states = fileStates.filter { $0.status == .downloaded || $0.isInline }
    presentShareSheet(for: states)
}

public func shareState(_ state: FileDownloadState) {
    presentShareSheet(for: [state])
}

public func shareSelected() {
    let states = selectedIndices.sorted().compactMap { index in
        fileStates.first { $0.index == index }
    }
    presentShareSheet(for: states)
}

private func presentShareSheet(for states: [FileDownloadState]) {
    var items: [Any] = []

    for state in states {
        if state.isInline, let content = state.inlineContent {
            items.append(content)
            continue
        }

        guard let result = state.result else { continue }
        switch result {
        case .text(let text):
            items.append(text)
        case .html(let html):
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).html")
            try? html.data(using: .utf8)?.write(to: tempURL)
            items.append(tempURL)
        case .link(let urlString):
            if let url = URL(string: urlString) {
                items.append(url)
            } else {
                items.append(urlString)
            }
        case .image(let fileURL, _, _), .file(let fileURL, _, _):
            items.append(fileURL)
        case .multiFile:
            break
        }
    }

    guard !items.isEmpty else { return }
    shareItems = items
    showShareSheet = true
}
```

Remove the old `presentShareSheetForSelected()` method.

- [ ] **Step 5: Clean up `Views/MultiFileReceiveView.swift`**

After moving the view model class to the new file:

1. Delete the `@MainActor public class MultiFileReceiveViewModel` and its nested types from `Views/MultiFileReceiveView.swift`.
2. Keep the `import SwiftUI`, `import Factory`, `import Common`, and `#if os(iOS)` guards.
3. Keep the `MultiFileReceiveView` struct and the `ShareSheet` extension.
4. Ensure there are no duplicate declarations.

- [ ] **Step 6: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/MultiFileReceiveViewModel.swift \
        mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/MultiFileReceiveView.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Refactor MultiFileReceiveViewModel and support all result types"
```

---

### Task 14: Update `MultiFileReceiveView`

**Files:**
- Modify: `Views/MultiFileReceiveView.swift`
- Test: build target + snapshot tests (Task 16)

**Interfaces:**
- Consumes: `MultiFileReceiveViewModel`, `FileCard`
- Produces: Updated list UI with Share All button.

- [ ] **Step 1: Replace the file body**

Replace the contents of `Views/MultiFileReceiveView.swift` with:

```swift
import SwiftUI
import Factory
import Common

#if os(iOS)
public struct MultiFileReceiveView: View {
    @StateObject public var viewModel: MultiFileReceiveViewModel

    public init(viewModel: MultiFileReceiveViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showShareSheet) {
                ShareSheet(items: viewModel.shareItems)
            }
            .task {
                await viewModel.startDownloadingAll()
            }
            .onDisappear {
                Task { await viewModel.cleanupDownloadedFiles() }
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if viewModel.isDownloading {
                progressBanner
            }

            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    ForEach(viewModel.fileStates) { state in
                        FileCard(state: state) {
                            viewModel.shareState(state)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }

            if viewModel.fileStates.contains(where: { !$0.isInline || $0.status == .downloaded }) {
                shareAllButton
            }
        }
        .background(DesignSystem.Colors.background)
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Received")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(DesignSystem.Colors.foreground)

                Text("\(viewModel.totalCount) \(viewModel.totalCount == 1 ? "item" : "items") from MacBook Pro")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Button("Done") {
                viewModel.delegate.onDeliverComplete()
            }
            .font(DesignSystem.Typography.h4)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    private var progressBanner: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(DesignSystem.Colors.primary)

            Text("Receiving file \(viewModel.downloadedCount + 1) of \(viewModel.totalCount)…")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    private var shareAllButton: some View {
        Button(action: { viewModel.shareAll() }) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
                Text("Share All (\(viewModel.downloadedCount))")
                    .font(DesignSystem.Typography.h4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.md)
    }
}
#endif
```

- [ ] **Step 2: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/MultiFileReceiveView.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Update MultiFileReceiveView to use FileCard and Share All"
```

---

### Task 15: Update `ISQRRootView` to route all results through `MultiFileReceiveView`

**Files:**
- Modify: `Views/ISQRRootView.swift`
- Test: build target + snapshot tests

**Interfaces:**
- Consumes: `QRClaimResult`, `MultiFileReceiveViewModel`
- Produces: A helper that creates a `MultiFileReceiveViewModel` for any result.

- [ ] **Step 1: Add a result-to-view-model helper**

Add the following helper at the bottom of `Views/ISQRRootView.swift` (inside the `#endif` if needed, but keep it iOS-only):

```swift
#if os(iOS)
@MainActor
private extension ISQRRootView {
    func makeMultiFileViewModel(for result: QRClaimResult, delegate: ISQRDeliverDelegate) -> MultiFileReceiveViewModel {
        switch result {
        case .multiFile(let manifest, let host, let tlsPort, let sessionId, let correlationID):
            return MultiFileReceiveViewModel(
                manifest: manifest,
                host: host,
                tlsPort: tlsPort,
                sessionId: sessionId,
                correlationID: correlationID,
                delegate: delegate
            )
        default:
            return MultiFileReceiveViewModel(singleResult: result, delegate: delegate)
        }
    }
}
#endif
```

- [ ] **Step 2: Replace the `.result` branch in `contentView`**

Change:

```swift
case .result(let result):
    switch result {
    case .multiFile(let manifest, let host, let tlsPort, let sessionId, let correlationID):
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: host,
            tlsPort: tlsPort,
            sessionId: sessionId,
            correlationID: correlationID,
            delegate: viewModel
        )
        MultiFileReceiveView(viewModel: vm)
    case .image, .file:
        let vm = MultiFileReceiveViewModel(
            singleResult: result,
            delegate: viewModel
        )
        MultiFileReceiveView(viewModel: vm)
    default:
        QRTransferResultView(result: result, delegate: viewModel)
    }
```

to:

```swift
case .result(let result):
    let vm = makeMultiFileViewModel(for: result, delegate: viewModel)
    MultiFileReceiveView(viewModel: vm)
```

- [ ] **Step 3: Build**

Run the iOS build.

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/ISQRRootView.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Route all receive results through MultiFileReceiveView"
```

---

### Task 16: Update snapshot tests

**Files:**
- Modify: `mobile/ios/Tests/AlbumTransporterAppSnapshotTests/InstantShareSnapshotTests.swift`
- Test: `cd mobile/ios && scripts/run_snapshot_tests.sh record` (after verifying tests fail without baselines)

**Interfaces:**
- Consumes: `FileCard`, `MultiFileReceiveViewModel`, `MultiFileReceiveView`

- [ ] **Step 1: Add snapshot tests for each card type**

Append the following tests to `InstantShareSnapshotTests`:

```swift
// MARK: - Text Card

func test_share_receive_text_card() throws {
    let manifest = MultiFileManifest(
        fileCount: 1,
        files: [
            .init(
                index: 0,
                type: "text",
                filename: "notes.txt",
                contentType: "text/plain",
                sizeBytes: 1234,
                content: "Hello from Mac!\n\nThis is a shared text message with multiple lines."
            )
        ]
    )
    let vm = MultiFileReceiveViewModel(
        manifest: manifest,
        host: "192.168.1.100",
        tlsPort: 8443,
        sessionId: "test-session",
        correlationID: "test-correlation",
        delegate: SnapshotISQRDeliverDelegate()
    )
    let viewController = makeHostedPage(title: "Received Files") {
        MultiFileReceiveView(viewModel: vm)
    }
    try SnapshotSupport.assertSnapshot(pageName: "share-receive-text-card", viewController: viewController)
}

// MARK: - HTML Card

func test_share_receive_html_card() throws {
    let manifest = MultiFileManifest(
        fileCount: 1,
        files: [
            .init(
                index: 0,
                type: "html",
                filename: "note.html",
                contentType: "text/html",
                sizeBytes: 2048,
                content: "<html><body><h1>Hello</h1><p>Rich text preview.</p></body></html>"
            )
        ]
    )
    let vm = MultiFileReceiveViewModel(
        manifest: manifest,
        host: "192.168.1.100",
        tlsPort: 8443,
        sessionId: "test-session",
        correlationID: "test-correlation",
        delegate: SnapshotISQRDeliverDelegate()
    )
    let viewController = makeHostedPage(title: "Received Files") {
        MultiFileReceiveView(viewModel: vm)
    }
    try SnapshotSupport.assertSnapshot(pageName: "share-receive-html-card", viewController: viewController)
}

// MARK: - Web Link Card

func test_share_receive_link_card() throws {
    let result = QRClaimResult.link("https://example.com/shared-document")
    let vm = MultiFileReceiveViewModel(singleResult: result, delegate: SnapshotISQRDeliverDelegate())
    let viewController = makeHostedPage(title: "Received Files") {
        MultiFileReceiveView(viewModel: vm)
    }
    try SnapshotSupport.assertSnapshot(pageName: "share-receive-link-card", viewController: viewController)
}

// MARK: - Mixed File List

func test_share_receive_mixed_list() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-test-mixed", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let imageURL = tempDir.appendingPathComponent("vacation_photo.jpg")
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
    let image = renderer.image { ctx in
        UIColor.systemOrange.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    try image.jpegData(compressionQuality: 0.8)?.write(to: imageURL)

    let manifest = MultiFileManifest(
        fileCount: 3,
        files: [
            .init(
                index: 0,
                type: "text",
                filename: "gllue_links.txt",
                contentType: "text/plain",
                sizeBytes: 1200,
                content: "x.gllue.com\nGllue - Remember me Sign In\nhire58.com.cn"
            ),
            .init(
                index: 1,
                type: "file",
                filename: "vacation_photo.jpg",
                contentType: "image/jpeg",
                sizeBytes: 2_400_000,
                content: nil
            ),
            .init(
                index: 2,
                type: "file",
                filename: "design_assets.zip",
                contentType: "application/zip",
                sizeBytes: 24_700_000,
                content: nil
            )
        ]
    )
    let vm = MultiFileReceiveViewModel(
        manifest: manifest,
        host: "192.168.1.100",
        tlsPort: 8443,
        sessionId: "test-session",
        correlationID: "test-correlation",
        delegate: SnapshotISQRDeliverDelegate()
    )
    // Pre-populate the image result so the card renders the thumbnail.
    if let index = vm.fileStates.firstIndex(where: { $0.filename == "vacation_photo.jpg" }) {
        vm.fileStates[index].result = .image(fileURL: imageURL, contentType: "image/jpeg", filename: "vacation_photo.jpg")
        vm.fileStates[index].status = .downloaded
    }
    let viewController = makeHostedPage(title: "Received Files") {
        MultiFileReceiveView(viewModel: vm)
    }
    try SnapshotSupport.assertSnapshot(pageName: "share-receive-mixed-list", viewController: viewController)

    try? FileManager.default.removeItem(at: tempDir)
}
```

- [ ] **Step 2: Update existing single-image and single-file tests**

The existing `test_share_receive_single_image()` and `test_share_receive_single_file()` tests already use `MultiFileReceiveView`. Verify they still pass; the UI will look different, so new baselines will be generated in record mode.

- [ ] **Step 3: Run snapshot tests in record mode**

```bash
cd mobile/ios && scripts/run_snapshot_tests.sh record
```

Expected: tests run and generate new baselines. Review the generated PNGs in `mobile/ios/Tests/AlbumTransporterAppSnapshotTests/__Snapshots__/`.

- [ ] **Step 4: Run snapshot tests in test mode**

```bash
cd mobile/ios && scripts/run_snapshot_tests.sh test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/ios/Tests/AlbumTransporterAppSnapshotTests/InstantShareSnapshotTests.swift \
        mobile/ios/Tests/AlbumTransporterAppSnapshotTests/__Snapshots__/
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Update snapshot tests for file card UI"
```

---

### Task 17: Add unit tests for `MultiFileReceiveViewModel`

**Files:**
- Create: `mobile/ios/Tests/AlbumTransporterKitTests/MultiFileReceiveViewModelTests.swift`
- Test: `cd mobile/ios && scripts/run_unit_tests.sh`

**Interfaces:**
- Consumes: `MultiFileReceiveViewModel`

- [ ] **Step 1: Create the test file**

```swift
import XCTest
@testable import ISFromPC

@MainActor
final class MultiFileReceiveViewModelTests: XCTestCase {
    private final class StubDelegate: ISQRDeliverDelegate {
        func onDeliverComplete() {}
    }

    func test_inlineTextResult_isInitializedAsDownloaded() {
        let manifest = MultiFileManifest(
            fileCount: 1,
            files: [
                .init(index: 0, type: "text", filename: "notes.txt",
                      contentType: "text/plain", sizeBytes: 10,
                      content: "hello")
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "host",
            tlsPort: 8443,
            sessionId: "sid",
            correlationID: "cid",
            delegate: StubDelegate()
        )

        XCTAssertEqual(vm.fileStates.count, 1)
        XCTAssertEqual(vm.fileStates[0].status, .downloaded)
        XCTAssertEqual(vm.fileStates[0].result, .text("hello"))
    }

    func test_inlineHtmlResult_preservesHtmlResultType() {
        let manifest = MultiFileManifest(
            fileCount: 1,
            files: [
                .init(index: 0, type: "html", filename: "note.html",
                      contentType: "text/html", sizeBytes: 20,
                      content: "<p>hi</p>")
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "host",
            tlsPort: 8443,
            sessionId: "sid",
            correlationID: "cid",
            delegate: StubDelegate()
        )

        if case .html(let value) = vm.fileStates[0].result {
            XCTAssertEqual(value, "<p>hi</p>")
        } else {
            XCTFail("Expected html result")
        }
    }

    func test_singleTextResult_wrapsIntoOneItemState() {
        let vm = MultiFileReceiveViewModel(
            singleResult: .text("hello"),
            delegate: StubDelegate()
        )

        XCTAssertEqual(vm.fileStates.count, 1)
        XCTAssertEqual(vm.fileStates[0].entryType, "text")
        XCTAssertEqual(vm.fileStates[0].status, .downloaded)
    }

    func test_singleLinkResult_wrapsIntoOneItemState() {
        let vm = MultiFileReceiveViewModel(
            singleResult: .link("https://example.com"),
            delegate: StubDelegate()
        )

        XCTAssertEqual(vm.fileStates.count, 1)
        XCTAssertEqual(vm.fileStates[0].entryType, "link")
        XCTAssertEqual(vm.fileStates[0].status, .downloaded)
    }

    func test_shareAll_setsShareItemsForAllDownloadedStates() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vm-test")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("doc.txt")
        try? Data("content".utf8).write(to: fileURL)

        let vm = MultiFileReceiveViewModel(
            singleResult: .file(fileURL: fileURL, contentType: "text/plain", filename: "doc.txt"),
            delegate: StubDelegate()
        )
        vm.shareAll()

        XCTAssertEqual(vm.shareItems.count, 1)
        XCTAssertTrue(vm.showShareSheet)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
```

- [ ] **Step 2: Run unit tests**

```bash
cd mobile/ios && scripts/run_unit_tests.sh
```

Expected: tests pass.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios/Tests/AlbumTransporterKitTests/MultiFileReceiveViewModelTests.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add MultiFileReceiveViewModel unit tests"
```

---

### Task 18: Final verification

**Files:** all modified files.

- [ ] **Step 1: Run the full iOS test suite**

```bash
cd mobile/ios && scripts/run_unit_tests.sh && scripts/run_snapshot_tests.sh test
```

Expected: unit tests and snapshot tests both pass.

- [ ] **Step 2: Run a smoke build of the main app**

```bash
xcodebuild build -project mobile/ios/AlbumTransporterApp.xcodeproj -scheme AlbumTransporterApp -destination "platform=iOS Simulator,name=iPhone 17 Pro Max"
```

Expected: build succeeds with no warnings introduced by this change.

- [ ] **Step 3: Final review of git diff**

```bash
git diff --stat
```

Expected: changes are limited to the planned files.

- [ ] **Step 4: Commit any final fixes**

If any fixes were required, commit them with a descriptive message.

---

## Self-review checklist

- [x] Spec coverage: every requirement from the design spec maps to a task.
  - Shared card chrome → Tasks 1–5.
  - Card action button → Task 6.
  - Text/HTML/Image/Generic/WebLink cards → Tasks 7–11.
  - Dispatcher → Task 12.
  - View model updates → Task 13.
  - View update → Task 14.
  - Routing change → Task 15.
  - Snapshot tests → Task 16.
  - Unit tests → Task 17.
- [x] Task ordering: `FileTypeBadge` (Task 2) is created before `ExpandedFileCardLayout` (Task 3) and `CompactFileCardLayout` (Task 4) so each task builds independently.
- [x] Placeholder scan: no TBD, TODO, or vague steps; each step includes concrete code or commands.
- [x] Type consistency: `MultiFileReceiveViewModel.FileDownloadState`, `QRClaimResult`, and `FileCard` signatures are consistent across tasks.
