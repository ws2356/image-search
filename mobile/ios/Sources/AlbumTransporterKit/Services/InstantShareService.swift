import Foundation

/// Top-level service that coordinates the mDNS browser, bootstrap client,
/// and trust session for the mobile-side instant-share flow.
///
/// Lifecycle (PC-hosted architecture):
/// 1. `startDiscovery()` — starts mDNS browse for PC services
/// 2. `selectPC(_:)` — user picks a discovered PC
/// 3. `startSession(connectionConfig:)` — sends HTTP bootstrap to the PC
/// 4. Extension calls trust client: handshake → apply → confirm
/// 5. Extension calls upload client: upload text or image to PC
@MainActor
public final class InstantShareService: ObservableObject {
    @Published private(set) var mdnsBrowser: InstantShareMDNSBrowser
    @Published private(set) var trustSession: InstantShareTrustSessionManager
    @Published public var connectionConfig: InstantShareConnectionConfig?
    @Published private(set) var selectedPC: InstantShareDiscoveredPC?
    @Published public var currentPIN: String?
    @Published private(set) var sharedText: String = ""
    @Published private(set) var sharedImage: (data: Data, filename: String, contentType: String)?
    @Published private(set) var lastError: String?
    @Published private(set) var statusLog: [String] = []

    var sharedImageData: Data? {
        sharedImage?.data
    }

    var sharedImageFilename: String {
        sharedImage?.filename ?? ""
    }

    var sharedImageContentType: String {
        sharedImage?.contentType ?? "application/octet-stream"
    }

    private let bootstrapClient = InstantShareHTTPSessionBootstrapClient()

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

    /// Configure the shared image payload.
    func setSharedImage(data: Data, filename: String, contentType: String) {
        self.sharedImage = (data, filename, contentType)
        log("Shared image set (\(data.count) bytes, \(filename))")
    }

    /// Start the instant-share session by sending HTTP bootstrap to the PC.
    func startSession(connectionConfig: InstantShareConnectionConfig) async throws {
        self.connectionConfig = connectionConfig
        log("Starting instant-share session...")

        guard let pc = selectedPC else {
            log("No PC selected")
            throw InstantShareBootstrapError.invalidURL
        }

        do {
            try await bootstrapClient.sendBootstrap(
                to: pc.host,
                port: pc.port,
                connectionConfig: connectionConfig
            )
            log("Bootstrap sent to PC \(pc.name)")
        } catch {
            log("Failed to send bootstrap: \(error.localizedDescription)")
            throw error
        }

        log("Session started. Ready for trust handshake.")
    }

    /// Stop the session and clean up.
    func stopSession() {
        log("Stopping session...")
        trustSession.reset()
        currentPIN = nil
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