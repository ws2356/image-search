import CoreBluetooth
import Foundation

/// Top-level service that coordinates the BLE scanner, HTTPS server, trust
/// session, and shared payload for the mobile-side instant-share flow.
///
/// Lifecycle:
/// 1. `startDiscovery()` — starts BLE scan for PC peripherals
/// 2. `selectPC(_:)` — user picks a discovered peripheral
/// 3. `startSession(connectionConfig:sharedText:)` — opens HTTPS server,
///    generates a PIN, writes ConnectionConfig to the PC
/// 4. PC calls /trust/handshake → /trust/apply (PIN) → /trust/confirm (long-poll)
/// 5. PC calls /payload/text or /payload/image
/// 6. PC calls /delivery-result
@MainActor
public final class InstantShareService: ObservableObject {
    @Published private(set) var scanner: InstantShareBLEScanner
    @Published private(set) var httpsServer: InstantShareHTTPServer
    @Published private(set) var trustSession: InstantShareTrustSessionManager
    @Published private(set) var connectionConfig: InstantShareConnectionConfig?
    @Published private(set) var selectedPeripheral: InstantShareDiscoveredPeripheral?
    @Published private(set) var currentPIN: String?
    @Published private(set) var sharedText: String = ""
    @Published private(set) var sharedImage: (data: Data, filename: String, contentType: String)?
    @Published private(set) var lastError: String?
    @Published private(set) var statusLog: [String] = []
    @Published private(set) var selectedPeripheralInfo: InstantSharePeripheralInfo?

    private let connector = InstantShareBLEPeripheralConnector()

    public init() {
        let trustManager = InstantShareTrustSessionManager()
        self.trustSession = trustManager
        self.httpsServer = InstantShareHTTPServer(trustManager: trustManager)
        self.scanner = InstantShareBLEScanner()
    }

    /// Start scanning for PC peripherals.
    func startDiscovery() {
        log("Starting BLE discovery...")
        scanner.startScanning()
    }

    /// Stop scanning.
    func stopDiscovery() {
        scanner.stopScanning()
    }

    /// Select a discovered PC and prepare the session.
    func selectPC(_ peripheral: InstantShareDiscoveredPeripheral) {
        selectedPeripheral = peripheral
        log("Selected PC: \(peripheral.name ?? "Unknown") (RSSI: \(peripheral.rssi))")
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

    /// Start the full instant-share session: HTTPS server + BLE write.
    func startSession(connectionConfig: InstantShareConnectionConfig) async throws {
        self.connectionConfig = connectionConfig
        log("Starting instant-share session on port \(connectionConfig.mobilePort)...")

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

        // 3. Write ConnectionConfig to the PC
        guard let discovered = selectedPeripheral,
              let cbPeripheral = scanner.peripheral(for: discovered) else {
            log("No PC selected or peripheral not available")
            httpsServer.stop()
            throw InstantShareBLEPeripheralConnector.ConnectorError.serviceNotFound
        }
        do {
            let info = try await connector.connect(
                peripheral: cbPeripheral,
                connectionConfig: connectionConfig
            )
            self.selectedPeripheralInfo = info
            if let name = info.deviceName, !name.isEmpty {
                log("PC device name: \(name)")
            }
            if let sig = info.deviceSignature {
                log("PC signature: key=\(sig.signatureKeyID) ts=\(sig.timestampMS)")
            }
            log("ConnectionConfig written to PC")
        } catch {
            log("Failed to write ConnectionConfig: \(error.localizedDescription)")
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
        selectedPeripheral = nil
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
