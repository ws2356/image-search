#!/usr/bin/env bash
set -euo pipefail

# Bump iOS app version keys in the Xcode project and App/Info.plist.
# Usage:
#   bump_version.sh --major
#   bump_version.sh --minor
#   bump_version.sh --patch
#
# Behavior:
# - Uses the Xcode project's MARKETING_VERSION and CURRENT_PROJECT_VERSION as the
#   source of truth.
# - Updates MARKETING_VERSION in the Xcode project and CFBundleShortVersionString
#   in App/Info.plist.
# - Increments CURRENT_PROJECT_VERSION by 1 and syncs CFBundleVersion to match.
# - Commits only the Xcode project and App/Info.plist unless NO_COMMIT=1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${IOS_ROOT}/../.." && pwd)"
PROJECT_PBXPROJ_PATH="${PROJECT_PBXPROJ_PATH:-${IOS_ROOT}/AlbumTransporterApp.xcodeproj/project.pbxproj}"
PLIST_PATH="${PLIST_PATH:-${IOS_ROOT}/App/Info.plist}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
NO_COMMIT="${NO_COMMIT:-0}"

usage() {
    cat <<'EOF'
Usage: bump_version.sh [--major | --minor | --patch]

Options:
  --major  Increase major by 1; reset minor/patch to 0
  --minor  Increase minor by 1; reset patch to 0
  --patch  Increase patch by 1

Environment overrides:
  PROJECT_PBXPROJ_PATH  Alternate project.pbxproj path for testing
  PLIST_PATH            Alternate Info.plist path for testing
  NO_COMMIT=1           Update files but skip git commit
EOF
}

require_file() {
    local path="$1"
    local description="$2"

    if [[ ! -f "$path" ]]; then
        echo "Error: missing ${description}: ${path}" >&2
        exit 1
    fi
}

extract_unique_project_value() {
    local key="$1"
    local -a values=()

    mapfile -t values < <(
        grep -Eo "${key} = [^;]+;" "${PROJECT_PBXPROJ_PATH}" \
            | sed -E 's/^[^=]+= ([^;]+);$/\1/' \
            | sort -u
    )

    if [[ ${#values[@]} -eq 0 ]]; then
        echo "Error: missing ${key} in ${PROJECT_PBXPROJ_PATH}" >&2
        exit 1
    fi
    if [[ ${#values[@]} -ne 1 ]]; then
        echo "Error: expected a single ${key} value in ${PROJECT_PBXPROJ_PATH}, found: ${values[*]}" >&2
        exit 1
    fi

    printf '%s\n' "${values[0]}"
}

replace_project_value() {
    local key="$1"
    local value="$2"

    sed -E -i '' "s/(${key} = )[^;]+;/\\1${value};/g" "${PROJECT_PBXPROJ_PATH}"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    --major|--minor|--patch) ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Error: unknown option '$1'" >&2
        usage
        exit 1
        ;;
esac

require_file "${PROJECT_PBXPROJ_PATH}" "Xcode project file"
require_file "${PLIST_PATH}" "Info.plist"
[[ -x "${PLIST_BUDDY}" ]] || { echo "Error: missing PlistBuddy at ${PLIST_BUDDY}" >&2; exit 1; }

current_marketing_version="$(extract_unique_project_value "MARKETING_VERSION")"
current_build_number="$(extract_unique_project_value "CURRENT_PROJECT_VERSION")"

if [[ ! "${current_marketing_version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: unsupported MARKETING_VERSION '${current_marketing_version}'. Expected X.Y.Z" >&2
    exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
if [[ ! "${current_build_number}" =~ ^[0-9]+$ ]]; then
    echo "Error: unsupported CURRENT_PROJECT_VERSION '${current_build_number}'. Expected an integer build number." >&2
    exit 1
fi

plist_marketing_version="$("${PLIST_BUDDY}" -c "Print :CFBundleShortVersionString" "${PLIST_PATH}")"
plist_build_number="$("${PLIST_BUDDY}" -c "Print :CFBundleVersion" "${PLIST_PATH}")"
if [[ "${plist_marketing_version}" != "${current_marketing_version}" || "${plist_build_number}" != "${current_build_number}" ]]; then
    echo "Info: normalizing ${PLIST_PATH} from ${plist_marketing_version} (${plist_build_number}) to ${current_marketing_version} (${current_build_number})."
fi

case "$1" in
    --major)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
    --minor)
        minor=$((minor + 1))
        patch=0
        ;;
    --patch)
        patch=$((patch + 1))
        ;;
esac

next_marketing_version="${major}.${minor}.${patch}"
next_build_number="$((current_build_number + 1))"

replace_project_value "MARKETING_VERSION" "${next_marketing_version}"
replace_project_value "CURRENT_PROJECT_VERSION" "${next_build_number}"
"${PLIST_BUDDY}" -c "Set :CFBundleShortVersionString ${next_marketing_version}" "${PLIST_PATH}"
"${PLIST_BUDDY}" -c "Set :CFBundleVersion ${next_build_number}" "${PLIST_PATH}"
plutil -lint "${PLIST_PATH}" >/dev/null

updated_marketing_version="$(extract_unique_project_value "MARKETING_VERSION")"
updated_build_number="$(extract_unique_project_value "CURRENT_PROJECT_VERSION")"
updated_plist_marketing_version="$("${PLIST_BUDDY}" -c "Print :CFBundleShortVersionString" "${PLIST_PATH}")"
updated_plist_build_number="$("${PLIST_BUDDY}" -c "Print :CFBundleVersion" "${PLIST_PATH}")"

if [[ "${updated_marketing_version}" != "${next_marketing_version}" || "${updated_plist_marketing_version}" != "${next_marketing_version}" ]]; then
    echo "Error: failed to update marketing version to ${next_marketing_version}" >&2
    exit 1
fi
if [[ "${updated_build_number}" != "${next_build_number}" || "${updated_plist_build_number}" != "${next_build_number}" ]]; then
    echo "Error: failed to update build number to ${next_build_number}" >&2
    exit 1
fi

if [[ "${NO_COMMIT}" == "1" ]]; then
    echo "Updated iOS version to ${next_marketing_version} (build ${next_build_number}) without committing."
    exit 0
fi

cd "${REPO_ROOT}"
git add "${PROJECT_PBXPROJ_PATH}" "${PLIST_PATH}"

if git diff --cached --quiet -- "${PROJECT_PBXPROJ_PATH}" "${PLIST_PATH}"; then
    echo "No version change detected; nothing to commit."
    exit 0
fi

git commit -m "Bump ios version to: ${next_marketing_version} (build ${next_build_number})" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" \
    -- "${PROJECT_PBXPROJ_PATH}" "${PLIST_PATH}"

echo "Updated and committed iOS version: ${next_marketing_version} (build ${next_build_number})"
