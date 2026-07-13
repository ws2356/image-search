# SnapGet User Instruction Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a first-time user instruction screen in the SnapGet iOS app that explains PC↔mobile sharing and PC setup, permanently replaced by DeviceManagementView after the user completes their first session.

**Architecture:** A `SharedStorageProvider` extension tracks session completion in an app group UserDefaults. A TCA dependency client (`SharedStorageClient`) wraps it for use in reducers. `RootFeature` reads the flag and conditionally shows `UserInstructionView` or `DeviceManagementView`. Both PC→mobile (ISQRRootViewModel) and mobile→PC (CompletionFeature) flows set the flag on success.

**Tech Stack:** SwiftUI, TCA (Composable Architecture), Factory (DI), UserDefaults app group

## Global Constraints

- App group identifier: `group.net.boldman.snapget`
- UserDefaults key: `hasCompletedSession`
- Use `@Injected(\.sharedStorageProvider)` for non-TCA code (Factory pattern)
- Use `@Dependency(\.sharedStorage)` for TCA reducers
- `Container.shared` only appears inside dependency `liveValue` implementations
- Download URL: `https://www.boldman.net/snapget.html#download`

---

### Task 1: Add SnapGet app group to SharedStorageProvider

**Files:**
- Modify: `mobile/ios-packages/Common/Sources/Common/Services/SharedStorageProvider.swift`

**Interfaces:**
- Produces: `SharedStorageProtocol.snapgetAppGroupUserDefaults: UserDefaults`, `SharedStorageProtocol.hasCompletedSession: Bool { get set }`

- [ ] **Step 1: Read current SharedStorageProvider**

Read `mobile/ios-packages/Common/Sources/Common/Services/SharedStorageProvider.swift` to understand the existing structure.

- [ ] **Step 2: Add snapget app group properties**

Add `snapgetAppGroupUserDefaults` and `hasCompletedSession` to the protocol and class:

```swift
// mobile/ios-packages/Common/Sources/Common/Services/SharedStorageProvider.swift

import Foundation

public protocol SharedStorageProtocol {
    var commonAppGroupUserDefaults: UserDefaults { get }
    var snapgetAppGroupUserDefaults: UserDefaults { get }
    var hasCompletedSession: Bool { get set }
}

let appGroupIdentifier = "group.net.boldman.common"
let snapgetAppGroupIdentifier = "group.net.boldman.snapget"

public class SharedStorageProvider: SharedStorageProtocol {
    public let commonAppGroupUserDefaults: UserDefaults = .init(suiteName: appGroupIdentifier)!
    public let snapgetAppGroupUserDefaults: UserDefaults = .init(suiteName: snapgetAppGroupIdentifier)!

    public var hasCompletedSession: Bool {
        get { snapgetAppGroupUserDefaults.bool(forKey: "hasCompletedSession") }
        set { snapgetAppGroupUserDefaults.set(newValue, forKey: "hasCompletedSession") }
    }

    public init() {}
}
```

- [ ] **Step 3: Build Common package to verify**

Run: `cd mobile/ios-packages/Common && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add mobile/ios-packages/Common/Sources/Common/Services/SharedStorageProvider.swift
git commit -m "feat: add SnapGet app group hasCompletedSession to SharedStorageProvider [LLM: opencode/mimo-v2.5-pro]"
```

---

### Task 2: Add TCA dependency client for SharedStorageProvider

**Files:**
- Modify: `mobile/ios-packages/Common/Package.swift` (add ComposableArchitecture dependency)
- Create: `mobile/ios-packages/Common/Sources/Common/DI/SharedStorageClient.swift`

**Interfaces:**
- Produces: `DependencyValues.sharedStorage: SharedStorageClient`, `SharedStorageClient.hasCompletedSession() -> Bool`, `SharedStorageClient.setHasCompletedSession(Bool) -> Void`

- [ ] **Step 1: Add ComposableArchitecture to Common's Package.swift**

Edit `mobile/ios-packages/Common/Package.swift` to add TCA dependency:

```swift
// Add to dependencies array:
.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.17.0"),

// Add to Common target dependencies:
.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
```

- [ ] **Step 2: Resolve dependencies**

Run: `cd mobile/ios-packages/Common && swift package resolve`
Expected: Resolves successfully

- [ ] **Step 3: Create SharedStorageClient**

Create `mobile/ios-packages/Common/Sources/Common/DI/SharedStorageClient.swift`:

```swift
//
//  SharedStorageClient.swift
//  Common
//
//  TCA dependency client wrapping SharedStorageProvider for SnapGet session state.
//

import ComposableArchitecture
import Foundation
import Factory

@DependencyClient
public struct SharedStorageClient: Sendable {
    public var hasCompletedSession: @Sendable () -> Bool = { false }
    public var setHasCompletedSession: @Sendable (Bool) -> Void
}

extension SharedStorageClient: DependencyKey {
    public static let liveValue = SharedStorageClient(
        hasCompletedSession: {
            Container.shared.sharedStorageProvider().hasCompletedSession
        },
        setHasCompletedSession: { newValue in
            Container.shared.sharedStorageProvider().hasCompletedSession = newValue
        }
    )
}

extension DependencyValues {
    public var sharedStorage: SharedStorageClient {
        get { self[SharedStorageClient.self] }
        set { self[SharedStorageClient.self] = newValue }
    }
}
```

- [ ] **Step 4: Build Common package to verify**

Run: `cd mobile/ios-packages/Common && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add mobile/ios-packages/Common/Package.swift mobile/ios-packages/Common/Sources/Common/DI/SharedStorageClient.swift
git commit -m "feat: add SharedStorageClient TCA dependency in Common [LLM: opencode/mimo-v2.5-pro]"
```

---

### Task 3: Create UserInstructionView

**Files:**
- Create: `mobile/instant-share/App/UserInstructionView.swift`

**Interfaces:**
- Produces: `UserInstructionView: View` (static view, no dependencies)

- [ ] **Step 1: Create UserInstructionView**

Create `mobile/instant-share/App/UserInstructionView.swift`:

```swift
//
//  UserInstructionView.swift
//  SnapGet
//
//  First-time user instruction screen explaining PC↔mobile sharing setup.
//

import SwiftUI

#if os(iOS)
struct UserInstructionView: View {
    @State private var showCopiedToast = false

    private let downloadURL = "https://www.boldman.net/snapget.html#download"

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                usageCardsSection
                pcSetupSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        .linearGradient(
                            colors: [Color(hex: 0x0A84FF), Color(hex: 0x0040CC)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color(hex: 0x007AFF).opacity(0.45), radius: 12, y: 6)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("SnapGet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text("Instantly share files, images, text and links between your phone and PC")
                .font(.subheadline)
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Usage Cards

    private var usageCardsSection: some View {
        VStack(spacing: 12) {
            UsageCard(
                iconName: "desktopcomputer",
                iconColor: Color(hex: 0x007AFF),
                iconBackground: Color(hex: 0xE8F4FD),
                title: "Share from your PC",
                description: "Right-click any file, image, text or link on your PC and send it to this device. Requires the SnapGet desktop app."
            )

            UsageCard(
                iconName: "iphone",
                iconColor: Color(hex: 0x34C759),
                iconBackground: Color(hex: 0xE8FDE8),
                title: "Share from this device",
                description: "Select files, photos, or text on your phone and send them to your PC. Requires the SnapGet desktop app."
            )
        }
    }

    // MARK: - PC Setup Section

    private var pcSetupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PC Setup")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                SetupStepRow(
                    number: 1,
                    title: "Download SnapGet for PC",
                    detail: downloadURL,
                    isLink: true,
                    onTap: copyDownloadURL
                )
                .overlay(alignment: .bottom) {
                    Divider().padding(.leading, 56)
                }

                SetupStepRow(
                    number: 2,
                    title: "Install and launch SnapGet on your PC",
                    detail: "Run the installer and open the app.",
                    isLink: false
                )
                .overlay(alignment: .bottom) {
                    Divider().padding(.leading, 56)
                }

                SetupStepRow(
                    number: 3,
                    title: "Enable the share extension",
                    detail: "In SnapGet settings, enable the share extension to allow sharing from your PC.",
                    isLink: false
                )
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                toastView
                    .padding(.bottom, -40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var toastView: some View {
        Text("Link copied to clipboard")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0x1C1C1E))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func copyDownloadURL() {
        UIPasteboard.general.string = downloadURL
        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Subviews

private struct UsageCard: View {
    let iconName: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x6E6E73))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct SetupStepRow: View {
    let number: Int
    let title: String
    let detail: String
    let isLink: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x007AFF))
                        .frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    if isLink {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x007AFF))
                    } else {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .disabled(!isLink)
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
#endif
```

- [ ] **Step 2: Verify the file compiles**

Check that the SnapGet main target includes this file in its build sources (it should be in the `App/` directory which is part of the main target).

- [ ] **Step 3: Commit**

```bash
git add mobile/instant-share/App/UserInstructionView.swift
git commit -m "feat: add UserInstructionView for first-time setup [LLM: opencode/mimo-v2.5-pro]"
```

---

### Task 4: Update RootFeature and RootView to show instruction screen conditionally

**Files:**
- Modify: `mobile/instant-share/App/RootView.swift`

**Interfaces:**
- Consumes: `DependencyValues.sharedStorage: SharedStorageClient` (from Task 2)
- Consumes: `UserInstructionView` (from Task 3)
- Consumes: `DeviceManagementView` (existing)

- [ ] **Step 1: Read current RootView.swift**

Read `mobile/instant-share/App/RootView.swift` to understand the current structure.

- [ ] **Step 2: Update RootFeature.State with hasCompletedSession**

Add `hasCompletedSession: Bool = false` to `RootFeature.State`.

- [ ] **Step 3: Update RootFeature.Action with onAppear**

Add `case onAppear` to `RootFeature.Action`.

- [ ] **Step 4: Add @Dependency and update reducer body**

Add `@Dependency(\.sharedStorage) var sharedStorage` to `RootFeature`. Update the `Reduce` to handle `.onAppear` and update `.sheetContent(.dismiss)` to re-read the flag.

- [ ] **Step 5: Update RootView body for conditional rendering**

Replace the unconditional `DeviceManagementView` with:
```swift
if store.hasCompletedSession {
    DeviceManagementView(...)
} else {
    UserInstructionView()
}
```

Add `.task { store.send(.onAppear) }` to the view.

- [ ] **Step 6: Build to verify**

Run: `cd mobile/instant-share && xcodebuild build -project InstantShare.xcodeproj -scheme InstantShare -destination "platform=iOS Simulator,name=iPhone 16" -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add mobile/instant-share/App/RootView.swift
git commit -m "feat: conditionally show UserInstructionView in RootView [LLM: opencode/mimo-v2.5-pro]"
```

---

### Task 5: Set hasCompletedSession flag on PC→mobile transfer success

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/ISQRRootViewModel.swift`

**Interfaces:**
- Consumes: `SharedStorageProtocol` via `@Injected(\.sharedStorageProvider)` (Factory pattern)
- Produces: Sets `hasCompletedSession = true` on successful claim

- [ ] **Step 1: Read current ISQRRootViewModel.swift**

Read `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/ISQRRootViewModel.swift`.

- [ ] **Step 2: Add @Injected property**

Add to the class properties:
```swift
@Injected(\.sharedStorageProvider) private(set) var sharedStorageProvider: SharedStorageProtocol
```

- [ ] **Step 3: Set flag in onClaimCompletion**

In `onClaimCompletion`, after `state = .result(claimResult)`, add:
```swift
sharedStorageProvider.hasCompletedSession = true
```

- [ ] **Step 4: Build ISFromPC to verify**

Run: `cd mobile/ios-packages/InstantShareKit && swift build --target ISFromPC`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/ISQRRootViewModel.swift
git commit -m "feat: set hasCompletedSession on PC-to-mobile transfer success [LLM: opencode/mimo-v2.5-pro]"
```

---

### Task 6: Set hasCompletedSession flag on mobile→PC transfer success

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromMobile/Features/CompletionFeature.swift`

**Interfaces:**
- Consumes: `DependencyValues.sharedStorage: SharedStorageClient` (from Task 2)
- Produces: Sets `hasCompletedSession = true` on `.done` action

- [ ] **Step 1: Add @Dependency to CompletionFeature**

Add to the `CompletionFeature` struct:
```swift
@Dependency(\.sharedStorage) var sharedStorage
```

- [ ] **Step 2: Set flag in .done handler**

In the `.done` case, before `return .send(.delegate(.done))`, add:
```swift
sharedStorage.setHasCompletedSession(true)
```

- [ ] **Step 3: Build ISFromMobile to verify**

Run: `cd mobile/ios-packages/InstantShareKit && swift build --target ISFromMobile`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromMobile/Features/CompletionFeature.swift
git commit -m "feat: set hasCompletedSession on mobile-to-PC transfer success [LLM: opencode/mimo-v2.5-pro]"
```

---

### Task 7: Final verification and snapshot tests

**Files:**
- Modify: `mobile/instant-share/InstantShareSnapshotTests/InstantShareSnapshotTests.swift` (add snapshot test for instruction screen)

- [ ] **Step 1: Build full project**

Run: `cd mobile/instant-share && xcodebuild build -project InstantShare.xcodeproj -scheme InstantShare -destination "platform=iOS Simulator,name=iPhone 16" -quiet`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run existing tests**

Run: `cd mobile/instant-share && xcodebuild test -project InstantShare.xcodeproj -scheme InstantShare -destination "platform=iOS Simulator,name=iPhone 16" -only-testing:InstantShareTests`
Expected: All tests pass

- [ ] **Step 3: Commit any fixes if needed**

- [ ] **Step 4: Run snapshot tests in record mode to capture new baseline**

Run: `cd mobile/ios && scripts/run_snapshot_tests.sh --mode record`
Expected: New snapshot captured for instruction screen

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test: add snapshot test for UserInstructionScreen [LLM: opencode/mimo-v2.5-pro]"
```
