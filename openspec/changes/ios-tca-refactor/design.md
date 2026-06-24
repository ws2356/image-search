## Context

The `ISFromMobile` module implements the iOS Share Extension for the "Instant Share" feature. It currently uses a single-view-model (MVVM) architecture:

- **1 View** (`InstantShareExtensionView`) — switches content based on an enum value
- **1 ViewModel** (`InstantShareExtensionViewModel`) — 410 lines managing discovery, payload, trust, upload, completion, and errors
- **8 service files** — network, crypto, identity, and payload extraction that will be preserved as-is
- **Factory DI container** — singleton registration for services

This change replaces the View/ViewModel layer with **The Composable Architecture (TCA)**, introducing unidirectional data flow, composable features, and testable reducers.

## Goals / Non-Goals

**Goals:**
- Replace the monolithic MVVM layer with 6 focused TCA features: `FlowFeature`, `DiscoverFeature`, `AuthFeature`, `TransferFeature`, `CompletionFeature`, `ErrorFeature`
- Introduce typed, unidirectional state management via `@Reducer`, `@ObservableState`, and `Effect`
- Wrap existing services in TCA `@Dependency` clients for testability
- Enable isolated unit testing of each feature's reducer with `TestStore`
- Preserve every aspect of current Share Extension behavior (flow, UI, API contracts)

**Non-Goals:**
- Rewrite or modify the 8 service-layer files (mDNS, trust, upload, crypto, payload extraction, handoff)
- Change HTTP API contracts, trust protocol, or data formats
- Change the ShareViewController UIKit host or extension lifecycle
- Introduce new user-facing capabilities
- Replace Factory container for service singletons (Factory continues as-is for service lifecycle)

## Decisions

### D1: Feature Decomposition Into 6 Features

**Decision:** Split the monolithic ViewModel into 6 TCA features, each owning a distinct phase of the flow:

| Feature | Responsibility | Maps to Current Phase |
|---|---|---|
| **FlowFeature** | Pure router — owns a `Route` enum, reducer transitions between route cases. FlowView switches on `route` and renders the child directly. No navigation stack or presentation modifiers. | Entire `switch sessionPhase` |
| **DiscoverFeature** | mDNS discovery, device list, payload card, Send button, pre-warm local network permission. | `.scanning`, `.ready`, `.starting` |
| **AuthFeature** | PIN input, trust handshake (handshake → apply → confirm), cancel during auth. | `.awaitingPinInput` |
| **TransferFeature** | Upload progress spinner; auto-navigates to CompletionFeature on success. | `.transferring` |
| **CompletionFeature** | Success confirmation with "Done" button that exits the extension (same as current `extensionContext?.completeRequest(...)` behavior). | `.success` |
| **ErrorFeature** | Full-screen error display with "Retry" → Discovery and "Cancel" → close extension. | `.failed(String)` |

**Rationale:** Each feature maps 1:1 to a distinct user-facing screen and has a clear single responsibility. FlowFeature acts as a lightweight coordinator — it owns no business logic, only the routing state.

**Alternatives considered:**
- *Single feature*: Would preserve the current monolith's complexity in one file.
- *3 features (Discover, Auth, Completion)*: Error handling would be duplicated or awkwardly shared.
- *NavigationStack-based*: Overkill for a linear flow without back-navigation; single-content-switch is simpler and matches the existing UX.

### D2: Navigation Model — FlowFeature as Pure Router with Route Enum

**Decision:** FlowFeature owns a single `Route` enum and FlowView renders the child directly — no `@Presents`, no NavigationStack, no presentation modifiers. This mirrors the existing code's `switch sessionPhase` pattern exactly.

```swift
@Reducer
struct FlowFeature {
    @ObservableState
    struct State: Equatable {
        var route: Route

        enum Route: Equatable {
            case discover(DiscoverFeature.State)
            case auth(AuthFeature.State)
            case transfer(TransferFeature.State)
            case completion(CompletionFeature.State)
            case error(ErrorFeature.State)
        }
    }

    @CasePathable
    enum Action {
        case discover(DiscoverFeature.Action)
        case auth(AuthFeature.Action)
        case transfer(TransferFeature.Action)
        case completion(CompletionFeature.Action)
        case error(ErrorFeature.Action)
    }
}
```

FlowFeature's reducer uses `Scope` to route each child action to the correct child reducer:

```swift
var body: some ReducerOf<Self> {
    Scope(state: \.route, action: \.self) {
        // Route enum delegates to correct child reducer based on current case
        ...
    }
}
```

FlowView does NOT render its own content — it switches on the route and renders the appropriate child view:

```swift
struct FlowView: View {
    let store: StoreOf<FlowFeature>

    var body: some View {
        switch store.state.route {
        case .discover:
            DiscoverView(store: store.scope(state: \.route.discover, action: \.discover))
        case .auth:
            AuthView(store: store.scope(state: \.route.auth, action: \.auth))
        case .transfer:
            TransferView(store: store.scope(state: \.route.transfer, action: \.transfer))
        case .completion:
            CompletionView(store: store.scope(state: \.route.completion, action: \.completion))
        case .error:
            ErrorView(store: store.scope(state: \.route.error, action: \.error))
        }
    }
    .task { store.send(.onAppear) }
}
```

When FlowFeature transitions the route between cases (e.g., `discover → auth`), the old child state is discarded and the new child view renders — there is no navigation stack, no presentation overlay.

Transition flow:
```
                    ┌── cancel ──► exit
                    │
.discover ──send()──► .auth ──confirmPIN()──► .transfer ──auto──► .completion ──done──► exit
  ▲                                                         │
  │                                                         │ (error)
  │                                                         ▼
  └────── retry ◄──────────────────────────────────── .error ──cancel──► exit
```

- **Done** (CompletionFeature): exits via `completeRequest()` on the context DI.
- **Cancel** (AuthFeature / ErrorFeature): exits via `cancelRequest()` on the context DI.
- **Retry** (ErrorFeature): returns to `.discover` for a fresh attempt without exiting the extension.

AuthFeature's role ends once the PIN is confirmed and session keys are exchanged. At that point control passes to TransferFeature, which manages the upload effect and auto-transitions to CompletionFeature on success or ErrorFeature on failure.

**Rationale:** The existing code already uses a `switch sessionPhase` pattern — this directly translates that pattern into TCA. No navigation primitives needed. FlowFeature is purely a router: it owns the route, its reducer transitions between cases, and FlowView renders the current page. Simple, testable, no overhead.

**Alternatives considered:**
- *`@Presents` with `.sheet`/`.fullScreenCover`*: Adds modal presentation animations and complexity where none is needed — this is a flat linear flow, not a modal stack.
- *`NavigationStack` with `StackState`*: Designed for drill-down hierarchies; the Share Extension has no back-navigation.
- *Single child state with embedded phase enum*: Would violate single responsibility by mixing all feature state into one struct.

### D3: Dependency Clients Wrapping Existing Services

**Decision:** Define TCA `@DependencyClient` types. Two wiring strategies depending on where the service lives:

#### Category A: Common/Shared Services (Factory bridge — keep `Container+Shared.swift`)

Services from `Common/DI/Container+Shared.swift` (`AppIdentityProviding`, `LocalDeviceIdentifierProviding`) are singletons shared across targets. Their TCA clients bridge via `Container.shared`:

```swift
extension IdentityClient: DependencyKey {
    static let liveValue = IdentityClient(
        selfCertificatePEM: { try await Container.shared.appIdentityProvider().selfCertificatePEM() },
        importPeerCertificate: { try await Container.shared.appIdentityProvider().importPeerCertificate(pem: $0) },
        ensureSelfIdentity: { try await Container.shared.appIdentityProvider().ensureSelfIdentity() },
        currentDeviceName: { await Container.shared.localDeviceIdentityProvider().currentIdentifier().deviceName }
    )
}
```

#### Category B: ISFromMobile-Only Services (direct instantiation — no Factory)

Services defined inside `ISFromMobile` (`InstantShareMDNSBrowser`, `InstantShareService`, `InstantShareTrustClient`, `InstantShareUploadClient`, `InstantSharePayloadExtractor`) are **not** registered via Factory. Their TCA clients instantiate them directly in `liveValue`. TCA resolves `@Dependency` once per store scope, so all features sharing the same `Store` get the same instance — singleton behavior without Factory.

```swift
extension MDNSBrowserClient: DependencyKey {
    static let liveValue = MDNSBrowserClient(
        startBrowsing: { InstantShareMDNSBrowser().startBrowsing() },
        stopBrowsing: { InstantShareMDNSBrowser().stopBrowsing() },
        discoveredDevices: {
            AsyncStream { continuation in
                let browser = InstantShareMDNSBrowser()
                let cancellable = browser.objectWillChange
                    .sink { continuation.yield(browser.discovered) }
                continuation.onTermination = { _ in cancellable.cancel() }
                browser.startBrowsing()
            }
        }
    )
}
```

```swift
extension InstantShareServiceClient: DependencyKey {
    static let liveValue = InstantShareServiceClient(
        selectPC: { InstantShareService().selectPC($0) },
        setSharedText: { InstantShareService().setSharedText($0) },
        ...
    )
}
```

**NOTE:** `InstantShareTrustSessionManager` is owned by `InstantShareService` — it's created inside `InstantShareService.init()`. The TCA dependency for `InstantShareService` creates a single instance per store, which means the trust session manager is also effectively singletonshared across features. `InstantShareTrustClient` and `InstantShareUploadClient` are ephemeral (created per-operation in the current code) — they read shared state from the service and identity clients as arguments.

#### Category C: InstantShareExtensionContext (static set before store creation)

`InstantShareExtensionContextClient` is unique — it wraps the UIKit `extensionContext` which is only available at runtime in `ShareViewController.viewDidLoad`. It uses a module-level static that's set before the store is created:

```swift
public struct InstantShareExtensionContextClient {
    public var inputItems: [NSExtensionItem]
    public var completeRequest: @Sendable () -> Void
    public var cancelRequest: @Sendable (Error?) -> Void
}

extension InstantShareExtensionContextClient: DependencyKey {
    public static var liveValue: InstantShareExtensionContextClient {
        guard let current else { fatalError("InstantShareExtensionContext not set — call ShareViewController.setup()") }
        return current
    }
    nonisolated(unsafe) public static var current: InstantShareExtensionContextClient?
}
```

ShareViewController sets `current` before creating the store. Test values override via `withDependencies`.

#### Rationale

- **Common services**: Factory maintains cross-target singleton lifecycle. The TCA client is a thin wrapper — test values override the client entirely, not Factory.
- **ISFromMobile services**: No need for Factory — TCA's own dependency resolution provides singleton semantics per store. Removing Factory for these services eliminates `Container+ShareExtension.swift` entirely.
- **Testability**: All dependency clients have `testValue` overrides. Tests use `withDependencies { $0.mdnsBrowser = .testValue }` to inject mocks.

**Dependency Clients needed:**
1. `MDNSBrowserClient` — wraps `InstantShareMDNSBrowser`
2. `PayloadExtractorClient` — wraps `InstantSharePayloadExtractor`
3. `InstantShareServiceClient` — wraps `InstantShareService`
4. `TrustClient` — wraps `InstantShareTrustClient`
5. `UploadClient` — wraps `InstantShareUploadClient`
6. `IdentityClient` — wraps `AppIdentityProviding` + `LocalDeviceIdentifierProviding` (**Factory bridge** via `Container.shared`)
7. `InstantShareExtensionContextClient` — wraps the UIKit `extensionContext` (inputItems, completeRequest, cancelRequest). Set via module-level static before store creation, read by `liveValue`. Replaces all `onCancel`/`onDone` callback plumbing.

**Alternatives considered:**
- *All services via Factory bridge*: Preserves Factory for ISFromMobile services but keeps `Container+ShareExtension.swift` alive, which the user wants removed.
- *All services via direct instantiation*: Would break singleton guarantees for Common services that must be shared with the main app target.

### D4: Error Handling — Errors Route to ErrorFeature

**Decision:** ErrorFeature is shown whenever an unrecoverable error occurs in any child feature. The flow:

1. Child feature encounters an unrecoverable error
2. Child sends a `.delegate(.failed(Error))` action
3. FlowFeature receives the delegate action, sets `route = .error(ErrorFeature.State(message:))` (replaces current route)
4. ErrorFeature shows the error message with "Retry" and "Cancel" buttons
5. "Retry" sends `.delegate(.retry)` → FlowFeature sets `route = .discover(DiscoverFeature.State())` (fresh start, no exit)
6. "Cancel" sends `.delegate(.cancel)` → FlowFeature calls `@Dependency(\.instantShareExtensionContext).cancelRequest(...)` — extension exits

Recoverable errors (e.g., PIN mismatch) remain inside AuthFeature — the AuthFeature shows an inline error and lets the user retry the PIN without routing to ErrorFeature.

TransferFeature errors (e.g., upload network failure) always escalate to ErrorFeature since the transfer is in-flight and unrecoverable.

**Rationale:** Clear policy for error severity. Only unrecoverable errors (network failure, protocol error, session failure) escalate to ErrorFeature. Recoverable errors stay in-context.

### D5: TCA Package Integration

**Decision:** Add `swift-composable-architecture` as a Swift Package dependency to the project. The package will be used by the `ISFromMobile` module only (services remain unaffected).

### D6: ShareViewController as Minimal UIKit Host

**Decision:** `ShareViewController` is a thin host — it sets up the `InstantShareExtensionContext` static, creates the store, and embeds `FlowView`. No `onCancel`/`onDone` callbacks, no action dispatching, no manual lifecycle calls.

```swift
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Set up extension context for TCA dependency injection
        InstantShareExtensionContextClient.current = InstantShareExtensionContextClient(
            inputItems: extensionContext?.inputItems as? [NSExtensionItem] ?? [],
            completeRequest: { [weak extensionContext] in
                extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            },
            cancelRequest: { [weak extensionContext] error in
                let nsError = error ?? NSError(domain: "InstantShareExtension", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "User canceled"])
                extensionContext?.cancelRequest(withError: nsError)
            }
        )

        // 2. Create store — liveValue handles all service instantiation
        let store = Store(initialState: FlowFeature.State(
            route: .discover(DiscoverFeature.State())
        )) {
            FlowFeature()
        }

        // 3. Embed FlowView — no callbacks, features use DI for exit
        let hosting = UIHostingController(rootView: FlowView(store: store))
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
```

#### Responsibility Mapping (what moved where)

| Old ShareViewController responsibility | New owner |
|---|---|
| `loadPayload(from:)` → extract extension items | `DiscoverFeature.onAppear` — reads `inputItems` from `@Dependency(\.instantShareExtensionContext)`, calls `PayloadExtractor.extract(from:)` |
| `startDiscovery()` | `DiscoverFeature.onAppear` — starts mDNS browsing after payload loaded |
| `ensureSelfIdentity()` | `FlowFeature.onAppear` — fires as a fire-and-forget effect |
| `beginRequestExtensionTime()` / expiring activity | `DiscoverFeature.onAppear` — initiates `ProcessInfo.performExpiringActivity` as an effect; expiration handler sends `.stopDiscovery` |
| `cancelAction()` / `extensionContext?.cancelRequest(...)` | `ErrorFeature.delegate(.cancel)` → FlowFeature calls `@Dependency(\.instantShareExtensionContext).cancelRequest(...)` |
| `doneAction()` / `extensionContext?.completeRequest(...)` | `CompletionFeature.delegate(.done)` → FlowFeature calls `@Dependency(\.instantShareExtensionContext).completeRequest()` |
| `onCancel`/`onDone` closures passed to FlowView | **Removed** — features use context DI directly |

**Rationale:** This eliminates all UIKit↔SwiftUI bridging glue. The TCA store owns all logic and side effects. ShareViewController becomes a minimal host that only manages the view hierarchy, staying out of the business flow entirely. `FlowView` has no callback parameters — it's a pure `Store` consumer.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| **R1: Share Extension memory/time limits** — Adding TCA increases binary size and potentially memory usage in the constrained extension process. | TCA is a lightweight framework (<500KB). The reduction from a monolithic ViewModel to focused reducers should offset any overhead. Monitor extension timeout under `beginRequestExtensionTime()`. |
| **R2: Combine-to-async-stream bridge** — `InstantShareMDNSBrowser` uses Combine publishers. TCA prefers `AsyncStream`. The bridge must be leak-free. | Use TCA's `.run { send in }` with `for await value in asyncStream` pattern. Test with `TestClock` to avoid flakiness. |
| **R3: PIN mismatch recovery is now intra-feature** — The current code transitions ⥫ `.awaitingPinInput` on PIN mismatch. In TCA, this must happen inside AuthFeature without routing to FlowFeature. | AuthFeature owns only the PIN input flow. PIN mismatch just sets `errorMessage` and stays in `.awaitingPinInput` state — no route transition needed. Upload lives in TransferFeature. |
| **R4: Service singletons must remain singletons** — `InstantShareService` and `InstantShareTrustSessionManager` must be shared across dependency clients. | The Factory container ensures singleton scope. Dependency clients access Container.shared, so all features use the same service instance. |
| **R5: Migration complexity** — Replacing the entire View/ViewModel layer at once is high-risk. | Feature-by-feature replacement is impractical because FlowFeature owns routing. We ship the complete replacement as one atomic change, validated by unit tests + integration test. |

## Open Questions

None.
