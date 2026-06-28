## 1. Design System Infrastructure

- [ ] 1.1 Create DesignSystem module with color constants (background, surface, primary dark, primary blue, success, error, text colors)
- [ ] 1.2 Add typography tokens (heading, body, caption, PIN digit fonts and sizes)
- [ ] 1.3 Create Qt stylesheet helpers for consistent button, card, and text styling
- [ ] 1.4 Create SVG icon resources (lock, checkmark, warning triangle, refresh, folder, copy, chevron)

## 2. Core Component Styling

> **Reminder**: All reusable components MUST live in dedicated modules within `dt_image_search/instant_sharing/mobile_to_pc/`, not co-located with individual screen widgets.

- [ ] 2.1 Create styled button components (primary dark, primary blue, ghost/secondary) in `components/buttons.py`
- [ ] 2.2 Create card component in `components/cards.py` with proper background and border styling
- [ ] 2.3 Create progress indicators and spinners in `components/progress.py`
- [ ] 2.4 Create text label components in `components/labels.py` with proper typography hierarchy

## 3. Screen Redesign - PIN Verification

- [ ] 3.1 Redesign PinCodeWidget with lock icon in yellow/orange rounded square
- [ ] 3.2 Implement styled PIN card container with 4 large digits
- [ ] 3.3 Add progress bar and status text below PIN
- [ ] 3.4 Update "Cancel Request" button to ghost/secondary style

## 4. Screen Redesign - Loading and Error

- [ ] 4.1 Redesign LoadingWidget with blue ring spinner and descriptive text
- [ ] 4.2 Redesign error state in UploadCompletionWidget with warning triangle icon
- [ ] 4.3 Add "Retry" button with refresh icon for error state
- [ ] 4.4 Update loading state heading and subtitle text

## 5. Screen Redesign - Completion

- [ ] 5.1 Redesign file completion with green checkmark circle and file info card
- [ ] 5.2 Implement file info card component with type badge, name, size, and path
- [ ] 5.3 Redesign text completion with text preview card in monospace
- [ ] 5.4 Add "Show in Finder" button (dark navy) and "Copy Text" button (blue)
- [ ] 5.5 Ensure "Close" button uses ghost/secondary style

## 6. Screen Redesign - QR Code

- [ ] 6.1 Redesign QR code container with blue corner bracket accents
- [ ] 6.2 Add "Scan to Receive" heading and "from {hostname}" subtitle
- [ ] 6.3 Style IP:port as rounded pill badge
- [ ] 6.4 Update "Cancel" button to ghost/secondary style

## 7. Integration and Testing

- [ ] 7.1 Update mini_window.py to use new styled components
- [ ] 7.2 Update qr_trigger_mini_window.py to use new styled components
- [ ] 7.3 Test all PC screens with design system colors
- [ ] 7.4 Verify all existing functionality is preserved
- [ ] 7.5 Run unit tests (`dt_image_search/scripts/run_tests.sh`) and ensure they pass
