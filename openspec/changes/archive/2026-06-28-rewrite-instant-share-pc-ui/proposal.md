## Why

The current PC-side mini-window UI for instant-share uses basic PySide6 widgets with emoji icons, system colors, and inconsistent styling. The new design specification introduces a polished, custom-styled UI with specific design tokens (white background, dark navy/blue accents), designed vector icons, card-based layouts, and distinct screens for different completion states (file, text, error). This rewrite brings the PC UI to visual parity with the new design system and improves the user experience across all instant-share flows.

## What Changes

- **Complete UI overhaul** of the PC-side mini-window for both mobile-to-PC and PC-to-mobile flows
- **New design system adoption**: Custom color palette (white background, dark navy primary, blue accent), typography (DM Sans, JetBrains Mono), and component styles
- **Screen redesign**: Updated layouts for PIN verification, loading, completion (file/text/error), and QR code display
- **New screens**: PC idle state, file info cards, text preview cards, blue corner bracket QR container
- **Icon system**: Replace emoji-based icons (🔑, ☑️) with designed vector icons (lock, checkmark, warning triangle)
- **Component styling**: Custom pill-shaped buttons, card containers, progress indicators matching the design spec
- **File preview**: Add file info cards with type badges, size, and path on completion screens

## Capabilities

### New Capabilities
- `instant-share-pc-ui-redesign`: Complete UI redesign of the PC-side instant-share mini-window, including all screen layouts, component styling, design system implementation, and icon updates

### Modified Capabilities
- (none — this is a visual-only rewrite with no protocol or behavior changes)

## Impact

- **Affected code**: All PySide6 widget files in `dt_image_search/instant_sharing/mobile_to_pc/` (pin_code_widget.py, loading_widget.py, upload_completion_widget.py) and `dt_image_search/instant_sharing/` (mini_window.py, qr_trigger_mini_window.py)
- **Design system**: New design tokens and styling patterns that may affect shared UI components
- **Testing**: Unit tests in `mobile/ios/scripts/run_unit_tests.sh` must continue passing (PC-side changes should not affect iOS tests)
- **Dependencies**: No new Python dependencies required; uses existing PySide6 and qrcode libraries
