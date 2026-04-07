PRD: Mobile Folder
1. Product overview

    1.1 Document title and version
    - PRD: Mobile Folder
    - Version: 0.1

    1.2 Product summary

    The project already supports adding local folders and incrementally indexing new media on desktop. Users whose photos and videos live primarily on phones still need a manual export or generic file transfer step before those assets become searchable, which adds friction and delays the first useful result.

    This feature extends the existing Add Folder entry point with a guided Mobile Device flow on macOS and Windows. Users choose a parent destination folder, scan a platform-specific QR code from an Android or iOS companion app, and start a secure local-only transfer over USB or Wi-Fi LAN. The desktop app creates or reuses a stable mobile-device folder and starts the existing incremental indexing pipeline while media is still transferring.

    This PRD is desktop-led. It defines the desktop UX, storage model, folder state model, recovery behaviors, and the minimum companion app behaviors required to support pairing, secure transfer, repeat backups, and reconnect flows.

2. Goals

    2.1 Business goals

    - Improve adoption of the Add Folder workflow for phone-first users.
    - Differentiate the project with a faster, guided mobile ingestion experience that highlights USB as the preferred path.
    - Maintain a privacy-forward, local-only transfer posture while preserving minimal operational telemetry.

2.2 User goals

 - Start a mobile backup from the same Add Folder entry point already used for local folders.
 - Understand that USB is usually faster while still being able to use Wi-Fi LAN when needed.
 - Choose where mobile backups live on disk without manually creating device folders.
 - See transfer progress and transfer state in the Folder TreeView without staying inside a blocking modal workflow.
 - Resume after disconnects through a reconnect flow instead of restarting a full backup.
 - Reuse the same device folder for later sessions and transfer only new or updated items.
 - Preserve original timestamps and available metadata while avoiding duplicate files.

2.3 Non-goals

 - Cloud relay, cloud backup, or any media transfer path that leaves the local device and desktop network boundary.
 - Bi-directional sync or desktop-to-mobile writes.
 - Propagating phone-side deletions to the desktop copy.
 - Explicit desktop pause or resume controls for a session.
 - Manual pairing-code entry as a fallback to QR scanning.
 - Mobile-initiated resume as a primary v1 workflow.
 - Preserving the source album hierarchy on disk.
 - Importing hidden items, recently deleted items, or cloud-placeholder assets that are not fully resident on-device.
 - Reworking the indexing UX beyond allowing transfer state to coexist with existing or future indexing state.

3. User personas

3.1 Key user types

 - Desktop users whose primary photo library is on a phone or tablet
 - Users moving large personal media libraries into the project for the first time
 - Repeat backup users who want a low-friction way to keep the desktop library fresh
 - Power users who may connect multiple mobile devices to one desktop over time

3.2 Basic persona details

 - Phone-first organizer: Keeps most family photos and videos on a phone and wants them searchable on desktop without manual export.
 - Repeat backup user: Has already backed up one or more devices and wants future sessions to detect only new or updated media.
 - Power desktop curator: Manages multiple devices and expects non-blocking progress visibility, stable storage paths, and predictable reconnect behavior.

3.3 Role-based access

 - Desktop user: Can choose the source type, select a parent destination path, initiate pairing, choose or override transport, start reconnect flows, and view transfer state.
 - Paired mobile companion app: Can request device media permissions, scan the QR code, participate in authenticated pairing, enumerate eligible media, and send media only after explicit OS-level and in-app consent.
 - Telemetry service (optional): May receive aggregated operational metrics such as session start, pairing outcome, transport type, time to first transferred item, and failure category, but must never receive media content, thumbnails, filenames, full paths, or raw 
file hashes.

4. Functional requirements

 - Source selection dialog (Priority: P0)
   - Clicking the existing Add Folder button must first show a source selection dialog with exactly two choices: Local Device and Mobile Device.
   - The Local Device option must continue the current behavior unchanged.
   - The Mobile Device option must explain that USB transfer is typically faster and Wi-Fi LAN is also supported.
 - Parent destination selection (Priority: P0)
   - After the user selects Mobile Device, the desktop app must prompt for a parent folder that will contain the device-specific backup folder.
   - The desktop app must create or reuse a stable device folder inside that parent path after device identity is known.
   - Device folders must use a human-readable name derived from the mobile device name and os type, with collision-safe naming when sibling folders would otherwise conflict.
 - QR pairing flow (Priority: P0)
   - The desktop app must show a QR-code dialog with separate Android and iOS codes.
   - Each QR code must include app install or deep link behavior plus a secure pairing code in one step.
   - An unscanned QR code must expire after 15 minutes.
   - After QR code expires, the QR dialog must expose a refresh button for each QR code to generate a new code and pairing secret.
   - Manual pairing-code fallback is out of scope for v1.
 - Transport negotiation (Priority: P0)
   - The system must prefer USB when available.
   - Supported USB channels are Android Open Accessory for Android and usbmuxd or libimobiledevice-based connectivity for iPhone and iPad.
   - Wi-Fi LAN must be supported as a fallback path.
   - Users must be able to override the automatically chosen channel when more than one valid channel is available.
 - Transfer and indexing orchestration (Priority: P0)
   - After successful pairing and destination resolution, the desktop app must create or reuse the device folder, register it as a root folder item, and trigger the existing incremental indexing pipeline immediately.
   - Transfer must continue non-modally while indexing can discover newly arrived files.
   - The user must be able to continue using the desktop app while transfer and indexing run in the background.
 - Media scope and organization (Priority: P0)
   - The system must support all media file formats surfaced by the platform media library APIs, including device-native photo formats and video formats available through those APIs.
   - The system must exclude hidden items, recently deleted items, and cloud-placeholder assets that are not fully stored on-device.
   - Files must be written into YYYY-MM subdirectories derived from the asset update date when available, otherwise the best available creation or capture date.
   - Original timestamps and available metadata must be preserved where the source OS exposes them.
 - Repeat backup behavior (Priority: P0)
   - Each mobile device must map to one desktop backup folder.
   - Later backup sessions for the same matched device must reuse that folder and transfer only new or updated items.
   - Phone-side deletions must be ignored.
   - Phone-side modifications must be eligible for transfer in a later backup and must use a conflict-free filename if they would overwrite an existing local file.
 - Device identity management (Priority: P0)
   - The system must use a generated UUID from the companion app as the primary device identity for matching.
   - If a device UUID is lost because of reinstall or similar events, a new Add Folder flow must treat the device as new.
   - If the user reconnects to an existing mobile folder with a mismatched device identity, the desktop app must show a decision dialog:
     - New device: run a full backup scan for that folder but skip any file whose SHA-1 already matches a local file.
     - Previously paired device: run incremental backup and transfer only items newer than the latest item transferred in the last session.
  - Before transfer starts after either mismatch decision, the stored device UUID must be updated.
 - Folder TreeView transfer states (Priority: P0)
   - Each root folder item associated with a mobile backup must expose a transfer state independent of indexing state.
   - Canonical transfer states for v1 are awaiting_pairing, transferring, disconnected, transfer_completed, and failed.
   - Transfer state must persist outside the modal dialogs so the user can inspect status later.
 - Reconnect and recovery (Priority: P0)
   - Eligible mobile folder items must expose a Reconnect action in the Folder TreeView context menu.
   - Reconnect must include QR scanning as part of the flow.
   - If the connection drops during transfer, the folder must move to disconnected and become resumable through reconnect rather than requiring a new Add Folder flow.
   - Mobile-initiated resume remains future scope.
 - Concurrency model (Priority: P1)
   - The desktop app must support multiple concurrent mobile device backups.
   - Only one active backup session may exist per device at a time.
   - State, transfer progress, and error handling must remain isolated per device session.
 - Security and privacy (Priority: P0)
   - The QR code must carry a secure pairing code that both devices use to derive authenticated encrypted transport keys.
   - Unscanned QR codes must expire after 15 minutes.
   - Derived transport keys must expire after 8 hours and must support rotation on either device.
   - Later reconnections may reset trust and derive fresh keys using a new QR code.
   - Telemetry may be sent to the cloud only if it excludes user media and identifying content data.

5. User experience and design
    5.1 Source selection dialog
      - Two buttons for each source type with icons and brief descriptions. User can click close button or enter Escape key to exit without confirmation.
    5.2 QR code dialog with separate Android and iOS codes
      - Shows two QR codes side by side with platform-specific instructions. Each code includes a refresh button that appears after expiry. The dialog can be closed at any time. Need to request user confirmation before closing.
    5.3 Transfer progress and state indicators in the Folder TreeView
      - Each mobile folder item shows a transfer state badge or icon.

6. Narrative

A user clicks Add Folder expecting to bring phone media into the project just as easily as a local folder. Instead of leaving the product to export files manually, the user chooses Mobile Device, selects a parent destination, scans a QR code, and starts a secure
local transfer. The desktop app creates a stable device-owned folder, begins receiving photos and videos over USB or Wi-Fi, and lets the existing incremental indexer process new arrivals immediately. If the cable is pulled or the network drops, the folder remains
visible with a reconnect path, so the user can continue later without starting over.

7. Success metrics
  - Setup completion rate is at least 50% for Mobile Device initial connection and 75% for reconnection.
  - Median time from successful QR scan to first byte transferred is <= 120 seconds on USB and <= 240 seconds on Wi-Fi LAN.
  - Contributing to at least 20% of all Add Folder sessions within 3 months of launch.
  - At least 95% of users who finish one mobile backup can identify the transfer state of that folder from the Folder TreeView without reopening the QR flow.

8. Corner cases and constraints
 - The same desktop may run multiple mobile backup sessions concurrently.
 - A device may reconnect over a different transport channel than the previous session.
