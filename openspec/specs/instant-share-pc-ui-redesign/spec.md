## Purpose
Complete UI redesign of the PC-side instant-share mini-window, including all screen layouts, component styling, design system implementation, and QR code container.

## Requirements

### Requirement: PC design system implementation
The PC mini-window SHALL implement a design system with specific color tokens, typography, and component styles matching the React design specification.

#### Scenario: Design tokens are accessible
- **WHEN** any PC widget needs to access design colors or typography
- **THEN** the system SHALL provide access via DesignSystem module constants
- **AND** all colors SHALL match the specification: background (#FFFFFF), surface (#F5F7FA), primary dark (#1B2A4A), primary blue (#3478F6)

#### Scenario: Typography follows specification
- **WHEN** text is displayed in any PC screen
- **THEN** the system SHALL use DM Sans font family where available
- **AND** heading size SHALL be ~24px bold
- **AND** body size SHALL be ~16px regular
- **AND** caption size SHALL be ~13px regular
- **AND** PIN digits SHALL use JetBrains Mono at ~44px bold

### Requirement: PC PIN verification screen redesign
The PC PIN verification screen SHALL be redesigned with a lock icon, styled PIN card, and progress indicator.

#### Scenario: PIN display shows correctly
- **WHEN** PC is waiting for PIN verification
- **THEN** screen SHALL show lock icon in yellow/orange rounded square
- **AND** heading SHALL display "Verify Device"
- **AND** subtitle SHALL display description text
- **AND** PIN SHALL be displayed in a styled card container with 4 large digits
- **AND** progress bar SHALL be shown below PIN
- **AND** status text SHALL show "Waiting for PIN entry on iPhone..."
- **AND** "Cancel Request" button SHALL be styled as ghost/secondary

#### Scenario: PIN card styling matches design
- **WHEN** PIN digits are displayed
- **THEN** each digit SHALL be ~44px bold in JetBrains Mono
- **AND** digits SHALL be spaced ~12-16px apart
- **AND** card background SHALL be #F5F7FA
- **AND** card border-radius SHALL be ~16px

### Requirement: PC loading state redesign
The PC loading state SHALL be redesigned with a centered spinner and descriptive text.

#### Scenario: Loading state displays correctly
- **WHEN** PC is establishing connection
- **THEN** screen SHALL show blue ring spinner (~60px)
- **AND** heading SHALL display "Connecting..."
- **AND** subtitle SHALL display "Establishing secure connection to your Mac"
- **AND** background SHALL be white (#FFFFFF)

### Requirement: PC completion screen redesign
The PC completion screen SHALL be redesigned with success icon, file info card, and action buttons.

#### Scenario: File completion displays correctly
- **WHEN** file transfer completes successfully
- **THEN** screen SHALL show green checkmark circle (~60px) with mint background
- **AND** heading SHALL display "File Received"
- **AND** subtitle SHALL display "Saved to your Downloads folder"
- **AND** file info card SHALL show file type badge, name, size, and path
- **AND** two buttons SHALL be shown: "Close" (ghost) and "Show in Finder" (dark navy)

#### Scenario: Text completion displays correctly
- **WHEN** text transfer completes successfully
- **THEN** screen SHALL show green checkmark circle with mint background
- **AND** heading SHALL display "Text Received"
- **AND** subtitle SHALL display "Ready to paste anywhere on your Mac."
- **AND** text preview card SHALL show truncated text in monospace
- **AND** two buttons SHALL be shown: "Close" (ghost) and "Copy Text" (blue)

#### Scenario: Error state displays correctly
- **WHEN** transfer fails or connection is lost
- **THEN** screen SHALL show red warning triangle circle (~60px) with pink background
- **AND** heading SHALL display "Connection Lost"
- **AND** error description SHALL explain the failure
- **AND** "Retry" button SHALL be shown (dark navy with refresh icon)

### Requirement: PC QR code container redesign
The PC QR code display SHALL be redesigned with blue corner bracket accents.

#### Scenario: QR code shows with styled container
- **WHEN** PC displays QR code for mobile scanning
- **THEN** QR code SHALL be in a white card with rounded corners (~16px)
- **AND** blue corner bracket accents SHALL be shown at corners
- **AND** "Scan to Receive" heading SHALL be displayed
- **AND** "from {hostname}" subtitle SHALL be shown
- **AND** IP:port SHALL be displayed in a rounded pill badge
- **AND** "Cancel" button SHALL be styled as ghost/secondary

### Requirement: Component styling consistency
All PC UI components SHALL follow consistent styling patterns defined in the design system.

#### Scenario: Button styling is consistent
- **WHEN** any button is displayed on PC
- **THEN** primary dark buttons SHALL use #1B2A4A background with white text
- **AND** primary blue buttons SHALL use #3478F6 background with white text
- **AND** ghost/secondary buttons SHALL use #F0F4F8 background with dark text
- **AND** all buttons SHALL have pill shape (border-radius ~24px)
- **AND** button height SHALL be ~48px

#### Scenario: Card styling is consistent
- **WHEN** any card component is displayed on PC
- **THEN** cards SHALL use #F5F7FA background
- **AND** border-radius SHALL be ~12-16px
- **AND** padding SHALL be ~16px

### Requirement: Reusable component file organization
Reusable PC UI components SHALL be extracted into dedicated files separate from screen-specific widgets.

#### Scenario: Shared components are in dedicated files
- **WHEN** a UI component is used across multiple PC screens
- **THEN** it SHALL live in a dedicated module within `dt_image_search/instant_sharing/mobile_to_pc/`
- **AND** screen-specific widgets SHALL import and use these shared components
