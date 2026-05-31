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

### Requirement: Desktop phased UI rollout
The desktop side SHALL ship a minimum viable instant-share receive UX first and SHALL defer visual design/polish refinements to a dedicated later pass.

#### Scenario: Desktop MVP UI available for flow bring-up
- **WHEN** instant-share MVP is enabled for testing
- **THEN** desktop provides functional minimal receive UX and status visibility without requiring final polished visuals

#### Scenario: Desktop polish pass occurs after MVP validation
- **WHEN** end-to-end flow is validated with MVP UX
- **THEN** desktop UI design and polish tasks are executed as a separate follow-up pass
