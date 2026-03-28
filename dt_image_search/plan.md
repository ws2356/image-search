## Plan: Telemetry Version & Package Tags

Add two global telemetry dimensions, app_version and package_type, so logs/traces/metrics are diagnosable by build identity. Implement a single runtime metadata resolver in Python, then inject values into OpenTelemetry Resource (global to logs/traces/metrics) and selected per-event attributes for consistency. Use package_type = msix for packaged production and package_type = debug for IDE runs; for debug app_version use empty string.

**Steps**
1. Discovery hardening and baseline checks.
2. Confirm current telemetry wiring in /Users/ws2356/dev/image-search/dt_image_search/telemetry/telemetry_client.py and startup metric call in /Users/ws2356/dev/image-search/dt_image_search/__main__.py to avoid missing attribute paths.
3. Confirm version source format in /Users/ws2356/dev/image-search/dt_image_search/resources/AppxManifest.xml and update behavior in /Users/ws2356/dev/image-search/dt_image_search/scripts/bump_app_version.ps1 so runtime parser expects 4-part version for msix.
4. Phase 1: Introduce runtime metadata resolver module (parallel-safe with Phase 2 prep).
5. Add a small helper module (recommended path: /Users/ws2356/dev/image-search/dt_image_search/telemetry/runtime_metadata.py) that computes app_version and package_type once at import time and exposes getters (or constants) for telemetry use.
6. package_type resolution logic:
7. If running debug from IDE/source (reuse /Users/ws2356/dev/image-search/dt_image_search/tools/dt_is_debug.py), return debug.
8. Otherwise return msix (per decision).
9. app_version resolution logic:
10. If package_type is debug, return empty string.
11. If package_type is msix, parse Version from AppxManifest.xml (namespace-aware XML read) and return the full manifest value.
12. If parsing fails in msix path, return empty string and emit one local warning log path that does not recurse telemetry export noise.
13. Phase 2: Inject metadata into telemetry providers (depends on Step 5).
14. Update Resource attributes in /Users/ws2356/dev/image-search/dt_image_search/telemetry/telemetry_client.py to include app_version and package_type alongside service.name, ensuring all OTLP logs/traces/metrics inherit these tags.
15. Extend span decorator path in /Users/ws2356/dev/image-search/dt_image_search/telemetry/telemetry_client.py within with_trace to set app_version and package_type on spans (keeps span-level queries explicit even if backend drops resource joins).
16. Extend metric attributes where explicit labels already exist:
17. Add app_version and package_type to error_counter labels in log().
18. Add app_version and package_type to startup_counter.add in /Users/ws2356/dev/image-search/dt_image_search/__main__.py.
19. Keep search metric behavior unchanged unless there is already a stable add() call path.
20. Phase 3: Packaging and resilience checks (depends on Phase 1 and 2).
21. Verify runtime metadata resolver works in non-Windows debug without attempting invalid msix manifest assumptions.
22. Verify resolver does not introduce circular imports with telemetry_client, dts_config, or bm_context.
23. Ensure failure paths do not raise during module import; telemetry initialization must remain non-fatal.
24. Verification phase.
25. Static checks: run py_compile (or equivalent) on /Users/ws2356/dev/image-search/dt_image_search/telemetry/telemetry_client.py, new runtime metadata module, and /Users/ws2356/dev/image-search/dt_image_search/__main__.py.
26. Runtime smoke (debug): launch from source and assert emitted telemetry/log context carries package_type=debug and app_version empty.
27. Runtime smoke (packaged/msix): run packaged app and assert telemetry carries package_type=msix with app_version from AppxManifest.xml Version.
28. Log verification: ensure no regressions in existing SSL-noise filtering behavior after attribute additions.

**Relevant files**
- /Users/ws2356/dev/image-search/dt_image_search/telemetry/telemetry_client.py — primary telemetry resource/span/log metric attribute injection points.
- /Users/ws2356/dev/image-search/dt_image_search/__main__.py — startup_counter.add call site for startup metric labels.
- /Users/ws2356/dev/image-search/dt_image_search/tools/dt_is_debug.py — debug/package runtime detection source of truth.
- /Users/ws2356/dev/image-search/dt_image_search/telemetry/runtime_metadata.py — new centralized resolver for app_version and package_type.
- /Users/ws2356/dev/image-search/dt_image_search/resources/AppxManifest.xml — authoritative msix version source at runtime.
- /Users/ws2356/dev/image-search/dt_image_search/scripts/bump_app_version.ps1 — production version injection pipeline to keep runtime parser assumptions aligned.

**Verification**
1. Run syntax validation for touched Python files.
2. Execute a small in-process probe to print resolved app_version/package_type in debug mode.
3. Trigger at least one traced function and one error log path; confirm attributes appear in exported payload/log backend dimensions.
4. In packaged/msix environment, validate app_version equals manifest Version and package_type equals msix.

**Decisions**
- Debug app_version value: empty string.
- Production package_type value: msix.
- app_version should be meaningful only for msix package type.
- Scope includes telemetry enrichment only (logs/traces/metrics); excludes redesign of packaging scripts and unrelated telemetry transport behavior.

**Further Considerations**
1. Manifest path resolution in packaged runtime can vary by working directory; prefer path resolution anchored to module/executable directory with deterministic fallback order.
2. If backend query ergonomics prefer semantic conventions, optionally add service.version as a duplicate of app_version in Resource attributes while retaining explicit app_version key for dashboards.
3. If future non-msix production targets are expected, reserve enum expansion strategy for package_type (for example, pyinstaller, msix, debug) without changing current msix output.