fastlane documentation
----

# Authentication

Fastlane now prefers App Store Connect API key auth via `API_KEY_ID` and `API_KEY_FILE_PATH` in `mobile/ios/fastlane/.env.credential`; `API_KEY_ISSUER_ID` is optional for individual keys. Manual signing uses `IOS_CODE_SIGN_IDENTITY` and, when `IOS_SIGNING_STYLE=manual`, `IOS_PROVISIONING_PROFILE_SPECIFIER` from `mobile/ios/fastlane/.env`.

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios prerelease_check

```sh
[bundle exec] fastlane ios prerelease_check
```

Validate Fastlane, signing, and upload prerequisites

### ios build_ipa

```sh
[bundle exec] fastlane ios build_ipa
```

Archive and export an App Store Connect IPA using the repo script

### ios app_store_release

```sh
[bundle exec] fastlane ios app_store_release
```

Build and upload the IPA and/or metadata to App Store Connect

### ios release_binary

```sh
[bundle exec] fastlane ios release_binary
```

Build and upload only the IPA to App Store Connect

### ios release_metadata

```sh
[bundle exec] fastlane ios release_metadata
```

Upload only metadata to App Store Connect

### ios release_all

```sh
[bundle exec] fastlane ios release_all
```

Build and upload both IPA and metadata to App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
