# Text File Card Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make downloaded text files (`contentType` starting with `text/`) render a text preview in the iOS InstantShare receive flow, using the same card shape as inline text.

**Architecture:** Extract the preview-resolution logic into a small, testable `TextPreviewContentResolver` service. `FileDownloadState` exposes a `textPreviewContent` property that delegates to the resolver. `FileCard` routes text files to `TextFileCard`, which renders the preview with a monospaced font and applies the 5-line / 500-character limits.

**Tech Stack:** Swift 6, SwiftUI, Swift Package Manager, XCTest.

## Global Constraints

- iOS 15+ / macOS 10.15+.
- All file paths use forward slashes.
- Follow existing code style: PascalCase types, snake_case functions/variables, private members prefixed with `_` or `private`.
- Keep UI code free of business logic; business logic lives in the resolver / view model.
- Use `pathlib.Path` for path manipulation where applicable (N/A for Swift — use `URL` and `FileManager`).
- No `print()` or standard logging; use telemetry where appropriate (not needed for this UI change).
- Add new tests to the package test target.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sources/ISFromPC/Services/TextPreviewContentResolver.swift` | Pure logic: decide whether a file entry can be previewed as text, read it safely, and truncate to the character limit. |
| `Sources/ISFromPC/ViewModels/MultiFileReceiveViewModel.swift` | Expose `textPreviewContent` on `FileDownloadState` by delegating to the resolver. |
| `Sources/ISFromPC/Views/Components/FileCards/FileCard.swift` | Route `entryType == "file"` + `contentType` starts with `text/` to `TextFileCard`. |
| `Sources/ISFromPC/Views/Components/FileCards/TextFileCard.swift` | Render the preview with monospaced font, placeholder for failure/oversized files, and Copy/Share footer. |
| `Tests/ISFromPCTests/TextPreviewContentResolverTests.swift` | Unit tests for the resolver. |
| `Package.swift` | Add the `ISFromPCTests` test target. |

---

### Task 1: Create `TextPreviewContentResolver` and add test target

**Files:**
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Services/TextPreviewContentResolver.swift`
- Create: `mobile/ios-packages/InstantShareKit/Tests/ISFromPCTests/TextPreviewContentResolverTests.swift`
- Modify: `mobile/ios-packages/InstantShareKit/Package.swift`

**Interfaces:**
- Consumes: `QRClaimResult` from `Sources/ISFromPC/Services/QRTriggerDownloadClient.swift`.
- Produces: `TextPreviewContentResolver.resolve(inlineContent:contentType:result:) -> String?`.

- [ ] **Step 1: Add the test target to `Package.swift`**

Add the following entry inside the `targets` array, after the existing targets:

```swift
.testTarget(
    name: "ISFromPCTests",
    dependencies: [
        .target(name: "ISFromPC"),
    ]
),
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/ISFromPCTests/TextPreviewContentResolverTests.swift`:

```swift
import XCTest
@testable import ISFromPC

final class TextPreviewContentResolverTests: XCTestCase {
    func testInlineTextReturnsContent() {
        let result = TextPreviewContentResolver.resolve(
            inlineContent: "Hello, world!",
            contentType: "text/plain",
            result: nil
        )
        XCTAssertEqual(result, "Hello, world!")
    }

    func testInlineTextTruncatedTo500Characters() {
        let longText = String(repeating: "a", count: 600)
        let result = TextPreviewContentResolver.resolve(
            inlineContent: longText,
            contentType: "text/plain",
            result: nil
        )
        XCTAssertEqual(result?.count, 500)
        XCTAssertTrue(result?.hasPrefix("aaa") == true)
    }

    func testTextFileReturnsContents() throws {
        let text = "File contents here"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "text/plain",
            result: .file(fileURL: url, contentType: "text/plain", filename: "test.txt")
        )
        XCTAssertEqual(result, text)
    }

    func testNonTextContentTypeReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).bin")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "application/octet-stream",
            result: .file(fileURL: url, contentType: "application/octet-stream", filename: "test.bin")
        )
        XCTAssertNil(result)
    }

    func testLargeFileReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        let largeText = String(repeating: "x", count: 1_048_577)
        try largeText.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "text/plain",
            result: .file(fileURL: url, contentType: "text/plain", filename: "large.txt")
        )
        XCTAssertNil(result)
    }

    func testEmptyInlineContentFallsBackToFile() throws {
        let text = "From file"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "text/plain",
            result: .file(fileURL: url, contentType: "text/plain", filename: "test.txt")
        )
        XCTAssertEqual(result, text)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift test --filter TextPreviewContentResolverTests
```

Expected: compilation fails because `TextPreviewContentResolver` does not exist yet. This confirms the tests are wired to the correct type and the test target is configured.

- [ ] **Step 4: Create `TextPreviewContentResolver.swift`**

```swift
import Foundation

struct TextPreviewContentResolver {
    static let maxPreviewCharacterCount = 500
    static let maxPreviewFileSize = 1_048_576 // 1 MB

    static func resolve(
        inlineContent: String?,
        contentType: String,
        result: QRClaimResult?
    ) -> String? {
        let source: String? = {
            if let inlineContent, !inlineContent.isEmpty {
                return inlineContent
            }
            guard let result else { return nil }
            switch result {
            case .file(let url, let fileContentType, _):
                guard fileContentType.lowercased().hasPrefix("text/") else { return nil }
                return readPreviewText(from: url)
            default:
                return nil
            }
        }()

        guard let source else { return nil }
        return String(source.prefix(maxPreviewCharacterCount))
    }

    private static func readPreviewText(from url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size <= maxPreviewFileSize else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift test --filter TextPreviewContentResolverTests
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add \
  mobile/ios-packages/InstantShareKit/Package.swift \
  mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Services/TextPreviewContentResolver.swift \
  mobile/ios-packages/InstantShareKit/Tests/ISFromPCTests/TextPreviewContentResolverTests.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Add TextPreviewContentResolver and unit tests"
```

---

### Task 2: Wire `TextPreviewContentResolver` into `FileDownloadState`

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/MultiFileReceiveViewModel.swift`

**Interfaces:**
- Consumes: `TextPreviewContentResolver.resolve(inlineContent:contentType:result:)`.
- Produces: `FileDownloadState.textPreviewContent: String?`.

- [ ] **Step 1: Add `textPreviewContent` to `FileDownloadState`**

Inside the `FileDownloadState` struct, add the following computed property after `downloadedTextContent`:

```swift
public var textPreviewContent: String? {
    TextPreviewContentResolver.resolve(
        inlineContent: inlineContent,
        contentType: contentType,
        result: result
    )
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/MultiFileReceiveViewModel.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Expose textPreviewContent on FileDownloadState"
```

---

### Task 3: Update `FileCard` routing for text files

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileCard.swift`

**Interfaces:**
- Consumes: `FileDownloadState.contentType`.
- Produces: `TextFileCard` rendered for text files.

- [ ] **Step 1: Modify the `"file"` branch**

Replace the existing `"file"` case in `FileCard.body` with:

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

- [ ] **Step 2: Build to verify no compilation errors**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/FileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Route text files to TextFileCard"
```

---

### Task 4: Update `TextFileCard` UI and previews

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/TextFileCard.swift`

**Interfaces:**
- Consumes: `FileDownloadState.textPreviewContent`, `FileDownloadState.status`.
- Produces: Updated view body and preview block.

- [ ] **Step 1: Replace the body with preview-aware rendering**

Update `TextFileCard.body` to:

```swift
var body: some View {
    FileCardContainer(isDownloading: state.status == .downloading) {
        ExpandedFileCardLayout(state: state) {
            if let preview = state.textPreviewContent {
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
                    withAnimation {
                        showCopiedToast = true
                    }
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
```

- [ ] **Step 2: Add the placeholder view**

Add the following private computed property to `TextFileCard`:

```swift
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

- [ ] **Step 3: Update the preview block**

Replace the existing `#Preview` with previews for inline text, downloaded text file, and failed state:

```swift
#Preview {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-sample.txt")
    try? "This text was read from a downloaded file.".write(to: fileURL, atomically: true, encoding: .utf8)

    return VStack(spacing: DesignSystem.Spacing.lg) {
        TextFileCard(
            state: MultiFileReceiveViewModel.FileDownloadState(
                index: 0,
                entryType: "text",
                filename: "notes.txt",
                contentType: "text/plain",
                sizeBytes: 1234,
                inlineContent: "This is inline text content that should appear in the preview area.",
                status: .downloaded,
                result: .text("This is inline text content that should appear in the preview area.")
            )
        ) {}

        TextFileCard(
            state: MultiFileReceiveViewModel.FileDownloadState(
                index: 1,
                entryType: "file",
                filename: "data.json",
                contentType: "text/plain",
                sizeBytes: 5678,
                inlineContent: nil,
                status: .downloaded,
                result: .file(fileURL: fileURL, contentType: "text/plain", filename: "data.json")
            )
        ) {}

        TextFileCard(
            state: MultiFileReceiveViewModel.FileDownloadState(
                index: 2,
                entryType: "file",
                filename: "missing.txt",
                contentType: "text/plain",
                sizeBytes: 100,
                inlineContent: nil,
                status: .failed,
                result: nil,
                errorMessage: "Download failed"
            )
        ) {}
    }
    .padding()
    .background(Color.white)
}
```

- [ ] **Step 4: Build to verify no compilation errors**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/TextFileCard.swift
git commit -m "[LLM: opencode-go/kimi-k2.7-code] Render text previews with monospaced font and placeholder states"
```

---

### Task 5: Verify end-to-end build and tests

**Files:**
- N/A (verification task)

- [ ] **Step 1: Run the full test suite**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift test
```

Expected: all `TextPreviewContentResolverTests` pass. The test target compiles and runs on macOS because `TextPreviewContentResolver` and `QRClaimResult` are not iOS-guarded.

- [ ] **Step 2: Build the iOS package**

Run:

```bash
cd mobile/ios-packages/InstantShareKit
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Optional — build the iOS app to catch UI-only issues**

Run:

```bash
cd mobile/ios
xcodebuild build -project AlbumTransporterApp.xcodeproj -scheme AlbumTransporterApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

Expected: build succeeds.

- [ ] **Step 4: Commit if any fixes were needed**

If no fixes were needed, no additional commit is necessary.

---

## Spec Coverage Checklist

| Spec Requirement | Implementing Task |
|------------------|-------------------|
| Text files (`contentType` starts with `text/`) render a preview | Task 1 (resolver), Task 3 (routing) |
| Inline text continues to work | Task 1 (resolver), Task 4 (UI uses `textPreviewContent`) |
| 5-line limit | Task 4 (`.lineLimit(5)`) |
| 500-character limit | Task 1 (`prefix(maxPreviewCharacterCount)`) |
| 1 MB file-size cap | Task 1 (`maxPreviewFileSize`) |
| Monospaced font | Task 4 (`DesignSystem.Typography.monoBody`) |
| Spinner while downloading | Already handled by `FileCardContainer` (no change) |
| Failed state placeholder | Task 4 (`placeholder` view) |
| Copy and Share footer | Task 4 (retained from existing footer) |

## Placeholder Scan

No placeholders. Every step contains concrete code, file paths, and commands.
