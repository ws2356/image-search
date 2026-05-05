import SwiftUI

@MainActor
struct PairingPageViewModel: ViewModelProtocol {
    private let model: any AppPageModeling
    private let onPageResultHandler: ((_ result: PageResult, _ target: PageTarget?) -> Void)?

    init(
        model: any AppPageModeling,
        onPageResult: ((_ result: PageResult, _ target: PageTarget?) -> Void)? = nil
    ) {
        self.model = model
        self.onPageResultHandler = onPageResult
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
        if onPageResultHandler != nil {
            onPageResult(.success, target: .primary)
            return
        }
        await model.beginPairing()
    }

    func scanAgain() async {
        await model.openScanFlow()
    }

    func scanAgainTapped() async {
        model.recordInteraction(name: "scan_again_tapped", location: "pairing")
        if onPageResultHandler != nil {
            onPageResult(.success, target: .secondary)
            return
        }
        await model.openScanFlow()
    }

    func goBack() async {
        await model.returnHome()
    }

    func backTapped() async {
        model.recordInteraction(name: "back_tapped", location: "pairing")
        if onPageResultHandler != nil {
            onPageResult(.cancel, target: nil)
            return
        }
        await model.returnHome()
    }

    func openSettingsTapped() {
        model.recordInteraction(name: "open_settings_tapped", location: "pairing_scanner")
    }

    func scannerFailed() {
        model.recordInteraction(name: "scanner_failed", location: "pairing_scanner")
        onPageResult(.failure, target: nil)
    }
    
    func onPageResult(_ result: PageResult, target: PageTarget?) {
        onPageResultHandler?(result, target)
    }
}
