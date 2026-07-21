import SwiftUI
import Factory
import Common

#if os(iOS)
@MainActor
public class MultiFileReceiveViewModel: ObservableObject {
    public let manifest: MultiFileManifest
    public let host: String
    public let tlsPort: Int
    public let sessionId: String
    public let correlationID: String
    public let delegate: ISQRDeliverDelegate

    @Published public internal(set) var fileStates: [FileDownloadState]
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
        public var textPreviewContent: String? {
            TextPreviewContentResolver.resolve(
                inlineContent: inlineContent,
                contentType: contentType,
                result: result
            )
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
            let result: QRClaimResult? = {
                guard let content = entry.content else { return nil }
                switch entry.type {
                case "text": return .text(content)
                case "html": return .html(content)
                case "link": return .link(content)
                default: return nil
                }
            }()
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

    /// Creates a view model for any single `QRClaimResult`.
    /// Inline results are pre-populated; downloadable results are already on disk.
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
        case .text(let text):
            self.fileStates = [FileDownloadState(
                index: 0, entryType: "text", filename: "Shared Text",
                contentType: "text/plain", sizeBytes: text.utf8.count,
                inlineContent: text, status: .downloaded, result: singleResult
            )]
        case .html(let html):
            self.fileStates = [FileDownloadState(
                index: 0, entryType: "html", filename: "Shared Note",
                contentType: "text/html", sizeBytes: html.utf8.count,
                inlineContent: html, status: .downloaded, result: singleResult
            )]
        case .link(let urlString):
            self.fileStates = [FileDownloadState(
                index: 0, entryType: "link", filename: "Web Link",
                contentType: "text/uri-list", sizeBytes: urlString.utf8.count,
                inlineContent: urlString, status: .downloaded, result: singleResult
            )]
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
        case .multiFile:
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

    public func shareAll() {
        let states = fileStates.filter { $0.status == .downloaded || $0.isInline }
        presentShareSheet(for: states)
    }

    public func shareState(_ state: FileDownloadState) {
        presentShareSheet(for: [state])
    }

    public func shareSelected() {
        let states = selectedIndices.sorted().compactMap { index in
            fileStates.first { $0.index == index }
        }
        presentShareSheet(for: states)
    }

    private func presentShareSheet(for states: [FileDownloadState]) {
        var items: [Any] = []

        for state in states {
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
#endif
