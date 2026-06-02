# Desktop Receive UX Mock Review

Two variants for how the desktop (AuSearch) side handles incoming shares from the iOS Share Extension.

## Variant A – Notification Only

**File:** `desktop-variant-a-notification-only.html`

- All progress shown in macOS system notifications
- User never leaves their current app
- Accept/decline actions in the notification itself
- No AuSearch window required for the receive flow
- Best for: users who multitask and don't want window popups

## Variant B – Click Notification → AuSearch Window

**File:** `desktop-variant-b-click-to-ausearch.html`

- Initial notification with single "View Transfer" button
- Clicking opens AuSearch with full transfer panel
- PIN confirmation, progress bar, device status all visible
- Post-transfer actions: Open File, Show in Finder
- Best for: users who want visual confirmation and control

## Decision Questions

1. **Do you want AuSearch to open automatically?** (A = no, B = yes)
2. **Should users see PIN confirmation in notifications or in the app window?** (A = notification, B = app window)
3. **Is visual progress important for the user?** (A = progress bar in notification, B = full progress panel in app)
4. **Should the receive flow be self-contained in notifications?** (A = yes, B = no)

## How to View

Open the `.html` files in any browser. They are self-contained mockups with no external dependencies.
