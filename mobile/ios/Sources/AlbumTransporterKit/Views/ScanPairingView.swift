import SwiftUI

struct ScanPairingView: View {
    let status: PairingStatus
    @Binding var scannedQRCodeValue: String
    let onStartPairing: () -> Void
    let onBack: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            LiveQRCodeScannerScreen(
                status: status,
                scannedQRCodeValue: $scannedQRCodeValue,
                onStartPairing: onStartPairing,
                onBack: onBack,
                onOpenSettings: onOpenSettings
            )
            .toolbar(.hidden, for: .navigationBar)
        } else {
            LiveQRCodeScannerScreen(
                status: status,
                scannedQRCodeValue: $scannedQRCodeValue,
                onStartPairing: onStartPairing,
                onBack: onBack,
                onOpenSettings: onOpenSettings
            )
            .navigationBarHidden(true)
        }
        #else
        PairingStatusView(
            status: status,
            onScanAgain: onStartPairing,
            onBack: onBack
        )
        #endif
    }
}
