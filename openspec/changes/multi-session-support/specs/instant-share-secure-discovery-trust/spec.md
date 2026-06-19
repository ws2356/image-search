## MODIFIED Requirements

### Requirement: Handshake/apply/confirm trust API flow
The trust flow SHALL use three HTTP APIs:
- `/trust/handshake` for DH exchange (includes bootstrap data)
- `/trust/apply` to receive PIN encrypted with symmetric key derived from handshake
- `/trust/confirm` sent after user taps Confirm (not in parallel, no long-poll)

All requests SHALL include an `X-Session-Id` header for session routing when multiple trust sessions are active.

#### Scenario: Handshake does not carry pin code
- **WHEN** iOS calls `/trust/handshake` on PC-hosted HTTP service with `X-Session-Id` header
- **THEN** request and response contain DH and nonce material only and do not contain pin code fields
- **AND** the PC SHALL route the handshake to the correct `TrustSession` identified by `session_id`

#### Scenario: Confirm is a simple POST
- **WHEN** the user taps "Confirm" on iOS after verifying the PIN
- **THEN** the extension sends `/trust/confirm` with `X-Session-Id` as a simple POST (no long-poll) and PC returns encrypted `trust_status: "trusted"`
- **AND** the PC SHALL route the confirm to the correct session

#### Scenario: Concurrent trust handshakes
- **WHEN** mobile device X and mobile device Y both initiate trust handshakes within the same time window
- **THEN** the PC SHALL create two independent `TrustSession` instances with different `session_id` values
- **AND** each handshake SHALL proceed independently through the apply/confirm steps

### Requirement: Trust session registry supports multiple concurrent sessions
The `TrustSessionRegistry` SHALL maintain a collection of active trust sessions keyed by `session_id`. Methods `create_handshake_session()`, `get_session()`, `complete_handshake()` SHALL route by `session_id`.

#### Scenario: Multiple concurrent trust sessions
- **WHEN** two mobile devices each call `/trust/handshake`
- **THEN** the `TrustSessionRegistry` SHALL contain two independent `TrustSession` entries
- **AND** each SHALL have its own DH key material, nonces, and state

#### Scenario: Session lookup by session_id
- **WHEN** `/trust/confirm` is called with `X-Session-Id: aaa`
- **AND** sessions `aaa` and `bbb` both exist in the registry
- **THEN** the request SHALL be routed to session `aaa` only
- **AND** session `bbb` SHALL be unaffected
