import Common
import SwiftUI
import ISFromPC
import ComposableArchitecture

@main
struct InstantShareApp: App {
    let store: StoreOf<RootFeature>

    init() {
        self.store = Store(initialState: RootFeature.State()) {
            RootFeature()
        }
        FontRegistration.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
                    .ignoresSafeArea()
            } else {
                RootView(store: store)
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        guard let url = activity.webpageURL else { return }
                        if let payload = QRClaimPayload(universalLinkURL: url) {
                            store.send(.receivedSharePayload(payload))
                        }
                    }
            }
        }
    }
}
