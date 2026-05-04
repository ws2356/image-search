import SwiftUI

@MainActor
struct TransferPageViewModel {
    private let model: any TransferPageModeling

    init(model: any TransferPageModeling) {
        self.model = model
    }

    var snapshot: TransferSnapshot {
        model.transferSnapshot
    }

    var isShowingStopConfirmation: Bool {
        model.isShowingStopConfirmation
    }

    var isShowingStopConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingStopConfirmation },
            set: { model.isShowingStopConfirmation = $0 }
        )
    }

    func requestStopTransfer() {
        model.recordInteraction(name: "stop_backup_tapped", location: "transfer")
        model.requestStopTransfer()
    }

    func recordStopConfirmationPresented() {
        model.recordDialogView(name: "stop_confirmation")
    }

    func confirmStopTransfer() async {
        model.recordInteraction(name: "stop_confirmed", location: "stop_confirmation")
        await model.confirmStopTransfer()
    }

    func keepBackingUp() {
        model.recordInteraction(name: "stop_cancelled", location: "stop_confirmation")
    }
}
