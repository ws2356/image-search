## MODIFIED Requirements

### Requirement: QR code display
After generating the opt-code, the Launch Agent SHALL display an independent mini-window with a QR code encoding the PC's LAN IP addresses, port, session id, and opt-code. Each QR stash SHALL open its own mini-window, independent of any other active sessions' windows.

#### Scenario: Show QR mini-window
- **WHEN** a payload is stashed and opt-code generated
- **THEN** the Launch Agent SHALL create a new mini-window for QR display (one per stash)
- **THEN** the QR code SHALL encode a URL in the format: `https://dl.boldman.net/share?ips=<comma-separated-ips>&port=<port>&stash=<stash_id>&opt=<opt-code>`
- **THEN** the window SHALL display the QR code prominently, along with the opt-code as fallback text, PC name (and port), and "Scan with AuBackup" instructions
- **AND** the window title SHALL be "Sending to Phone"

#### Scenario: QR stash coexists with active transfer sessions
- **WHEN** a payload is stashed via QR trigger
- **AND** one or more mobile-to-pc transfer sessions are already active (each in their own mini-windows)
- **THEN** a new independent mini-window SHALL open for the QR stash session
- **AND** the existing transfer sessions' mini-windows SHALL continue unaffected

#### Scenario: Multiple concurrent QR stashes
- **WHEN** the user shares content via Share Extension twice in quick succession
- **THEN** each share SHALL create its own mini-window with its own QR code and opt-code
- **AND** all QR windows SHALL be independently positioned and closable

#### Scenario: QR window lifecycle
- **WHEN** the user clicks "Cancel" on a QR stash mini-window
- **THEN** the stash SHALL be invalidated and the window SHALL close immediately
- **WHEN** the opt-code expires (5-minute TTL)
- **THEN** the stash SHALL be invalidated and the window SHALL show "Expired" and auto-close after 10 seconds
- **WHEN** the stash is successfully claimed
- **THEN** the window SHALL show "Delivered" and auto-close after 4 seconds

### Requirement: Stash expiry cleanup
The Launch Agent SHALL use a oneshot timer per stash (set to the opt-code TTL of 5 minutes) to invalidate expired stashes instead of a periodic cleanup loop. Each stash timer SHALL be independent of other sessions' lifecycle timers.

#### Scenario: Oneshot timer cleanup
- **WHEN** a stash is created
- **THEN** a oneshot timer SHALL be scheduled for 5 minutes
- **WHEN** the timer fires
- **THEN** the stash SHALL be marked as expired if not already claimed
- **AND** the associated mini-window SHALL show "Expired" and auto-close

#### Scenario: Timer cancelled on claim
- **WHEN** a stash is successfully claimed before the timer fires
- **THEN** the oneshot timer SHALL be cancelled

#### Scenario: Other sessions unaffected by stash expiry
- **WHEN** a stash expires while a mobile-to-pc transfer session is still active
- **THEN** the mobile-to-pc transfer session's mini-window SHALL continue unaffected
- **AND** only the expired stash's mini-window SHALL close
