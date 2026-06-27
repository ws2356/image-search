## Why

The `mini_window.py` file has grown to 383 lines handling all UI phases (connecting, PIN display, progress, success, errors) in a single class with a monolithic `_refresh_ui()` method that uses conditional visibility toggling. This makes the code hard to maintain, test, or extend — every new state or UI variant requires patching the same file and function with more conditionals. Splitting into focused widget files will improve readability, enable isolated unit testing, and make it easier to add new UI states in the future.

## What Changes

- Create `dt_image_search/instant_sharing/mobile_to_pc/` subfolder
- Move `MiniWindowPhase` enum and `MiniWindowState` dataclass into `mobile_to_pc/state.py`
- Create three standalone widget files in `mobile_to_pc/`:
  - `pin_code_widget.py` — displays the 6-digit PIN code prominently for phone verification
  - `loading_widget.py` — shows connecting/negotiating/transferring progress with progress bar
  - `upload_completion_widget.py` — shows success, failure, timeout, aborted, and busy terminal states
- Refactor `InstantShareMiniWindow` in `mini_window.py` to use a `QStackedWidget` that switches between the three widgets based on phase
- Keep the public API of `InstantShareMiniWindow` (`apply_session_event`, `show_pin`, `build_phase`) unchanged so consumers (`mini_window_factory.py`, `qr_trigger_mini_window_factory.py`) work without modification

## Capabilities

### New Capabilities
- `mobile-to-pc-ui`: The mobile-to-PC instant share UI widgets (PIN display, loading/progress, upload completion) as isolated, composable components within a stacked-widget architecture.

### Modified Capabilities
*(No existing spec-level requirements are changing — this is purely an internal UI refactor.)*

## Impact

- **Modified**: `dt_image_search/instant_sharing/mini_window.py` — refactored to use `QStackedWidget` with three child widgets; `MiniWindowPhase` and `MiniWindowState` relocated to `mobile_to_pc/state.py`
- **New files**:
  - `dt_image_search/instant_sharing/mobile_to_pc/__init__.py`
  - `dt_image_search/instant_sharing/mobile_to_pc/state.py`
  - `dt_image_search/instant_sharing/mobile_to_pc/pin_code_widget.py`
  - `dt_image_search/instant_sharing/mobile_to_pc/loading_widget.py`
  - `dt_image_search/instant_sharing/mobile_to_pc/upload_completion_widget.py`
- **Imports**: `mini_window_factory.py` currently imports `MiniWindowPhase` and `_TERMINAL_PHASES` from `mini_window` — these will need to be re-exported from `mini_window.py` or import from the new location
- **No dependency changes**: no new third-party dependencies required
- **Testing**: each widget can be unit-tested independently with mocked `MiniWindowState`
