import Common
import SwiftUI
import ISFromPC

@main
struct InstantShareApp: App {
    @State private var sharePayload: QRClaimPayload?

    init() {
        FontRegistration.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
                    .ignoresSafeArea()
            } else {
                RootView(sharePayload: $sharePayload)
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        guard let url = activity.webpageURL else { return }
                        if let payload = QRClaimPayload(universalLinkURL: url) {
                            sharePayload = payload
                        }
                    }
            }
        }
    }
}
