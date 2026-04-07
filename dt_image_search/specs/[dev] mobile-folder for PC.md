
8. Technical considerations

   8.1 Integration points

   - Existing Add Folder action and local folder chooser flow
   - Desktop UI built with PySide6, including new dialogs plus Folder TreeView state rendering and context menu actions
   - Existing background threading model for transfer workers and indexing workers
   - Existing event bus for decoupled state updates from background tasks to the UI
   - Existing incremental indexing pipeline and root-folder registration logic
   - Existing local persistence layer, likely backed by SQLite, for folder metadata, device mapping, session state, and transfer cursors
   - Existing telemetry client for operational metrics
   - OS-specific device connectivity dependencies:
    - Android: Android Open Accessory (AOA)
    - iPhone and iPad: usbmuxd or libimobiledevice
    - Both platforms: Wi-Fi LAN fallback

    8.2 Data storage and privacy

 - The desktop app must persist mobile-folder metadata including parent path, resolved device folder path, device UUID, display name, last successful session marker, latest transferred item marker, current transfer state, and reconnect eligibility.
 - The desktop app must persist enough per-item history to support incremental transfer, SHA-1 skip logic for mismatch full scans, and conflict-free naming decisions.
 - Device folders must be structured as <selected parent>/<device name>/<YYYY-MM>/..., with a collision-safe variant when device-name conflicts occur.
 - Media content, thumbnails, filenames, and full paths must stay local and must not be sent to telemetry.
 - If telemetry is enabled, it may send only aggregated operational events and anonymized session identifiers.
 - The project must preserve original timestamps and available metadata on disk whenever the source platform exposes them.

8.3 Scalability and performance

 - Transfer must stream incrementally rather than requiring the full mobile library to be materialized before files start arriving on desktop.
 - Background transfer must not block the UI thread.
 - The system must tolerate multiple concurrent devices while enforcing a single active session per device.
 - Existing incremental indexing must continue to operate correctly as new files arrive during a transfer session.
 - Full-scan mismatch handling must avoid re-copying unchanged files by using SHA-1 comparison.
 - Wi-Fi fallback should not require a complete restart of the folder registration flow.

8.4 Security and privacy

 - The QR pairing code should be treated as a short-lived bootstrap secret and invalidated on first successful use or at 15-minute expiry.
 - The transport layer should use authenticated encryption with per-session derived keys rather than treating the QR payload itself as a long-lived secret.
 - The 8-hour key lifetime should trigger rekeying or reconnect-based key renewal before continued transfer.
 - When either device rotates trust material, the next reconnect flow should derive fresh keys from a newly issued QR code.
 - Pairing and reconnect flows must require explicit user action and must not allow a background device to attach silently.
 - No cloud relay is allowed for media transport.

8.5 Potential challenges

 - Packaging and maintaining reliable USB support across macOS and Windows for Android and iOS dependencies
 - LAN discovery reliability across firewall, VPN, and segmented-network conditions
 - Defining a secure yet operable key-rotation strategy that fits the 8-hour key lifetime
 - Resolving device identity loss or mismatch without surprising users or duplicating large libraries
 - Handling device names that change over time while preserving stable device-folder mapping
 - Balancing SHA-1 dedupe accuracy against performance for large mismatch-driven full scans
 - Ensuring transfer and indexing state can coexist cleanly in the Folder TreeView without confusing users

8.6 Validation and testing considerations

 - Test first-time pairing on macOS and Windows with Android USB, Android Wi-Fi, iPhone USB, and iPhone Wi-Fi.
 - Test QR expiry, QR refresh, and reconnect flows independently.
 - Test device identity mismatch handling for both new device and previously paired device choices.
 - Test transfer interruption cases including USB unplug, Wi-Fi loss, desktop restart, expired trust material, and destination disk full.
 - Test concurrent sessions with at least three devices and verify independent state updates.
 - Test metadata preservation, YYYY-MM partitioning, and conflict-free naming with modified media.
 - Test exclusion of hidden, recently deleted, and cloud-placeholder assets.
 - Test that telemetry events never include content-bearing fields.
