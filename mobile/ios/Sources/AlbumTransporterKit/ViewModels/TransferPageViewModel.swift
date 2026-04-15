@MainActor
struct TransferPageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var snapshot: TransferSnapshot {
        model.transferSnapshot
    }

    func requestStopTransfer() {
        model.requestStopTransfer()
    }
}
