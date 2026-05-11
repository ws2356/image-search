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

    func beginPairing() async {
        await model.handleResultForPage(.pair, result: .success, target: .primary)
    }

    func beginPairingTapped() async {
        model.recordInteraction(name: "start_pairing_tapped", location: "pairing")
        await model.handleResultForPage(.pair, result: .success, target: .primary)
    }

    func scanAgain() async {
        await model.handleResultForPage(.pair, result: .success, target: .secondary)
    }

    func scanAgainTapped() async {
        model.recordInteraction(name: "scan_again_tapped", location: "pairing")
        await model.handleResultForPage(.pair, result: .success, target: .secondary)
    }

    func goBack() async {
        await model.handleResultForPage(.pair, result: .cancel, target: nil)
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
