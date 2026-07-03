import SwiftUI
import ISDeviceManagement
import ISFromPC
import ComposableArchitecture

struct QRSheetNavigator: Navigator {
    let dismiss: () -> Void
    func requestExit() {
        dismiss()
    }
}

struct RootView: View {
    @State private var showQRSheet = false

    var body: some View {
        NavigationView {
            DeviceManagementView(
                store: Store(initialState: DeviceManagementFeature.State()) {
                    DeviceManagementFeature()
                }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showQRSheet = true }) {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .fullScreenCover(isPresented: $showQRSheet) {
                ISQRRootView(navigator: QRSheetNavigator(dismiss: { showQRSheet = false }))
            }
        }
        .navigationViewStyle(.stack)
    }
}
