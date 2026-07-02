## 1. Create subfolder structure

- [x] 1.1 Create `dt_image_search/instant_sharing/mobile_to_pc/` directory with `__init__.py`
- [x] 1.2 Create `state.py` with `MiniWindowPhase` enum, `MiniWindowState` dataclass, `_phase_message()` helper, `_phase_icon()` helper, `_payload_label()` helper, and `_TERMINAL_PHASES` frozenset (moved from `mini_window.py`)

## 2. Create PinCodeWidget

- [x] 2.1 Create `pin_code_widget.py` with `PinCodeWidget(QWidget)` class
- [x] 2.2 Back the Cancel button with a Qt signal (`cancelled`) connected to the abort handler

## 3. Create LoadingWidget

- [x] 3.1 Create `loading_widget.py` with `LoadingWidget(QWidget)` class

## 4. Create UploadCompletionWidget

- [x] 4.1 Create `upload_completion_widget.py` with `UploadCompletionWidget(QWidget)` class

## 5. Refactor mini_window.py

- [x] 5.1 Replace imports from PySide6 with imports from new `mobile_to_pc` modules
- [x] 5.2 Remove `MiniWindowPhase`, `MiniWindowState`, `_TERMINAL_PHASES`, `_phase_message()`, `_phase_icon()`, `_payload_label()` — import from `mobile_to_pc/state.py` and re-export
- [x] 5.3 Add `QStackedWidget` to `_setup_ui()` with three child pages (PinCodeWidget, LoadingWidget, UploadCompletionWidget)
- [x] 5.4 Replace `_refresh_ui()` logic with phase-to-page index mapping and `set_state()` dispatch to active widget
- [x] 5.5 Preserve `apply_session_event()`, `show_pin()`, `build_phase()`, `closeEvent()` signatures and behavior
- [x] 5.6 Verify `mini_window_factory.py` imports (`InstantShareMiniWindow`, `MiniWindowPhase`, `_TERMINAL_PHASES`) continue to work
- [x] 5.7 Verify `__init__.py` imports (`InstantShareMiniWindow`, `MiniWindowPhase`, `MiniWindowState`) continue to work

## 6. Verify

- [x] 6.1 Run `python -c "from dt_image_search.instant_sharing.mini_window import InstantShareMiniWindow, MiniWindowPhase, MiniWindowState, _TERMINAL_PHASES"` — ✓ backward compatible
- [x] 6.2 Run `python -c "from dt_image_search.instant_sharing import InstantShareMiniWindow, MiniWindowPhase, MiniWindowState"` — ✓ package-level exports OK
- [x] 6.3 Unit tests pass (`test_session.py`) — ✓ OK
