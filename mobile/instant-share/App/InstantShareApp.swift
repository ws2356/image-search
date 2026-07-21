import SwiftUI
import Common
import ISFromPC

@main
struct AppWrapper: App {
    let store: StoreOf<RootFeature> = Store(initialState: RootFeature.State()) {
        RootFeature()
    }

    init() {
        FontRegistration.registerCustomFonts()
    }

    public var body: some Scene {
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
