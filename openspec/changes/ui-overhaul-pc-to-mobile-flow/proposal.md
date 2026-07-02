## Why

The PC-to-Mobile (p2m) instant share flow in the iOS app currently uses outdated UI styling that doesn't match the modern design system. The Mobile-to-PC (m2p) flow has already been updated with a cohesive design system, creating an inconsistent user experience between the two flows. New design mockups are available that define the desired visual treatment for the p2m flow, including updated screens for receiving text, images, and files.

## What Changes

- **Create reusable UI components** for the p2m flow, following the same patterns as ISFromMobile (DesignSystem, PrimaryButton, CardView, etc.)
- **Update QRTransferResultView** to match the new design with updated layout, typography, and styling for text, image, and file results
- **Update MultiFileReceiveView** to use the design system and match the new multi-file download UI
- **Update QRClaimView** loading state with design system styling
- **Apply design tokens** (colors, typography, spacing, corner radius) consistently across all p2m views
- **Maintain existing functionality** while improving visual presentation

## Capabilities

### New Capabilities
- `p2m-design-system`: Centralized design tokens and reusable UI components for the PC-to-Mobile flow
- `p2m-completion-screens`: Updated completion screens for receiving text, images, and files with modern styling

### Modified Capabilities
- None - this is a visual overhaul without changing spec-level behavior

## Impact

- **Affected Files**:
  - `mobile/ios/Sources/ISFromPC/Views/QRTransferResultView.swift`
  - `mobile/ios/Sources/ISFromPC/Views/MultiFileReceiveView.swift`
  - `mobile/ios/Sources/ISFromPC/Views/QRClaimView.swift`
  - `mobile/ios/Sources/ISFromPC/Views/RichTextReceiveView.swift`
- **New Files**:
  - `mobile/ios/Sources/ISFromPC/Views/Components/DesignSystem.swift`
  - `mobile/ios/Sources/ISFromPC/Views/Components/PrimaryButton.swift`
  - `mobile/ios/Sources/ISFromPC/Views/Components/CardView.swift`
  - `mobile/ios/Sources/ISFromPC/Views/Components/ProgressIndicator.swift`
- **Dependencies**: Uses existing ISFromMobile design system as reference
- **Tests**: Unit tests in `mobile/ios/scripts/run_unit_tests.sh` must pass after changes