## ADDED Requirements

### Requirement: Desktop auto-activation on incoming instant-share
The desktop system SHALL detect incoming instant-share session requests and SHALL present desktop receive UX according to the finalized UX variant.

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
- Variant B: click notification entry opens AuSearch for receive flow

#### Scenario: Mock review artifacts are available
- **WHEN** product/design review for instant-sharing desktop UX is initiated
- **THEN** both Variant A and Variant B mock sets are available for comparison

### Requirement: Finalized UX variant controls runtime behavior
The system SHALL implement runtime receive behavior according to the selected UX variant after mock review decision.

#### Scenario: Variant A selected
- **WHEN** Variant A is selected as final UX
- **THEN** incoming instant-share uses notification-only receive flow

#### Scenario: Variant B selected
- **WHEN** Variant B is selected as final UX
- **THEN** clicking the instant-share notification entry opens AuSearch for receive handling

### Requirement: Production desktop receive UX
The desktop side SHALL ship production-quality instant-share receive UX for the selected receive pattern, including clear lifecycle, completion, failure, timeout, busy, and user-aborted states.

#### Scenario: Production receive UX shows lifecycle state
- **WHEN** instant-share is enabled and a session progresses through receive states
- **THEN** desktop presents the selected production receive UX with clear state-specific feedback

#### Scenario: Production receive UX handles terminal outcomes
- **WHEN** an instant-share session ends in success, failure, timeout, busy rejection, or user abort
- **THEN** desktop presents the corresponding final outcome through the production receive UX
