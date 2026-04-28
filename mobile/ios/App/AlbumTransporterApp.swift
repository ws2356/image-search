import AlbumTransporterKit
import SwiftUI

@main
struct AlbumTransporterApp: App {
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
