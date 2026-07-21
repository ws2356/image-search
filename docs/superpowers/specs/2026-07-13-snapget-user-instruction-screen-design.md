# SnapGet User Instruction Screen

## Goal

Show a first-time user instruction screen in the SnapGet iOS app instead of the DeviceManagementView. The screen explains two ways to use the app (PC→mobile and mobile→PC) and guides users to set up the SnapGet desktop companion. Once the user completes their first session in either direction, the instruction screen is permanently replaced by DeviceManagementView.

## Data Model

### Persisted Flag

- **App group**: `group.net.boldman.snapget`
- **Key**: `hasCompletedSession`
- **Type**: `Bool`
- **Default**: `false`
- **Storage**: `UserDefaults(suiteName: "group.net.boldman.snapget")`
- **Access**: Via `SharedStorageProvider` in `Common` module (add new property for SnapGet app group)

### When the flag is set to `true`

| Direction | Trigger point | Writer |
|-----------|--------------|--------|
| PC→mobile | `ISQRRootViewModel.onClaimCompletion(.success)` fires after a successful claim | `ISQRRootViewModel` |
| mobile→PC | `CompletionFeature` processes `.done` action after a successful transfer | `CompletionFeature` |

### When the flag is read

| Context | Read point |
|---------|-----------|
| App launch | `RootFeature` `.onAppear` action |
| After sheet dismiss | `RootFeature` `.sheetContent(.dismiss)` handler |

## Architecture

### SharedStorageProvider Changes (Common module)

Add a new property to `SharedStorageProvider` for the SnapGet app group:

```swift
// In mobile/ios-packages/Common/Sources/Common/Services/SharedStorageProvider.swift
public protocol SharedStorageProtocol {
    var commonAppGroupUserDefaults: UserDefaults { get }
    var snapgetAppGroupUserDefaults: UserDefaults { get }
    var hasCompletedSession: Bool { get set }
}

let snapgetAppGroupIdentifier = "group.net.boldman.snapget"

public class SharedStorageProvider: SharedStorageProtocol {
    public let commonAppGroupUserDefaults: UserDefaults = .init(suiteName: appGroupIdentifier)!
    public let snapgetAppGroupUserDefaults: UserDefaults = .init(suiteName: snapgetAppGroupIdentifier)!

    public var hasCompletedSession: Bool {
        get { snapgetAppGroupUserDefaults.bool(forKey: "hasCompletedSession") }
        set { snapgetAppGroupUserDefaults.set(newValue, forKey: "hasCompletedSession") }
    }
}
```

### SharedStorageClient (New TCA dependency)

New file in `Common` package (so both the SnapGet main target and `ISFromMobile` can access it):

```swift
import ComposableArchitecture
import Common
import Factory

@DependencyClient
struct SharedStorageClient {
    var hasCompletedSession: @Sendable () -> Bool = { false }
    var setHasCompletedSession: @Sendable (Bool) -> Void
}

extension SharedStorageClient: DependencyKey {
    static let liveValue = SharedStorageClient(
        hasCompletedSession: {
            Container.shared.sharedStorageProvider().hasCompletedSession
        },
        setHasCompletedSession: { newValue in
            Container.shared.sharedStorageProvider().hasCompletedSession = newValue
        }
    )
}

extension DependencyValues {
    var sharedStorage: SharedStorageClient {
        get { self[SharedStorageClient.self] }
        set { self[SharedStorageClient.self] = newValue }
    }
}
```

### RootFeature Changes

File: `mobile/instant-share/App/RootView.swift`

```swift
@Reducer
struct RootFeature: Sendable {
    @ObservableState
    struct State: Equatable {
        var deviceManagement: DeviceManagementFeature.State = .init()
        @Presents var sheetContent: ShareSheetContent?
        var hasCompletedSession: Bool = false  // NEW
    }

    @CasePathable
    enum Action {
        case deviceManagement(DeviceManagementFeature.Action)
        case sheetContent(PresentationAction<Never>)
        case scanButtonTapped
        case receivedSharePayload(QRClaimPayload)
        case onAppear  // NEW
    }

    @Dependency(\.sharedStorage) var sharedStorage  // NEW

    var body: some ReducerOf<Self> {
        Scope(state: \.deviceManagement, action: \.deviceManagement) {
            DeviceManagementFeature()
        }
        Reduce { state, action in
            switch action {
            case .onAppear:  // NEW
                state.hasCompletedSession = sharedStorage.hasCompletedSession()
                return .none

            case .sheetContent(.dismiss):
                state.sheetContent = nil
                state.hasCompletedSession = sharedStorage.hasCompletedSession()  // NEW: re-read flag
                return .none

            // ... existing cases unchanged
            }
        }
    }
}
```

### RootView Changes

File: `mobile/instant-share/App/RootView.swift`

```swift
struct RootView: View {
    let store: StoreOf<RootFeature>

    var body: some View {
        WithPerceptionTracking {
            let sheetObserved = store.sheetContent
            NavigationView {
                if store.hasCompletedSession {  // NEW: conditional
                    DeviceManagementView(
                        store: store.scope(state: \.deviceManagement, action: \.deviceManagement)
                    )
                } else {
                    UserInstructionView()  // NEW
                }
                // toolbar stays the same
            }
            .task { store.send(.onAppear) }  // NEW: trigger flag load
            // ... rest unchanged
        }
    }
}
```

### ISQRRootViewModel Changes

File: `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/ISQRRootViewModel.swift`

Add `sharedStorageProvider` via Factory `@Injected` (same pattern as `MultiFileReceiveViewModel`):

```swift
public class ISQRRootViewModel: ObservableObject, ... {
    @Injected(\.sharedStorageProvider) private(set) var sharedStorageProvider: SharedStorageProtocol  // NEW
    let navigator: Navigator
    // ... existing properties unchanged
}
```

In `onClaimCompletion`, after successful claim:

```swift
func onClaimCompletion(_ result: Result<QRClaimResult, any Error>) {
    switch result {
    case .success(let claimResult):
        self.qrClaimResult = claimResult
        state = .result(claimResult)
        // NEW: mark session as completed
        sharedStorageProvider.hasCompletedSession = true
    case .failure(let error):
        // ... existing error handling
    }
}
```

### CompletionFeature Changes

File: `mobile/ios-packages/InstantShareKit/Sources/ISFromMobile/Features/CompletionFeature.swift`

Add `@Dependency(\.sharedStorage)` and use it in the `.done` action handler:

```swift
@Reducer
public struct CompletionFeature {
    // ... existing state/actions

    @Dependency(\.sharedStorage) var sharedStorage  // NEW

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .done:
                LocalLog.debug("CompletionFeature done action received")
                sharedStorage.setHasCompletedSession(true)  // NEW
                return .send(.delegate(.done))
            case .delegate:
                return .none
            }
        }
    }
}
```

### New File: UserInstructionView

File: `mobile/instant-share/App/UserInstructionView.swift`

Static SwiftUI view with:

1. **Header**: App icon + "SnapGet" + subtitle "Instantly share files, images, text and links between your phone and PC"
2. **PC → Mobile card**: `desktopcomputer` icon + "Share from your PC" + description about right-clicking files/text/images/links on PC
3. **Mobile → PC card**: `iphone` icon + "Share from this device" + description about selecting files/photos/text on phone
4. **PC Setup section**:
   - Step 1: "Download SnapGet for PC" — tappable URL `https://www.boldman.net/snapget.html#download` that copies to clipboard with toast
   - Step 2: "Install and launch SnapGet on your PC"
   - Step 3: "Enable the share extension in SnapGet settings"

## Files to Modify

| File | Change |
|------|--------|
| `mobile/ios-packages/Common/Sources/Common/Services/SharedStorageProvider.swift` | Add `snapgetAppGroupUserDefaults` and `hasCompletedSession` properties |
| `mobile/instant-share/App/RootView.swift` | Add `hasCompletedSession` to state, `onAppear` action, conditional view switching |
| `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/ViewModels/ISQRRootViewModel.swift` | Add `@Injected(\.sharedStorageProvider)`, set flag on successful claim |
| `mobile/ios-packages/InstantShareKit/Sources/ISFromMobile/Features/CompletionFeature.swift` | Add `@Dependency(\.sharedStorage)`, set flag on successful transfer |

## New Files

| File | Purpose |
|------|---------|
| `mobile/instant-share/App/UserInstructionView.swift` | First-time user instruction screen |
| `mobile/ios-packages/Common/Sources/Common/DI/SharedStorageClient.swift` | TCA dependency client wrapping SharedStorageProvider |

## Testing

- Verify instruction screen shows on fresh install (no `hasCompletedSession` key exists)
- Verify PC→mobile flow: receive files → tap Done → DeviceManagementView appears
- Verify mobile→PC flow: send files via Share Extension → return to app → DeviceManagementView appears
- Verify flag persists across app restarts
- Verify QR scan toolbar button works in both states
