import SwiftUI

@MainActor
struct PairingPageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var status: PairingStatus {
        model.pairingStatus
    }

    var scannedQRCodeBinding: Binding<String> {
        Binding(
            get: { model.scannedQRCodeValue },
            set: { model.scannedQRCodeValue = $0 }
        )
    }

    func onQRScanned() async {
        model.recordInteraction(name: "start_pairing_tapped", location: "pairing")
        await model.handleResultForPage(.scan, result: .success, target: .primary)
    }

    func scanAgainTapped() async {
        model.recordInteraction(name: "scan_again_tapped", location: "pairing")
        await model.handleResultForPage(.pair, result: .success, target: .secondary)
    }

    func backTapped() async {
        model.recordInteraction(name: "back_tapped", location: "pairing")
        await model.handleResultForPage(.pair, result: .cancel, target: nil)
    }

    func openSettingsTapped() {
        model.recordInteraction(name: "open_settings_tapped", location: "pairing_scanner")
    }

    func scannerFailed() {
        model.recordInteraction(name: "scanner_failed", location: "pairing_scanner")
        Task { [model] in
            await model.handleResultForPage(.pair, result: .failure, target: nil)
        }
    }
}
