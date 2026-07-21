import SwiftUI
import Factory
import Common

#if os(iOS)
public struct MultiFileReceiveView: View {
    @StateObject public var viewModel: MultiFileReceiveViewModel

    public init(viewModel: MultiFileReceiveViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showShareSheet) {
                ShareSheet(items: viewModel.shareItems)
            }
            .task {
                await viewModel.startDownloadingAll()
            }
            .onDisappear {
                Task { await viewModel.cleanupDownloadedFiles() }
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if viewModel.isDownloading {
                progressBanner
            }

            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    ForEach(viewModel.fileStates) { state in
                        FileCard(state: state) {
                            viewModel.shareState(state)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }

            if viewModel.fileStates.contains(where: { !$0.isInline || $0.status == .downloaded }) {
                shareAllButton
            }
        }
        .background(DesignSystem.Colors.background)
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Received")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(DesignSystem.Colors.foreground)

                Text("\(viewModel.totalCount) \(viewModel.totalCount == 1 ? "item" : "items") from MacBook Pro")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Button("Done") {
                viewModel.delegate.onDeliverComplete()
            }
            .font(DesignSystem.Typography.h4)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    private var progressBanner: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(DesignSystem.Colors.primary)

            Text("Receiving file \(viewModel.downloadedCount + 1) of \(viewModel.totalCount)…")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    private var shareAllButton: some View {
        Button(action: { viewModel.shareAll() }) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
                Text("Share All (\(viewModel.downloadedCount))")
                    .font(DesignSystem.Typography.h4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.md)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
