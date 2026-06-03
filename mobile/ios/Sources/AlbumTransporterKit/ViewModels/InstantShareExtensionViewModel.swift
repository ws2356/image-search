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

        setPayloadOnService(from: envelope)

        let config = buildConnectionConfig(pc: pc, envelope: envelope)
        service.connectionConfig = config

        do {
            InstantShareLog.info("[Extension VM] starting session on port \(config.mobilePort)")
            try await service.startSession(connectionConfig: config)
            isProcessing = false

            if let pin = service.currentPIN {
                InstantShareLog.info("[Extension VM] PIN: \(pin)")
                sessionPhase = .verifying(pin: pin)
            } else {
                sessionPhase = .failed("PIN not generated")
            }
        } catch {
            isProcessing = false
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            InstantShareLog.error("[Extension VM] startSession failed: \(msg)")
            sessionPhase = .failed(msg)
        }
    }

    public func confirmPIN() {
        InstantShareLog.info("[Extension VM] PIN confirmed")
        service.confirmTrust()
        sessionPhase = .transferring
        Task {
            do {
                let result = try await waitForTransferCompletion()
                InstantShareLog.info("[Extension VM] transfer result: \(result)")
                sessionPhase = .success
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                InstantShareLog.error("[Extension VM] transfer failed: \(msg)")
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

    private func setPayloadOnService(from envelope: InstantSharePayloadEnvelope) {
        switch envelope.payloadType {
        case .text:
            service.setSharedText(envelope.textContent ?? "")
        case .image:
            if let url = envelope.fileURL,
               let data = try? Data(contentsOf: url) {
                let filename = envelope.filename ?? "shared-image.jpg"
                let contentType = envelope.contentType ?? "image/jpeg"
                service.setSharedImage(data: data, filename: filename, contentType: contentType)
            }
        default:
            break
        }
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
            mobilePort: 8443,
            mobileIPList: [pc.host],
            correlationID: UUID().uuidString.lowercased(),
            metadata: metadata
        )
    }

    private func waitForTransferCompletion() async throws -> String {
        let deadline = Date().addingTimeInterval(30)
        let server = service.httpsServer
        while Date() < deadline {
            if server.sharedTextDelivered {
                return "text-delivered"
            }
            if server.sharedImageDelivered {
                return "image-delivered"
            }
            if let err = server.lastError, !err.isEmpty {
                throw NSError(domain: "InstantShare", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw NSError(domain: "InstantShare", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transfer timed out"])
    }
}
