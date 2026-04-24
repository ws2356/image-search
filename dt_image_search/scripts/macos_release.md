# macOS Release Guide

End-to-end workflow for building and distributing a signed, notarized AuSearch DMG.

---

## Prerequisites

| What | Where / How |
|---|---|
| Developer ID Application certificate | Keychain Access — note the exact name, e.g. `Developer ID Application: First Last (TEAMID)` |
| App-specific password | <https://appleid.apple.com/account/manage> → App-Specific Passwords |
| Apple Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| Python 3.10 venv | `source /path/to/.venv_python3.10/bin/activate` |

Export the three notarization secrets before running any distribution step:

```bash
export DEVELOPER_ID_IDENTITY="Developer ID Application: First Last (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="ABCDE12345"
```

---

## Step 0 — Update the version

Edit `dt_image_search/resources/AppInfo.plist` and set the new version string, then commit it:

```xml
<key>CFBundleShortVersionString</key>
<string>1.2.3</string>

<key>CFBundleVersion</key>
<string>1.2.3</string>
```

The spec reads this file at build time; no patching scripts are needed.

---

## Step 1 — Build the .app bundle

```bash
cd /path/to/image-search

# Production build (outputs to pyinstaller-dist-prod/AuSearch.app)
bash dt_image_search/scripts/build_pyinstaller.sh --build-type prod
```

> **Note:** UPX is automatically disabled on macOS (it would break code signatures).

---

## Step 2 — Full distribution pipeline (recommended)

The `distribute_macos.sh` script runs all remaining steps in order:
codesign → package DMG → notarize → staple.

```bash
bash dt_image_search/scripts/distribute_macos.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --output   dist/AuSearch-1.2.3.dmg
```

Use `--skip-notarize` to build and sign locally without submitting to Apple:

```bash
bash dt_image_search/scripts/distribute_macos.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --output   dist/AuSearch-1.2.3.dmg \
    --skip-notarize
```

---

## Step-by-step (individual scripts)

Run these when you need finer control over each phase.

### 2a — Codesign

Signs all Mach-O binaries inside-out with Hardened Runtime.

```bash
bash dt_image_search/scripts/codesign_app.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app
# identity read from $DEVELOPER_ID_IDENTITY
```

Entitlements: `dt_image_search/scripts/AuSearch.entitlements`

### 2b — Package DMG

Creates a compressed DMG with a drag-to-/Applications layout, then signs it.

```bash
bash dt_image_search/scripts/package_dmg.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --output   dist/AuSearch-1.2.3.dmg
```

### 2c — Notarize

Submits the DMG to Apple and waits for an `Accepted` result.
The Apple rejection log is printed automatically on failure.

```bash
bash dt_image_search/scripts/notarize.sh \
    --dmg-path dist/AuSearch-1.2.3.dmg
# requires APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
```

### 2d — Staple

Embeds the notarization ticket so users can verify offline.

```bash
bash dt_image_search/scripts/staple_dmg.sh \
    --dmg-path dist/AuSearch-1.2.3.dmg
```

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
   bash dt_image_search/scripts/distribute_macos.sh \
       --app-path pyinstaller-dist-prod/AuSearch.app \
       --output   dist/AuSearch-<version>.dmg
   ```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `codesign_app.sh` — `WARNING: could not sign …` | Non-Mach-O files that `file` matched (rare). Verify with `codesign -dvvv <file>`. |
| `spctl --assess` fails after `codesign_app.sh` | Expected — Gatekeeper only passes after notarization. |
| `notarize.sh` exits non-zero, prints Apple log | Fix the issues in the log (usually unsigned nested binary or missing entitlement), then re-run from step 2a. |
| `stapler validate` fails | Notarization may not have completed. Re-run `notarize.sh` first. |
| macOS firewall prompt blocks the server | Users must click **Allow**. Entitlements do not suppress this prompt. |

---

## Pre-release checklist

- [ ] `dt_image_search/resources/AppInfo.plist` version updated and committed
- [ ] `pip list` reviewed — no unintended dependency upgrades
- [ ] App launches and connects to iPhone on a clean macOS account
- [ ] `codesign --verify --deep --strict AuSearch.app` exits 0
- [ ] `spctl --assess --type execute AuSearch.app` exits 0 (after notarization)
- [ ] DMG mounts and drag-to-/Applications works on a test machine
