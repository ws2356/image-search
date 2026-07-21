import AlbumTransporterKit
import Common
import SwiftUI

@main
struct AlbumTransporterApp: App {
    init() {
        FontRegistration.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                Color.clear
                    .ignoresSafeArea()
            } else {
                AlbumTransporterRootView()
            }
        }
    }
}
