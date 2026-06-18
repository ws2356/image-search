import Foundation

/// Top-level service that coordinates the mDNS browser and trust session
/// for the mobile-side instant-share flow.
///
/// Lifecycle (PC-hosted architecture):
/// 1. `startDiscovery()` — starts mDNS browse for PC services
/// 2. `selectPC(_:)` — user picks a discovered PC
/// 3. `startSession(connectionConfig:)` — stores connection config (bootstrap is part of trust handshake)
/// 4. Extension calls trust client: handshake (includes bootstrap) → apply → confirm
/// 5. Extension calls upload client: upload text or image to PC
@MainActor
public final class InstantShareService: ObservableObject {
    @Published private(set) var mdnsBrowser: InstantShareMDNSBrowser
    @Published private(set) var trustSession: InstantShareTrustSessionManager
    @Published public var connectionConfig: InstantShareConnectionConfig?
    @Published private(set) var selectedPC: InstantShareDiscoveredPC?
    @Published private(set) var sharedText: String = ""
    @Published private(set) var sharedImage: (fileURL: URL, filename: String, contentType: String)?
    @Published private(set) var lastError: String?
    @Published private(set) var statusLog: [String] = []

    var sharedImageFileURL: URL? {
        sharedImage?.fileURL
    }

    var sharedImageFilename: String {
        sharedImage?.filename ?? ""
    }

    var sharedImageContentType: String {
        sharedImage?.contentType ?? "application/octet-stream"
    }

    public init() {
        let trustManager = InstantShareTrustSessionManager()
        self.trustSession = trustManager
        self.mdnsBrowser = InstantShareMDNSBrowser()
    }

    /// Start browsing for PCs via mDNS.
    func startDiscovery() {
        log("Starting mDNS discovery...")
        mdnsBrowser.startBrowsing()
    }

    /// Stop browsing.
    func stopDiscovery() {
        mdnsBrowser.stopBrowsing()
    }

    /// Select a discovered PC and prepare the session.
    func selectPC(_ pc: InstantShareDiscoveredPC) {
        selectedPC = pc
        log("Selected PC: \(pc.name) at \(pc.host):\(pc.port)")
    }

    /// Configure the shared text payload.
    func setSharedText(_ text: String) {
        self.sharedText = text
        log("Shared text set (\(text.count) chars)")
    }

    /// Configure the shared image payload from a file URL.
    func setSharedImage(fileURL: URL, filename: String, contentType: String) {
        self.sharedImage = (fileURL, filename, contentType)
        log("Shared image set (file: \(fileURL.lastPathComponent), \(filename))")
    }

    /// Start the instant-share session by storing the connection config.
    /// Bootstrap is now part of the trust handshake request to the PC.
    func startSession(connectionConfig: InstantShareConnectionConfig) async {
        self.connectionConfig = connectionConfig
        log("Session connection config stored")
    }

    /// Stop the session and clean up.
    func stopSession() {
        log("Stopping session...")
        trustSession.reset()
        connectionConfig = nil
        selectedPC = nil
        sharedText = ""
        sharedImage = nil
        log("Session stopped")
    }

    /// Reject trust when user declines or PIN doesn't match.
    func rejectTrust() {
        log("Trust rejected by user")
        trustSession.reset()
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        statusLog.append("[\(timestamp)] \(message)")
    }
}