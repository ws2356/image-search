## 1. Create subfolder structure

- [ ] 1.1 Create `dt_image_search/instant_sharing/mobile_to_pc/` directory with `__init__.py`
- [ ] 1.2 Create `state.py` with `MiniWindowPhase` enum, `MiniWindowState` dataclass, `_phase_message()` helper, `_phase_icon()` helper, `_payload_label()` helper, and `_TERMINAL_PHASES` frozenset (moved from `mini_window.py`)

## 2. Create PinCodeWidget

- [ ] 2.1 Create `pin_code_widget.py` with `PinCodeWidget(QWidget)` class containing:
  - Phase icon label (🔑)
  - Message label ("Verify this PIN matches the one on your iPhone:")
  - PIN label (36pt bold, centered)
  - Cancel button (emits `cancelled` signal)
  - `set_state(state: MiniWindowState)` method that updates all labels
- [ ] 2.2 Back the Cancel button with a Qt signal (`cancelled`) connected to the abort handler

## 3. Create LoadingWidget

- [ ] 3.1 Create `loading_widget.py` with `LoadingWidget(QWidget)` class containing:
  - Phase icon label (📡/🔐/⬇️/💾)
  - Title label ("Instant Share")
  - Message label (word-wrap, min height 48px)
  - Progress bar (indeterminate for connecting/negotiating, determinate for transferring)
  - Cancel button (visible during active phases only)
  - `set_state(state: MiniWindowState)` method that updates widgets based on phase

## 4. Create UploadCompletionWidget

- [ ] 4.1 Create `upload_completion_widget.py` with `UploadCompletionWidget(QWidget)` class containing:
  - Phase icon label (✅/❌/⏰/🛑/⏳)
  - Message label
  - Error label (red text, shown for FAILED/TIMED_OUT/ABORTED)
  - Progress bar (100% for SUCCESS, hidden for error phases)
  - Dismiss button (always visible on terminal phases)
  - Copy to Clipboard button (visible on SUCCESS with text content)
  - Show in Finder button (visible on SUCCESS with file path)
  - `set_state(state: MiniWindowState)` method that updates widgets based on phase
  - Signals for dismiss, copy, and show-in-finder actions

## 5. Refactor mini_window.py

- [ ] 5.1 Replace imports from PySide6 with imports from new `mobile_to_pc` modules
- [ ] 5.2 Remove `MiniWindowPhase`, `MiniWindowState`, `_TERMINAL_PHASES`, `_phase_message()`, `_phase_icon()`, `_payload_label()` — import from `mobile_to_pc/state.py` and re-export
- [ ] 5.3 Add `QStackedWidget` to `_setup_ui()` with three child pages (PinCodeWidget, LoadingWidget, UploadCompletionWidget)
- [ ] 5.4 Replace `_refresh_ui()` logic with phase-to-page index mapping and `set_state()` dispatch to active widget
- [ ] 5.5 Preserve `apply_session_event()`, `show_pin()`, `build_phase()`, `closeEvent()` signatures and behavior
- [ ] 5.6 Verify `mini_window_factory.py` imports (`InstantShareMiniWindow`, `MiniWindowPhase`, `_TERMINAL_PHASES`) continue to work
- [ ] 5.7 Verify `__init__.py` imports (`InstantShareMiniWindow`, `MiniWindowPhase`, `MiniWindowState`) continue to work

## 6. Verify

- [ ] 6.1 Run `python -c "from dt_image_search.instant_sharing.mini_window import InstantShareMiniWindow, MiniWindowPhase, MiniWindowState, _TERMINAL_PHASES"` to confirm backward compatibility
- [ ] 6.2 Run `python -c "from dt_image_search.instant_sharing import InstantShareMiniWindow, MiniWindowPhase, MiniWindowState"` to confirm package-level exports
- [ ] 6.3 Run `python dt_image_search/main.py` (or equivalent smoke test) to confirm UI renders correctly
