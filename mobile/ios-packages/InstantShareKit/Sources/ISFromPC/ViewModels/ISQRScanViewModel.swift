import SwiftUI
import Common

#if os(iOS)
enum QRScanResult {
    case success(qrLink: String)
    case failure(error: Error)
    case canceled
    case changeSetting
}

@MainActor
protocol QRScanDelegate {
    func onQRScanResult(_ result: QRScanResult) async -> Void
}

@MainActor
class ISQRScanViewModel: ObservableObject, ScanningBaseViewModel {
    let delegate: QRScanDelegate

    init(delegate: QRScanDelegate) {
        self.delegate = delegate
    }

    func onQRScanned(scannedValue: String) async {
        await delegate.onQRScanResult(.success(qrLink: scannedValue))
    }

    func onScannerFailed(error: Error) async {
        await self.delegate.onQRScanResult(.failure(error: error))
    }

    func onBackTapped() async {
        await delegate.onQRScanResult(.canceled)
    }

    func onOpenSettingsTapped() async {
        await delegate.onQRScanResult(.changeSetting)
    }
}
#endif
