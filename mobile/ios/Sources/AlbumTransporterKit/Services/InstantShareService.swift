import Foundation

/// Top-level service that coordinates the mDNS browser, bootstrap client,
/// HTTPS server, and trust session for the mobile-side instant-share flow.
///
/// Lifecycle:
/// 1. `startDiscovery()` — starts mDNS browse for PC services
/// 2. `selectPC(_:)` — user picks a discovered PC
/// 3. `startSession(connectionConfig:)` — opens HTTPS server, generates PIN,
///    sends HTTP bootstrap to the PC, then waits for PC to connect
/// 4. PC calls /trust/handshake → /trust/apply (PIN) → /trust/confirm (long-poll)
/// 5. PC calls /payload/text or /payload/image
/// 6. PC calls /delivery-result
@MainActor
public final class InstantShareService: ObservableObject {
    @Published private(set) var mdnsBrowser: InstantShareMDNSBrowser
    @Published private(set) var httpsServer: InstantShareHTTPServer
    @Published private(set) var trustSession: InstantShareTrustSessionManager
    @Published public var connectionConfig: InstantShareConnectionConfig?
    @Published private(set) var selectedPC: InstantShareDiscoveredPC?
    @Published private(set) var currentPIN: String?
    @Published private(set) var sharedText: String = ""
    @Published private(set) var sharedImage: (data: Data, filename: String, contentType: String)?
    @Published private(set) var lastError: String?
    @Published private(set) var statusLog: [String] = []

    private let bootstrapClient = InstantShareHTTPSessionBootstrapClient()

    public init() {
        let trustManager = InstantShareTrustSessionManager()
        self.trustSession = trustManager
        self.httpsServer = InstantShareHTTPServer(trustManager: trustManager)
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
        httpsServer.setSharedText(text)
        log("Shared text set (\(text.count) chars)")
    }

    /// Configure the shared image payload.
    func setSharedImage(data: Data, filename: String, contentType: String) {
        self.sharedImage = (data, filename, contentType)
        httpsServer.setSharedImage(data: data, filename: filename, contentType: contentType)
        log("Shared image set (\(data.count) bytes, \(filename))")
    }

    /// Start the full instant-share session: HTTPS server + HTTP bootstrap.
    func startSession(connectionConfig: InstantShareConnectionConfig) async throws {
        self.connectionConfig = connectionConfig
        log("Starting instant-share session on port \(connectionConfig.mobilePort)...")

        guard let pc = selectedPC else {
            log("No PC selected")
            throw InstantShareHTTPServer.ServerError.invalidPort
        }

        // 1. Start the HTTPS server
        do {
            try httpsServer.start(port: UInt16(connectionConfig.mobilePort))
            log("HTTPS server started on port \(httpsServer.boundPort ?? UInt16(connectionConfig.mobilePort))")
        } catch {
            log("Failed to start HTTPS server: \(error.localizedDescription)")
            throw error
        }

        // 2. Generate a fresh PIN
        let pin = httpsServer.generatePIN()
        self.currentPIN = pin
        log("Generated PIN: \(pin)")

        // 3. Send HTTP bootstrap to PC (replaces BLE ConnectionConfig write)
        do {
            try await bootstrapClient.sendBootstrap(
                to: pc.host,
                port: pc.port,
                connectionConfig: connectionConfig
            )
            log("Bootstrap sent to PC \(pc.name)")
        } catch {
            log("Failed to send bootstrap: \(error.localizedDescription)")
            httpsServer.stop()
            throw error
        }

        log("Session started. Waiting for PC to connect...")
    }

    /// Stop the session and clean up.
    func stopSession() {
        log("Stopping session...")
        httpsServer.stop()
        trustSession.reset()
        currentPIN = nil
        connectionConfig = nil
        selectedPC = nil
        log("Session stopped")
    }

    /// Confirm trust after user verifies PIN match.
    func confirmTrust() {
        log("Trust confirmed by user")
        httpsServer.confirmTrust()
    }

    /// Reject trust when user declines or PIN doesn't match.
    func rejectTrust() {
        log("Trust rejected by user")
        httpsServer.rejectTrust()
        trustSession.reset()
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        statusLog.append("[\(timestamp)] \(message)")
    }
}
