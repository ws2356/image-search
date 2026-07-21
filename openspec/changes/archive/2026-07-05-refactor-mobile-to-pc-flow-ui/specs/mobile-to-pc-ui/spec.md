## ADDED Requirements

### Requirement: Three separate widget classes under mobile_to_pc/ subfolder
The mobile-to-PC UI SHALL be split into three widget classes, each in its own file under `dt_image_search/instant_sharing/mobile_to_pc/`: `PinCodeWidget`, `LoadingWidget`, and `UploadCompletionWidget`. Each widget SHALL be a `QWidget` subclass responsible for rendering exactly one group of UI phases.

#### Scenario: PinCodeWidget covers only PIN display phase
- **WHEN** the session phase is `DISPLAYING_PIN`
- **THEN** `PinCodeWidget` SHALL be the active widget in the stacked layout
- **AND** it SHALL display the PIN code in large (36pt bold) centered text
- **AND** it SHALL display the device name and a Cancel button

#### Scenario: LoadingWidget covers connecting/negotiating/transferring phases
- **WHEN** the session phase is `CONNECTING`, `NEGOTIATING`, `TRANSFERRING`, or `DELIVERING`
- **THEN** `LoadingWidget` SHALL be the active widget
- **AND** it SHALL display a phase-appropriate icon and message
- **AND** it SHALL display a progress bar (indeterminate for connecting/negotiating, determinate for transferring)
- **AND** it SHALL display a Cancel button during active phases

#### Scenario: UploadCompletionWidget covers all terminal phases
- **WHEN** the session phase is `SUCCESS`, `FAILED`, `TIMED_OUT`, `ABORTED`, or `BUSY`
- **THEN** `UploadCompletionWidget` SHALL be the active widget
- **AND** it SHALL display a terminal icon and message
- **AND** it SHALL display a Dismiss button
- **AND** for `SUCCESS` with text, a "Copy to Clipboard" button SHALL be shown
- **AND** for `SUCCESS` with a file path, a "Show in Finder" button SHALL be shown
- **AND** for error phases (`FAILED`, `TIMED_OUT`, `ABORTED`), the error message SHALL be shown in red

### Requirement: QStackedWidget switches between widgets on phase change
`InstantShareMiniWindow` SHALL use a `QStackedWidget` that contains exactly three child widgets (PinCodeWidget, LoadingWidget, UploadCompletionWidget). When the session phase changes, the stacked widget SHALL switch to the appropriate page. Only the active widget SHALL be visible at any time.

#### Scenario: Phase transition switches visible widget
- **WHEN** the phase transitions from `CONNECTING` to `DISPLAYING_PIN`
- **THEN** `QStackedWidget` SHALL switch from LoadingWidget to PinCodeWidget
- **AND** only PinCodeWidget content SHALL be visible

#### Scenario: Phase transition within same widget group does not switch
- **WHEN** the phase transitions from `TRANSFERRING` to `DELIVERING`
- **THEN** the QStackedWidget SHALL remain on LoadingWidget
- **AND** LoadingWidget SHALL update its displayed state

### Requirement: State data types in mobile_to_pc/state.py
`MiniWindowPhase` enum and `MiniWindowState` dataclass SHALL be defined in `dt_image_search/instant_sharing/mobile_to_pc/state.py`. They SHALL be re-exported from `dt_image_search/instant_sharing/mini_window.py` for backward compatibility.

#### Scenario: Import from both old and new location
- **WHEN** code imports `MiniWindowPhase` from `dt_image_search.instant_sharing.mini_window`
- **THEN** it SHALL resolve to the same class as importing from `dt_image_search.instant_sharing.mobile_to_pc.state`
- **AND** code importing from `mini_window` SHALL continue to work without changes

### Requirement: Backward-compatible InstantShareMiniWindow public API
The `InstantShareMiniWindow` class SHALL retain its existing public API: constructor, `apply_session_event()`, `show_pin()`, `build_phase()`, and `closeEvent()`. The behavior of each method SHALL remain identical to the pre-refactor implementation.

#### Scenario: apply_session_event updates widget and brings window to front
- **WHEN** `apply_session_event()` is called with `state="transferring"`
- **THEN** the stacked widget SHALL switch to LoadingWidget
- **AND** LoadingWidget SHALL display the transfer message and progress
- **AND** the window SHALL be raised and activated

#### Scenario: show_pin displays PIN code
- **WHEN** `show_pin("123456")` is called
- **THEN** the stacked widget SHALL switch to PinCodeWidget
- **AND** PinCodeWidget SHALL display "123456" in large text

#### Scenario: Terminal phases trigger auto-close
- **WHEN** a terminal phase (`SUCCESS`, `FAILED`, `TIMED_OUT`, `ABORTED`, `BUSY`) is applied
- **THEN** the auto-close timer SHALL be started (4s for `SUCCESS`, 8s for errors/busy)
- **AND** auto-close SHALL be suppressed for `SUCCESS` with text content or file path

### Requirement: Widgets accept state via set_state method
Each widget SHALL implement a `set_state(state: MiniWindowState) -> None` method that the parent `InstantShareMiniWindow` calls to push new state after switching the stacked widget page.

#### Scenario: set_state updates widget content
- **WHEN** `set_state()` is called on UploadCompletionWidget with a `SUCCESS` state
- **THEN** the widget SHALL display the success icon and message
- **AND** appropriate action buttons SHALL be visible
