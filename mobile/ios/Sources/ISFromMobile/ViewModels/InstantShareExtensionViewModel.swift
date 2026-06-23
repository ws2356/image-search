import SwiftUI
import UniformTypeIdentifiers
import Combine
import Network
import Security
import Common


@MainActor
public enum ExtensionSessionPhase {
    case scanning
    case ready
    case starting
    case awaitingPinInput
    case transferring
    case success
    case failed(String)
}

@MainActor
public final class InstantShareExtensionViewModel: ObservableObject {
    @Published public var discoveredDevices: [InstantShareDiscoveredPC] = []
    @Published public var selectedDevice: InstantShareDiscoveredPC?
    @Published public var payloadEnvelopes: [InstantSharePayloadEnvelope] = []
    @Published public var errorMessage: String?
    @Published public var sessionPhase: ExtensionSessionPhase = .scanning
    @Published public var isProcessing: Bool = false
    @Published public var sharedText: String = ""
    @Published public var sharedImageFilename: String = ""
    @Published public var sharedImageContentType: String = ""
    @Published public var totalImageCount: Int = 0
    @Published public var sentImageCount: Int = 0

    public var batchProgress: Float {
        totalImageCount > 0 ? Float(sentImageCount) / Float(totalImageCount) : 0
    }

    let mdnsBrowser: InstantShareMDNSBrowser
    let service: InstantShareService
    private let appIdentityProvider: AppIdentityProviding
    private let deviceIdentifierProvider: LocalDeviceIdentifierProviding
    private var cancellables: Set<AnyCancellable> = []

    public init(
        mdnsBrowser: InstantShareMDNSBrowser,
        service: InstantShareService,
        appIdentityProvider: AppIdentityProviding,
        deviceIdentifierProvider: LocalDeviceIdentifierProviding
    ) {
        self.mdnsBrowser = mdnsBrowser
        self.service = service
        self.appIdentityProvider = appIdentityProvider
        self.deviceIdentifierProvider = deviceIdentifierProvider
        LocalLog.info("[Extension VM] init, subscribing to mdnsBrowser")
        mdnsBrowser.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let count = self.mdnsBrowser.discovered.count
                if count != self.discoveredDevices.count {
                    LocalLog.info("[Extension VM] mDNS: \(count) PCs discovered")
                }
                self.discoveredDevices = self.mdnsBrowser.discovered
            }
            .store(in: &cancellables)
    }

    public func startDiscovery() {
        LocalLog.info("[Extension VM] startDiscovery")
        sessionPhase = .scanning
        mdnsBrowser.startBrowsing()
    }

    public func stopDiscovery() {
        mdnsBrowser.stopBrowsing()
    }

    public func loadPayload(from extensionItems: [NSExtensionItem]) async {
        LocalLog.info("[Extension VM] loadPayload: \(extensionItems.count) items")
        isProcessing = true
        defer { isProcessing = false }
        do {
            nonisolated(unsafe) let items = extensionItems
            let envelopes = try await InstantSharePayloadExtractor.extract(from: items)
            self.payloadEnvelopes = envelopes
            LocalLog.info("[Extension VM] payloads extracted: count=\(envelopes.count)")
            // Set sharedText from the first text envelope if present
            if let textEnvelope = envelopes.first(where: { $0.payloadType == .text }),
               let text = textEnvelope.textContent {
                self.sharedText = text
            }
        } catch {
            LocalLog.error("[Extension VM] loadPayload failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    public func selectDevice(_ device: InstantShareDiscoveredPC) {
        self.selectedDevice = device
        service.selectPC(device)
        LocalLog.info("[Extension VM] selected PC: \(device.name)")
        preWarmLocalNetworkPermission(hosts: device.hosts, port: device.port)
    }

    public var canSend: Bool {
        selectedDevice != nil && !payloadEnvelopes.isEmpty && !isProcessing
    }

    public func send() async {
        guard let pc = selectedDevice, !payloadEnvelopes.isEmpty else {
            errorMessage = "No device selected or no payload."
            return
        }

        sessionPhase = .starting
        isProcessing = true
        errorMessage = nil

        // Process all envelopes
        var images: [(fileURL: URL, filename: String, contentType: String)] = []
        for envelope in payloadEnvelopes {
            switch envelope.payloadType {
            case .text:
                if let text = envelope.textContent {
                    service.setSharedText(text)
                }
            case .image:
                if let fileURL = envelope.fileURL {
                    let filename = envelope.filename ?? "image"
                    let contentType = envelope.contentType ?? "image/jpeg"
                    images.append((fileURL, filename, contentType))
                }
            default:
                break
            }
        }

        // Store images in the service
        if images.count == 1, let first = images.first {
            service.setSharedImage(fileURL: first.fileURL, filename: first.filename, contentType: first.contentType)
        } else if !images.isEmpty {
            service.setSharedImages(images)
        }

        let config = buildConnectionConfig(pc: pc, envelopes: payloadEnvelopes)
        service.connectionConfig = config

        let deviceName = await deviceIdentifierProvider.currentIdentifier().deviceName

        LocalLog.info("[Extension VM] attempting blind mTLS transfer to \(pc.hosts):\(pc.tlsPort)")
        do {
            try await attemptRevisitTransfer(pc: pc, config: config, deviceName: deviceName)
            return
        } catch {
            LocalLog.info("[Extension VM] blind mTLS transfer failed, falling back to trust handshake: \(error.localizedDescription)")
        }

        do {
            LocalLog.info("[Extension VM] storing connection config for PC \(pc.hosts):\(pc.port)")
            await service.startSession(connectionConfig: config)

            LocalLog.info("[Extension VM] starting trust handshake...")
            let trustClient = InstantShareTrustClient(
                trustSessionManager: service.trustSession
            )

            let handshakePort = pc.port
            let handshakeHosts = pc.hosts

            try await trustClient.handshake(
                hosts: handshakeHosts,
                port: handshakePort,
                sessionID: config.sessionID,
                correlationID: config.correlationID,
                mobilePort: config.mobilePort,
                mobileIPList: config.mobileIPList,
                payloadClass: config.metadata.payloadClass.rawValue,
                targetIntent: config.metadata.targetIntent.rawValue,
                trustMode: config.metadata.trustMode.rawValue
            )
            LocalLog.info("[Extension VM] handshake completed")

            try await trustClient.apply(
                hosts: handshakeHosts,
                port: handshakePort,
                sessionID: config.sessionID,
                correlationID: config.correlationID
            )
            LocalLog.info("[Extension VM] apply completed, awaiting PIN input")

            isProcessing = false
            sessionPhase = .awaitingPinInput
        } catch {
            isProcessing = false
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            LocalLog.error("[Extension VM] send failed: \(msg)")
            sessionPhase = .failed(msg)
        }
    }

    private func attemptRevisitTransfer(
        pc: InstantShareDiscoveredPC,
        config: InstantShareConnectionConfig,
        deviceName: String
    ) async throws {
        let uploadClient = InstantShareUploadClient(
            appIdentityProvider: appIdentityProvider
        )
        let revisitSessionID = UUID().uuidString.lowercased()
        let revisitCorrelationID = UUID().uuidString.lowercased()

        switch service.sharedText.isEmpty {
        case false:
            try await uploadClient.uploadText(
                hosts: pc.hosts,
                port: pc.tlsPort,
                sessionID: revisitSessionID,
                correlationID: revisitCorrelationID,
                text: service.sharedText,
                peerDeviceName: deviceName
            )
            LocalLog.info("[Extension VM] revisit text transfer succeeded via TLS port \(pc.tlsPort)")
        default:
            let images = service.sharedImages
            if images.count == 1, let img = images.first {
                try await uploadClient.uploadImage(
                    hosts: pc.hosts,
                    port: pc.tlsPort,
                    sessionID: revisitSessionID,
                    correlationID: revisitCorrelationID,
                    fileURL: img.fileURL,
                    contentType: img.contentType,
                    filename: img.filename,
                    peerDeviceName: deviceName
                )
                LocalLog.info("[Extension VM] revisit image transfer succeeded via TLS port \(pc.tlsPort)")
            } else if !images.isEmpty {
                try await uploadClient.uploadImages(
                    hosts: pc.hosts,
                    port: pc.tlsPort,
                    sessionID: revisitSessionID,
                    correlationID: revisitCorrelationID,
                    urls: images.map { ($0.fileURL, $0.filename, $0.contentType) },
                    peerDeviceName: deviceName
                )
                LocalLog.info("[Extension VM] revisit batch transfer (\(images.count) images) succeeded via TLS port \(pc.tlsPort)")
            }
        }

        sessionPhase = .success
        isProcessing = false
    }

    public func confirmPIN(pinCode: String) async {
        LocalLog.info("[Extension VM] PIN confirmed with code: \(pinCode)")
        sessionPhase = .transferring

        let deviceName = await deviceIdentifierProvider.currentIdentifier().deviceName
        
        guard let pc = selectedDevice, let config = service.connectionConfig else {
            sessionPhase = .failed("No connection config available")
            return
        }

        Task {
            do {
                let trustClient = InstantShareTrustClient(
                    trustSessionManager: service.trustSession
                )
                let uploadClient = InstantShareUploadClient(
                    appIdentityProvider: appIdentityProvider
                )

                let handshakeHosts = pc.hosts

                let myCert = try? await appIdentityProvider.selfCertificatePEM()
                let peerCert = try await trustClient.confirm(
                    hosts: handshakeHosts,
                    port: pc.port,
                    sessionID: config.sessionID,
                    correlationID: config.correlationID,
                    pinCode: pinCode,
                    deviceCertificatePEM: myCert
                )
                guard let peerCert else {
                    return
                }
                do {
                    try await appIdentityProvider.importPeerCertificate(pem: peerCert)
                    LocalLog.info("[Extension VM] imported peer certificate")
                } catch {
                    LocalLog.error("[Extension VM] imported peer certificate failed: \(error)")
                }

                switch service.sharedText.isEmpty {
                case false:
                    try await uploadClient.uploadText(
                        hosts: handshakeHosts,
                        port: pc.tlsPort,
                        sessionID: config.sessionID,
                        correlationID: config.correlationID,
                        text: service.sharedText,
                        peerDeviceName: deviceName
                    )
                    LocalLog.info("[Extension VM] text uploaded via TLS port \(pc.tlsPort)")
                default:
                    let images = service.sharedImages
                    if images.count == 1, let img = images.first {
                        try await uploadClient.uploadImage(
                            hosts: handshakeHosts,
                            port: pc.tlsPort,
                            sessionID: config.sessionID,
                            correlationID: config.correlationID,
                            fileURL: img.fileURL,
                            contentType: img.contentType,
                            filename: img.filename,
                            peerDeviceName: deviceName
                        )
                        LocalLog.info("[Extension VM] image uploaded via TLS port \(pc.tlsPort)")
                    } else if !images.isEmpty {
                        try await uploadClient.uploadImages(
                            hosts: handshakeHosts,
                            port: pc.tlsPort,
                            sessionID: config.sessionID,
                            correlationID: config.correlationID,
                            urls: images.map { ($0.fileURL, $0.filename, $0.contentType) },
                            peerDeviceName: deviceName
                        )
                        LocalLog.info("[Extension VM] batch transfer (\(images.count) images) succeeded via TLS port \(pc.tlsPort)")
                    }
                }

                sessionPhase = .success
            } catch let error as InstantShareTrustClientError {
                LocalLog.error("[Extension VM] confirm/transfer failed: \(error)")
                if case .httpError(let statusCode, let errorCode, _) = error,
                   statusCode == 403 && errorCode == "PIN_MISMATCH_OR_REJECTED" {
                    errorMessage = "PIN code incorrect. Please check the code on your Mac and try again."
                    sessionPhase = .awaitingPinInput
                } else {
                    let msg = error.localizedDescription
                    sessionPhase = .failed(msg)
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                LocalLog.error("[Extension VM] confirm/transfer failed: \(msg)")
                sessionPhase = .failed(msg)
            }
        }
    }

    public func rejectPIN() {
        LocalLog.info("[Extension VM] PIN rejected")
        service.rejectTrust()
        sessionPhase = .failed("Trust verification rejected.")
    }

    public func dismissCompletion() {
        service.stopSession()
        sessionPhase = .scanning
    }

    /// Fire lightweight HTTP requests to all IPs concurrently to trigger the iOS
    /// local network permission prompt before the user taps Send.
    /// Results are intentionally ignored.
    private func preWarmLocalNetworkPermission(hosts: [String], port: Int) {
        LocalLog.debug("[Extension VM] pre-warming local network permission for \(hosts)")
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for host in hosts {
                    guard let url = URL(string: "http://\(host):\(port)/") else { continue }
                    group.addTask {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 2
                        _ = try? await URLSession.shared.data(for: request)
                    }
                }
            }
        }
    }

    private func buildConnectionConfig(pc: InstantShareDiscoveredPC, envelopes: [InstantSharePayloadEnvelope]) -> InstantShareConnectionConfig {
        let hasImage = envelopes.contains(where: { $0.payloadType == .image })
        let payloadClass: InstantSharePayloadClass = hasImage ? .image : .text
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
