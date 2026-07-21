## Why

The current `ISFromMobile` codebase uses a monolithic MVVM pattern with a single ViewModel (`InstantShareExtensionViewModel`) and a single View (`InstantShareExtensionView`) that switches content based on a `sessionPhase` enum. This architecture has several problems:

1. **Single responsibility violation** — The ViewModel manages mDNS discovery, device selection, payload extraction, trust handshake, PIN input, upload progress, error handling, and completion — all in one 410-line file.
2. **Poor testability** — Business logic is entangled with Combine subscriptions and async side effects in a single `ObservableObject`, making isolated unit testing difficult.
3. **Unidirectional data flow is ad-hoc** — The `sessionPhase` enum approximates a state machine but lacks the rigor of typed, reducible state transitions.
4. **Error handling is scattered** — Errors surface as phase transitions, optional string messages, and boolean `isProcessing` flags with no consistent policy.

Refactoring to **The Composable Architecture (TCA)** introduces a unidirectional data flow, typed state machines per feature, explicit effect management, and testability as a first-class concern — all while preserving the existing behavior.

## What Changes

- **Replace** the single `InstantShareExtensionViewModel` + `InstantShareExtensionView` with seven TCA features:
  - **FlowFeature** — Pure router: owns a `Route` enum, reducer transitions between route cases. FlowView switches on `route` and renders the child directly — no NavigationStack, no presentation modifiers.
  - **DiscoverFeature** — mDNS device discovery, device selection, payload display, and "Send" action. Covers scanning/ready/starting phases. On send, transitions to PendingRevisitFeature.
  - **PendingRevisitFeature** — Attempts a direct TLS "revisit" transfer (with app-layer signature auth headers) using previously-established trust. On success routes to CompletionFeature directly; on failure falls back to AuthFeature for the full trust handshake.
  - **AuthFeature** — PIN input + trust handshake confirmation/rejection. Covers awaitingPinInput phase.
  - **TransferFeature** — Upload progress indicator with spinner; automatically navigates to CompletionFeature when transfer completes. Covers transferring phase.
  - **CompletionFeature** — Success confirmation with "Done" button that exits the share extension (calls `extensionContext?.completeRequest(...)`).
  - **ErrorFeature** — Full-screen error display with "Retry" (→ Discovery) and "Cancel" buttons.
- **Remove `InstantShareService` entirely** — its state (sessionId, shared text/images, selected device, connection config) moves to `InstantShareContext`, a `@Shared`-based struct passed between features. Its trust session manager becomes a standalone `TrustSessionManagerClient` dependency. `InstantShareConnectionConfig` and `InstantShareMetadata` are also removed from the mobile side (data derived from `InstantShareContext`).
- **Introduce `InstantShareContext`** — a `@Shared` / `@SharedReader`-based struct (`sessionId`, `targetDevice`, `sharedItems`, `isLoadingSharedItems`) shared across features. FlowFeature owns write access (loads payload on appear), DiscoverFeature owns sessionId + targetDevice, other features read via `@SharedReader`.
- **Replace Factory DI for ISFromMobile services** — TCA `@Dependency` clients instantiate `InstantShareMDNSBrowser`, `InstantShareTrustSessionManager`, etc. directly (no Factory). No `InstantShareServiceClient` exists. Common cross-target services (`AppIdentityProviding`, `LocalDeviceIdentifierProviding`) keep their Factory bridge via `Container+Shared.swift`.
- **Delete `Container+ShareExtension.swift`** entirely — no longer needed.
- **Introduce `InstantShareExtensionContext`** — a new `@DependencyClient` wrapping the UIKit `extensionContext` (inputItems, completeRequest, cancelRequest). Set as a module-level static before store creation. All features access extension lifecycle through DI instead of UIKit callback closures — FlowView no longer needs `onCancel`/`onDone` parameters.
- **No new capabilities** — this is a pure architectural refactoring with zero behavioral change to the existing share extension flow.

## Capabilities

### New Capabilities

*(None — this change is purely an internal architectural refactoring with no new user-facing capabilities.)*

### Modified Capabilities

*(None — no existing spec requirements are changing. All existing behavior must be preserved exactly.)*

## Impact

| Area | Impact |
|---|---|
| **`mobile/ios/Sources/ISFromMobile/Features/`** | New folder for 7 TCA feature files + 1 `InstantShareContext.swift` type + 7 view files |
| **`mobile/ios/Sources/ISFromMobile/ViewModels/`** | `InstantShareExtensionViewModel.swift` removed entirely |
| **`mobile/ios/Sources/ISFromMobile/DI/`** | `Container+ShareExtension.swift` **deleted** entirely — no Factory DI for ISFromMobile services. Only `Common/DI/Container+Shared.swift` remains for cross-target singletons. |  
| **`mobile/ios/Sources/ISFromMobile/DependencyClients/`** | New folder for 6 `@DependencyClient` files (MDNSBrowser, PayloadExtractor, Trust, Upload, TrustSessionManager, Identity, InstantShareExtensionContext). No `InstantShareServiceClient`. |
| **`mobile/ios/Sources/ISFromMobile/Services/`** | `InstantShareService.swift` **deleted**. `InstantShareConnectionConfig` and `InstantShareMetadata` types removed from `InstantShareServices.swift` (request/response structs kept, with metadata inlined). |
| **`mobile/ios/ShareExtension/ShareViewController.swift`** | Stripped to minimal host — sets `InstantShareExtensionContext` static, creates `Store`, embeds `FlowView(store:)`. No callbacks, no action dispatching, no lifecycle management. |
| **Dependencies** | Need to add `swift-composable-architecture` package dependency to the project |
| **Tests** | New unit tests for 7 feature reducers + InstantShareContext tests. Existing `InstantShareServicesTests` updated to remove `InstantShareConnectionConfig`/`InstantShareMetadata` test cases. |
