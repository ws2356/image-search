# fastlane documentation

## Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

## Available Actions

### iOS

#### ios prerelease_check

```sh
[bundle exec] fastlane ios prerelease_check
```

Validate Fastlane, signing, and upload prerequisites.

#### ios build_ipa

```sh
[bundle exec] fastlane ios build_ipa
```

Archive and export an App Store Connect IPA.

#### ios download_metadata

```sh
[bundle exec] fastlane ios download_metadata
```

Download current App Store Connect metadata into fastlane/metadata.

#### ios release_binary

```sh
[bundle exec] fastlane ios release_binary
```

Build and upload only the IPA to App Store Connect.

#### ios release_metadata

```sh
[bundle exec] fastlane ios release_metadata
```

Upload only metadata to App Store Connect.

#### ios release_all

```sh
[bundle exec] fastlane ios release_all
```

Build and upload both IPA and metadata to App Store Connect.

### Environment Variables

See `.env` and `.env.credential` for configuration.
