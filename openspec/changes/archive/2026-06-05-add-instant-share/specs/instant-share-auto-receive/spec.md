## ADDED Requirements

### Requirement: Desktop auto-activation on incoming instant-share
The desktop system SHALL detect incoming instant-share session requests via the bootstrap HTTP endpoint and SHALL present the standalone receive mini window according to the finalized UX variant.

#### Scenario: Activate receive panel while app is running
- **WHEN** an authenticated instant-share session request arrives and the desktop app process is active
- **THEN** the app applies the finalized receive UX variant and shows sender/type summary within the same session lifecycle

#### Scenario: Activate receive panel when app is minimized
- **WHEN** an authenticated instant-share request arrives while the app is minimized
- **THEN** the app applies the finalized receive UX variant and indicates transfer progress status

### Requirement: Event-bus driven UX state synchronization
The system SHALL publish instant-share lifecycle state changes to the desktop event bus so controllers and views remain synchronized across queued, transferring, delivering, success, and failure states.

#### Scenario: Broadcast state progression
- **WHEN** an instant-share session transitions from `negotiating` to `transferring`
- **THEN** the event bus emits a state transition event that updates all subscribed receive UX components

### Requirement: Desktop receive UX mock variants before behavior lock
The system SHALL provide two desktop receive UX mock sets for review before final behavior lock:
- Variant A: full notification-only UX
- Variant B: standalone mini window independent from main AuSearch app

#### Scenario: Mock review artifacts are available
- **WHEN** product/design review for instant-sharing desktop UX is initiated
- **THEN** both Variant A and Variant B mock sets are available for comparison

### Requirement: Finalized UX variant controls runtime behavior
The system SHALL implement runtime receive behavior according to the selected UX variant after mock review decision.

#### Scenario: Variant A selected
- **WHEN** Variant A is selected as final UX
- **THEN** incoming instant-share uses notification-only receive flow

#### Scenario: Variant B selected (standalone mini window)
- **WHEN** Variant B is selected as final UX
- **THEN** clicking the instant-share notification entry opens a standalone mini window (360x520px) independent from main AuSearch app
- **THEN** the mini window has its own title bar, traffic lights, and lifecycle
- **THEN** the mini window is completely separate from existing backup, browser, and search features

### Requirement: Production desktop receive UX
The desktop side SHALL ship production-quality instant-share receive UX as a standalone mini window for the selected receive pattern, including clear lifecycle, completion, failure, timeout, busy, and user-aborted states.

#### Scenario: Production receive UX shows lifecycle state
- **WHEN** instant-share is enabled and a session progresses through receive states
- **THEN** desktop presents the standalone mini window with clear state-specific feedback

#### Scenario: Production receive UX handles terminal outcomes
- **WHEN** an instant-share session ends in success, failure, timeout, busy rejection, or user abort
- **THEN** desktop presents the corresponding final outcome through the standalone mini window

### Requirement: Mini window independence from main app
The standalone mini window SHALL NOT share UI surface, navigation, tab state, or panel layout with the main AuSearch application.

#### Scenario: Mini window opens without affecting main app
- **WHEN** an incoming instant-share triggers the mini window to open
- **THEN** the main AuSearch window state remains unchanged — no tabs switch, no panels shift, no navigation occurs

#### Scenario: Mini window closes independently
- **WHEN** the instant-share session completes or is dismissed
- **THEN** only the mini window closes; the main AuSearch window is unaffected
