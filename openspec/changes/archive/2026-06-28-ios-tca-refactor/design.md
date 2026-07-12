## Context

The `ISFromMobile` module implements the iOS Share Extension for the "Instant Share" feature. It currently uses a single-view-model (MVVM) architecture:

- **1 View** (`InstantShareExtensionView`) — switches content based on an enum value
- **1 ViewModel** (`InstantShareExtensionViewModel`) — 410 lines managing discovery, payload, trust, upload, completion, and errors
- **8 service files** — network, crypto, identity, and payload extraction that will be preserved as-is
- **Factory DI container** — singleton registration for services

This change replaces the View/ViewModel layer with **The Composable Architecture (TCA)**, introducing unidirectional data flow, composable features, and testable reducers.

## Goals / Non-Goals

**Goals:**
- Replace the monolithic MVVM layer with 7 focused TCA features: `FlowFeature`, `DiscoverFeature`, `PendingRevisitFeature`, `AuthFeature`, `TransferFeature`, `CompletionFeature`, `ErrorFeature`
- Introduce typed, unidirectional state management via `@Reducer`, `@ObservableState`, and `Effect`
- Wrap existing services in TCA `@Dependency` clients for testability
- Enable isolated unit testing of each feature's reducer with `TestStore`
- Preserve every aspect of current Share Extension behavior (flow, UI, API contracts)

**Non-Goals:**
- Rewrite or modify the remaining service-layer files (mDNS, trust, upload, crypto, payload extraction, handoff)
- Change HTTP API contracts, trust protocol, or data formats
- Change the ShareViewController UIKit host or extension lifecycle
- Introduce new user-facing capabilities
- Replace Factory container for common service singletons (kept via `Container+Shared.swift`)

## Decisions

### D1: Feature Decomposition Into 7 Features

**Decision:** Split the monolithic ViewModel into 7 TCA features, each owning a distinct phase of the flow:

| Feature | Responsibility | Maps to Current Phase |
|---|---|---|
| **FlowFeature** | Router + shared context owner. Owns `Route` enum for transitions. Owns `@Shared(.instantShareContext)` — loads shared items from extension context on appear and sets `sharedItems` in the context. | Entire `switch sessionPhase` |
| **DiscoverFeature** | mDNS discovery, device list, payload card, Send button, pre-warm local network. Owns `sessionId` (re-init on appear) and `targetDevice` in `@Shared(.instantShareContext)`. On send, transitions to PendingRevisitFeature. | `.scanning`, `.ready`, `.starting` |
| **PendingRevisitFeature** | Attempts a "revisit" TLS transfer directly (with app-layer signature auth headers) using the previously-established trust, reading shared items from `@SharedReader(.instantShareContext)`. On success delegates to CompletionFeature; on failure delegates to AuthFeature. | *(new)* |
| **AuthFeature** | PIN input, trust handshake (handshake → apply → confirm), cancel during auth. Reads shared items from `@SharedReader(.instantShareContext)` for upload after PIN confirm. | `.awaitingPinInput` |
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
            case pendingRevisit(PendingRevisitFeature.State)
            case auth(AuthFeature.State)
            case transfer(TransferFeature.State)
            case completion(CompletionFeature.State)
            case error(ErrorFeature.State)
        }
    }

    @CasePathable
    enum Action {
        case discover(DiscoverFeature.Action)
        case pendingRevisit(PendingRevisitFeature.Action)
        case auth(AuthFeature.Action)
        case transfer(TransferFeature.Action)
        case completion(CompletionFeature.Action)
        case error(ErrorFeature.Action)
    }

    @Shared(.instantShareContext) var context
}
```

FlowFeature's reducer uses `Scope` to route each child action to the correct child reducer. It also owns the shared context — on `.onAppear`, an effect reads `inputItems` from `@Dependency(\.instantShareExtensionContext)`, calls `PayloadExtractor.extract(from:)`, and writes the result into `context.sharedItems` while setting `context.isLoadingSharedItems = false`. Child features access the context via `@Shared` (write-capable) or `@SharedReader` (read-only).

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
    @Shared(.instantShareContext) var context
    let store: StoreOf<FlowFeature>

    var body: some View {
        switch store.state.route {
        case .discover:
            DiscoverView(store: store.scope(state: \.route.discover, action: \.discover))
        case .pendingRevisit:
            PendingRevisitView(store: store.scope(state: \.route.pendingRevisit, action: \.pendingRevisit))
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
.discover ──send()──► .pendingRevisit ──success──► .completion ──done──► exit
                         │
                     (failure)
                         │
                         ▼
                    .auth ──confirmPIN()──► .transfer ──auto──► .completion ──done──► exit
                      ▲                                              │
                      │                                              │ (error)
                      │                                              ▼
                      └────── retry ◄───────────────────────── .error ──cancel──► exit
```

- **PendingRevisit → Completion**: revisit transfer succeeded — content was delivered directly via TLS with app-layer signature auth. Transition to `.completion` immediately, skipping trust handshake and upload entirely.
- **PendingRevisit → Auth**: revisit transfer failed (no existing trust, network unreachable, etc.) — fall back to full trust handshake flow. FlowFeature sets `route = .auth(AuthFeature.State())`.
- **Done** (CompletionFeature): exits via `completeRequest()` on the context DI.
- **Cancel** (AuthFeature / ErrorFeature): exits via `cancelRequest()` on the context DI.
- **Retry** (ErrorFeature): returns to `.discover` for a fresh attempt without exiting the extension.

AuthFeature's role ends once the PIN is confirmed and session keys are exchanged. At that point control passes to TransferFeature, which manages the upload effect and auto-transitions to CompletionFeature on success or ErrorFeature on failure.

**Rationale:** The existing code already uses a `switch sessionPhase` pattern — this directly translates that pattern into TCA. No navigation primitives needed. FlowFeature is purely a router: it owns the route, its reducer transitions between cases, and FlowView renders the current page. Simple, testable, no overhead.

**Alternatives considered:**
- *`@Presents` with `.sheet`/`.fullScreenCover`*: Adds modal presentation animations and complexity where none is needed — this is a flat linear flow, not a modal stack.
- *`NavigationStack` with `StackState`*: Designed for drill-down hierarchies; the Share Extension has no back-navigation.
- *Single child state with embedded phase enum*: Would violate single responsibility by mixing all feature state into one struct.

### D2b: InstantShareContext — Shared State Across Features

**Decision:** Introduce a single `InstantShareContext` struct shared across features via TCA's `@Shared` / `@SharedReader` (in-memory persistence). This replaces the `InstantShareService` singleton (which held session state, shared text/images, and connection config) and the intermediate `InstantShareConnectionConfig`/`InstantShareMetadata` types.

```swift
struct InstantShareContext: Equatable {
    var sessionId: String = UUID().uuidString.lowercased()
    var targetDevice: InstantShareDiscoveredPC? = nil
    var sharedItems: SharedItems = .text("")
    var isLoadingSharedItems: Bool = false
}

enum SharedItems: Equatable {
    case text(String)
    case images([SharedImage])
    case files([SharedFile])

    var payloadClass: InstantSharePayloadClass {
        switch self {
        case .text: return .text
        case .images: return .image
        case .files: return .text  // files not yet supported via instant-share
        }
    }

    var targetIntent: String {
        switch self {
        case .text: return "clipboard_only"
        case .images: return "clipboard_or_file"
        case .files: return "clipboard_or_file"
        }
    }
}

struct SharedImage: Equatable {
    let fileURL: URL
    let filename: String
    let contentType: String
}

struct SharedFile: Equatable {
    let fileURL: URL
    let filename: String
    let contentType: String
}
```

**Ownership rules:**

| Feature | Access | Writes |
|---|---|---|
| **FlowFeature** | `@Shared(.instantShareContext)` | Sets `sharedItems` and `isLoadingSharedItems` on appear after loading from extension context |
| **DiscoverFeature** | `@Shared(.instantShareContext)` | Re-init `sessionId` on appear; sets `targetDevice` on user selection |
| **PendingRevisitFeature** | `@SharedReader(.instantShareContext)` | Read-only — reads `sessionId`, `targetDevice`, `sharedItems` for revisit upload |
| **AuthFeature** | `@SharedReader(.instantShareContext)` | Read-only — reads `sessionId`, `targetDevice`, `sharedItems` for trust handshake + upload |
| **TransferFeature** | `@SharedReader(.instantShareContext)` | Read-only — reads `sessionId`, `targetDevice`, `sharedItems` for upload |
| **CompletionFeature** | *(none)* | No context access needed |
| **ErrorFeature** | *(none)* | No context access needed |

**Shared key registration (in-memory):**

```swift
extension SharedReaderKey where Self == InMemoryKey<InstantShareContext>.Default {
    static var instantShareContext: Self {
        Self[.inMemory("instantShareContext"), default: InstantShareContext()]
    }
}
```

**Rationale:** `InstantShareService` acted as a mutable singleton that held session state, shared payload, and connection config. By moving this into TCA's `@Shared` system we:
- Eliminate the `InstantShareService` class entirely (removed from codebase)
- Eliminate `InstantShareConnectionConfig` and `InstantShareMetadata` (data derived from context)
- Give each feature only the access level it needs (write vs read-only)
- Keep all state changes observable through TCA's change tracking
- Remove the only remaining Factory-registered ISFromMobile service

**Alternatives considered:**
- *Passing data through FlowFeature's State*: Would require deep forwarding of shared data through all child features. `@Shared` eliminates boilerplate.
- *Each feature loading its own payload*: Duplication and inconsistency risk.
- *Keep InstantShareService*: Defeats the purpose of removing the service singleton.

### D3: Dependency Clients Wrapping Existing Services

**Decision:** Define TCA `@DependencyClient` types. Two wiring strategies depending on where the service lives:

#### Category A: Common/Shared Services (Factory bridge — keep `Container+Shared.swift`)

Services from `Common/DI/Container+Shared.swift` (`AppIdentityProviding`, `LocalDeviceIdentifierProviding`) are singletons shared across targets. Their TCA clients bridge via `Container.shared`:

```swift
extension IdentityClient: DependencyKey {
    static let liveValue = IdentityClient(
        selfCertificatePEM: { try await Container.shared.appIdentityProvider().selfCertificatePEM() },
        importPeerCertificate: { try await Container.shared.appIdentityProvider().importPeerCertificate(pem: $0) },
        initialize: { try await Container.shared.appIdentityProvider().initialize() },
        currentDeviceName: { await Container.shared.localDeviceIdentityProvider().currentIdentifier().deviceName }
    )
}
```

#### Category B: ISFromMobile-Only Services (direct instantiation — no Factory)

Services defined inside `ISFromMobile` (`InstantShareMDNSBrowser`, `InstantShareTrustClient`, `InstantShareUploadClient`, `InstantSharePayloadExtractor`, `InstantShareTrustSessionManager`) are **not** registered via Factory. Their TCA clients instantiate them directly in `liveValue`. TCA resolves `@Dependency` once per store scope, so all features sharing the same `Store` get the same instance — singleton behavior without Factory.

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

**NOTE:** `InstantShareTrustSessionManager` was previously owned by `InstantShareService`. With `InstantShareService` removed, it is now a standalone dependency (`TrustSessionManagerClient`) — instantiated directly as a singleton in `liveValue`. `InstantShareTrustClient` and `InstantShareUploadClient` remain ephemeral (created per-operation) and receive the trust session manager or identity provider as constructor arguments from the dependency client.

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
3. `TrustClient` — wraps `InstantShareTrustClient`
4. `UploadClient` — wraps `InstantShareUploadClient`
5. `TrustSessionManagerClient` — wraps `InstantShareTrustSessionManager` (singleton, replaces `InstantShareService`'s ownership)
6. `IdentityClient` — wraps `AppIdentityProviding` + `LocalDeviceIdentifierProviding` (**Factory bridge** via `Container.shared`)
7. `InstantShareExtensionContextClient` — wraps the UIKit `extensionContext` (inputItems, completeRequest, cancelRequest). Set via module-level static before store creation, read by `liveValue`. Replaces all `onCancel`/`onDone` callback plumbing.

**Removed clients:**
- `InstantShareServiceClient` — no longer needed. `InstantShareService` is removed. Its responsibilities are split between `InstantShareContext` (@Shared state) and `TrustSessionManagerClient` (singleton).

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

| Old ShareViewController/ViewModel responsibility | New owner |
|---|---|---|
| `loadPayload(from:)` → extract extension items | **FlowFeature.onAppear** — reads `inputItems` from `@Dependency(\.instantShareExtensionContext)`, calls `PayloadExtractor.extract(from:)`, writes result into `$context.sharedItems` |
| `startDiscovery()` | `DiscoverFeature.onAppear` — starts mDNS browsing (payload already loaded by FlowFeature) |
| `initialize()` | `FlowFeature.onAppear` — fires as a fire-and-forget effect |
| `beginRequestExtensionTime()` / expiring activity | `DiscoverFeature.onAppear` — initiates `ProcessInfo.performExpiringActivity` as an effect; expiration handler sends `.stopDiscovery` |
| `cancelAction()` / `extensionContext?.cancelRequest(...)` | `ErrorFeature.delegate(.cancel)` → FlowFeature calls `@Dependency(\.instantShareExtensionContext).cancelRequest(...)` |
| `doneAction()` / `extensionContext?.completeRequest(...)` | `CompletionFeature.delegate(.done)` → FlowFeature calls `@Dependency(\.instantShareExtensionContext).completeRequest()` |
| `onCancel`/`onDone` closures passed to FlowView | **Removed** — features use context DI directly |
| `attemptRevisitTransfer()` | **Moved to PendingRevisitFeature** — reads `context.sharedItems`, `context.sessionId`, `context.targetDevice` via `@SharedReader(.instantShareContext)`. Success → `.delegate(.revisitSucceeded(...))`; failure → `.delegate(.revisitFailed)`. |
| Session id generation / PC selection | **DiscoverFeature** — reinit `context.sessionId` on appear; set `context.targetDevice` on user selection. `sessionId` doubles as `correlationId`. |
| `InstantShareService` / `InstantShareConnectionConfig` / `InstantShareMetadata` | **Removed entirely** — state lives in `InstantShareContext`, metadata derived from `SharedItems` enum. |

**Rationale:** This eliminates all UIKit↔SwiftUI bridging glue. The TCA store owns all logic and side effects. ShareViewController becomes a minimal host that only manages the view hierarchy, staying out of the business flow entirely. `FlowView` has no callback parameters — it's a pure `Store` consumer.

### D7: PendingRevisitFeature — Dedicated Revisit Transfer Screen

**Decision:** Extract the "revisit transfer" attempt — currently embedded in the ViewModel's `send()` method — into its own `PendingRevisitFeature`. This feature owns the attempt to deliver content directly to a previously-trusted device using TLS with app-layer signature auth headers, bypassing the PIN/trust flow when possible.

**Feature design:**

```swift
@Reducer
struct PendingRevisitFeature {
    @ObservableState
    struct State: Equatable {
        let payloadDescription: String  // For display while checking
    }

    @CasePathable
    enum Action {
        case attemptRevisit
        case delegate(Delegate)
        enum Delegate: Equatable {
            case revisitSucceeded(payloadDescription: String)
            case revisitFailed
        }
    }

    @SharedReader(.instantShareContext) var context
    @Dependency(\.uploadClient) var uploadClient
    @Dependency(\.identityClient) var identityClient
}
```

**Behavior:**
1. `PendingRevisitView` appears with a spinner and "Checking existing trust..." message.
2. `.task { store.send(.attemptRevisit) }` triggers the revisit effect.
3. The effect reads `context.sharedItems`, `context.sessionId`, and `context.targetDevice` from `@SharedReader(.instantShareContext)`, builds the upload request inline (deriving metadata from the SharedItems enum), then attempts the TLS upload via `UploadClient` using the PC's `tlsPort` with `context.sessionId` (doubles as correlationId) and the current device name from `IdentityClient`.
4. On success → sends `.delegate(.revisitSucceeded(payloadDescription:))`. FlowFeature routes to `.completion`.
5. On failure (any error: no existing trust, network unreachable, TLS verification failure, etc.) → sends `.delegate(.revisitFailed)`. FlowFeature routes to `.auth` for full trust handshake.

**No user interaction needed:** The revisit attempt is automatic — there are no buttons on this screen. The user either sees it briefly before being taken to completion (fast path), or the screen transitions to PIN entry (slow path).

**Error handling:** A revisit failure is NOT an error in the error-feature sense. It's an expected fallback — the device simply has no prior trust. The error is swallowed and the flow routes to AuthFeature. If the revisit transfer itself partially fails (e.g., TLS error mid-transfer), the upload client throws, the `.revisitFailed` delegate fires, and the user proceeds through PIN + upload normally.

**Rationale:** Extracting this into its own feature has several advantages:
- **Single responsibility**: DiscoverFeature no longer mixes mDNS/payload concerns with upload logic. PendingRevisitFeature has one job: try the revisit, report the result.
- **Clear visual feedback**: The user sees a dedicated "checking trust" screen instead of a disjointed spinner state, making the flow more predictable.
- **Simpler FlowFeature transitions**: The revisit decision is clearly modeled as a delegate with two outcomes (succeeded/failed), rather than a conditional side-effect hidden inside DiscoverFeature's `send()`.
- **Testability**: PendingRevisitFeature can be unit-tested in isolation with a mock upload client — test the success path, the network error path, the TLS error path, etc.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| **R1: Share Extension memory/time limits** — Adding TCA increases binary size and potentially memory usage in the constrained extension process. | TCA is a lightweight framework (<500KB). The reduction from a monolithic ViewModel to focused reducers should offset any overhead. Monitor extension timeout under `beginRequestExtensionTime()`. |
| **R2: Combine-to-async-stream bridge** — `InstantShareMDNSBrowser` uses Combine publishers. TCA prefers `AsyncStream`. The bridge must be leak-free. | Use TCA's `.run { send in }` with `for await value in asyncStream` pattern. Test with `TestClock` to avoid flakiness. |
| **R3: PIN mismatch recovery is now intra-feature** — The current code transitions ⥫ `.awaitingPinInput` on PIN mismatch. In TCA, this must happen inside AuthFeature without routing to FlowFeature. | AuthFeature owns only the PIN input flow. PIN mismatch just sets `errorMessage` and stays in `.awaitingPinInput` state — no route transition needed. Upload lives in TransferFeature. |
| **R4: `@Shared` context consistency** — Multiple features read/write `InstantShareContext` through `@Shared`/`@SharedReader`. Race conditions or stale reads could occur. | TCA's `@Shared` provides in-memory synchronous reads. Since all effects run on the same MainActor queue and FlowFeature controls route transitions, there's no concurrent access. DiscoverFeature writes `targetDevice` before sending `.delegate(.didStartPendingRevisit)`; PendingRevisitFeature reads it after the transition. |
| **R5: `InstantShareTrustSessionManager` singleton lifecycle** — Must be shared across TrustClient calls but reset between sessions. | `TrustSessionManagerClient`'s `liveValue` instantiates one manager per store. FlowFeature's `stopSession` (or equivalent cleanup) calls `reset()`. |
| **R6: Migration complexity** — Replacing the entire View/ViewModel layer at once is high-risk. | Feature-by-feature replacement is impractical because FlowFeature owns routing. We ship the complete replacement as one atomic change, validated by unit tests + integration test. |
| **R7: Removed `InstantShareConnectionConfig` breakage** — The PC-side API contract expects `connectionConfig` fields. Trust/upload clients must build those fields inline from context data. | The request serialization structs (`InstantShareTrustHandshakeRequest`, etc.) already encode individual metadata fields. Removing `InstantShareConnectionConfig` as an intermediate does not change the wire format — the same fields are produced from `InstantShareContext` + static values. |

## Open Questions

None.
