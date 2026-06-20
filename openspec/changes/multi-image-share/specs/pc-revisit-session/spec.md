## MODIFIED Requirements

### Requirement: On-the-fly session creation for revisit transfers
When a transfer request arrives via mTLS and no active trust session matches the `X-Session-Id` header, the PC SHALL create a session on-the-fly. For batch transfers, the first image's request creates the session; subsequent images reuse it.

#### Scenario: Revisit batch transfer session created on first image
- **WHEN** the first `/transfer/image` request of a revisit batch arrives
- **THEN** the PC SHALL create an on-the-fly session with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`
- **AND** subsequent `/transfer/image` requests with the same `X-Session-Id` SHALL reuse the session

#### Scenario: Revisit batch delivery complete after all images
- **WHEN** the final image of a revisit batch arrives
- **THEN** the PC SHALL transition to `DELIVERING` → `DONE`
- **AND** `handle_delivery_complete()` SHALL only be called after the last image

### Requirement: Revisit session lifecycle events
The orchestrator SHALL publish lifecycle events for revisit sessions. For batch transfers, lifecycle events SHALL include `image_count` and `received_count`.

#### Scenario: Batch revisit lifecycle event
- **WHEN** a revisit batch session has 3 expected images and 2 received
- **THEN** the lifecycle event SHALL include `image_count: 3` and `received_count: 2`
- **AND** the mini-window SHALL display appropriate batch progress
