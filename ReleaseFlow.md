1. Package AuSearch and notarize (macOS) / Create MSIX (Windows)
2. Release dmg via Github Releases - https://github.com/ws2356/ausearch-release.git
3. Release download site - web/. Get the latest dmg link and update `web/.env` variable AUSEARCH_MACOS_DOWNLOAD_URL=&lt;link to new dmg&gt;
4. Download iOS app metadata, update it, then upload to App Store Connect via Fastlane
5. Build iOS app via Fastlane, then upload to App Store Connect via Fastlane