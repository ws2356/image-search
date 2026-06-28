## ADDED Requirements

### Requirement: Dark theme design system implementation
The system SHALL implement a dark theme design system with specific color tokens, typography, and component styles matching the React design specification.

#### Scenario: Design tokens are accessible
- **WHEN** any view needs to access design colors or typography
- **THEN** the system SHALL provide type-safe access via DesignSystem namespace
- **AND** all colors SHALL match the specification: background (#090b12), foreground (#e8eaf0), primary (#3b7dfa)

#### Scenario: Typography follows specification
- **WHEN** text is displayed in any screen
- **THEN** the system SHALL use DM Sans font family with weights 300-700
- **AND** base font size SHALL be 15px equivalent
- **AND** heading hierarchy SHALL follow specification (h1: 2xl, h2: xl, h3: lg, h4: base)

### Requirement: Device discovery screen redesign
The device discovery screens SHALL be redesigned to match the new design specification with three states: empty, scanning, and found.

#### Scenario: Empty state displays correctly
- **WHEN** no devices are discovered
- **THEN** the screen SHALL show "No Devices Found" with dashed zone styling
- **AND** send button SHALL be disabled
- **AND** background SHALL use deep navy color (#090b12)

#### Scenario: Scanning state displays correctly
- **WHEN** device discovery is in progress
- **THEN** the screen SHALL show pulse-animated "Scanning..." badge
- **AND** spinner SHALL be displayed in search row
- **AND** animation SHALL match React design specification

#### Scenario: Found state displays correctly
- **WHEN** devices are discovered
- **THEN** device cards SHALL show device name with blue check circle for selected device
- **AND** "Send to [Device]" CTA button SHALL be enabled
- **AND** card styling SHALL match design specification

### Requirement: PIN entry screen redesign
The PIN entry screen SHALL be redesigned with phone-style numeric keypad and visual feedback.

#### Scenario: PIN input displays correctly
- **WHEN** user needs to enter PIN
- **THEN** 4-digit PIN boxes SHALL show visual states: empty (dim placeholder), active (blue glow ring), filled (bold digit)
- **AND** keypad SHALL have sub-labels (ABC/DEF/etc.) on digit keys 2-9
- **AND** cancel button SHALL clear all digits

#### Scenario: PIN entry animations work correctly
- **WHEN** user enters or removes digits
- **THEN** active digit box SHALL show blue glow ring animation
- **AND** filled digits SHALL display with bold styling
- **AND** transitions SHALL be smooth and responsive

### Requirement: Completion screen redesign
The completion screen SHALL be redesigned with success animations and file summary.

#### Scenario: Success state displays correctly
- **WHEN** transfer completes successfully
- **THEN** screen SHALL show "Sent!" with green checkmark
- **AND** concentric ring animation SHALL play
- **AND** file summary SHALL be displayed below success message
- **AND** "Done" button SHALL use primary color (#3b7dfa) background, matching all other primary CTA buttons across the flow

#### Scenario: Success animation timing
- **WHEN** completion screen appears
- **THEN** checkmark animation SHALL complete within 1 second
- **AND** concentric rings SHALL animate outward
- **AND** animation SHALL not block user interaction

### Requirement: Loading and error state redesign
Loading and error states SHALL be redesigned with consistent styling matching the design system.

#### Scenario: Loading state displays correctly
- **WHEN** system is processing
- **THEN** centered spinner SHALL be displayed with "Connecting..." text
- **AND** spinner SHALL use primary color (#3b7dfa)
- **AND** background SHALL maintain dark theme

#### Scenario: Error state displays correctly
- **WHEN** an error occurs
- **THEN** red alert icon SHALL be displayed with error message
- **AND** "Try Again" button SHALL be styled with primary color
- **AND** error message SHALL be readable against dark background

### Requirement: Component styling consistency
All UI components SHALL follow consistent styling patterns defined in the design system.

#### Scenario: Button styling is consistent
- **WHEN** any button is displayed
- **THEN** primary buttons SHALL use primary color (#3b7dfa) background
- **AND** secondary buttons SHALL use secondary styling
- **AND** disabled states SHALL have reduced opacity

#### Scenario: Card styling is consistent
- **WHEN** any card component is displayed
- **THEN** cards SHALL use card background color (#111420)
- **AND** border radius SHALL be 10px (0.625rem)
- **AND** border SHALL use subtle white border (rgba(255,255,255,0.07))

### Requirement: Reusable component file organization
Reusable UI components SHALL be extracted into dedicated files separate from screen-specific views. This ensures components can be shared across screens and tested in isolation.

#### Scenario: Shared components are in dedicated files
- **WHEN** a UI component is used across multiple screens (e.g., PrimaryButton, CardView, ProgressIndicator)
- **THEN** it SHALL live in a dedicated `Components/` directory within `ISFromMobile/Features/Views/`
- **AND** screen-specific views SHALL import and use these shared components rather than duplicating styling logic