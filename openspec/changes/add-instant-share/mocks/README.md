# Desktop Receive UX Mock Review

Two variants for how the desktop side handles incoming shares from the iOS Share Extension.

## Variant A – Notification Only

**File:** `desktop-variant-a-notification-only.html`

- All progress shown in macOS system notifications
- User never leaves their current app
- Accept/decline actions in the notification itself
- No additional window required for the receive flow
- Best for: users who multitask and don't want window popups

## Variant B – Instant Share Mini Window

**File:** `desktop-variant-b-click-to-ausearch.html`

- Initial notification with single "View Transfer" button
- Clicking opens a **standalone mini window** (360x520px) independent from the main AuSearch app
- The mini window is a dedicated Instant Share surface with its own title bar, traffic lights, and lifecycle
- Completely separate from existing backup, browser, and search features
- PIN confirmation, progress bar, device status all visible in the mini window
- Post-transfer actions: Show in Finder, OK to dismiss
- Window title changes with transfer state: "安全配对" → "正在接收..." → "传输完成"
- Traffic lights: only close is active after transfer completes; minimize/maximize disabled during transfer
- Best for: users who want visual confirmation and control without leaving their workflow

## Decision: Variant B Selected (Separate Mini Window)

Variant B has been selected as the final desktop receive UX pattern. The key architectural decision:

**Instant Share lives in a completely separate window, independent from the main AuSearch app.**

- The mini window is self-contained and does not share UI surface with backup, browser, or search features
- It opens on demand when an incoming share arrives (via notification click) and closes after completion
- The main AuSearch window is not affected — no tabs change, no panels shift, no navigation occurs
- This separation ensures the instant-share flow has zero coupling to existing feature UI

## How to View

Open the `.html` files in any browser. They are self-contained mockups with no external dependencies.
