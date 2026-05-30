## ADDED Requirements

### Requirement: Desktop auto-activation on incoming instant-share
The desktop system SHALL detect incoming instant-share session requests and SHALL automatically activate a dedicated receive UX surface in AuSearch/AuBackup without requiring manual navigation.

#### Scenario: Activate receive panel while app is running
- **WHEN** an authenticated instant-share session request arrives and the desktop app process is active
- **THEN** the app opens or focuses the instant receive panel and displays sender/type summary within the same session lifecycle

#### Scenario: Activate receive panel when app is minimized
- **WHEN** an authenticated instant-share request arrives while the app is minimized
- **THEN** the app restores a visible receive surface and indicates transfer progress status

### Requirement: Event-bus driven UX state synchronization
The system SHALL publish instant-share lifecycle state changes to the desktop event bus so controllers and views remain synchronized across queued, transferring, delivering, success, and failure states.

#### Scenario: Broadcast state progression
- **WHEN** an instant-share session transitions from `negotiating` to `transferring`
- **THEN** the event bus emits a state transition event that updates all subscribed receive UX components

### Requirement: User-configurable activation behavior
The system SHALL allow users to configure whether incoming instant-share requests auto-focus the window or show a non-intrusive notification-only receive state.

#### Scenario: Respect notification-only preference
- **WHEN** a user has selected notification-only activation behavior
- **THEN** an incoming instant-share request presents a notification and updates background receive state without forcing full window focus
