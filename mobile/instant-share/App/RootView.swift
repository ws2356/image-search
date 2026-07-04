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

enum ShareSheetContent: Identifiable {
    case scan
    case claim(QRClaimPayload)

    var id: String {
        switch self {
        case .scan: return "scan"
        case .claim(let payload): return payload.id
        }
    }
}

struct RootView: View {
    @Binding var sharePayload: QRClaimPayload?
    @State private var sheetContent: ShareSheetContent?

    var body: some View {
        NavigationView {
            DeviceManagementView(
                store: Store(initialState: DeviceManagementFeature.State()) {
                    DeviceManagementFeature()
                }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { sheetContent = .scan }) {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: sharePayload) { newPayload in
            if let payload = newPayload {
                sheetContent = .claim(payload)
            }
        }
        .fullScreenCover(item: $sheetContent) { content in
            switch content {
            case .scan:
                ISQRRootView(navigator: QRSheetNavigator(dismiss: { sheetContent = nil }))
            case .claim(let payload):
                ISQRRootView(
                    qrPayload: payload,
                    navigator: QRSheetNavigator(dismiss: {
                        sharePayload = nil
                        sheetContent = nil
                    })
                )
            }
        }
    }
}
