import SwiftUI
import Combine

@MainActor
final class TransferPageViewModel: ObservableObject {
    private let model: any TransferPageModeling
    private var modelChangeCancellable: AnyCancellable?

    init(model: any TransferPageModeling) {
        self.model = model
        if let observableModel = model as? MobileAppModel {
            modelChangeCancellable = observableModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    var snapshot: TransferSnapshot {
        model.transferSnapshot
    }

    var isShowingStopConfirmation: Bool {
        model.isShowingStopConfirmation
    }

    var isShowingStopConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.model.isShowingStopConfirmation },
            set: { self.model.isShowingStopConfirmation = $0 }
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
