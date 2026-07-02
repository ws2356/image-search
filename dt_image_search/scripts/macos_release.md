# macOS Release Guide

End-to-end workflow for building and distributing a signed, notarized AuSearch PKG installer.

---

## Prerequisites

| What | Where / How |
|---|---|
| Developer ID Application certificate | Keychain Access — note the exact name, e.g. `Developer ID Application: First Last (TEAMID)` |
| Developer ID Installer certificate | Keychain Access — note the exact name, e.g. `Developer ID Installer: First Last (TEAMID)` |
| App-specific password | <https://appleid.apple.com/account/manage> → App-Specific Passwords |
| Apple Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| Python 3.10 venv | `source /path/to/.venv_python3.10/bin/activate` |

Export these before running any distribution step:

```bash
export DEVELOPER_ID_IDENTITY="Developer ID Application: First Last (TEAMID)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: First Last (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="ABCDE12345"
```

---

## Step 1 — Build the .app bundle

```bash
cd /path/to/image-search

# Production build (outputs to pyinstaller-dist-prod/AuSearch.app)
bash dt_image_search/scripts/build_pyinstaller.sh --build-type prod
```

> **Note:** UPX is automatically disabled on macOS (it would break code signatures).
> Version and display-name keys come from `dt_image_search/resources/AppInfo.plist`,
> which is read by the spec at build time.  Update that file and commit it before
> building a release.

---

## Step 2 — Full distribution pipeline (recommended)

`create_distributable_pkg.sh` runs all remaining steps in order:
**codesign → package & sign PKG → notarize → staple**.

```bash
bash dt_image_search/scripts/create_distributable_pkg.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app
```

Use `--skip-notarize` to build and sign locally without submitting to Apple:

```bash
bash dt_image_search/scripts/create_distributable_pkg.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --skip-notarize
```

---

## Step-by-step (individual scripts)

### 2a — Codesign the .app

Signs all Mach-O binaries inside-out with Hardened Runtime (no deprecated `--deep` flag).

```bash
bash dt_image_search/scripts/codesign_app.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app
# identity read from $DEVELOPER_ID_IDENTITY
```

Entitlements: `dt_image_search/scripts/AuSearch.entitlements`

### 2b — Package and sign the PKG

Creates a signed distribution PKG (.app + LaunchAgent postinstall script).

```bash
bash dt_image_search/scripts/build_pkg.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app
# installer identity read from $DEVELOPER_ID_INSTALLER
```

### 2c — Notarize

Submits the **signed** PKG to Apple and waits for an `Accepted` result.
The Apple rejection log is printed automatically on failure.

```bash
bash dt_image_search/scripts/notarize.sh \
    --pkg-path pyinstaller-dist-prod/AuSearch.pkg
# requires APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
```

Typical turnaround: 1–5 minutes.

### 2d — Staple

Embeds the notarization ticket so users can verify offline.

```bash
bash dt_image_search/scripts/staple_pkg.sh \
    --pkg-path pyinstaller-dist-prod/AuSearch.pkg
```

---

## What the PKG installer does

When the user runs the PKG:

1. **Copies `AuSearch.app` to `/Applications/`**
2. **Installs a LaunchAgent** at `~/Library/LaunchAgents/net.boldman.ausearch.instantshare.plist`
3. **Immediately starts the daemon** for the current console user via `launchctl bootstrap`
4. **LaunchAgent auto-starts** the instant share daemon at every subsequent login

The LaunchAgent runs `AuSearch --daemon`, which starts the mDNS advertiser,
bootstrap HTTP server, and Qt mini window factory — with **no visible window**
until a mobile device connects.

### Requested permissions

| Permission | How it's granted |
|---|---|
| Local network access (mDNS + HTTP) | `com.apple.security.network.server` and `com.apple.security.network.multicast` entitlements; `NSLocalNetworkUsageDescription` in Info.plist (system shows a one-time dialog) |
| Internet access (telemetry) | `com.apple.security.network.client` entitlement |
| Apple Events (Finder integration) | `com.apple.security.automation.apple-events` entitlement |

---

## Re-signing after a Python or dependency update

Any change to binaries inside the bundle — including updating Python itself or
adding/upgrading a pip package — invalidates the existing code signature.  You
must rebuild and go through the full distribution pipeline again.

### Why this is necessary

macOS enforces that every Mach-O file inside a signed `.app` matches the
signature recorded in the bundle seal.  If a dylib or `.so` file is replaced
(even by a byte-identical file with a different timestamp), the seal breaks and
Gatekeeper will reject the app.  There is no way to re-sign only part of the
bundle without redoing the whole signing + notarization chain.

### Steps

1. **Update the dependency** in your Python environment as usual
   (`pip install -U <package>`).

2. **Rebuild the .app** — this pulls in the new binaries:

   ```bash
   bash dt_image_search/scripts/build_pyinstaller.sh --build-type prod
   ```

3. **Re-run the full distribution pipeline:**

   ```bash
   bash dt_image_search/scripts/create_distributable_pkg.sh \
       --app-path pyinstaller-dist-prod/AuSearch.app
   ```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `codesign_app.sh` — `WARNING: could not sign …` | Non-Mach-O file detected by `file` (rare). Verify with `codesign -dvvv <file>`. |
| `spctl --assess` fails after `codesign_app.sh` | Expected — Gatekeeper only passes after notarization. |
| `notarize.sh` exits non-zero, prints Apple log | Fix the issues listed in the log (usually unsigned nested binary or missing entitlement), then re-run from step 2a. |
| `stapler validate` fails | Notarization not yet complete. Re-run `notarize.sh` first. |
| macOS firewall prompt blocks the server | Users must click **Allow**. Entitlements do not suppress this prompt. |
| LaunchAgent not loaded after install | Check `~/Library/LaunchAgents/net.boldman.ausearch.instantshare.plist` exists; manually run `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/net.boldman.ausearch.instantshare.plist` |

---

## Pre-release checklist

- [ ] `dt_image_search/resources/AppInfo.plist` version updated and committed
- [ ] `pip list` reviewed — no unintended dependency upgrades
- [ ] App launches and connects to iPhone on a clean macOS account
- [ ] `codesign --verify --deep --strict AuSearch.app` exits 0
- [ ] `spctl --assess --type execute AuSearch.app` exits 0 (after notarization)
- [ ] PKG installs and LaunchAgent starts on a test machine
- [ ] Instant share daemon runs without any visible window until mobile connects

---

## Create GitHub release via CLI

After you have the final PKG, create (or update) a GitHub release and upload the PKG asset:

```bash
bash dt_image_search/scripts/create_github_release.sh \
    --tag v1.2.3 \
    --title "AuSearch v1.2.3" \
    --notes-file ./release-notes.md \
    --pkg-path ./pyinstaller-dist-prod/AuSearch.pkg
```

You can also pass release notes inline with `--notes "..."`.
