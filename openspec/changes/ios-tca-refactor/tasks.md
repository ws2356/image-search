## 1. Setup — Add TCA Package Dependency

- [ ] 1.1 Add `swift-composable-architecture` SPM package to the Xcode project (or Package.swift if using SPM-based project structure)
- [ ] 1.2 Verify the package resolves and builds with the ISFromMobile target

## 2. Create Dependency Clients (TCA @Dependency wrappers)

**Wiring rule:** ISFromMobile-only services instantiate directly in `liveValue` (TCA caches per-store). Common/shared services (`Container+Shared.swift`) bridge via `Container.shared`.

- [ ] 2.1 Create `DependencyClients/MDNSBrowserClient.swift` — wraps `InstantShareMDNSBrowser` with `startBrowsing`, `stopBrowsing`, and `discoveredDevices` async stream (bridging Combine publisher to `AsyncStream`). **Direct instantiation** in `liveValue`.
- [ ] 2.2 Create `DependencyClients/PayloadExtractorClient.swift` — wraps `InstantSharePayloadExtractor.extract(from:)` as an async throwing function. **Direct call** (static methods, no instance needed).
- [ ] 2.3 Create `DependencyClients/InstantShareServiceClient.swift` — wraps `InstantShareService` methods (selectPC, setSharedText, setSharedImages, startSession, stopSession, rejectTrust, connectionConfig). **Direct instantiation** in `liveValue` — TCA dependency resolution provides singleton semantics per store.
- [ ] 2.4 Create `DependencyClients/TrustClient.swift` — wraps `InstantShareTrustClient` (handshake, apply, confirm methods). **Direct instantiation** per call (same as current code — TrustClient is ephemeral).
- [ ] 2.5 Create `DependencyClients/UploadClient.swift` — wraps `InstantShareUploadClient` (uploadText, uploadImage, uploadImages). **Direct instantiation** per call (same as current code — UploadClient is ephemeral).
- [ ] 2.6 Create `DependencyClients/IdentityClient.swift` — wraps `AppIdentityProviding` and `LocalDeviceIdentifierProviding` for certificate, device identity, and device name access. **Factory bridge** via `Container.shared.appIdentityProvider()` / `Container.shared.localDeviceIdentityProvider()` — these are cross-target singletons.
- [ ] 2.7 Create `DependencyClients/InstantShareExtensionContextClient.swift` — new struct wrapping `extensionContext` with three members: `inputItems: [NSExtensionItem]`, `completeRequest: () -> Void`, `cancelRequest: (Error?) -> Void`. `liveValue` reads from a module-level static that ShareViewController sets before creating the store. This replaces the `onCancel`/`onDone` callback pattern entirely — any feature can complete or cancel the extension via DI.

## 3. Implement ErrorFeature (simplest, no dependencies on other features)

- [ ] 3.1 Create `Features/ErrorFeature.swift` with `@Reducer`, `@ObservableState`, and delegate actions (`.retry`, `.cancel`)
- [ ] 3.2 Create `Views/ErrorView.swift` — warning icon, error message text, "Try Again" button → sends `.retry`, "Cancel" button → sends `.cancel`
- [ ] 3.3 Write unit tests for ErrorFeature reducer (state transitions for retry/cancel actions)

## 4. Implement CompletionFeature

- [ ] 4.1 Create `Features/CompletionFeature.swift` with `@Reducer`, `@ObservableState` (payloadDescription), and delegate action `.done` — FlowFeature handles `.done` by calling `@Dependency(\.instantShareExtensionContext).completeRequest()` to exit the extension, same as existing behavior
- [ ] 4.2 Create `Views/CompletionView.swift` — checkmark SF Symbol, "Sent!" title, payload description, "Done" button → sends `.done` (does NOT navigate back to discovery)
- [ ] 4.3 Write unit tests for CompletionFeature reducer

## 5. Implement DiscoverFeature

- [ ] 5.1 Create `Features/DiscoverFeature.swift` with `@Reducer`, `@ObservableState` (discoveredDevices, selectedDevice, payloadEnvelopes, errorMessage, isProcessing), and dependency clients (MDNSBrowserClient, PayloadExtractorClient, InstantShareServiceClient, IdentityClient, **InstantShareExtensionContextClient**)
- [ ] 5.2 Implement `.onAppear` action — triggered by `DiscoverView`'s `.task` modifier. Effect reads `inputItems` from `@Dependency(\.instantShareExtensionContext)`, calls `PayloadExtractor.extract(from:)`, stores envelopes in state, then starts mDNS discovery. This replaces the ShareViewController's manual payload loading and discovery start.
- [ ] 5.3 Implement `.onAppear` expiring activity effect — call `ProcessInfo.processInfo.performExpiringActivity` with a reason. When the system fires the expiration handler, send a `.stopDiscovery` action internally. This replaces the `beginRequestExtensionTime()` in ShareViewController.
- [ ] 5.4 Implement actions: `.stopDiscovery`, `.devicesUpdated([InstantShareDiscoveredPC])`, `.selectDevice(InstantShareDiscoveredPC)`, `.send`, `.preWarmLocalNetwork`, delegate actions `.didStartAuth`, `.didEncounterError(String)`
- [ ] 5.5 Implement the `send()` reducer effect — replicate the current ViewModel's `send()` logic: attempt revisit transfer first, fall back to trust handshake (handshake + apply), then send `.delegate(.didStartAuth)` on success
- [ ] 5.6 Create `Views/DiscoverView.swift` — payload card, device selector card (mDNS list with radio buttons), error caption, "Send" button with disabled state logic. Uses `.task { store.send(.onAppear) }` to trigger initialization.
- [ ] 5.7 Write unit tests for DiscoverFeature reducer: device selection, payload loading from context, send flow, revisit transfer success/failure paths

## 6. Implement AuthFeature

- [ ] 6.1 Create `Features/AuthFeature.swift` with `@Reducer`, `@ObservableState` (pinCode, errorMessage, isProcessing), and dependency clients (TrustClient, UploadClient, InstantShareServiceClient, IdentityClient)
- [ ] 6.2 Implement actions: `.pinCodeChanged(String)`, `.confirmPIN`, `.rejectPIN`, `.confirmResponse`, delegate actions `.authCompleted`, `.authFailed(String)`, `.authCancelled`. AuthFeature's `rejectPIN` action calls `service.rejectTrust()` via dependency and produces `.delegate(.authCancelled)`. FlowFeature handles `.authCancelled` by calling `context.cancelRequest(nil)` (exits extension, no error page shown).
- [ ] 6.3 Implement the `confirmPIN()` reducer effect — replicate the current ViewModel's `confirmPIN()` logic: call trustClient.confirm(), import peer cert, upload text/images, handle PIN mismatch (recoverable, stay in AuthFeature)
- [ ] 6.4 Handle PIN mismatch recovery — set `errorMessage` and stay in `.awaitingPinInput` state (do not route to ErrorFeature)
- [ ] 6.5 Create `Views/AuthView.swift` — "Enter PIN" header, `PinCodeInputView`, error caption, Cancel button. Cancel triggers `.rejectPIN` action → FlowFeature receives `.auth(.delegate(.authFailed(...)))` → sets error route. (No callback plumbing needed — exit via context DI.)
- [ ] 6.6 Write unit tests for AuthFeature reducer: PIN confirmation, trust handshake success/failure, PIN mismatch recovery, unrecoverable errors

## 7. Implement TransferFeature

- [ ] 7.1 Create `Features/TransferFeature.swift` with `@Reducer`, `@ObservableState` (progress: Float), and dependency clients (UploadClient, InstantShareServiceClient, IdentityClient)
- [ ] 7.2 Implement actions: `.startTransfer`, `.transferCompleted`, `.transferFailed(String)`, delegate actions `.transferSucceeded`, `.transferFailed(String)`
- [ ] 7.3 Implement the `startTransfer` reducer effect — replicate the upload logic currently in ViewModel's `confirmPIN()` method: upload text or batch images via UploadClient, then send `.transferCompleted` on success
- [ ] 7.4 Create `Views/TransferView.swift` — spinner (ProgressView), "Sending..." title, progress bar showing batch upload progress, no user action buttons (auto-navigates when done)
- [ ] 7.5 Write unit tests for TransferFeature reducer: successful text upload, successful single-image upload, successful batch upload, upload failure paths

## 8. Implement FlowFeature (coordinator)

- [ ] 8.1 Create `Features/FlowFeature.swift` with `@Reducer`, `@ObservableState` (Route enum with 5 cases: discover, auth, transfer, completion, error), and `@CasePathable` Action enum that scopes each child's actions
- [ ] 8.2 Implement FlowFeature reducer using `Scope` to route each child action case to the corresponding child reducer. Add an `.onAppear` action that fires `ensureSelfIdentity()` via `@Dependency(\.identityClient)`, then sends a scoped `.onAppear` to the current child route. Handle delegate actions to transition between route cases:
  - Discover → Auth (on `.didStartAuth`) — sets `route = .auth(AuthFeature.State())`
  - Auth → Transfer (on `.authCompleted`) — sets `route = .transfer(TransferFeature.State())`
  - Auth → Error (on `.authFailed(String)`) — sets `route = .error(ErrorFeature.State(message:))`
  - Auth → exit (on `.authCancelled`) — calls `@Dependency(\.instantShareExtensionContext).cancelRequest(nil)` (user tapped Cancel during PIN entry)
  - Transfer → Completion (on `.transferSucceeded`) — sets `route = .completion(CompletionFeature.State(...))`
  - Transfer → Error (on `.transferFailed(String)`) — sets `route = .error(ErrorFeature.State(message:))`
  - Discover → Error (on `.didEncounterError(String)`) — sets `route = .error(ErrorFeature.State(message:))`
  - Error → Discover (on `.retry`) — sets `route = .discover(DiscoverFeature.State())`
  - Completion → exit (on `.done`) — calls `@Dependency(\.instantShareExtensionContext).completeRequest()`
  - Error → exit (on `.cancel`) — calls `@Dependency(\.instantShareExtensionContext).cancelRequest(nil)`
- [ ] 8.3 Create `Views/FlowView.swift` — switches directly on `store.route` using a `switch` statement. No `.sheet()`, no `.fullScreenCover()`, no NavigationStack. Each case renders the corresponding child view with a scoped store. Uses `.task { store.send(.onAppear) }` to trigger initialization. **No `onCancel`/`onDone` callback parameters** — child views (`CompletionView`, `ErrorView`) trigger exit via their feature's delegate actions, which FlowFeature handles by calling the InstantShareExtensionContext dependency.

## 9. Update ShareViewController (minimal UIKit host)

- [ ] 9.1 In `ShareViewController.viewDidLoad`, set up the `InstantShareExtensionContext` static with the extension's `extensionContext` before creating the store:
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
- [ ] 9.2 Create `StoreOf<FlowFeature>` directly (no Factory, no `withDependencies`) — `liveValue` of each dependency handles instantiation. Replace `InstantShareExtensionView` with `FlowView(store:)`:

  ```swift
  let store = Store(initialState: FlowFeature.State(
      route: .discover(DiscoverFeature.State())
  )) {
      FlowFeature()
  }
  let hosting = UIHostingController(rootView: FlowView(store: store))
  ```
- [ ] 9.3 Remove all legacy ShareViewController logic: no `loadPayload()`, no `startDiscovery()`, no `ensureSelfIdentity()`, no `beginRequestExtensionTime()`, no `cancelAction()`/`doneAction()` methods. These responsibilities have moved to FlowFeature, DiscoverFeature, and the `InstantShareExtensionContext` dependency.

## 10. Remove Legacy Code

- [ ] 10.1 Delete `DI/Container+ShareExtension.swift` — entire file removed (no Factory DI for ISFromMobile services)
- [ ] 10.2 Delete `ViewModels/InstantShareExtensionViewModel.swift` — all logic migrated to TCA features
- [ ] 10.3 Delete `Views/InstantShareExtensionView.swift` — replaced by FlowView + child feature views
- [ ] 10.4 Remove any remaining references to deleted files from Xcode project or build settings

## 11. Build & Verify

- [ ] 11.1 Build the Share Extension target — verify zero compiler errors
- [ ] 11.2 Run unit tests for all 6 feature reducers — verify all pass
- [ ] 11.3 Run snapshot tests — update snapshots if UI changed, then verify clean test run
- [ ] 11.4 Run `mobile/ios/scripts/run_unit_tests.sh` — verify no regressions in broader test suite
- [ ] 11.5 Manual smoke test: trigger Share Extension in iOS Simulator, verify full flow (discovery → auth → transfer → completion) works end-to-end
