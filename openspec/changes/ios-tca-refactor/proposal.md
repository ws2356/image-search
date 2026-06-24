## Why

The current `ISFromMobile` codebase uses a monolithic MVVM pattern with a single ViewModel (`InstantShareExtensionViewModel`) and a single View (`InstantShareExtensionView`) that switches content based on a `sessionPhase` enum. This architecture has several problems:

1. **Single responsibility violation** — The ViewModel manages mDNS discovery, device selection, payload extraction, trust handshake, PIN input, upload progress, error handling, and completion — all in one 410-line file.
2. **Poor testability** — Business logic is entangled with Combine subscriptions and async side effects in a single `ObservableObject`, making isolated unit testing difficult.
3. **Unidirectional data flow is ad-hoc** — The `sessionPhase` enum approximates a state machine but lacks the rigor of typed, reducible state transitions.
4. **Error handling is scattered** — Errors surface as phase transitions, optional string messages, and boolean `isProcessing` flags with no consistent policy.

Refactoring to **The Composable Architecture (TCA)** introduces a unidirectional data flow, typed state machines per feature, explicit effect management, and testability as a first-class concern — all while preserving the existing behavior.

## What Changes

- **Replace** the single `InstantShareExtensionViewModel` + `InstantShareExtensionView` with six TCA features:
  - **FlowFeature** — Pure router: owns a `Route` enum, reducer transitions between route cases. FlowView switches on `route` and renders the child directly — no NavigationStack, no presentation modifiers.
  - **DiscoverFeature** — mDNS device discovery, device selection, payload display, and "Send" action. Covers scanning/ready/starting phases.
  - **AuthFeature** — PIN input + trust handshake confirmation/rejection. Covers awaitingPinInput phase.
  - **TransferFeature** — Upload progress indicator with spinner; automatically navigates to CompletionFeature when transfer completes. Covers transferring phase.
  - **CompletionFeature** — Success confirmation with "Done" button that exits the share extension (calls `extensionContext?.completeRequest(...)`).
  - **ErrorFeature** — Full-screen error display with "Retry" (→ Discovery) and "Cancel" buttons.
- **Preserve all existing service-layer code** (`InstantShareService`, `InstantShareMDNSBrowser`, `InstantShareTrustClient`, `InstantShareUploadClient`, etc.) without behavioral changes.
- **Replace Factory DI for ISFromMobile services** — TCA `@Dependency` clients instantiate `InstantShareMDNSBrowser`, `InstantShareService`, etc. directly (no Factory). Common cross-target services (`AppIdentityProviding`, `LocalDeviceIdentifierProviding`) keep their Factory bridge via `Container+Shared.swift`.
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
| **`mobile/ios/Sources/ISFromMobile/Views/`** | `InstantShareExtensionView.swift` replaced by 6 new feature view files |
| **`mobile/ios/Sources/ISFromMobile/ViewModels/`** | `InstantShareExtensionViewModel.swift` removed entirely |
| **`mobile/ios/Sources/ISFromMobile/DI/`** | `Container+ShareExtension.swift` **deleted** entirely — ISFromMobile services instantiated directly by TCA `@Dependency` live values. Only `Common/DI/Container+Shared.swift` remains for cross-target singletons. |  
| **`mobile/ios/Sources/ISFromMobile/DependencyClients/`** | New folder for 7 `@DependencyClient` files, including `InstantShareExtensionContextClient` wrapping the UIKit `extensionContext`. |
| **`mobile/ios/Sources/ISFromMobile/Services/`** | No changes — services remain untouched |
| **`mobile/ios/ShareExtension/ShareViewController.swift`** | Stripped to minimal host — sets `InstantShareExtensionContext` static, creates `Store`, embeds `FlowView(store:)`. No callbacks, no action dispatching, no lifecycle management. |
| **Dependencies** | Need to add `swift-composable-architecture` package dependency to the project |
| **Tests** | New unit tests for each feature's reducer become possible; snapshot tests need updating if view hierarchy changes |
