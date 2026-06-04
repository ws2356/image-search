import SwiftUI
import UniformTypeIdentifiers
import Combine
import Network

@MainActor
public enum ExtensionSessionPhase {
    case scanning
    case ready
    case starting
    case verifying(pin: String)
    case transferring
    case success
    case failed(String)
}

@MainActor
public final class InstantShareExtensionViewModel: ObservableObject {
    @Published public var discoveredDevices: [InstantShareDiscoveredPC] = []
    @Published public var selectedDevice: InstantShareDiscoveredPC?
    @Published public var payloadEnvelope: InstantSharePayloadEnvelope?
    @Published public var errorMessage: String?
    @Published public var sessionPhase: ExtensionSessionPhase = .scanning
    @Published public var isProcessing: Bool = false
    @Published public var sharedText: String = ""
    @Published public var sharedImageData: Data?
    @Published public var sharedImageFilename: String = ""
    @Published public var sharedImageContentType: String = ""

    let mdnsBrowser: InstantShareMDNSBrowser
    let service: InstantShareService
    private var cancellables: Set<AnyCancellable> = []

    public init(mdnsBrowser: InstantShareMDNSBrowser, service: InstantShareService) {
        self.mdnsBrowser = mdnsBrowser
        self.service = service
        InstantShareLog.info("[Extension VM] init, subscribing to mdnsBrowser")
        mdnsBrowser.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let count = self.mdnsBrowser.discovered.count
                if count != self.discoveredDevices.count {
                    InstantShareLog.info("[Extension VM] mDNS: \(count) PCs discovered")
                }
                self.discoveredDevices = self.mdnsBrowser.discovered
            }
            .store(in: &cancellables)
    }

    public func startDiscovery() {
        InstantShareLog.info("[Extension VM] startDiscovery")
        sessionPhase = .scanning
        mdnsBrowser.startBrowsing()
    }

    public func stopDiscovery() {
        mdnsBrowser.stopBrowsing()
    }

    public func loadPayload(from extensionItems: [NSExtensionItem]) async {
        InstantShareLog.info("[Extension VM] loadPayload: \(extensionItems.count) items")
        isProcessing = true
        defer { isProcessing = false }
        do {
            nonisolated(unsafe) let items = extensionItems
            let envelope = try await InstantSharePayloadExtractor.extract(from: items)
            self.payloadEnvelope = envelope
            InstantShareLog.info("[Extension VM] payload extracted: type=\(envelope.payloadType)")
            if envelope.payloadType == .text, let text = envelope.textContent {
                self.sharedText = text
            }
        } catch {
            InstantShareLog.error("[Extension VM] loadPayload failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    public func selectDevice(_ device: InstantShareDiscoveredPC) {
        self.selectedDevice = device
        service.selectPC(device)
        InstantShareLog.info("[Extension VM] selected PC: \(device.name)")
    }

    public var canSend: Bool {
        selectedDevice != nil && payloadEnvelope != nil && !isProcessing
    }

    public func send() async {
        guard let pc = selectedDevice, let envelope = payloadEnvelope else {
            errorMessage = "No device selected or no payload."
            return
        }

        sessionPhase = .starting
        isProcessing = true
        errorMessage = nil

        let config = buildConnectionConfig(pc: pc, envelope: envelope)
        service.connectionConfig = config

        do {
            InstantShareLog.info("[Extension VM] storing connection config for PC \(pc.host):\(pc.port)")
            await service.startSession(connectionConfig: config)

            InstantShareLog.info("[Extension VM] starting trust handshake...")
            let trustClient = InstantShareTrustClient(
                trustSessionManager: service.trustSession
            )

            let handshakePort = pc.port
            let handshakeHost = pc.host

            try await trustClient.handshake(
                host: handshakeHost,
                port: handshakePort,
                sessionID: config.sessionID,
                correlationID: config.correlationID,
                mobilePort: config.mobilePort,
                mobileIPList: config.mobileIPList,
                payloadClass: config.metadata.payloadClass.rawValue,
                targetIntent: config.metadata.targetIntent.rawValue,
                trustMode: config.metadata.trustMode.rawValue
            )
            InstantShareLog.info("[Extension VM] handshake completed")

            let pin = try await trustClient.apply(
                host: handshakeHost,
                port: handshakePort,
                sessionID: config.sessionID,
                correlationID: config.correlationID
            )
            InstantShareLog.info("[Extension VM] PIN received: \(pin)")
            service.currentPIN = pin

            isProcessing = false
            sessionPhase = .verifying(pin: pin)
        } catch {
            isProcessing = false
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            InstantShareLog.error("[Extension VM] send failed: \(msg)")
            sessionPhase = .failed(msg)
        }
    }

    public func confirmPIN() {
        InstantShareLog.info("[Extension VM] PIN confirmed")
        sessionPhase = .transferring

        guard let pc = selectedDevice, let config = service.connectionConfig else {
            sessionPhase = .failed("No connection config available")
            return
        }

        Task {
            do {
                let trustClient = InstantShareTrustClient(
                    trustSessionManager: service.trustSession
                )
                let uploadClient = InstantShareUploadClient()

                let handshakeHost = pc.host

                try await trustClient.confirm(
                    host: handshakeHost,
                    port: pc.port,
                    sessionID: config.sessionID,
                    correlationID: config.correlationID
                )
                InstantShareLog.info("[Extension VM] trust confirmed")

                switch service.sharedText.isEmpty {
                case false:
                    try await uploadClient.uploadText(
                        host: handshakeHost,
                        port: pc.port,
                        sessionID: config.sessionID,
                        correlationID: config.correlationID,
                        text: service.sharedText
                    )
                    InstantShareLog.info("[Extension VM] text uploaded")
                default:
                    if let imageData = service.sharedImageData {
                        try await uploadClient.uploadImage(
                            host: handshakeHost,
                            port: pc.port,
                            sessionID: config.sessionID,
                            correlationID: config.correlationID,
                            imageData: imageData,
                            contentType: service.sharedImageContentType,
                            filename: service.sharedImageFilename
                        )
                        InstantShareLog.info("[Extension VM] image uploaded")
                    }
                }

                sessionPhase = .success
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                InstantShareLog.error("[Extension VM] confirm/transfer failed: \(msg)")
                sessionPhase = .failed(msg)
            }
        }
    }

    public func rejectPIN() {
        InstantShareLog.info("[Extension VM] PIN rejected")
        service.rejectTrust()
        sessionPhase = .failed("Trust verification rejected.")
    }

    public func dismissCompletion() {
        service.stopSession()
        sessionPhase = .scanning
    }

    private func buildConnectionConfig(pc: InstantShareDiscoveredPC, envelope: InstantSharePayloadEnvelope) -> InstantShareConnectionConfig {
        let payloadClass: InstantSharePayloadClass = envelope.payloadType == .text ? .text : .image
        let targetIntent: InstantShareTargetIntent = payloadClass == .text ? .clipboardOnly : .clipboardOrFile
        let trustMode: InstantShareTrustMode = .firstShare

        let metadata = InstantShareMetadata(
            payloadClass: payloadClass,
            targetIntent: targetIntent,
            trustMode: trustMode
        )

        return InstantShareConnectionConfig(
            sessionID: UUID().uuidString.lowercased(),
            mobilePort: 1,
            mobileIPList: ["127.0.0.1"],
            correlationID: UUID().uuidString.lowercased(),
            metadata: metadata
        )
    }
}