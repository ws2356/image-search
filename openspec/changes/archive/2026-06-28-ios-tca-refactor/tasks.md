## 1. Setup — Add TCA Package Dependency

- [x] 1.1 Add `swift-composable-architecture` SPM package to the Xcode project (or Package.swift if using SPM-based project structure)
- [x] 1.2 Verify the package resolves and builds with the ISFromMobile target

## 2. Create Dependency Clients (TCA @Dependency wrappers)

**Wiring rule:** ISFromMobile-only services instantiate directly in `liveValue` (TCA caches per-store). Common/shared services (`Container+Shared.swift`) bridge via `Container.shared`. `InstantShareService` is removed entirely — its state lives in `InstantShareContext` (TCA `@Shared`) and its `trustSession` lives in a standalone `TrustSessionManagerClient`.

- [x] 2.1 Create `DependencyClients/MDNSBrowserClient.swift` — wraps `InstantShareMDNSBrowser` with `startBrowsing`, `stopBrowsing`, and `discoveredDevices` async stream (bridging Combine publisher to `AsyncStream`). **Direct instantiation** in `liveValue`.
- [x] 2.2 Create `DependencyClients/PayloadExtractorClient.swift` — wraps `InstantSharePayloadExtractor.extract(from:)` as an async throwing function. **Direct call** (static methods, no instance needed).
- [x] 2.3 Create `DependencyClients/TrustClient.swift` — wraps `InstantShareTrustClient` (handshake, apply, confirm methods). **Singleton** in `liveValue` — `InstantShareTrustClient` is `@unchecked Sendable` but has no mutable state of its own (all `let` properties); `@unchecked` is only because the shared `trustSessionManager` reference is a mutable class, which is itself a singleton. The singleton `TrustClient` captures the same `InstantShareTrustSessionManager` instance used by `TrustSessionManagerClient.liveValue`. This eliminates per-call alloc/dealloc overhead with zero correctness risk — same sharing pattern as today's code (one manager shared across all RPC calls), just without ephemeral wrapper instances. Both classes are stateless wrappers around config + delegated state.
- [x] 2.4 Create `DependencyClients/UploadClient.swift` — wraps `InstantShareUploadClient` (uploadText, uploadImage, uploadImages). **Singleton** in `liveValue` — `InstantShareUploadClient` is compiler-verified `Sendable` (checked). All properties are `let`, zero mutable state. The singleton references `Container.shared.appIdentityProvider()` (a cross-target singleton, same pattern as `IdentityClient` in 2.6). Creating a new instance per call is wasteful allocation with zero correctness benefit.
- [x] 2.5 Create `DependencyClients/TrustSessionManagerClient.swift` — wraps `InstantShareTrustSessionManager` (handshake handling, encrypt/decrypt, reset). **Direct instantiation** singleton in `liveValue`. Replaces `InstantShareService`'s ownership of the trust session manager. Exposes `reset()` for cleanup between sessions.
- [x] 2.6 Create `DependencyClients/IdentityClient.swift` — wraps `AppIdentityProviding` and `LocalDeviceIdentifierProviding` for certificate, device identity, and device name access. **Factory bridge** via `Container.shared.appIdentityProvider()` / `Container.shared.localDeviceIdentityProvider()` — these are cross-target singletons.
- [x] 2.7 Create `DependencyClients/InstantShareExtensionContextClient.swift` — new struct wrapping `extensionContext` with three members: `inputItems: [NSExtensionItem]`, `completeRequest: () -> Void`, `cancelRequest: (Error?) -> Void`. `liveValue` reads from a module-level static that ShareViewController sets before creating the store. This replaces the `onCancel`/`onDone` callback pattern entirely — any feature can complete or cancel the extension via DI.

**Note:** `InstantShareServiceClient` is intentionally omitted — `InstantShareService` is removed (section 11). Its state responsibilities go to `InstantShareContext` (section 2b), its trust session manager goes to `TrustSessionManagerClient` (2.5 above).

## 2b. Create InstantShareContext (replaces InstantShareService state)

- [x] 2b.1 Create `Features/InstantShareContext.swift` with:
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

      var payloadClass: InstantSharePayloadClass { ... }
      var targetIntent: String { ... }
  }

  struct SharedImage: Equatable {
      let fileURL: URL; let filename: String; let contentType: String
  }

  struct SharedFile: Equatable {
      let fileURL: URL; let filename: String; let contentType: String
  }
  ```
- [x] 2b.2 Register the in-memory shared key:
  ```swift
  extension SharedReaderKey where Self == InMemoryKey<InstantShareContext>.Default {
      static var instantShareContext: Self {
          Self[.inMemory("instantShareContext"), default: InstantShareContext()]
      }
  }
  ```

## 3. Implement ErrorFeature (simplest, no dependencies on other features)

- [x] 3.1 Create `Features/ErrorFeature.swift` with `@Reducer`, `@ObservableState`, and delegate actions (`.retry`, `.cancel`)
- [x] 3.2 Create `Views/ErrorView.swift` — warning icon, error message text, "Try Again" button → sends `.retry`, "Cancel" button → sends `.cancel`
- [x] 3.3 Write unit tests for ErrorFeature reducer (state transitions for retry/cancel actions)

## 4. Implement CompletionFeature

- [x] 4.1 Create `Features/CompletionFeature.swift` with `@Reducer`, `@ObservableState` (payloadDescription), and delegate action `.done` — FlowFeature handles `.done` by calling `@Dependency(\.instantShareExtensionContext).completeRequest()` to exit the extension, same as existing behavior
- [x] 4.2 Create `Views/CompletionView.swift` — checkmark SF Symbol, "Sent!" title, payload description, "Done" button → sends `.done` (does NOT navigate back to discovery)
- [x] 4.3 Write unit tests for CompletionFeature reducer

## 5. Implement DiscoverFeature

- [x] 5.1 Create `Features/DiscoverFeature.swift` with `@Reducer`, `@ObservableState` (discoveredDevices, selectedDevice, errorMessage, isProcessing), `@Shared(.instantShareContext)`, and dependency clients (MDNSBrowserClient, IdentityClient). Payload loading moves to FlowFeature (section 9). The payload is read from `context.sharedItems` when needed.
- [x] 5.2 Implement `.onAppear` action — triggered by `DiscoverView`'s `.task` modifier. Effect sets `$context.sessionId = UUID().uuidString.lowercased()` (reinit session), then starts mDNS discovery. Payload was already loaded by FlowFeature (section 9.2) into `context.sharedItems`. This replaces the ShareViewController's `startDiscovery()`.
- [x] 5.3 Implement `.onAppear` expiring activity effect — call `ProcessInfo.processInfo.performExpiringActivity` with a reason. When the system fires the expiration handler, send a `.stopDiscovery` action internally. This replaces the `beginRequestExtensionTime()` in ShareViewController.
- [x] 5.4 Implement actions: `.stopDiscovery`, `.devicesUpdated([InstantShareDiscoveredPC])`, `.selectDevice(InstantShareDiscoveredPC)`, `.send`, `.preWarmLocalNetwork`, delegate actions `.didStartPendingRevisit`, `.didEncounterError(String)`. `selectDevice` sets `$context.targetDevice = device`. `preWarmLocalNetwork` reads hosts/port from the selected device in state.
- [x] 5.5 Implement the `send()` reducer effect — no service interaction. Sets `$context.targetDevice` (already set from selection), reads `context.sharedItems` to build the `sessionId` and `correlationId` (both use `context.sessionId`), then sends `.delegate(.didStartPendingRevisit)`. The revisit attempt is handled by PendingRevisitFeature (section 6).
- [x] 5.6 Create `Views/DiscoverView.swift` — payload card (reads `context.sharedItems`), device selector card (mDNS list with radio buttons), error caption, "Send" button with disabled state logic. Uses `.task { store.send(.onAppear) }` to trigger initialization.
- [x] 5.7 Write unit tests for DiscoverFeature reducer: device selection, sessionId reinit on appear, send flow (verify delegate transitions to `.didStartPendingRevisit` after setting context), error during device selection

## 6. Implement PendingRevisitFeature

- [x] 6.1 Create `Features/PendingRevisitFeature.swift` with `@Reducer`, `@ObservableState` (payloadDescription: String), `@SharedReader(.instantShareContext)`, and dependency clients (UploadClient, IdentityClient). Define delegate actions `.revisitSucceeded(payloadDescription: String)` and `.revisitFailed` for FlowFeature to route accordingly.
- [x] 6.2 Implement the `.attemptRevisit` reducer effect — triggered by the view's `.task` modifier. The effect reads `context.sharedItems`, `context.sessionId`, and `context.targetDevice` from `@SharedReader(.instantShareContext)`, derives upload arguments (shared text/images, TLS port from targetDevice), then attempts a direct TLS upload via `UploadClient` using the PC's `tlsPort` (app-layer auth via X-Session-Signature, X-Peer-Device-Id headers) with `context.sessionId` (doubles as correlationId) and the current device name from `@Dependency(\.identityClient)`. On success, sends `.delegate(.revisitSucceeded(payloadDescription:))`. On any error, sends `.delegate(.revisitFailed)` — revisit failure is an expected fallback (no prior trust), not an error-screen error.
- [x] 6.3 Create `Views/PendingRevisitView.swift` — spinner with "Checking existing trust..." status text. No user action buttons (auto-navigates when revisit attempt completes). Uses `.task { store.send(.attemptRevisit) }` to trigger the effect on appear.
- [x] 6.4 Write unit tests for PendingRevisitFeature reducer: successful revisit transfer path, network error path, TLS verification failure path, empty shared data path

## 7. Implement AuthFeature

- [x] 7.1 Create `Features/AuthFeature.swift` with `@Reducer`, `@ObservableState` (pinCode, errorMessage, isProcessing), `@SharedReader(.instantShareContext)`, and dependency clients (TrustClient, UploadClient, TrustSessionManagerClient, IdentityClient). No `InstantShareServiceClient` — `InstantShareService` is removed.
- [x] 7.2 Implement actions: `.pinCodeChanged(String)`, `.confirmPIN`, `.rejectPIN`, `.confirmResponse`, delegate actions `.authCompleted`, `.authFailed(String)`, `.authCancelled`. AuthFeature's `rejectPIN` action calls `@Dependency(\.trustSessionManager).reset()` instead of the old `service.rejectTrust()`, then produces `.delegate(.authCancelled)`. FlowFeature handles `.authCancelled` by calling `context.cancelRequest(nil)` (exits extension, no error page shown).
- [x] 7.3 Implement the `confirmPIN()` reducer effect — replicate the current ViewModel's `confirmPIN()` logic: read `context.sessionId`, `context.targetDevice`, and `context.sharedItems` from `@SharedReader(.instantShareContext)`. Call trustClient.confirm() with sessionId and targetDevice hosts/port. Import peer cert. Upload text/images from `SharedItems` using UploadClient. Handle PIN mismatch (recoverable, stay in AuthFeature).
- [x] 7.4 Handle PIN mismatch recovery — set `errorMessage` and stay in `.awaitingPinInput` state (do not route to ErrorFeature)
- [x] 7.5 Create `Views/AuthView.swift` — "Enter PIN" header, `PinCodeInputView`, error caption, Cancel button. Cancel triggers `.rejectPIN` action → FlowFeature receives `.auth(.delegate(.authCancelled))` → calls `@Dependency(\.instantShareExtensionContext).cancelRequest(nil)` (exits extension immediately). (No callback plumbing needed — exit via context DI.)
- [x] 7.6 Write unit tests for AuthFeature reducer: PIN confirmation, trust handshake success/failure, PIN mismatch recovery, unrecoverable errors

## 8. Implement TransferFeature

- [x] 8.1 Create `Features/TransferFeature.swift` with `@Reducer`, `@ObservableState` (progress: Float), `@SharedReader(.instantShareContext)`, and dependency clients (UploadClient, IdentityClient). No `InstantShareServiceClient`.
- [x] 8.2 Implement actions: `.startTransfer`, `.transferCompleted`, `.transferFailed(String)`, delegate actions `.transferSucceeded`, `.transferFailed(String)`
- [x] 8.3 Implement the `startTransfer` reducer effect — read `context.sessionId`, `context.targetDevice`, and `context.sharedItems` from `@SharedReader(.instantShareContext)`. Upload text or batch images via UploadClient using `targetDevice.tlsPort`, then send `.transferCompleted` on success
- [x] 8.4 Create `Views/TransferView.swift` — spinner (ProgressView), "Sending..." title, progress bar showing batch upload progress, no user action buttons (auto-navigates when done)
- [x] 8.5 Write unit tests for TransferFeature reducer: successful text upload, successful single-image upload, successful batch upload, upload failure paths

## 9. Implement FlowFeature (coordinator)

- [x] 9.1 Create `Features/FlowFeature.swift` with `@Reducer`, `@ObservableState` (Route enum with 6 cases: discover, pendingRevisit, auth, transfer, completion, error), `@Shared(.instantShareContext)`, and `@CasePathable` Action enum that scopes each child's actions.
- [x] 9.2 Implement FlowFeature reducer using `Scope` to route each child action case to the corresponding child reducer. Add an `.onAppear` action that:
    1. Fires `initialize()` via `@Dependency(\.identityClient)`
    2. Loads shared items: reads `inputItems` from `@Dependency(\.instantShareExtensionContext)`, calls `PayloadExtractor.extract(from:)`, writes the result into `$context.sharedItems` with appropriate `SharedItems` case (text/images/files), sets `$context.isLoadingSharedItems = false`
    (Each child feature's view handles its own `.task`/`.onAppear` — FlowFeature does not forward it.)

    Handle delegate actions to transition between route cases:
  - Discover → PendingRevisit (on `.didStartPendingRevisit`) — sets `route = .pendingRevisit(PendingRevisitFeature.State(payloadDescription:))`
  - PendingRevisit → Completion (on `.revisitSucceeded(payloadDescription:)`) — sets `route = .completion(CompletionFeature.State(payloadDescription:))`
  - PendingRevisit → Auth (on `.revisitFailed`) — sets `route = .auth(AuthFeature.State())`
  - Auth → Transfer (on `.authCompleted`) — sets `route = .transfer(TransferFeature.State())`
  - Auth → Error (on `.authFailed(String)`) — sets `route = .error(ErrorFeature.State(message:))`
  - Auth → exit (on `.authCancelled`) — calls `@Dependency(\.instantShareExtensionContext).cancelRequest(nil)` (user tapped Cancel during PIN entry), also resets `@Dependency(\.trustSessionManager).reset()`
  - Transfer → Completion (on `.transferSucceeded`) — sets `route = .completion(CompletionFeature.State(...))`
  - Transfer → Error (on `.transferFailed(String)`) — sets `route = .error(ErrorFeature.State(message:))`
  - Discover → Error (on `.didEncounterError(String)`) — sets `route = .error(ErrorFeature.State(message:))`
  - Error → Discover (on `.retry`) — resets `context` to fresh `InstantShareContext()`, sets `route = .discover(DiscoverFeature.State())`
  - Completion → exit (on `.done`) — calls `@Dependency(\.instantShareExtensionContext).completeRequest()`
  - Error → exit (on `.cancel`) — calls `@Dependency(\.instantShareExtensionContext).cancelRequest(nil)`
- [x] 9.3 Create `Views/FlowView.swift` — switches directly on `store.route` using a `switch` statement. No `.sheet()`, no `.fullScreenCover()`, no NavigationStack. Each case renders the corresponding child view with a scoped store. Uses `.task { store.send(.onAppear) }` to trigger initialization. **No `onCancel`/`onDone` callback parameters** — child views trigger exit via their feature's delegate actions, which FlowFeature handles by calling the InstantShareExtensionContext dependency. FlowView also annotates `@Shared(.instantShareContext)` to propagate the shared context to child views.

## 10. Update ShareViewController (minimal UIKit host)

- [x] 10.1 In `ShareViewController.viewDidLoad`, set up the `InstantShareExtensionContext` static with the extension's `extensionContext` before creating the store:
  ```swift
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
  ```
- [x] 10.2 Create `StoreOf<FlowFeature>` directly (no Factory, no `withDependencies`) — `liveValue` of each dependency handles instantiation. Replace `InstantShareExtensionView` with `FlowView(store:)`:

  ```swift
  let store = Store(initialState: FlowFeature.State(
      route: .discover(DiscoverFeature.State())
  )) {
      FlowFeature()
  }
  let hosting = UIHostingController(rootView: FlowView(store: store))
  ```
- [x] 10.3 Remove all legacy ShareViewController logic: no `loadPayload()`, no `startDiscovery()`, no `initialize()`, no `beginRequestExtensionTime()`, no `cancelAction()`/`doneAction()` methods. These responsibilities have moved to FlowFeature, DiscoverFeature, and the `InstantShareExtensionContext` dependency.

## 11. Remove Legacy Code

- [x] 11.1 Delete `Services/InstantShareService.swift` — entire file removed. `InstantShareService` is replaced by `InstantShareContext` (@Shared) for state and `TrustSessionManagerClient` (dependency) for trust session management.
- [x] 11.2 Delete `DI/Container+ShareExtension.swift` — entire file removed (no Factory DI for ISFromMobile services)
- [x] 11.3 Delete `ViewModels/InstantShareExtensionViewModel.swift` — all logic migrated to TCA features
- [x] 11.4 Delete `Views/InstantShareExtensionView.swift` — replaced by FlowView + child feature views
- [x] 11.5 Remove `InstantShareConnectionConfig` and `InstantShareMetadata` from `Services/InstantShareServices.swift` on the mobile side — these types are no longer needed as such; their fields are derived from `InstantShareContext` + static values. Keep the request/response structs (`InstantShareTrustHandshakeRequest`, etc.) but remove the `metadata` field from each — inline `flowID`, `payloadClass`, `targetIntent`, `trustMode` directly. Alternatively, keep a lightweight helper builder function that produces those fields from `SharedItems`.
- [x] 11.6 Update `InstantShareTrustClient.swift` — remove references to `InstantShareConnectionConfig`. The client now receives `hosts`, `port`, `sessionID`, `correlationID`, and metadata fields directly (read from `InstantShareContext` by the calling feature).
- [x] 11.7 Remove any remaining references to deleted files from Xcode project or build settings

## 12. Build & Verify

- [ ] 12.1 Build the Share Extension target — verify zero compiler errors. Verify `InstantShareService.swift`, `Container+ShareExtension.swift` are no longer compiled.
- [ ] 12.2 Run unit tests for all 7 feature reducers + `InstantShareContext` tests — verify all pass
- [ ] 12.3 Update any existing tests in `InstantShareServicesTests.swift` that reference `InstantShareConnectionConfig`/`InstantShareMetadata` — remove or inline those test cases. Run `mobile/ios/scripts/run_unit_tests.sh` to verify no regressions.
- [ ] 12.4 Manual smoke test: trigger Share Extension in iOS Simulator, verify full flow (discovery → pendingRevisit → auth/trust → transfer → completion) works end-to-end, including the revisit fast-path where pendingRevisit → completion directly.
