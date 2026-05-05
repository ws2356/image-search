import SwiftUI
import Combine

@MainActor
final class TransferPageViewModel: ObservableObject, ViewModelProtocol {
    private let model: any TransferPageModeling
    private var modelChangeCancellable: AnyCancellable?
    private let onPageResultHandler: ((_ result: PageResult, _ target: PageTarget?) -> Void)?

    init(
        model: any TransferPageModeling,
        onPageResult: ((_ result: PageResult, _ target: PageTarget?) -> Void)? = nil
    ) {
        self.model = model
        self.onPageResultHandler = onPageResult
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
        if onPageResultHandler != nil {
            onPageResult(.success, target: .primary)
            return
        }
        model.requestStopTransfer()
    }

    func recordStopConfirmationPresented() {
        model.recordDialogView(name: "stop_confirmation")
    }

    func confirmStopTransfer() async {
        model.recordInteraction(name: "stop_confirmed", location: "stop_confirmation")
        if onPageResultHandler != nil {
            onPageResult(.cancel, target: .stopTransferConfirmed)
            return
        }
        await model.confirmStopTransfer()
    }

    func keepBackingUp() {
        model.recordInteraction(name: "stop_cancelled", location: "stop_confirmation")
    }

    func onPageResult(_ result: PageResult, target: PageTarget?) {
        onPageResultHandler?(result, target)
    }
}
