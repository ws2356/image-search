## Context

The PC-side instant-share mini-window is implemented in PySide6 (Qt for Python) using native widgets. The current implementation uses basic styling with emoji icons, system colors, and minimal visual polish. The new design specification (from `ui-design/instant-share/figma-design/`) defines a custom dark-themed UI with specific design tokens, vector icons, card-based layouts, and distinct screen states.

Current state:
- `mini_window.py`: Main QDialog with QStackedWidget routing (PIN → Loading → Completion)
- `pin_code_widget.py`: PIN display with emoji icon and basic label
- `loading_widget.py`: Progress bar with phase emoji and cancel button
- `upload_completion_widget.py`: Result display with emoji icons
- `qr_trigger_mini_window.py`: QR code display for PC-to-mobile flow

Constraints:
- Must preserve existing PySide6/Qt architecture and event bus communication
- Must maintain all existing functionality (PIN display, loading states, completion, QR)
- Must work on macOS (primary platform) with potential Linux/Windows support
- Must not affect iOS-side code or tests

## Goals / Non-Goals

**Goals:**
- Implement the new design system with specific color tokens and typography
- Redesign all PC mini-window screens to match the new design specification
- Create reusable styled components (buttons, cards, progress indicators)
- Replace emoji icons with designed vector icons
- Add file info cards and text preview cards on completion screens
- Add blue corner bracket accents on QR code container
- Ensure all existing functionality is preserved

**Non-Goals:**
- Changing the underlying event bus or state machine architecture
- Modifying protocol-level behavior (discovery, trust, transfer)
- Implementing mobile-side UI changes (separate scope)
- Adding new features beyond visual redesign
- Changing window lifecycle or auto-close behavior

## Decisions

### Decision 1: Design Token Implementation
**Choice**: Create a Python `DesignSystem` module with static color and typography constants
**Rationale**: Provides centralized access to design tokens, enables easy updates, and follows the pattern established in the iOS implementation
**Alternatives considered**:
- CSS stylesheets: Not native to PySide6
- Inline constants: Violates design system consistency
- External config files: Adds runtime overhead

### Decision 2: Component Styling Approach
**Choice**: Create Qt stylesheet (QSS) helpers and widget subclasses for consistent styling
**Rationale**: Qt stylesheets provide CSS-like styling for native widgets, enabling consistent visual appearance across all components
**Alternatives considered**:
- Custom painting: More flexible but harder to maintain
- Widget subclasses only: Limited styling control
- External theme engine: Over-engineering for current needs

### Decision 3: Icon System
**Choice**: Use SVG icons rendered via Qt's SVG support or QPainter
**Rationale**: SVG icons scale cleanly, can be styled with design system colors, and replace emoji inconsistencies
**Alternatives considered**:
- Icon font: Requires bundling, less flexible
- PNG icons: Don't scale, require multiple sizes
- Unicode symbols: Limited set, inconsistent rendering

### Decision 4: Typography Implementation
**Choice**: Use system font with DM Sans as preferred, JetBrains Mono for PIN display
**Rationale**: DM Sans matches the design specification; JetBrains Mono provides clear PIN readability; system font fallback ensures compatibility
**Alternatives considered**:
- Bundle DM Sans: Increases package size
- Use only system fonts: Doesn't match design spec
- Custom font loading: Adds complexity

### Decision 5: QR Code Container
**Choice**: Create a custom QWidget with painted blue corner brackets around the QR code
**Rationale**: The blue corner brackets are a distinctive design element that differentiates the new design from the old plain QR display
**Alternatives considered**:
- Simple border: Doesn't match design
- Image overlay: Less flexible, harder to maintain
- CSS borders: Not applicable in Qt widgets

## Risks / Trade-offs

### Risk 1: Font Availability
**Mitigation**: Use system font as fallback if DM Sans is not available; document font installation requirements

### Risk 2: SVG Icon Rendering Performance
**Mitigation**: Cache rendered icons, use simple SVG paths, test on target platforms

### Risk 3: Qt Stylesheet Limitations
**Mitigation**: Identify complex styling patterns early; use custom painting for elements that can't be styled via QSS

### Risk 4: Cross-Platform Consistency
**Mitigation**: Test on macOS (primary), document any platform-specific rendering differences

### Risk 5: Design Drift
**Mitigation**: Create component library with documentation, regular design review checkpoints
