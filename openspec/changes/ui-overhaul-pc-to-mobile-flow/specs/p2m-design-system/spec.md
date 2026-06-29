## ADDED Requirements

### Requirement: DesignSystem colors
The system SHALL provide a centralized set of color constants matching the ISFromMobile design system.

#### Scenario: Colors are accessible
- **WHEN** accessing DesignSystem.Colors from any ISFromPC view
- **THEN** the correct color values are returned (primary: #3b7dfa, success: #34C759, error: #FF453A)

### Requirement: DesignSystem typography
The system SHALL provide a centralized set of font constants using DM Sans font family.

#### Scenario: Fonts are accessible
- **WHEN** accessing DesignSystem.Typography from any ISFromPC view
- **THEN** the correct font sizes and weights are returned (h1: 24pt bold, h2: 20pt bold, body: 15pt regular)

### Requirement: DesignSystem spacing
The system SHALL provide a centralized set of spacing constants.

#### Scenario: Spacing values are accessible
- **WHEN** accessing DesignSystem.Spacing from any ISFromPC view
- **THEN** the correct spacing values are returned (xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32)

### Requirement: DesignSystem corner radius
The system SHALL provide a centralized set of corner radius constants.

#### Scenario: Corner radius values are accessible
- **WHEN** accessing DesignSystem.CornerRadius from any ISFromPC view
- **THEN** the correct corner radius values are returned (card: 10, button: 14)

### Requirement: PrimaryButton component
The system SHALL provide a reusable PrimaryButton component with primary, secondary, and destructive styles.

#### Scenario: Primary button renders correctly
- **WHEN** PrimaryButton is initialized with style .primary
- **THEN** the button has blue background, white text, and rounded corners

#### Scenario: Secondary button renders correctly
- **WHEN** PrimaryButton is initialized with style .secondary
- **THEN** the button has transparent background, blue text, and rounded corners

#### Scenario: Destructive button renders correctly
- **WHEN** PrimaryButton is initialized with style .destructive
- **THEN** the button has red-tinted background, red text, and rounded corners

#### Scenario: Loading state is disabled
- **WHEN** PrimaryButton is initialized with isLoading: true
- **THEN** the button shows a spinner and is disabled

### Requirement: CardView component
The system SHALL provide a reusable CardView component with card background and border.

#### Scenario: CardView renders correctly
- **WHEN** CardView contains content
- **THEN** the content is wrapped in a light gray card with rounded corners and subtle border

### Requirement: LoadingSpinner component
The system SHALL provide a reusable LoadingSpinner component with centered spinner and text.

#### Scenario: LoadingSpinner renders with default message
- **WHEN** LoadingSpinner is initialized without parameters
- **THEN** it shows a centered spinner with "Connecting..." text

#### Scenario: LoadingSpinner renders with custom message
- **WHEN** LoadingSpinner is initialized with a custom message
- **THEN** it shows a centered spinner with the custom text

### Requirement: TransferProgress component
The system SHALL provide a reusable TransferProgress component showing a linear progress bar with percentage.

#### Scenario: TransferProgress renders at 50%
- **WHEN** TransferProgress is initialized with progress: 0.5
- **THEN** it shows a progress bar filled to 50% with "50%" text below