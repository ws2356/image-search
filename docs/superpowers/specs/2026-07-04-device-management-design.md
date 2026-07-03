# Device Management Feature — Instant Share iOS App

**Date:** 2026-07-04
**Status:** Design (approved, pending implementation)

## Goal

Add a device management screen as the initial screen of the Instant Share iOS app. It shows a list of devices with which the app has exchanged peer certificates (stored in the keychain), allows deleting entries, and provides a toolbar button to launch the PC-to-mobile QR receive flow in a separate navigation stack.

## Architecture

### Dependency Graph

No cross-target dependencies between feature packages. Each depends only on `Common`.

```
Main App ─┬─ ISDeviceManagement ── Common
           ├─ ISFromPC ──────────── Common    (QR receive, presented as full-screen cover)
           └─ ISFromMobile ──────── Common    (only used by Share Extension target)

ShareExtension ─ ISFromMobile ── Common
```

### Navigation Model

```
InstantShareApp.swift
  └── RootView (new, in the app target)
        ├── [default] DeviceManagementView (ISDeviceManagement, no toolbar)
        │     └── List of TrustedDevice rows (name, deviceID)
        ├── Toolbar: QR scan button (owned by RootView, outside ISDeviceManagement)
        └── [fullScreenCover] ISQRRootView (ISFromPC, separate nav stack)
              └── NavigationStack
                    ├── [.scan] ISQRScanPageView → scans QR
                    ├── [.claiming] QRClaimView → claims session
                    └── [.result] MultiFileReceiveView → receives files
```

The QR flow is presented as a `.fullScreenCover` from `RootView`. The cover owns a separate `NavigationStack` (from `ISQRRootView`). On completion, the `Navigator.requestExit()` callback dismisses the cover.

When a universal link is received, the same `ISQRRootView` is presented with initial state `.claiming` (skipping the scan step).

## New Target: `ISDeviceManagement`

Added to `InstantShareKit/Package.swift`:

```
InstantShareKit/Sources/ISDeviceManagement/
  ├── DeviceManagementFeature.swift   # TCA Reducer
  ├── DeviceManagementView.swift      # SwiftUI view
  └── TrustedDevice.swift             # Model
```

- **Target type:** `.dynamic` library
- **Dependencies:** `Common` (for `AppIdentityProviding`, `SecCertificate` extensions, design system)
- **Product name:** `ISDeviceManagement`

### TrustedDevice Model

```swift
struct TrustedDevice: Identifiable, Equatable {
    let id: String          // deviceUUID from certificate extension
    let name: String        // commonName from SecCertificate
    let pubkeyHash: Data    // for deletion via deletePeerCertificate(forPubkeyHash:)
}
```

### DeviceManagementFeature (TCA Reducer)

**State:**
```swift
struct State: Equatable {
    var trustedDevices: [TrustedDevice] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
}
```

**Actions:**
- `onAppear` — loads all peer certificates from keychain
- `deleteDevice(TrustedDevice)` — deletes peer cert by pubkeyHash, updates list
- `delegate(Delegate)` — notifies parent

**Dependencies:**
- `@Injected(\.appIdentityProvider)` from Factory — provides `loadAllPeerCertificates()` and `deletePeerCertificate(forPubkeyHash:)`

Since `ISDeviceManagement` does not depend on `ISFromMobile`, it cannot use the TCA `IdentityClient`. Instead it uses Factory's `@Injected(\.appIdentityProvider)` directly — the same pattern already used by `QRClaimViewModel` in `ISFromPC`. This is injected as a property in the ViewModel / feature code rather than via TCA's `@Dependency`.

### DeviceManagementView

- List of `TrustedDevice` rows
- Each row shows device name and device ID
- Swipe-to-delete action
- No toolbar — the enclosing `RootView` owns all toolbar items including the QR button
- Empty state when no devices paired
- Uses `DesignSystem` tokens from Common (colors, spacing, typography)

### Data Flow

**Loading:**
```
DeviceManagementFeature.onAppear
  → appIdentityProvider.loadAllPeerCertificates()
  → map [SecCertificate] → [TrustedDevice] (extract commonName, deviceUUID, pubkeyHash)
  → set state.trustedDevices
```

**Deletion:**
```
User swipes to delete
  → store.send(.deleteDevice(device))
  → appIdentityProvider.deletePeerCertificate(forPubkeyHash: device.pubkeyHash)
  → remove from state.trustedDevices
```

## Changes to Existing Code

### InstantShareKit/Package.swift

Add `ISDeviceManagement` target:
```swift
.target(
    name: "ISDeviceManagement",
    dependencies: [
        .product(name: "Factory", package: "Factory"),
        .product(name: "Common", package: "Common"),
    ],
    resources: []
)
```

Add `ISDeviceManagement` product:
```swift
.library(
    name: "ISDeviceManagement",
    type: .dynamic,
    targets: ["ISDeviceManagement"]
)
```

The target does NOT depend on `ISFromPC` or `ISFromMobile`.

### ISFromPC — Configurable Initial State

**ISQRRootViewModel** currently hardcodes `state: State = .claiming`. Change to accept initial state:

```swift
public init(
    initialState: State = .claiming,
    qrClaimPayload: QRClaimPayload? = nil,
    navigator: Navigator
) {
    self.state = initialState
    self.qrClaimPayload = qrClaimPayload
    self.navigator = navigator
}
```

When `initialState == .scan` and `qrClaimPayload == nil`, the scanning flow creates the payload from the scanned URL via `QRClaimPayload(universalLinkURL:)`.

**ISQRRootView** receives new initializer:

```swift
public init(navigator: Navigator)  // scanning-first entry (used by device list)
// existing init remains for universal link entry:
public init(qrPayload: QRClaimPayload, navigator: Navigator)
```

### InstantShareApp.swift (App Target)

Replace `FlowView` with a new `RootView`:

```swift
@main
struct InstantShareApp: App {
    @State private var showQRSheet = false
    @State private var qrSheetInitialState: ISQRRootViewModel.State = .scan
    @State private var pendingQRPayload: QRClaimPayload? = nil

    var body: some Scene {
        WindowGroup {
            RootView(
                showQRSheet: $showQRSheet,
                qrSheetInitialState: $qrSheetInitialState,
                pendingQRPayload: $pendingQRPayload
            )
        }
        .onOpenURL { url in
            if let payload = QRClaimPayload(universalLinkURL: url) {
                pendingQRPayload = payload
                qrSheetInitialState = .claiming
                showQRSheet = true
            }
        }
    }
}
```

**RootView** (new file in the app target, not in any package) — wraps `DeviceManagementView`, owns the QR toolbar button and the full-screen cover:

```swift
struct RootView: View {
    @Binding var showQRSheet: Bool
    @Binding var qrSheetInitialState: ISQRRootViewModel.State
    @Binding var pendingQRPayload: QRClaimPayload?

    var body: some View {
        NavigationStack {
            DeviceManagementView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showQRSheet = true }) {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                }
                .fullScreenCover(isPresented: $showQRSheet) {
                    if qrSheetInitialState == .scan {
                        ISQRRootView(navigator: QRSheetNavigator(dismiss: { showQRSheet = false }))
                    } else if let payload = pendingQRPayload {
                        ISQRRootView(qrPayload: payload, navigator: QRSheetNavigator(dismiss: { showQRSheet = false }))
                    }
                }
        }
    }
}
```

### InstantShare.xcodeproj/project.pbxproj

Add `ISDeviceManagement` as a package product dependency for the main app target.

## Non-Goals

- No changes to `FlowFeature` or `FlowView` (share extension domain)
- No changes to `ISFromMobile`
- No new QR scanner — reuses `ISQRScanPageView` from `ISFromPC`
- No cross-target TCA coupling — the QR sheet is driven by `@State` binding, not a reducer
- No renaming of existing devices (View + Delete only)

## Future Considerations

- Universal link handling for `.claiming` entry point
- Device renaming (stored locally in UserDefaults keyed by pubkeyHash)
- Empty state design for first-launch experience
