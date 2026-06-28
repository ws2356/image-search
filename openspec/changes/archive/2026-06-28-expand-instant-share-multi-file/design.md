## Context

AuSearch's instant-share feature currently supports PC-to-mobile sharing via a macOS Share Extension → QR code → iOS scan flow. The macOS Share Extension activates on single files only (`public.file-url` maxCount=1). All upstream infrastructure (stash entries, QR trigger handler, mini window, iOS download client) is designed around single-payload-per-session.

The mobile-to-PC direction already supports batch image sharing with session-level `image_count`/`received_count` tracking and batch-progress mini windows. This design extends the PC-to-mobile direction with analogous batch support.

## Goals / Non-Goals

**Goals:**
- Allow macOS Share Extension to accept multiple file selections (Finder or app-driven)
- Extend `QRTriggerHandler` / `StashEntry` to hold a list of files (file paths, filenames, content types) within a single batch stash
- Show batch count and filenames in the `QRTriggerMiniWindow`
- Enable iOS download client to receive a file manifest and download files sequentially
- Keep backward compatibility: single-file sharing continues to work unchanged

**Non-Goals:**
- No changes to the mobile-to-PC batch image flow (already done via `multi-image-session-pc` / `multi-image-payload-ios`)
- No changes to text/HTML sharing (single payload remains single)
- No zip/archive packaging on the PC side — files are served individually
- No changes to the trust handshake or mTLS infrastructure
- No changes to the `ausearch://claim?` QR URL format (stash_id is sufficient; file count lives in the download manifest)

## Decisions

| # | Decision | Rationale | Alternatives considered |
|---|----------|-----------|------------------------|
| D1 | Extend `StashEntry` with a `files: list[FileEntry]` field instead of creating N separate stashes | A single QR code per batch is the simplest UX. N stashes would require N QR codes or a compound QR, both poor UX. A single stash with a file list keeps the QR claim simple. | N stash entries: rejected — UX complexity. Archive all files into a zip: rejected — adds latency and disk I/O on PC side, forces iOS to decompress. |
| D2 | Rename `/transfer/download` → `/transfer/manifest`. This endpoint always returns JSON manifest (`{file_count, files: [{index, filename, content_type, size_bytes}]}`) — for both single and multi-file stashes. Actual file bytes are served by `/transfer/download/<index>`. | Consistent API surface: manifest-first, download-second. Single file is just a 1-entry manifest. iOS always calls manifest to discover what's available, then downloads each file by index. Eliminates the bifurcated inline-bytes-vs-JSON behavior. | Keep `/transfer/download` returning inline bytes for single files: rejected — inconsistent API, client must branch on response type. |
| D3 | Add `/api/instant-share/v1/transfer/download/<file_index>` as the universal per-file download endpoint. Works for any stash (single → index 0, batch → index 0..N-1). | Clean RESTful separation. Reuses the existing session-based auth. The file index is 0-based and validated against the stash's file count. | Query parameter `?index=N`: works but less RESTful. Multipart response: rejected — adds complexity on both sides. |
| D4 | macOS Share Extension payload stashing: send `{type: "image", files: [{file_path, filename}, ...]}` in single POST to `/qr-trigger` | Single socket call, atomic stash creation. Avoids N sequential socket calls from the sandboxed extension. | N separate `/qr-trigger` calls: rejected — slower, partial-failure complexity. |
| D5 | iOS download: show aggregated progress "Downloading X of Y" with per-file save actions | Consistent with existing mobile-to-PC batch progress UX. Users can save files individually or save all. | Save-all-only: rejected — reduces user control. Background download: rejected — adds complexity for a short-lived QR flow. |
| D6 | QR trigger mini window: show "Sharing N files" with a scrollable filename list | Simple, informative. Reuses existing mini window infrastructure. No need for a full redesign. | Thumbnail previews: rejected — requires file reading/rendering in the mini window, adds latency and complexity. |

## Risks / Trade-offs

- **[R1] Large file count (e.g., 50+ files selected in Finder)**: The QR code window could overflow with filenames.
  → Mitigation: Cap the filename list display at 10 entries with "+N more files..." below. Stash also enforces a max file count (configurable, default 50).

- **[R2] iOS download of many files over potentially slow Wi-Fi**: Sequential downloads could time out the QR claim window (5 min default).
  → Mitigation: Extend the stash TTL when the first file download starts (reset to 5 min). Show per-file download speed and estimated remaining time on iOS.

- **[R3] Partial batch failure during iOS download**: If file 3 of 5 fails, the user should still get files 1, 2, 4, 5.
  → Mitigation: Per-file download with independent error handling. Failed files are skipped; successful files are saved. The mini window shows a summary at the end.

- **[R4] API breaking change — `/transfer/download` renamed to `/transfer/manifest`**: Old iOS clients that call `/transfer/download` expecting inline file bytes will break.
  → Mitigation: This is a coordinated PC + iOS update. The `/transfer/manifest` + `/transfer/download/<index>` pattern ships together. Old iOS clients on the old `/transfer/download` path receive a 404 after PC update, which must be handled gracefully (upgrade prompt). The `/qr-trigger` handler is backward-compatible with old macOS extensions (detects `file_path` vs `files` key).

## Open Questions

- **Q1**: Should the iOS client offer a "Save All" button in addition to per-file save? (Design assumes yes — requires user research.)
- **Q2**: Maximum batch file count — is 50 reasonable? Configurable via `instant_share.max_batch_file_count` in config? (Starting default: 50)
