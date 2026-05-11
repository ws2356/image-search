import SwiftUI
import Combine

@MainActor
final class TransferPageViewModel: ObservableObject {
    private let model: any TransferPageModeling
    private var modelChangeCancellable: AnyCancellable?
    private var transferPollingTask: Task<Void, Never>?
    private var hasStartedTransferOrchestration = false

    @Published private(set) var snapshot: TransferSnapshot

    init(model: any TransferPageModeling) {
        self.model = model
        self.snapshot = model.transferSnapshot
        if let observableModel = model as? MobileAppModel {
            modelChangeCancellable = observableModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
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
        await model.confirmStopTransfer(currentSnapshot: snapshot)
    }

    func orchestrateTransfer() async {
        guard !hasStartedTransferOrchestration else {
            return
        }
        hasStartedTransferOrchestration = true

        startTransferPolling()
        let finalSnapshot = await model.transferServiceForTransferView.startTransfer(progress: { _ in })
        applySnapshotIfNewer(finalSnapshot)
        stopTransferPolling()
        guard model.route == .transfer else {
            model.persistSnapshot()
            return
        }

        await model.completeTransfer(with: snapshot)
    }

    func keepBackingUp() {
        model.recordInteraction(name: "stop_cancelled", location: "stop_confirmation")
    }

    private func startTransferPolling() {
        stopTransferPolling()
        let interval = model.transferProgressPollingIntervalNanoseconds
        transferPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if let inFlightSnapshot = await model.transferServiceForTransferView.progressSnapshot() {
                    await MainActor.run {
                        self.applySnapshotIfNewer(inFlightSnapshot)
                    }
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopTransferPolling() {
        transferPollingTask?.cancel()
        transferPollingTask = nil
    }

    private func applySnapshotIfNewer(_ newSnapshot: TransferSnapshot) {
        guard newSnapshot.transferredCount >= snapshot.transferredCount else {
            return
        }
        snapshot = newSnapshot
    }
}
