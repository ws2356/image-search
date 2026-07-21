#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${IOS_ROOT}/AlbumTransporterApp.xcodeproj}"
SCHEME="${SCHEME:-AlbumTransporterApp}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${IOS_ROOT}/build/derived-data}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${IOS_ROOT}/build/${SCHEME}.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-${IOS_ROOT}/build/ipa}"
EXPORT_METHOD="${EXPORT_METHOD:-app-store-connect}"
TEAM_ID="${TEAM_ID:-ZU6V838VRQ}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"
CODE_SIGN_IDENTITY_NAME="${CODE_SIGN_IDENTITY_NAME:-}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"
SIGNING_STYLE="${SIGNING_STYLE:-automatic}"
PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER:-}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-net.boldman.albumtransporter}"

usage() {
    cat <<'EOF'
Usage: export_ipa.sh

Environment overrides:
  PROJECT_PATH                 Xcode project path
  SCHEME                       Shared Xcode scheme (default: AlbumTransporterApp)
  CONFIGURATION                Build configuration (default: Release)
  DESTINATION                  xcodebuild destination (default: generic/platform=iOS)
  DERIVED_DATA_PATH            DerivedData output path
  ARCHIVE_PATH                 .xcarchive output path
  EXPORT_PATH                  Export directory for the IPA
  EXPORT_METHOD                Export method, e.g. app-store-connect, ad-hoc, development
  TEAM_ID                      Apple development team ID
  EXPORT_OPTIONS_PLIST         Existing ExportOptions.plist to use as-is
  ALLOW_PROVISIONING_UPDATES   Set to 1 to pass -allowProvisioningUpdates
  CLEAN_BUILD                  Set to 0 to skip the clean step before archive
  CODE_SIGN_IDENTITY_NAME      Optional code signing identity name from Keychain
  KEYCHAIN_PATH                Optional keychain path forwarded via OTHER_CODE_SIGN_FLAGS
  SIGNING_STYLE                automatic (default) or manual
  PROVISIONING_PROFILE_SPECIFIER Provisioning profile name/specifier for manual signing
  BUNDLE_IDENTIFIER            Bundle identifier used in ExportOptions.plist for manual signing
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 1
    fi
}

write_export_options_plist() {
    local plist_path="$1"
    {
        cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>${EXPORT_METHOD}</string>
    <key>signingStyle</key>
    <string>${SIGNING_STYLE}</string>
EOF
        if [[ -n "${CODE_SIGN_IDENTITY_NAME}" ]]; then
            cat <<EOF
    <key>signingCertificate</key>
    <string>${CODE_SIGN_IDENTITY_NAME}</string>
EOF
        fi
        if [[ "${SIGNING_STYLE}" == "manual" ]]; then
            cat <<EOF
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_IDENTIFIER}</key>
        <string>${PROVISIONING_PROFILE_SPECIFIER}</string>
    </dict>
EOF
        fi
        cat <<EOF
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF
    } >"${plist_path}"
}

main() {
    require_command xcodebuild

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    if [[ ! -d "${PROJECT_PATH}" ]]; then
        echo "error: project not found at ${PROJECT_PATH}" >&2
        exit 1
    fi
    if [[ -n "${KEYCHAIN_PATH}" && ! -f "${KEYCHAIN_PATH}" ]]; then
        echo "error: keychain not found at ${KEYCHAIN_PATH}" >&2
        exit 1
    fi
    if [[ "${SIGNING_STYLE}" != "automatic" && "${SIGNING_STYLE}" != "manual" ]]; then
        echo "error: SIGNING_STYLE must be 'automatic' or 'manual'" >&2
        exit 1
    fi
    if [[ "${SIGNING_STYLE}" == "manual" && -z "${PROVISIONING_PROFILE_SPECIFIER}" ]]; then
        echo "error: PROVISIONING_PROFILE_SPECIFIER is required when SIGNING_STYLE=manual" >&2
        exit 1
    fi

    mkdir -p "$(dirname "${ARCHIVE_PATH}")" "${EXPORT_PATH}" "${DERIVED_DATA_PATH}"

    local cleanup_plist="0"
    if [[ -z "${EXPORT_OPTIONS_PLIST}" ]]; then
        EXPORT_OPTIONS_PLIST="$(mktemp "${IOS_ROOT}/build/export-options.XXXXXX.plist")"
        cleanup_plist="1"
        write_export_options_plist "${EXPORT_OPTIONS_PLIST}"
    elif [[ ! -f "${EXPORT_OPTIONS_PLIST}" ]]; then
        echo "error: export options plist not found at ${EXPORT_OPTIONS_PLIST}" >&2
        exit 1
    fi

    if [[ "${cleanup_plist}" == "1" ]]; then
        trap 'rm -f "${EXPORT_OPTIONS_PLIST}"' EXIT
    fi

    local -a common_args=(
        -project "${PROJECT_PATH}"
        -scheme "${SCHEME}"
        -configuration "${CONFIGURATION}"
        -destination "${DESTINATION}"
        -derivedDataPath "${DERIVED_DATA_PATH}"
        DEVELOPMENT_TEAM="${TEAM_ID}"
    )
    if [[ "${ALLOW_PROVISIONING_UPDATES}" == "1" ]]; then
        common_args+=(-allowProvisioningUpdates)
    fi
    if [[ "${SIGNING_STYLE}" != "manual" ]]; then
        common_args+=(CODE_SIGN_STYLE="$(tr '[:lower:]' '[:upper:]' <<< "${SIGNING_STYLE:0:1}")${SIGNING_STYLE:1}")
    fi
    if [[ -n "${CODE_SIGN_IDENTITY_NAME}" && "${SIGNING_STYLE}" != "manual" ]]; then
        common_args+=(CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY_NAME}")
    fi
    if [[ -n "${KEYCHAIN_PATH}" ]]; then
        common_args+=(OTHER_CODE_SIGN_FLAGS="--keychain ${KEYCHAIN_PATH}")
    fi

    local -a archive_args=(archive -archivePath "${ARCHIVE_PATH}")
    if [[ "${CLEAN_BUILD}" == "1" ]]; then
        archive_args=(clean "${archive_args[@]}")
    fi

    echo "==> Archiving ${SCHEME} (${CONFIGURATION})"
    if [[ -n "${CODE_SIGN_IDENTITY_NAME}" ]]; then
        echo "==> Using code signing identity: ${CODE_SIGN_IDENTITY_NAME}"
    fi
    if [[ "${SIGNING_STYLE}" == "manual" ]]; then
        echo "==> Using provisioning profile during export: ${PROVISIONING_PROFILE_SPECIFIER}"
    fi
    xcodebuild "${common_args[@]}" "${archive_args[@]}"

    echo "==> Exporting IPA (${EXPORT_METHOD})"
    local -a export_args=(
        -exportArchive
        -archivePath "${ARCHIVE_PATH}"
        -exportPath "${EXPORT_PATH}"
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"
    )
    if [[ "${ALLOW_PROVISIONING_UPDATES}" == "1" ]]; then
        export_args+=(-allowProvisioningUpdates)
    fi
    xcodebuild "${export_args[@]}"

    local ipa_path
    ipa_path="$(find "${EXPORT_PATH}" -maxdepth 1 -name '*.ipa' -print -quit)"
    if [[ -z "${ipa_path}" ]]; then
        echo "warning: export completed but no .ipa file was found under ${EXPORT_PATH}" >&2
        exit 1
    fi

    echo "IPA exported to ${ipa_path}"

    local app_bundle
    app_bundle="$(find "${ARCHIVE_PATH}/Products" -name 'AuBackup.app' -type d -print -quit)"
    if [[ -n "${app_bundle}" ]]; then
        "${IOS_ROOT}/scripts/verify_build_metadata.sh" "${app_bundle}"
    fi
}

main "$@"
