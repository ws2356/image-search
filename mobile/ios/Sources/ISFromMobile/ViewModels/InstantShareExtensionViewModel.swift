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
    @Published public var payloadEnvelope: InstantSharePayloadEnvelope?
    @Published public var errorMessage: String?
    @Published public var sessionPhase: ExtensionSessionPhase = .scanning
    @Published public var isProcessing: Bool = false
    @Published public var sharedText: String = ""
    @Published public var sharedImageFilename: String = ""
    @Published public var sharedImageContentType: String = ""

    let mdnsBrowser: InstantShareMDNSBrowser
    let service: InstantShareService
    private let appIdentityProvider: AppIdentityProviding
    private var cancellables: Set<AnyCancellable> = []

    public init(
        mdnsBrowser: InstantShareMDNSBrowser,
        service: InstantShareService,
        appIdentityProvider: AppIdentityProviding = KeychainAppIdentityProvider(
            localDeviceIdentifierProvider: LocalDeviceIdentifierStore()
        )
    ) {
        self.mdnsBrowser = mdnsBrowser
        self.service = service
        self.appIdentityProvider = appIdentityProvider
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
            let envelope = try await InstantSharePayloadExtractor.extract(from: items)
            self.payloadEnvelope = envelope
            LocalLog.info("[Extension VM] payload extracted: type=\(envelope.payloadType)")
            if envelope.payloadType == .text, let text = envelope.textContent {
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

        switch envelope.payloadType {
        case .text:
            if let text = envelope.textContent {
                service.setSharedText(text)
            }
        case .image:
            if let fileURL = envelope.fileURL {
                service.setSharedImage(
                    fileURL: fileURL,
                    filename: envelope.filename ?? "image",
                    contentType: envelope.contentType ?? "image/jpeg"
                )
            }
        default:
            break
        }

        let config = buildConnectionConfig(pc: pc, envelope: envelope)
        service.connectionConfig = config

        let deviceName = await UIDevice.current.name

        LocalLog.info("[Extension VM] attempting blind mTLS transfer to \(pc.host):\(pc.tlsPort)")
        do {
            try await attemptRevisitTransfer(pc: pc, config: config, deviceName: deviceName)
            return
        } catch {
            LocalLog.info("[Extension VM] blind mTLS transfer failed, falling back to trust handshake: \(error.localizedDescription)")
        }

        do {
            LocalLog.info("[Extension VM] storing connection config for PC \(pc.host):\(pc.port)")
            await service.startSession(connectionConfig: config)

            LocalLog.info("[Extension VM] starting trust handshake...")
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
            LocalLog.info("[Extension VM] handshake completed")

            try await trustClient.apply(
                host: handshakeHost,
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
                host: pc.host,
                port: pc.tlsPort,
                sessionID: revisitSessionID,
                correlationID: revisitCorrelationID,
                text: service.sharedText,
                peerDeviceID: nil,
                peerDeviceName: deviceName
            )
            LocalLog.info("[Extension VM] revisit text transfer succeeded via TLS port \(pc.tlsPort)")
        default:
            if let imageFileURL = service.sharedImageFileURL {
                try await uploadClient.uploadImage(
                    host: pc.host,
                    port: pc.tlsPort,
                    sessionID: revisitSessionID,
                    correlationID: revisitCorrelationID,
                    fileURL: imageFileURL,
                    contentType: service.sharedImageContentType,
                    filename: service.sharedImageFilename,
                    peerDeviceID: nil,
                    peerDeviceName: deviceName
                )
                LocalLog.info("[Extension VM] revisit image transfer succeeded via TLS port \(pc.tlsPort)")
            }
        }

        sessionPhase = .success
        isProcessing = false
    }

    public func confirmPIN(pinCode: String) {
        LocalLog.info("[Extension VM] PIN confirmed with code: \(pinCode)")
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
                let uploadClient = InstantShareUploadClient(
                    appIdentityProvider: appIdentityProvider
                )

                let handshakeHost = pc.host

                let myCert = try? appIdentityProvider.selfCertificatePEM()
                let peerCert = try await trustClient.confirm(
                    host: handshakeHost,
                    port: pc.port,
                    sessionID: config.sessionID,
                    correlationID: config.correlationID,
                    pinCode: pinCode,
                    deviceCertificatePEM: myCert
                )
                guard let peerCert, let peerDeviceID = SecCertificate.fromPEM(peerCert)?.commonName else {
                    return
                }
                do {
                    try await appIdentityProvider.importPeerCertificate(
                        pem: peerCert,
                        for: peerDeviceID
                    )
                    LocalLog.info("[Extension VM] imported peer certificate for device=\(peerDeviceID)")
                } catch {
                    LocalLog.error("[Extension VM] imported peer certificate for device=\(peerDeviceID) failed: \(error)")
                }

                switch service.sharedText.isEmpty {
                case false:
                    try await uploadClient.uploadText(
                        host: handshakeHost,
                        port: pc.tlsPort,
                        sessionID: config.sessionID,
                        correlationID: config.correlationID,
                        text: service.sharedText,
                        peerDeviceID: peerDeviceID
                    )
                    LocalLog.info("[Extension VM] text uploaded via TLS port \(pc.tlsPort)")
                default:
                    if let imageFileURL = service.sharedImageFileURL {
                        try await uploadClient.uploadImage(
                            host: handshakeHost,
                            port: pc.tlsPort,
                            sessionID: config.sessionID,
                            correlationID: config.correlationID,
                            fileURL: imageFileURL,
                            contentType: service.sharedImageContentType,
                            filename: service.sharedImageFilename,
                            peerDeviceID: peerDeviceID
                        )
                        LocalLog.info("[Extension VM] image uploaded via TLS port \(pc.tlsPort)")
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
