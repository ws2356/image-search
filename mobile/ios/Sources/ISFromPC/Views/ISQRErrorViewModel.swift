import Common

@MainActor
class ISQRErrorViewModel: ErrorPageViewDelegate {
    let title: String
    let message: String
    private let onRetry: () async -> Void
    private let onDismiss: () async -> Void

    init(title: String, message: String, onRetry: @escaping () async -> Void, onDismiss: @escaping () async -> Void) {
        self.title = title
        self.message = message
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    func retryTapped() async {
        await onRetry()
    }

    func cancelTapped() async {
        await onDismiss()
    }
}
