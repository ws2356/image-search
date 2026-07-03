import Common
import ComposableArchitecture
import ISFromMobile
import SwiftUI

@main
struct InstantShareApp: App {
    init() {
        FontRegistration.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
                    .ignoresSafeArea()
            } else {
                FlowView(
                    store: Store(initialState: FlowFeature.State()) {
                        FlowFeature()
                    }
                )
            }
        }
    }
}
