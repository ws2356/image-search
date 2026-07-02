## Context

The `InstantShareMiniWindow` (`dt_image_search/instant_sharing/mini_window.py`, 383 lines) uses a monolithic `_refresh_ui()` method that toggles widget visibility based on the current `MiniWindowPhase`. All phases — connecting, negotiating, PIN display, transferring, delivering, success, failure, timeout, abort, busy — share the same layout and are managed through conditional `show()`/`hide()` calls. The `QtWidgets` import list includes 12 classes, most of which are only needed for specific phases.

This monolithic approach makes it difficult to:
- Test individual UI states in isolation
- Add new phases or modify existing ones without risk of regression
- Reason about which widgets are visible in which phase

Consumers (`mini_window_factory.py`) import `MiniWindowPhase`, `_TERMINAL_PHASES`, and `InstantShareMiniWindow` — these public exports must remain available from `mini_window` to avoid breaking imports.

## Goals / Non-Goals

**Goals:**
- Split the monolithic `mini_window.py` into separate widget files under `mobile_to_pc/`, one per logical UI group
- Use a `QStackedWidget` to switch between widgets cleanly based on `MiniWindowPhase`
- Preserve the full public API surface of `InstantShareMiniWindow` (constructor, `apply_session_event`, `show_pin`, `build_phase`, `closeEvent`)
- Keep `MiniWindowPhase`, `MiniWindowState`, and `_TERMINAL_PHASES` importable from `mini_window` (re-export)
- Enable unit testing of each widget independently with a mock state

**Non-Goals:**
- Changing the visual appearance, layout metrics, or behavior of any existing phase
- Refactoring `qr_trigger_mini_window.py` (pc-to-mobile flow is out of scope)
- Adding new UI phases or states
- Introducing new dependencies (PySide6 is already available)
- Changing the event bus or orchestration layer

## Decisions

### 1. Use `QStackedWidget` for phase switching
**Decision**: `InstantShareMiniWindow` will contain a `QStackedWidget` with three child pages, each a `QWidget` subclass. The stacked widget's `setCurrentWidget()` or `setCurrentIndex()` is called based on the phase group.

**Alternatives considered**:
- **Separate `QDialog` per phase**: Would need to manage multiple windows and their lifecycle — too heavyweight.
- **Conditional visibility (current approach)**: Harder to test, harder to reason about, prone to layout bugs.
- **`QStackedLayout`**: Works but `QStackedWidget` is more ergonomic (it's a widget itself) and provides better Qt Designer/QLayout integration.

**Rationale**: `QStackedWidget` is the standard Qt pattern for multi-page dialogs. Each page is a standalone widget that can be developed and tested independently. The index mapping from `MiniWindowPhase` to page is a simple dict lookup — no branching needed.

### 2. Widget boundaries: three groups based on phase semantics

| Widget | Phases | Responsibility |
|--------|--------|----------------|
| `PinCodeWidget` | `DISPLAYING_PIN` | Large PIN digits (36pt bold), device name, Cancel button |
| `LoadingWidget` | `CONNECTING`, `NEGOTIATING`, `TRANSFERRING`, `DELIVERING` | Spinner/icon, message text, progress bar, Cancel button |
| `UploadCompletionWidget` | `SUCCESS`, `FAILED`, `TIMED_OUT`, `ABORTED`, `BUSY` | Result icon, message, error text, action buttons (Dismiss, Copy, Show in Finder) |

**Rationale**: `PinCodeWidget` has the most unique UI (large PIN font, no progress bar). `LoadingWidget` shares the progress bar. `UploadCompletionWidget` handles all terminal states with their action buttons. Grouping by visual/interaction pattern rather than state machine granularity.

### 3. `MiniWindowPhase` and `MiniWindowState` move to `mobile_to_pc/state.py`
**Decision**: These types move to `mobile_to_pc/state.py` and are re-exported from `mini_window.py` for backward compatibility.

**Rationale**: These are the shared data types used by all widgets. Placing them in `state.py` avoids circular imports and makes the data model explicit. Re-exports from `mini_window.py` prevent breaking consumers (`mini_window_factory.py`, `qr_trigger_mini_window_factory.py`) that import `MiniWindowPhase` from `mini_window`.

### 4. Widgets communicate via state, not signals
**Decision**: Each widget receives a `MiniWindowState` instance in a `set_state(state)` method. The parent `InstantShareMiniWindow` calls `set_state` on the active widget after switching pages.

**Alternatives considered**: Qt signals/slots (more boilerplate for this use case), shared state object (less explicit).

**Rationale**: The widgets are owned by the `QStackedWidget` and never need to communicate directly with each other. The parent reads the event, builds a `MiniWindowState`, selects the correct page, and pushes the state to the active widget. Simple and testable.

### 5. Backward-compatible `_TERMINAL_PHASES` re-export
**Decision**: `_TERMINAL_PHASES` remains a module-level constant in `mini_window.py` (imported from `state.py`).

**Rationale**: `mini_window_factory.py` imports `_TERMINAL_PHASES` — it's considered semi-public. Even though it's prefixed with underscore, changing its source would break a consumer.

## Risks / Trade-offs

- **Risk: Widget layout regression** → Mitigation: Visual comparison of widget layouts against the original `_setup_ui()` + `_refresh_ui()` combination. Each widget's layout should be verified against the corresponding condition branches in the old code.
- **Risk: Broken import chain** → Mitigation: Re-export all public symbols from `mini_window.py`. Verify imports compile with `python -c "from dt_image_search.instant_sharing.mini_window import ..."`.
- **Risk: QStackedWidget adds a layout wrapper** → Mitigation: The stacked widget replaces the direct layout, so content margins may shift by one nesting level. Test window dimensions (360×520) and visual appearance.
- **Trade-off**: Three new files for ~200 total lines of code vs. one existing 383-line file. The split adds file overhead but dramatically improves maintainability per widget.
