#!/usr/bin/env bash

set -uo pipefail

ERRORS=0
WARNINGS=0

green="\033[32m"
yellow="\033[33m"
red="\033[31m"
cyan="\033[36m"
reset="\033[0m"

pass() {
    echo -e "${green}✔${reset} $1"
}

warn() {
    ((WARNINGS++))
    echo -e "${yellow}⚠ WARNING:${reset} $1"
}

fail() {
    ((ERRORS++))
    echo -e "${red}✘ ERROR:${reset} $1"
}

section() {
    echo
    echo -e "${cyan}$1${reset}"
}

###########################################################################
section "Java"

if command -v java >/dev/null 2>&1; then
    JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d. -f1)

    # Java 8 reports 1.8.x
    if [[ "$JAVA_MAJOR" == "1" ]]; then
        JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d. -f2)
    fi

    pass "Java found: $JAVA_VERSION"

    if (( JAVA_MAJOR < 17 )); then
        fail "Android development now requires JDK 17 or newer."
    elif (( JAVA_MAJOR == 17 )); then
        pass "JDK 17 detected (recommended)."
    elif (( JAVA_MAJOR <= 21 )); then
        pass "JDK $JAVA_MAJOR detected."
    else
        warn "JDK $JAVA_MAJOR is newer than commonly tested Android Studio versions."
    fi

else
    fail "Java is not installed."
fi

###########################################################################
section "JAVA_HOME"

if [[ -n "${JAVA_HOME:-}" ]]; then
    pass "JAVA_HOME=$JAVA_HOME"

    if [[ ! -d "$JAVA_HOME" ]]; then
        fail "JAVA_HOME does not exist."
    fi
else
    warn "JAVA_HOME is not set. macOS can usually infer it automatically, but setting it explicitly is recommended."
fi

###########################################################################
section "Android SDK"

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

if [[ -z "$SDK_ROOT" ]]; then
    if [[ -d "$HOME/Library/Android/sdk" ]]; then
        SDK_ROOT="$HOME/Library/Android/sdk"
        warn "ANDROID_SDK_ROOT is not set. Using default SDK location."
    fi
fi

if [[ -z "$SDK_ROOT" ]]; then
    fail "Android SDK not found."
else
    pass "SDK: $SDK_ROOT"

    if [[ ! -d "$SDK_ROOT" ]]; then
        fail "SDK directory does not exist."
    fi
fi

###########################################################################
section "adb"

ADB="$SDK_ROOT/platform-tools/adb"

if [[ -x "$ADB" ]]; then
    VERSION=$("$ADB" version | head -1)
    pass "$VERSION"
else
    fail "adb not found."
fi

###########################################################################
section "sdkmanager"

SDKMANAGER=""

for candidate in \
    "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
    "$SDK_ROOT/cmdline-tools/bin/sdkmanager" \
    "$SDK_ROOT/tools/bin/sdkmanager"
do
    if [[ -x "$candidate" ]]; then
        SDKMANAGER="$candidate"
        break
    fi
done

if [[ -n "$SDKMANAGER" ]]; then
    pass "sdkmanager found."
else
    fail "sdkmanager not found."
fi

###########################################################################
section "emulator"

EMU="$SDK_ROOT/emulator/emulator"

if [[ -x "$EMU" ]]; then
    pass "Android Emulator installed."
else
    warn "Android Emulator not installed."
fi

###########################################################################
section "AVD Manager"

AVDMANAGER=""

for candidate in \
    "$SDK_ROOT/cmdline-tools/latest/bin/avdmanager" \
    "$SDK_ROOT/cmdline-tools/bin/avdmanager" \
    "$SDK_ROOT/tools/bin/avdmanager"
do
    if [[ -x "$candidate" ]]; then
        AVDMANAGER="$candidate"
        break
    fi
done

if [[ -n "$AVDMANAGER" ]]; then
    pass "avdmanager found."
else
    warn "avdmanager not found."
fi

###########################################################################
section "SDK Packages"

if [[ -d "$SDK_ROOT/platform-tools" ]]; then
    pass "platform-tools installed."
else
    fail "platform-tools missing."
fi

if [[ -d "$SDK_ROOT/build-tools" ]]; then
    pass "build-tools installed."

    LATEST_BUILD=$(ls "$SDK_ROOT/build-tools" | sort -V | tail -1)
    pass "Latest Build Tools: $LATEST_BUILD"
else
    fail "build-tools missing."
fi

if [[ -d "$SDK_ROOT/platforms" ]]; then
    pass "Android platforms installed."

    LATEST_PLATFORM=$(
        ls "$SDK_ROOT/platforms" |
        grep '^android-' |
        sort -V |
        tail -1
    )

    if [[ -n "$LATEST_PLATFORM" ]]; then
        pass "Latest Platform: $LATEST_PLATFORM"
    fi
else
    fail "No Android platform installed."
fi

###########################################################################
section "PATH"

if command -v adb >/dev/null 2>&1; then
    pass "adb is in PATH."
else
    warn "adb is not in PATH."
fi

if command -v emulator >/dev/null 2>&1; then
    pass "emulator is in PATH."
else
    warn "emulator is not in PATH."
fi

###########################################################################
section "ADB Server"

if [[ -x "$ADB" ]]; then
    if "$ADB" start-server >/dev/null 2>&1; then
        pass "ADB server starts successfully."
    else
        warn "Unable to start adb server."
    fi
fi

###########################################################################
section "Summary"

echo

if (( WARNINGS > 0 )); then
    echo -e "${yellow}Warnings:${reset} $WARNINGS"
fi

if (( ERRORS > 0 )); then
    echo -e "${red}Errors:${reset} $ERRORS"
    echo
    echo -e "${red}Android development environment is NOT ready.${reset}"
    exit 1
fi

echo -e "${green}Android development environment is ready.${reset}"

if (( WARNINGS > 0 )); then
    echo
    echo "Some recommended configurations are missing."
fi