// Re-exports the remote Swift package dependencies that the InstantShare app
// and its tests rely on, so they can be consumed transitively through `Common`
// instead of as direct Xcode Swift package product dependencies.
//
// This matters because Xcode wraps directly-referenced remote SPM products as
// dynamic frameworks for app/test-host targets, which triggers a
// NonisolatedNonsendingByDefault variant mismatch in xctest-dynamic-overlay
// under Xcode 26 (see InstantShare link error). Consuming them transitively
// through a local package keeps them on SPM's static build path.
@_exported import ComposableArchitecture
@_exported import Dependencies
@_exported import IdentifiedCollections
@_exported import ConcurrencyExtras
