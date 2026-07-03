import Common

enum ErrorHandlingResult {
    case retry
    case cancel
}

@MainActor
protocol ISQRErrorDelegate {
    func onErrorHandlingResult(_ result: ErrorHandlingResult) -> Void
}

@MainActor
class ISQRErrorViewModel: ErrorPageViewDelegate {
    let title: String
    let message: String
    let delegate: ISQRErrorDelegate

    init(title: String, message: String, delegate: ISQRErrorDelegate) {
        self.title = title
        self.message = message
        self.delegate = delegate
    }

    func retryTapped() async {
        await delegate.onErrorHandlingResult(.retry)
    }

    func cancelTapped() async {
        await delegate.onErrorHandlingResult(.cancel)
    }
}
