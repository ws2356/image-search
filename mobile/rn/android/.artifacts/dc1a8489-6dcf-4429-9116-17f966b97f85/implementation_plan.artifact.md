# Fix Gradle Sync Error: 'command node' not found

The project fails to sync because Gradle cannot find the `node` executable when evaluating `settings.gradle`. This is a common issue in React Native/Expo projects when running from an IDE (like Android Studio) that doesn't inherit the full shell `PATH`.

## Proposed Changes

### [Component Name] Gradle Configuration

#### [MODIFY] [settings.gradle](file:///Users/ws2356/dev/device-connect/mobile/rn/android/settings.gradle)

I will add a `detectNode` helper function at the top of `settings.gradle` to robustly find the `node` binary and use it instead of the bare `"node"` command.

#### [MODIFY] [app/build.gradle](file:///Users/ws2356/dev/device-connect/mobile/rn/android/app/build.gradle)

I will also update `app/build.gradle` to use the same logic if possible, or ensure it's configured to use the detected node binary.

## Verification Plan

### Automated Tests
- Run `./gradlew :app:tasks` to verify that `settings.gradle` and `app/build.gradle` are evaluated successfully without the "command 'node'" error.

### Manual Verification
- Ask the user to perform a "Sync Project with Gradle Files" in Android Studio.
