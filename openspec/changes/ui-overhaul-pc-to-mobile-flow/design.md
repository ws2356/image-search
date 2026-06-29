## Context

The PC-to-Mobile (p2m) instant share flow in the iOS app currently uses default SwiftUI styling with hardcoded colors, fonts, and spacing. This creates an inconsistent experience compared to the Mobile-to-PC (m2p) flow, which has already been updated with a modern design system. The m2p flow uses a centralized DesignSystem with reusable components like PrimaryButton, CardView, and ProgressIndicator.

**Current State:**
- ISFromPC views use ad-hoc styling with system fonts and colors
- No centralized design tokens
- No reusable UI components
- QRTransferResultView uses mixed styling patterns
- MultiFileReceiveView has basic styling with system gray colors
- QRClaimView is a simple progress spinner

**Reference:**
- ISFromMobile/Features/Views/Components/ contains the existing design system
- ui-design/instant-share/screenshots/new/ contains target design screenshots
- ui-design/instant-share/figma-design/src/app/App.tsx contains the React reference implementation

## Goals / Non-Goals

**Goals:**
- Create a reusable design system for ISFromPC matching ISFromMobile patterns
- Update all p2m views (QRTransferResultView, MultiFileReceiveView, QRClaimView) to use the design system
- Match the visual design from the new screenshots
- Maintain existing functionality and business logic
- Ensure unit tests pass after changes

**Non-Goals:**
- Changing business logic or state management
- Adding new features
- Modifying the ISFromMobile design system
- Changing API contracts or data models
- Supporting dark mode (deferred, same as ISFromMobile)

## Decisions

### 1. Design System Architecture

**Decision:** Create a local DesignSystem in ISFromPC that mirrors ISFromMobile's DesignSystem structure.

**Rationale:** 
- ISFromPC and ISFromMobile are separate modules in the iOS app
- Creating a shared design system would require refactoring module boundaries
- Mirroring the structure ensures consistency while keeping modules independent
- Future consolidation is possible if the codebase moves to a shared UI library

**Alternatives:**
- Extract design system to a shared Common module → Requires more refactoring, higher risk
- Import ISFromMobile module → Creates dependency from p2m to m2m flow, which should be independent

### 2. Component Reusability

**Decision:** Create reusable UI components (PrimaryButton, CardView, ProgressIndicator) in ISFromPC/Views/Components/

**Rationale:**
- Following the ISFromMobile pattern ensures consistency
- Components are simple and self-contained
- Each component should have a clear single responsibility
- Preview blocks enable isolated testing

### 3. QRTransferResultView Layout

**Decision:** Restructure QRTransferResultView to use CardView for content containers, PrimaryButton for actions, and DesignSystem typography.

**Key changes:**
- Text content: Scrollable text in CardView with copy button below
- Image content: Hero image with Save/Share buttons in bottom bar
- File content: File icon with metadata in CardView, action buttons below
- Link content: Link icon with URL in CardView, copy/open buttons

### 4. MultiFileReceiveView Updates

**Decision:** Apply DesignSystem colors and typography, use CardView for file rows, and update progress indicators.

**Key changes:**
- Header banner: Use DesignSystem colors for status indicators
- File rows: Use CardView with selection state
- Progress bar: Use TransferProgress component
- Action buttons: Use PrimaryButton

### 5. QRClaimView Loading State

**Decision:** Replace simple ProgressView with LoadingSpinner component that includes instructional text.

### 6. Toast Notifications

**Decision:** Keep existing toast implementation but update styling to use DesignSystem tokens.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Duplicate code between ISFromPC and ISFromMobile | Acceptable for now; future refactoring to shared module possible |
| Design token mismatches between modules | Keep tokens in sync manually; document differences |
| Unit test failures due to UI changes | Run tests after each component change, fix failures immediately |
| Snapshot test failures | Update snapshots using record mode after intentional UI changes |
| Layout issues on different screen sizes | Use DesignSystem spacing constants and SwiftUI's flexible layouts |