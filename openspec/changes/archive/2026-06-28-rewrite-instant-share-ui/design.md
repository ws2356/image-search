## Context

The current instant-share mobile-to-pc UI on iOS uses standard SwiftUI components with basic Material design styling. The React-based design specification (`ui-design/instant-share/figma-design`) introduces a custom dark theme with specific design tokens, refined typography, and polished component styles. The iOS implementation needs to be rewritten to match this new design system while preserving the existing Composable Architecture (TCA) state management and business logic.

Current state:
- iOS views in `mobile/ios/Sources/ISFromMobile/Features/Views/` use SwiftUI with TCA
- Basic styling with standard Material colors and system fonts
- Functional but visually inconsistent with the new design specification

Constraints:
- Must maintain existing TCA architecture and state management
- Must preserve all existing functionality (discovery, trust, transfer, completion)
- Must work within SwiftUI's rendering capabilities
- Must support both light and dark mode (though new design is dark-first)

## Goals / Non-Goals

**Goals:**
- Implement the new dark theme design system with specific color tokens
- Adopt DM Sans typography with specified weights and sizes
- Redesign all mobile-to-pc screens to match the React design specification
- Create reusable styled components that follow the design system
- Maintain pixel-perfect fidelity to the design screenshots
- Preserve all existing business logic and state management

**Non-Goals:**
- Changing the underlying TCA architecture or state flow
- Modifying business logic for discovery, trust, or transfer protocols
- Implementing PC-side UI changes (separate scope)
- Adding new features beyond visual redesign
- Changing navigation flow or screen sequence

## Decisions

### Decision 1: Design Token Implementation
**Choice**: Create a SwiftUI `DesignSystem` namespace with static color and typography constants
**Rationale**: Provides type-safe access to design tokens, enables easy updates, and follows SwiftUI best practices
**Alternatives considered**:
- Environment values: More dynamic but adds complexity for static tokens
- Asset catalogs: Less flexible for programmatic styling
- CSS-like variables: Not native to SwiftUI

### Decision 2: Component Styling Approach
**Choice**: Create extension methods on SwiftUI views for consistent styling, with reusable components in a dedicated `Components/` directory
**Rationale**: Allows applying styles like `.cardStyle()` or `.primaryButtonStyle()` while preserving view composition. Dedicated component files prevent duplication across screens and enable independent testing.
**Alternatives considered**:
- Custom view wrappers: More abstraction but harder to compose
- ViewModifier protocols: Similar but extensions are more discoverable
- In-line styling: Violates design system consistency
- Components co-located with screens: Leads to duplication when the same component appears in multiple views

### Decision 3: Typography Implementation
**Choice**: Use custom font registration with DM Sans weights (300-700)
**Rationale**: Matches the design specification's typography system exactly
**Alternatives considered**:
- System fonts: Simpler but doesn't match design
- SF Pro with weights: Apple's default but different from design
- Mixed approach: Inconsistent across screens

### Decision 4: Dark Theme Handling
**Choice**: Implement dark theme as primary with light theme support via color adaptation
**Rationale**: New design is dark-first but iOS requires light mode support for accessibility
**Alternatives considered**:
- Dark-only: Rejected due to iOS accessibility guidelines
- Separate theme files: More maintenance overhead
- Dynamic colors: Over-engineering for current needs

### Decision 5: Animation and Transition Patterns
**Choice**: Implement subtle animations matching React design (pulse effects, progress indicators)
**Rationale**: Enhances user experience without over-engineering
**Alternatives considered**:
- Static UI: Simpler but less polished
- Complex animations: Performance impact on older devices
- No animations: Inconsistent with design specification

## Risks / Trade-offs

### Risk 1: Font Registration Complexity
**Mitigation**: Use system font fallbacks if custom font loading fails, implement font registration in app delegate

### Risk 2: Design Token Maintenance
**Mitigation**: Centralize all design tokens in single file, document token usage patterns

### Risk 3: SwiftUI Limitations
**Mitigation**: Identify complex UI patterns early, create custom components for design elements that don't map to standard SwiftUI

### Risk 4: Performance Impact
**Mitigation**: Profile custom drawing code, use efficient rendering techniques, test on older devices

### Risk 5: Design Drift
**Mitigation**: Create component library with documentation, regular design review checkpoints

#### Caught Instance: Button Color Inconsistency
Design screenshots showed the completion screen "Done" button as dark navy (#1C1C2E) while all other primary CTAs (e.g., "Send to MacBook Pro") used blue (#3b7dfa). This was identified as unintentional during design review. Resolution: all primary action buttons SHALL use the primary color (#3b7dfa). See task 5.3.