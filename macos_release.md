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

## Step 1 — Build the .app bundle

```bash
cd /path/to/image-search

# Production build (outputs to pyinstaller-dist-prod/AuSearch.app)
bash dt_image_search/scripts/build_pyinstaller.sh --build-type prod
```

> **Note:** UPX is automatically disabled on macOS (it would break code signatures).  
> The output directory is `pyinstaller-dist-prod/`.

---

## Step 2 — Full distribution pipeline (recommended)

The `distribute_macos.sh` script runs all remaining steps in order:
patch → codesign → package DMG → notarize → staple.

```bash
bash dt_image_search/scripts/distribute_macos.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --version  1.2.3 \
    --output   dist/AuSearch-1.2.3.dmg
```

The finished, stapled DMG is at `dist/AuSearch-1.2.3.dmg`.

Use `--skip-notarize` to build and sign locally without submitting to Apple:

```bash
bash dt_image_search/scripts/distribute_macos.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --version  1.2.3 \
    --output   dist/AuSearch-1.2.3.dmg \
    --skip-notarize
```

---

## Step-by-step (individual scripts)

Run the steps manually when you need finer control.

### 2a — Patch Info.plist

Must run **before** codesigning — editing Info.plist after signing invalidates the signature.

```bash
bash dt_image_search/scripts/setup_bundle_metadata.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --version  1.2.3
```

Adds/updates: `CFBundleShortVersionString`, `CFBundleVersion`,
`CFBundleDisplayName`, and `NSLocalNetworkUsageDescription`.

### 2b — Codesign

Signs all Mach-O binaries inside-out with Hardened Runtime.

```bash
bash dt_image_search/scripts/codesign_app.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app
# identity read from $DEVELOPER_ID_IDENTITY
```

Entitlements file used: `dt_image_search/scripts/AuSearch.entitlements`

### 2c — Package DMG

Creates a compressed DMG with a drag-to-/Applications layout, then signs it.

```bash
bash dt_image_search/scripts/package_dmg.sh \
    --app-path pyinstaller-dist-prod/AuSearch.app \
    --output   dist/AuSearch-1.2.3.dmg
```

### 2d — Notarize

Submits the DMG to Apple and waits for an `Accepted` result.
The Apple rejection log is printed automatically on failure.

```bash
bash dt_image_search/scripts/notarize.sh \
    --dmg-path dist/AuSearch-1.2.3.dmg
# requires APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
```

Typical turnaround: 1–5 minutes.

### 2e — Staple

Embeds the notarization ticket so users can verify offline.

```bash
bash dt_image_search/scripts/staple_dmg.sh \
    --dmg-path dist/AuSearch-1.2.3.dmg
```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `codesign_app.sh` — `WARNING: could not sign …` | Non-Mach-O files that `file` matched as Mach-O (rare). Verify with `codesign -dvvv <file>`. |
| `spctl --assess` fails after `codesign_app.sh` | Expected — Gatekeeper only passes after notarization. |
| `notarize.sh` exits non-zero, prints Apple log | Fix the issues listed in the log (usually unsigned nested binary or missing entitlement), then re-run from step 2b. |
| `stapler validate` fails with `The file … does not have a ticket stapled to it` | Notarization may not have completed. Re-run `notarize.sh` first. |
| macOS firewall prompt blocks the server | Users must click **Allow** when prompted. Entitlements do not suppress this prompt. |
