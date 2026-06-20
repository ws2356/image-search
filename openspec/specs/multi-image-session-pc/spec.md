# multi-image-session-pc Specification

## Purpose
TBD - created by archiving change multi-image-share. Update Purpose after archive.
## Requirements
### Requirement: Session tracks batch image count and progress
The instant share session SHALL track the total expected image count and per-image delivery status. When multiple images are expected, the session SHALL remain in `TRANSFERRING` state until all images are received, then transition to `DELIVERING` only after the final image arrives.

#### Scenario: Session stays open for batch
- **WHEN** trust confirm includes `image_count: 5`
- **AND** the first image arrives via `/transfer/image`
- **THEN** the session SHALL remain in `TRANSFERRING` state
- **AND** the session SHALL track `received_count: 1` of `expected_count: 5`

#### Scenario: Session transitions to DELIVERING after last image
- **WHEN** the 5th of 5 expected images arrives
- **THEN** the session SHALL transition to `DELIVERING`
- **AND** the orchestrator SHALL publish a lifecycle event with `image_count: 5` and `received_count: 5`

### Requirement: Mini-window displays batch progress
The mini-window SHALL display batch progress when the session has multiple expected images. The progress text SHALL reflect the count (e.g., "Receiving image 3 of 5...") and the progress bar SHALL represent overall batch completion.

#### Scenario: Batch progress in mini-window
- **WHEN** a session has `image_count: 5` and `received_count: 2`
- **THEN** the mini-window SHALL display "Receiving shared items from iPhone..." with progress at 40%

#### Scenario: Single image retains existing behavior
- **WHEN** a session has `image_count: 1` (or 0, treated as unknown single)
- **THEN** the mini-window SHALL display the existing single-image UI without batch indicators

### Requirement: Transfer handler validates batch against session metadata
The `TransferHandler.receive_image()` SHALL validate that incoming images are within the expected batch count for the session. If more images arrive than expected, it SHALL reject with an error.

#### Scenario: Image received within expected count
- **WHEN** a session expects 5 images and the 3rd arrives
- **THEN** `receive_image` SHALL accept and deliver the image normally

#### Scenario: Image exceeds expected count
- **WHEN** a session expects 3 images and the 4th arrives
- **THEN** `receive_image` SHALL raise an error with `ErrorCode.TRANSFER_LIMIT_EXCEEDED`

### Requirement: Orchestrator publishes batch-aware lifecycle events
The orchestrator SHALL include `image_count` and `received_count` in lifecycle events for sessions with batch images. The orchestrator SHALL NOT call `handle_delivery_complete()` until all expected images are received.

#### Scenario: Lifecycle event for batch session
- **WHEN** the orchestrator publishes a lifecycle event for a batch session
- **THEN** the event SHALL include `image_count: N` and `received_count: M`
- **AND** `handle_delivery_complete()` SHALL only be called after `M == N`

