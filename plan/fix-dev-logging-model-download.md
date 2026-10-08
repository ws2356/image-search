# Fix: no log files + model download failure (dev build) — RESOLVED 2026-10-09

## Outcome
1. **No logs** — non-Qt entry points (shell, index server) now call
   `init_desktop_telemetry` → rotating `logs/app-utf8.log` in the app data dir.
   Verified for shell (smoke test) and server (extended
   tests/unit/test_index_server_app.py).
2. **Model download** — was an interrupted transfer (partial `model_cache.tmp`
   stalled at 34% of the 1.28 GB models.tar.gz; GitHub needs the system proxy).
   The downloader now resumes partial tmp across launches, validates checksums
   before extraction, times out HTTP, and pauses between retries. Verified
   live: resumed from 459 MB, checksum passed, extracted, model loaded.
3. **(Found via the new logs)** frozen model load crashed with a bare
   `IndexError` inside transformers 4.57 `auto_docstring` (short PyInstaller
   paths). Fixed with `dt_image_search/tools/transformers_frozen_compat.py`
   + tests/unit/test_transformers_frozen_compat.py; verified in the packaged
   dev build (attempt 1 load success, /health 200).

Pre-existing, out of scope: OTLP upload in the frozen app fails with
"Could not find a suitable TLS CA certificate bundle … /_internal/certifi/cacert.pem"
(certifi data not collected for the telemetry exporter). Also `git push` untested
locally due to GitHub auth device-flow errors.

Date: 2026-10-09

## Investigation results

### Issue 1: no log files in `~/Library/Application Support/net.boldman/imagesearch-dev/DTImageSearch-dev`
Root cause (confirmed):
- Dev build uses the Qt-free shell entry `dt_image_search/shell_main_entry.py` → `shell/shell_main.py`,
  which spawns the index server child `dt_image_search/index_server`.
- Neither process calls `init_telemetry(..., log_handlers=get_other_handlers())`. Only the legacy Qt
  `__main__.py` (unused, not the entry) and the instant-share agent do.
- `log()` falls back to `_ensure_initialized()` → stdout-only StreamHandler. Shell stdout is lost on
  GUI launch; server stdout is piped to `server_process._read_loop` which discards all non-`DTS_READY`
  lines. Net effect: zero local log files.

Fix: new shared bootstrap `pc_common/telemetry/desktop_telemetry.py::init_desktop_telemetry(service_name)`;
wire it in `shell_main.py` and `index_server/main.py::run_server` (server uses `debug_mode=True` —
stdout must stay intact for the `DTS_READY` handshake). Refactor Qt `__main__.py` and
`instant_share_agent_main.py` to use the same helper (DRY).

### Issue 2: model download failed
Evidence:
- DB config: `model_version=2`, `model_offline_mode=true` → v2 context downloads
  `model-all/models.tar.gz` (GitHub) at startup.
- Total size 1,368,863,911 (1.28 GB); `model_cache.tmp` stalled at 459,849,728 (~34%) at 00:00 with
  valid gzip magic → transfer interrupted mid-stream (network/proxy flakiness; system proxy
  127.0.0.1:7897 is used by `requests` automatically and works).
- Code made this worse:
  - After 3 failed attempts, `process_downloaded_file(tmp)` runs unconditionally → tries to extract an
    incomplete file → masks the real error.
  - `requests.get` has no timeout → hung connections block forever.
  - `Path(tmp).unlink()` at entry deletes partial tmp of previous runs → resume across restarts never applies.
  - No delay between retries.

Fix in `dts_model_downloader.py`:
- Keep tmp across attempts/launches; delete tmp only when a full-size checksum proves corruption.
- Extract only after a valid checksum; give up cleanly with a clear error otherwise.
- Timeout on the download request; small backoff between attempts.
- If server ignores Range (200 full body while partial exists) → restart from scratch (`wb`).

## Steps (TDD)
1. Red: extend `tests/unit/test_index_server_app.py` to assert `logs/app-utf8.log` is created by the server.
2. Implement fix 1 (helper + wiring + refactor of 2 existing entry points).
3. Green: rerun; manual direct-run of server & shell to inspect log content.
4. Red: `tests/unit/test_dts_model_downloader.py` (network/checksum mocked) for the 4 behaviors above.
5. Implement fix 2; add file to `dt_image_search/scripts/run_tests.sh`.
6. Green + full targeted test run.
7. Real-download verification: run server with `DTIS_BUILD_TYPE=dev` without `--skip-model-init`;
   confirm resume from existing 459MB tmp and successful extract.
8. Package dev app via `uv run dt_image_search/scripts/macos_release_flow.sh --skip-release --product main --build-type dev` and launch to verify both fixes in the packaged app.
