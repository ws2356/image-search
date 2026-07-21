# Device Management Feature — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a device management screen as the initial screen of the Instant Share iOS app, listing trusted peer certificates with swipe-to-delete, and a QR button in the app's RootView to launch the PC-to-mobile receive flow.

**Architecture:** New `ISDeviceManagement` target in `InstantShareKit` (depends on `Common` only). App's `RootView` wraps `DeviceManagementView` and owns the QR toolbar button + full-screen cover. `ISFromPC` gets a configurable initial state for `.scan` entry.

**Tech Stack:** Swift 6, SwiftPM, iOS 15+, ComposableArchitecture, Factory

## Global Constraints

- iOS deployment target 15.6
- All SPM targets are `.dynamic` libraries
- Follow existing patterns in `ISFromMobile` (TCA Reducer, `@DependencyClient`, `DependencyKey.liveValue`)
- `DeviceManagementClient` accesses `AppIdentityProviding` via `Container.shared.appIdentityProvider()`
- Use `DesignSystem` tokens for UI consistency
- No new UI frameworks — SwiftUI only

---

### Task 1: Add `loadAllPeerCertificates` to Protocol + Expose OID

**Files:**
- Modify: `mobile/ios-packages/Common/Sources/Common/Services/KeychainAppIdentityProvider.swift`

**Interfaces:**
- Produces: `AppIdentityProviding.loadAllPeerCertificates()` requirement, `KeychainAppIdentityProvider.deviceIdOID` made `public`

- [ ] **Add `loadAllPeerCertificates` to `AppIdentityProviding` protocol**

Insert into the protocol block after `deletePeerCertificate(forPubkeyHash:)`:

```swift
func loadAllPeerCertificates() async throws -> [SecCertificate]
```

- [ ] **Make `deviceIdOID` public**

Change line:
```swift
static let deviceIdOID = ASN1ObjectIdentifier("2.25.37020860436019520")
```
to:
```swift
public static let deviceIdOID = ASN1ObjectIdentifier("2.25.37020860436019520")
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/Common/Sources/Common/Services/KeychainAppIdentityProvider.swift
git commit -m "feat: add loadAllPeerCertificates to AppIdentityProviding protocol, expose deviceIdOID"
```

---

### Task 2: Make ISFromPC Initial State Configurable

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/ISQRRootViewModel.swift`
- Modify: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/ISQRRootView.swift`

**Interfaces:**
- Consumes: `QRClaimPayload`, `Navigator` (unchanged)
- Produces: `ISQRRootViewModel.init(initialState:qrClaimPayload:navigator:)`, `ISQRRootView.init(navigator:)`

- [ ] **Update `ISQRRootViewModel` initializer and `qrClaimPayload`**

Replace the current `init` and `state` default:

```swift
@Published public private(set) var state: State
let navigator: Navigator
private(set) var qrClaimPayload: QRClaimPayload?

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

Remove the old `var qrClaimPayload: QRClaimPayload` (no didSet observer needed — the cleanup logic in `onDisappear` already handles this) and the `init` that took a non-optional payload.

- [ ] **Update `handleScannedQRCode` to store parsed payload**

```swift
private func handleScannedQRCode(_ scannedValue: String) async {
    guard let url = URL(string: scannedValue),
          let payload = QRClaimPayload(universalLinkURL: url) else {
        state = .error(title: "Invalid QR Code", message: "Could not parse the scanned QR code.")
        return
    }
    self.qrClaimPayload = payload
    state = .claiming
}
```

- [ ] **Add scanning-first initializer to `ISQRRootView`**

Keep the existing init and add:

```swift
public init(navigator: Navigator) {
    _viewModel = StateObject(wrappedValue: ISQRRootViewModel(
        initialState: .scan,
        navigator: navigator
    ))
    self.navigator = navigator
}
```

Update the existing init to use the new ViewModel init:
```swift
public init(qrPayload: QRClaimPayload, navigator: Navigator) {
    _viewModel = StateObject(wrappedValue: ISQRRootViewModel(
        initialState: .claiming,
        qrClaimPayload: qrPayload,
        navigator: navigator
    ))
    self.navigator = navigator
}
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISFromPC/
git commit -m "feat: make ISQRRootViewModel initial state configurable, add scanning-first init"
```

---

### Task 3: Add ISDeviceManagement Target to Package.swift

**Files:**
- Modify: `mobile/ios-packages/InstantShareKit/Package.swift`

**Interfaces:**
- Produces: `ISDeviceManagement` product (`.dynamic`), `ISDeviceManagement` target

- [ ] **Add `ISDeviceManagement` product and target**

Insert the product after `ISFromMobile`:
```swift
.library(
    name: "ISDeviceManagement",
    type: .dynamic,
    targets: ["ISDeviceManagement"]
),
```

Insert the target after the `ISFromMobile` target:
```swift
.target(
    name: "ISDeviceManagement",
    dependencies: [
        .product(name: "Factory", package: "Factory"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Common", package: "Common"),
    ],
    resources: []
),
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Package.swift
git commit -m "feat: add ISDeviceManagement target to InstantShareKit"
```

---

### Task 4: Create TrustedDevice Model

**Files:**
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/TrustedDevice.swift`

**Interfaces:**
- Produces: `TrustedDevice` struct — public, `Identifiable`, `Equatable`

- [ ] **Create the model file**

```swift
import Foundation

public struct TrustedDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let pubkeyHash: Data

    public init(id: String, name: String, pubkeyHash: Data) {
        self.id = id
        self.name = name
        self.pubkeyHash = pubkeyHash
    }
}
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/TrustedDevice.swift
git commit -m "feat: add TrustedDevice model"
```

---

### Task 5: Create DeviceManagementClient

**Files:**
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/DeviceManagementClient.swift`

**Interfaces:**
- Consumes: `TrustedDevice`, `AppIdentityProviding`, `KeychainAppIdentityProvider.deviceIdOID`
- Produces: `DeviceManagementClient` with `@Dependency(\.deviceManagement)` key

- [ ] **Create the TCA DependencyClient**

```swift
import ComposableArchitecture
import Common
import Factory
import Foundation

@DependencyClient
struct DeviceManagementClient {
    var loadDevices: @Sendable () async throws -> [TrustedDevice] = { [] }
    var deleteDevice: @Sendable (_ pubkeyHash: Data) async throws -> Void
}

extension DeviceManagementClient: DependencyKey {
    static let liveValue = DeviceManagementClient(
        loadDevices: {
            let provider = Container.shared.appIdentityProvider()
            let certs = try await provider.loadAllPeerCertificates()
            return certs.compactMap { cert in
                guard let name = cert.commonName,
                      let id = cert.deviceUUIDFromExtension(KeychainAppIdentityProvider.deviceIdOID),
                      let hash = cert.publicKeyHash
                else { return nil }
                return TrustedDevice(id: id, name: name, pubkeyHash: hash)
            }
        },
        deleteDevice: { hash in
            let provider = Container.shared.appIdentityProvider()
            try await provider.deletePeerCertificate(forPubkeyHash: hash)
        }
    )
}

extension DependencyValues {
    var deviceManagement: DeviceManagementClient {
        get { self[DeviceManagementClient.self] }
        set { self[DeviceManagementClient.self] = newValue }
    }
}
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/DeviceManagementClient.swift
git commit -m "feat: add DeviceManagementClient TCA dependency"
```

---

### Task 6: Create DeviceManagementFeature

**Files:**
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/DeviceManagementFeature.swift`

**Interfaces:**
- Consumes: `TrustedDevice`, `@Dependency(\.deviceManagement)`
- Produces: `DeviceManagementFeature` Reducer, `DeviceManagementFeature.State`, `DeviceManagementFeature.Action`

- [ ] **Create the TCA Reducer**

```swift
import ComposableArchitecture
import Foundation

@Reducer
public struct DeviceManagementFeature {
    public init() {}

    @ObservableState
    public struct State: Equatable {
        public var trustedDevices: [TrustedDevice] = []
        public var isLoading: Bool = false
        public var errorMessage: String? = nil

        public init(
            trustedDevices: [TrustedDevice] = [],
            isLoading: Bool = false,
            errorMessage: String? = nil
        ) {
            self.trustedDevices = trustedDevices
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }
    }

    @CasePathable
    public enum Action {
        case onAppear
        case deleteDevice(TrustedDevice)
        case devicesLoaded([TrustedDevice])
        case deviceDeleted(TrustedDevice)
        case failed(String)
    }

    @Dependency(\.deviceManagement) var deviceManagement

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    let devices = try await deviceManagement.loadDevices()
                    await send(.devicesLoaded(devices))
                } catch: { error, send in
                    await send(.failed(error.localizedDescription))
                }

            case .devicesLoaded(let devices):
                state.isLoading = false
                state.trustedDevices = devices
                return .none

            case .deleteDevice(let device):
                state.trustedDevices.removeAll { $0.id == device.id }
                return .run { send in
                    try await deviceManagement.deleteDevice(device.pubkeyHash)
                    await send(.deviceDeleted(device))
                } catch: { error, send in
                    await send(.failed(error.localizedDescription))
                }

            case .deviceDeleted:
                return .none

            case .failed(let message):
                state.isLoading = false
                state.errorMessage = message
                return .none
            }
        }
    }
}
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/DeviceManagementFeature.swift
git commit -m "feat: add DeviceManagementFeature TCA reducer"
```

---

### Task 7: Create DeviceManagementView

**Files:**
- Create: `mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/DeviceManagementView.swift`

**Interfaces:**
- Consumes: `DeviceManagementFeature`, `DesignSystem` tokens (from Common)
- Produces: Public `DeviceManagementView` SwiftUI view

- [ ] **Create the SwiftUI view**

```swift
import SwiftUI
import ComposableArchitecture

#if os(iOS)
public struct DeviceManagementView: View {
    let store: StoreOf<DeviceManagementFeature>

    public init(store: StoreOf<DeviceManagementFeature>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            List {
                if store.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if store.trustedDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Trusted Devices")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.trustedDevices) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.body)
                            Text(device.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let device = store.trustedDevices[index]
                            store.send(.deleteDevice(device))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Devices")
            .task { store.send(.onAppear) }
            .overlay(alignment: .bottom) {
                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                }
            }
        }
    }
}
#endif
```

- [ ] **Commit**

```bash
git add mobile/ios-packages/InstantShareKit/Sources/ISDeviceManagement/DeviceManagementView.swift
git commit -m "feat: add DeviceManagementView"
```

---

### Task 8: Create RootView in App Target

**Files:**
- Create: `mobile/instant-share/App/RootView.swift`

**Interfaces:**
- Consumes: `DeviceManagementFeature`, `DeviceManagementView`, `ISQRRootView`, `ISQRRootViewModel`
- Produces: `RootView` SwiftUI view with QR toolbar button and full-screen cover

- [ ] **Create RootView.swift**

```swift
import SwiftUI
import Common
import ISDeviceManagement
import ISFromPC

struct QRSheetNavigator: Navigator {
    let dismiss: () -> Void
    func requestExit() {
        dismiss()
    }
}

struct RootView: View {
    @State private var showQRSheet = false
    @State private var qrSheetInitialState: ISQRRootViewModel.State = .scan
    @State private var pendingQRPayload: QRClaimPayload? = nil

    var body: some View {
        NavigationStack {
            DeviceManagementView(
                store: Store(initialState: DeviceManagementFeature.State()) {
                    DeviceManagementFeature()
                }
            )
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

- [ ] **Commit**

```bash
git add mobile/instant-share/App/RootView.swift
git commit -m "feat: add RootView with QR button and full-screen cover"
```

---

### Task 9: Update InstantShareApp Entry Point

**Files:**
- Modify: `mobile/instant-share/App/InstantShareApp.swift`

- [ ] **Replace FlowView with RootView**

```swift
import Common
import ISFromPC
import SwiftUI

@main
struct InstantShareApp: App {
    init() {
        FontRegistration.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
                    .ignoresSafeArea()
            } else {
                RootView()
            }
        }
        .onOpenURL { url in
            if let payload = QRClaimPayload(universalLinkURL: url) {
                // Handled by posting a notification; RootView observes it.
                // For now, universal link handling is deferred — the app
                // always opens to the device list with QR button.
            }
        }
    }
}
```

- [ ] **Commit**

```bash
git add mobile/instant-share/App/InstantShareApp.swift
git commit -m "feat: update app entry point to use RootView"
```

---

### Task 10: Update Xcode Project

**Files:**
- Modify: `mobile/instant-share/InstantShare.xcodeproj/project.pbxproj`

- [ ] **Add `ISDeviceManagement` product dependency**

In the `XCSwiftPackageProductDependency` section (near the existing ones for `Common`, `ISFromMobile`, `ISFromPC`), add a new entry with a unique UUID:

```
/* Begin XCSwiftPackageProductDependency section */
...
ISNEW000000000000000004 /* ISDeviceManagement */ = {
    isa = XCSwiftPackageProductDependency;
    productName = "ISDeviceManagement";
};
/* End XCSwiftPackageProductDependency section */
```

In the `PBXNativeTarget` section for the main `InstantShare` app target, add `ISNEW000000000000000004` to `packageProductDependencies`.

- [ ] **Commit**

```bash
git add mobile/instant-share/InstantShare.xcodeproj/project.pbxproj
git commit -m "feat: add ISDeviceManagement product dependency to Xcode project"
```

---

### Task 11: Verify Build

- [ ] **Build the project**

```bash
cd mobile/instant-share/ && xcodebuild -scheme InstantShare build
```

Expected result: **BUILD SUCCEEDED**

- [ ] **Commit any fixups**

```bash
git add -A && git commit -m "fix: build fixes after device management integration"
```
