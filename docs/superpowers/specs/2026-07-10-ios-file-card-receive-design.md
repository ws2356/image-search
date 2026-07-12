# iOS File Card Receive UI Design

## Purpose

Redesign the iOS receive surface so that every shared item — single or multiple, text/image/file/link — is rendered as a type-specific card inside a unified `MultiFileReceiveView`, with consistent download feedback and share-centric actions.

## Context

The current `ISFromPC` module routes different `QRClaimResult` types to different views:

- `.multiFile` → `MultiFileReceiveView` (a list of rows with extension badges, filenames, and status indicators).
- `.image` / `.file` → `MultiFileReceiveView` via `MultiFileReceiveViewModel(singleResult:)`.
- `.text` / `.html` / `.link` → `QRTransferResultView`, which renders standalone text, rich-text, or link UI.

The new design (see `ui-design/instant-share/screenshots/new/[mobile] pc-to-mobile completion file list.png` and `[mobile] pc-to-mobile completion file list - 2.png`) replaces the row list with full-width cards that expose a preview of the content and contextual action buttons. The standalone link design (`mobile/ios/Tests/AlbumTransporterAppSnapshotTests/__Snapshots__/share-receive-link_iPhone-17-Pro-Max_en-US.png`) is adapted into a card for the list.

## Goals

1. Render every received item as a card in `MultiFileReceiveView`.
2. Provide type-specific previews and actions:
   - **Text card** — text preview, **Copy**, **Share**.
   - **HTML card** — compact rich-text preview, **Copy**, **Share**.
   - **Image card** — image thumbnail, **Share**.
   - **Generic file card** — compact horizontal layout with **Share**.
   - **Web link card** — link icon + URL preview, **Copy Link**, **Open**, **Share**.
3. Remove all **Save** buttons from individual cards; rely on the system share sheet for saving.
4. Rename the bottom bulk action from **Save All** to **Share All**.
5. Show a centered activity indicator over a dimmed card while the file is downloading.
6. Keep the implementation testable with snapshot tests per card type.

## Non-Goals

- Changing the download network layer (`QRTriggerDownloadClient`).
- Adding new file types beyond text, image, generic file, and web link.
- Redesigning the QR scanner, claiming, or error pages.

## Design

### Architecture & Components

New files under `mobile/ios-packages/InstantShareKit/Sources/ISFromPC/Views/Components/FileCards/`:

| Component | Responsibility |
| :-- | :-- |
| `FileCardBackground` | Shared white rounded card with 1 pt border and `DesignSystem.CornerRadius.card`. |
| `ExpandedFileCardLayout` | Header row (badge, filename, size, type label) + fixed-height body + footer action buttons. |
| `CompactFileCardLayout` | Horizontal row: badge + filename/size on the left, inline trailing buttons on the right. |
| `TextFileCard` | Expanded layout; body shows multi-line text preview clipped to a fixed height. |
| `ImageFileCard` | Expanded layout; body shows the downloaded image thumbnail with `.aspectRatio(contentMode: .fill)` and `.clipped()`. |
| `GenericFileCard` | Compact layout; inline **Share** button. |
| `WebLinkCard` | Expanded layout; body shows centered link icon + truncated URL, adapted from `LinkReceiveView`. |
| `FileCard` | Type dispatcher that selects the correct card view from `FileDownloadState.entryType`. |
| `FileCardContainer` | Combines `FileCardBackground` with the download overlay logic (dimmed background + centered `ProgressView` when `status == .downloading`). |
| `HTMLFileCard` | Expanded layout; body renders the HTML in a compact `WKWebView` preview (reuses `RichTextWebView` rendering logic from the current standalone view). Footer: **Copy**, **Share**. |

`MultiFileReceiveView` is simplified to:

- Header bar (`Received`, item count, `Done`).
- Progress banner / bottom bar during active downloads (existing behavior).
- Scrollable `LazyVStack` of `FileCard(state:)` rows.
- Bottom **Share All** button when at least one downloadable/inline item exists.

### Data Flow

1. `ISQRRootView` routes every successful claim result to `MultiFileReceiveView`.
   - `.multiFile` passes the manifest directly.
   - `.image` / `.file` continue to use `MultiFileReceiveViewModel(singleResult:)`.
   - `.text`, `.html`, and `.link` are wrapped into a one-item `MultiFileManifest` so they also render in `MultiFileReceiveView`.
2. `MultiFileReceiveViewModel.FileDownloadState` already distinguishes inline types (`text`, `html`, `link`). Inline entries are initialized with `status == .downloaded` and a populated `result`, so no network download is attempted. HTML entries keep their `.html` result so the `HTMLFileCard` can render the formatted preview.
3. Downloadable entries iterate through `QRTriggerDownloadClient.downloadFileAtIndex(...)`, updating `status` to `.downloading`, `.downloaded`, or `.failed`.
4. Each card observes its own state. `FileCardContainer` renders the overlay during `.downloading`.
5. The bottom **Share All** button calls a new `shareAll()` method on the view model, which collects all downloaded items into the existing share sheet.

### Card Specifications

| Card type | Layout | Fixed body / total height | Footer / trailing actions |
| :-- | :-- | :-- | :-- |
| Text | Expanded | 120 pt body | **Copy**, **Share** |
| HTML | Expanded | 120 pt body | **Copy**, **Share** |
| Image | Expanded | 160 pt body | **Share** |
| Generic file | Compact | 72 pt total card height | **Share** |
| Web link | Expanded | 120 pt body | **Copy Link**, **Open**, **Share** |

Expanded cards have a fixed body height; their total height is also fixed because the header and footer have constant height. The compact generic-file card has a fixed total card height.

Shared styling:

- Filename: `DesignSystem.Typography.caption`, semibold, single line.
- Size: `DesignSystem.Typography.caption2`, `secondaryText`.
- Badge: 40 × 40 pt rounded rectangle with uppercase extension label.
- Type label (TEXT / IMAGE / LINK): right-aligned in header, `caption2`, `secondaryText`.
- Card background: `FileCardBackground` with `DesignSystem.CornerRadius.card`.

### Download State

During `status == .downloading`:

- The entire card is overlaid with a dimmed background (`DesignSystem.Colors.foreground.opacity(0.08)`).
- A centered `ProgressView` (`controlSize(.regular)`, `DesignSystem.Colors.primary`) is shown.
- Header and footer remain visible but non-interactive.

### Error Handling

- Failed downloads retain the existing red border and failed indicator in the header.
- Failed cards are non-interactive for actions unless a usable partial result exists.
- `MultiFileReceiveViewModel.downloadError` continues to surface top-level errors.

### Testing

- Add snapshot tests in `InstantShareSnapshotTests` for each card type (text, HTML, image, generic file, web link) in isolation and for a mixed list.
- Add or update unit tests for `MultiFileReceiveViewModel` covering:
  - Single-result wrapping for text/html/link/image/file.
  - Inline entries initialized as downloaded.
  - `shareAll()` selects all downloaded items.
  - Cleanup of temporary files.

## Alternatives Considered

- **Single configurable `FileCard`** with content builders: rejected because the compact generic-file card does not share the expanded header/body/footer layout, making a unified layout abstraction awkward.
- **Restyle existing `fileRow`**: rejected because it would not match the preview-body and action-button design shown in the screenshots and would become harder to extend.

## Open Questions

None. All clarifications have been resolved:

- Download spinner overlays the dimmed card.
- All Save buttons are removed; Share is present on every card.
- Web link card keeps **Copy Link**, **Open**, and **Share**.
- Bottom bulk action is **Share All**.
