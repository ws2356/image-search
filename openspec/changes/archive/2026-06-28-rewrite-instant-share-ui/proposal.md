## Why

The current instant-share mobile-to-pc UI on iOS uses a basic Material design with standard SwiftUI components. The new design introduces a custom dark theme with specific design tokens (deep navy background, blue primary accent), refined typography (DM Sans font family), and polished component styles that align with the React-based design specification. This rewrite will bring the iOS UI to high fidelity with the new design system, improving visual consistency and user experience across platforms.

## What Changes

- **Complete UI overhaul** of all mobile-to-pc screens in the ISFromMobile module
- **New design system adoption**: Custom dark theme with specific color palette, typography, and component styles
- **Screen redesign**: Updated layouts for device discovery (empty/scanning/found states), PIN entry, completion, loading, and error states
- **Component styling**: Custom styled buttons, cards, progress indicators, and status elements matching the React design spec
- **Typography update**: Adoption of DM Sans font family with specified weights and sizes
- **Color system implementation**: Deep navy background (#090b12), blue primary (#3b7dfa), and supporting color tokens

## Capabilities

### New Capabilities
- `instant-share-mobile-ui-redesign`: Complete UI redesign of the mobile-to-pc instant-share flow on iOS, including all screen layouts, component styling, and design system implementation

### Modified Capabilities
- `instant-share-secure-discovery-trust`: Minor UI adjustments to accommodate new design system while preserving existing trust and discovery protocol behavior

## Impact

- **Affected code**: All SwiftUI views in `mobile/ios/Sources/ISFromMobile/Features/Views/` (DiscoverView, AuthView, TransferView, CompletionView, ErrorView, PendingRevisitView, FlowView)
- **Design system**: New design tokens and styling patterns that may affect shared UI components
- **Testing**: Unit tests in `mobile/ios/Tests/AlbumTransporterKitTests/` may need updates for UI changes
- **Dependencies**: No new dependencies required; uses existing SwiftUI and Composable Architecture