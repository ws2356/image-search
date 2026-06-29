import SwiftUI
import Factory
import Common

@MainActor
public class MultiFileReceiveViewModel: ObservableObject {
    public let manifest: MultiFileManifest
    public let host: String
    public let tlsPort: Int
    public let sessionId: String
    public let correlationID: String
    public let delegate: ISQRDeliverDelegate

    @Published public private(set) var fileStates: [FileDownloadState]
    @Published public private(set) var isDownloading = false
    @Published public var selectedIndices: Set<Int> = []
    @Published public var shareItems: [Any] = []
    @Published public var showShareSheet = false
    @Published public var downloadError: String? = nil

    @Injected(\.appIdentityProvider) private(set) var appIdentityProvider: AppIdentityProviding

    public struct FileDownloadState: Identifiable {
        public let index: Int
        public let entryType: String
        public let filename: String
        public let contentType: String
        public let sizeBytes: Int
        public let inlineContent: String?
        public var status: DownloadStatus = .pending
        public var result: QRClaimResult? = nil
        public var errorMessage: String? = nil

        public var id: Int { index }
        public var isInline: Bool { entryType == "text" || entryType == "html" || entryType == "link" }
        public var downloadedTextContent: String? {
            switch result {
            case .text(let content): return content
            case .html(let html): return html
            case .link(let urlString): return urlString
            default: return nil
            }
        }
        public var isSelectable: Bool { isInline || status == .downloaded }

        public enum DownloadStatus {
            case pending
            case downloading
            case downloaded
            case failed
        }
    }

    public init(
        manifest: MultiFileManifest,
        host: String,
        tlsPort: Int,
        sessionId: String,
        correlationID: String,
        delegate: ISQRDeliverDelegate,
    ) {
        self.manifest = manifest
        self.host = host
        self.tlsPort = tlsPort
        self.sessionId = sessionId
        self.correlationID = correlationID
        self.delegate = delegate
        self.fileStates = manifest.files.map { entry in
            let initialStatus: FileDownloadState.DownloadStatus = entry.isInline ? .downloaded : .pending
            let result: QRClaimResult? = entry.isInline
                ? .text(entry.content ?? "")
                : nil
            return FileDownloadState(
                index: entry.index,
                entryType: entry.type,
                filename: entry.filename,
                contentType: entry.contentType,
                sizeBytes: entry.sizeBytes,
                inlineContent: entry.content,
                status: initialStatus,
                result: result
            )
        }
    }

    /// Creates a view model for a single pre-downloaded image or file result.
    /// Downloads are skipped because the result is already available on disk.
    public init(
        singleResult: QRClaimResult,
        delegate: ISQRDeliverDelegate
    ) {
        self.manifest = MultiFileManifest(fileCount: 1, files: [])
        self.host = ""
        self.tlsPort = 0
        self.sessionId = ""
        self.correlationID = ""
        self.delegate = delegate

        switch singleResult {
        case .image(let fileURL, let contentType, let filename):
            let displayName = filename ?? fileURL.lastPathComponent
            let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
            self.fileStates = [FileDownloadState(
                index: 0, entryType: "file", filename: displayName,
                contentType: contentType, sizeBytes: sizeBytes,
                inlineContent: nil, status: .downloaded, result: singleResult
            )]
        case .file(let fileURL, let contentType, let filename):
            let displayName = filename ?? fileURL.lastPathComponent
            let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0
            self.fileStates = [FileDownloadState(
                index: 0, entryType: "file", filename: displayName,
                contentType: contentType, sizeBytes: sizeBytes,
                inlineContent: nil, status: .downloaded, result: singleResult
            )]
        default:
            self.fileStates = []
        }
    }

    public func toggleSelection(at index: Int) {
        guard index < fileStates.count, fileStates[index].isSelectable else { return }
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }

    public func startDownloadingAll() async {
        let pendingCount = fileStates.filter { $0.status == .pending }.count
        guard pendingCount > 0 else { return }

        isDownloading = true
        defer { isDownloading = false }

        let client = QRTriggerDownloadClient(appIdentityProvider: appIdentityProvider)

        for i in fileStates.indices {
            guard !fileStates[i].isInline, fileStates[i].status == .pending else { continue }

            fileStates[i].status = .downloading

            do {
                let result = try await client.downloadFileAtIndex(
                    fileStates[i].index,
                    host: host,
                    port: tlsPort,
                    sessionId: sessionId,
                    correlationID: correlationID,
                    manifest: manifest
                )
                fileStates[i].result = result
                fileStates[i].status = .downloaded
            } catch {
                fileStates[i].status = .failed
                fileStates[i].errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    public func shareSelected() {
        presentShareSheetForSelected()
    }

    private func presentShareSheetForSelected() {
        var items: [Any] = []

        for index in selectedIndices.sorted() {
            guard index < fileStates.count else { continue }
            let state = fileStates[index]

            if state.isInline, let content = state.inlineContent {
                items.append(content)
                continue
            }

            guard let result = state.result else { continue }
            switch result {
            case .text(let text):
                items.append(text)
            case .html(let html):
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).html")
                try? html.data(using: .utf8)?.write(to: tempURL)
                items.append(tempURL)
            case .link(let urlString):
                if let url = URL(string: urlString) {
                    items.append(url)
                } else {
                    items.append(urlString)
                }
            case .image(let fileURL, _, _), .file(let fileURL, _, _):
                items.append(fileURL)
            case .multiFile:
                break
            }
        }

        guard !items.isEmpty else { return }
        shareItems = items
        showShareSheet = true
    }

    public var downloadedCount: Int {
        fileStates.filter { $0.status == .downloaded || $0.isInline }.count
    }

    public var failedCount: Int {
        fileStates.filter { $0.status == .failed }.count
    }

    public var totalCount: Int {
        fileStates.count
    }

    public func cleanupDownloadedFiles() async {
        for state in fileStates {
            guard let result = state.result else { continue }
            let urls = result.fileUrls
            for url in urls {
                try? await Task.detached {
                    try FileManager.default.removeItem(at: url)
                }.value
            }
        }
    }
}

public struct MultiFileReceiveView: View {
    @StateObject public var viewModel: MultiFileReceiveViewModel

    public init(viewModel: MultiFileReceiveViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        content
            .navigationTitle("Received Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { viewModel.delegate.onDeliverComplete() }
                        .font(DesignSystem.Typography.h4)
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
            }
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
        VStack(spacing: DesignSystem.Spacing.lg) {
            headerBanner
                .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.fileStates) { state in
                        fileRow(state)
                            .contentShape(Rectangle())
                            .opacity(state.isSelectable ? 1 : 0.6)
                            .onTapGesture {
                                if state.isSelectable {
                                    viewModel.toggleSelection(at: state.index)
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }

            VStack(spacing: DesignSystem.Spacing.md) {
                if viewModel.isDownloading {
                    ProgressView("Downloading \(viewModel.downloadedCount) of \(viewModel.totalCount)...")
                        .font(DesignSystem.Typography.body)
                        .tint(DesignSystem.Colors.primary)
                } else {
                    PrimaryButton(
                        title: viewModel.selectedIndices.isEmpty
                            ? "Select Files to Share"
                            : "Share (\(viewModel.selectedIndices.count) selected)",
                        icon: "square.and.arrow.up",
                        style: .primary
                    ) {
                        viewModel.shareSelected()
                    }
                    .disabled(viewModel.selectedIndices.isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var headerBanner: some View {
        CardView {
            HStack {
                if viewModel.isDownloading {
                    Label("Downloading \(viewModel.downloadedCount) of \(viewModel.totalCount)...", systemImage: "arrow.down.circle")
                        .foregroundStyle(DesignSystem.Colors.primary)
                } else if viewModel.failedCount > 0 {
                    Label("\(viewModel.downloadedCount) of \(viewModel.totalCount) available", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Colors.warning)
                } else if viewModel.downloadedCount == viewModel.totalCount {
                    Label("\(viewModel.totalCount) files — select to share", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.success)
                } else {
                    Label("\(viewModel.totalCount) files — select to share", systemImage: "square.and.arrow.up")
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
                Spacer()
                if viewModel.selectedIndices.count > 0 {
                    Text("\(viewModel.selectedIndices.count) selected")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            }
            .font(DesignSystem.Typography.body)
        }
    }

    @ViewBuilder
    private func fileRow(_ state: MultiFileReceiveViewModel.FileDownloadState) -> some View {
        let isSelected = viewModel.selectedIndices.contains(state.index)
        CardView {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.secondaryText)
                    .frame(width: 28)

                Image(systemName: iconName(for: state.contentType))
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    if state.isInline {
                        Text(state.inlineContent ?? "")
                            .font(DesignSystem.Typography.body)
                            .lineLimit(2)
                    } else if let textContent = state.downloadedTextContent {
                        Text(textContent)
                            .font(DesignSystem.Typography.body)
                            .lineLimit(5)
                        Text(state.filename.isEmpty ? "File \(state.index + 1)" : state.filename)
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    } else {
                        Text(state.filename.isEmpty ? "File \(state.index + 1)" : state.filename)
                            .font(DesignSystem.Typography.body)
                            .lineLimit(1)
                        Text(formatBytes(state.sizeBytes))
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }

                Spacer()

                switch state.status {
                case .pending:
                    Image(systemName: "clock")
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                case .downloading:
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(DesignSystem.Colors.primary)
                case .downloaded:
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.success)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.error)
                }
            }
        }
        .background(isSelected ? DesignSystem.Colors.selectedHighlight : Color.clear)
    }

    private func iconName(for contentType: String) -> String {
        let lowercased = contentType.lowercased()
        if lowercased.hasPrefix("image/") { return "photo" }
        if lowercased.hasPrefix("video/") { return "video" }
        if lowercased.hasPrefix("audio/") { return "music.note" }
        if lowercased.hasPrefix("text/uri-list") { return "link" }
        if lowercased.hasPrefix("text/") { return "doc.text" }
        if lowercased == "application/pdf" { return "doc.text" }
        return "doc"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}