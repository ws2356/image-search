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

    func scanAgain() async {
        await model.openScanFlow()
    }

    func goBack() async {
        await model.returnHome()
    }
}
