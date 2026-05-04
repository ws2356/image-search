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
        await model.beginPairing()
    }

    func beginPairingTapped() async {
        model.recordInteraction(name: "start_pairing_tapped", location: "pairing")
        await model.beginPairing()
    }

    func scanAgain() async {
        await model.openScanFlow()
    }

    func scanAgainTapped() async {
        model.recordInteraction(name: "scan_again_tapped", location: "pairing")
        await model.openScanFlow()
    }

    func goBack() async {
        await model.returnHome()
    }

    func backTapped() async {
        model.recordInteraction(name: "back_tapped", location: "pairing")
        await model.returnHome()
    }

    func openSettingsTapped() {
        model.recordInteraction(name: "open_settings_tapped", location: "pairing_scanner")
    }
}
