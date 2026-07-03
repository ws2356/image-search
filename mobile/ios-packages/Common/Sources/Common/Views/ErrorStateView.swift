import SwiftUI

@MainActor
public protocol ErrorPageViewDelegate: ObservableObject {
    var title: String { get }
    var message: String { get }

    func retryTapped() async

    func cancelTapped() async
}

public struct ErrorStateView<DelegateType: ErrorPageViewDelegate>: View {
    @StateObject private var viewModel: DelegateType
    
    public init(viewModelFactory: @escaping () -> DelegateType) {
        self._viewModel = StateObject(wrappedValue: viewModelFactory())
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    heroCircle(
                        icon: "exclamationmark.triangle.fill",
                        gradient: [Color(hex: 0xFF453A), Color(hex: 0xC02020)]
                    )

                    Text(viewModel.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text(viewModel.message)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                ActionButton(
                    title: "Try Again",
                    icon: "arrow.clockwise",
                    style: .primary,
                    action: {
                        Task {
                            await viewModel.retryTapped()
                        }
                    }
                )

                ActionButton(
                    title: "Back to Home",
                    icon: "house",
                    style: .secondary,
                    action: {
                        Task {
                            await viewModel.cancelTapped()
                        }
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .compatibleScrollBounceBasedOnSize()
        .appNavigationBar(title: viewModel.title)
    }
}
