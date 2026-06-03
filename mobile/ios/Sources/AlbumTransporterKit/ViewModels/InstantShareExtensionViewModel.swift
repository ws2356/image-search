import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
public final class InstantShareExtensionViewModel: ObservableObject {
    @Published var scannerState: String = "idle"
    @Published var discoveredDevices: [InstantShareDiscoveredPC] = []
    @Published public var selectedDevice: InstantShareDiscoveredPC?
    @Published public var payloadEnvelope: InstantSharePayloadEnvelope?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false

    private let mdnsBrowser: InstantShareMDNSBrowser
    private let service: InstantShareService
    private var cancellables: Set<AnyCancellable> = []

    public init(mdnsBrowser: InstantShareMDNSBrowser, service: InstantShareService) {
        self.mdnsBrowser = mdnsBrowser
        self.service = service
        InstantShareLog.info("[Extension VM] init, subscribing to mdnsBrowser.objectWillChange")
        mdnsBrowser.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let count = self.mdnsBrowser.discovered.count
                if count != self.discoveredDevices.count {
                    InstantShareLog.info(
                        "[Extension VM] mDNS browser changed, copying discovered (\(count) PCs) to discoveredDevices"
                    )
                }
                self.discoveredDevices = self.mdnsBrowser.discovered
            }
            .store(in: &cancellables)
    }

    public func startDiscovery() {
        InstantShareLog.info("[Extension VM] startDiscovery() called")
        scannerState = "browsing"
        mdnsBrowser.startBrowsing()
    }

    public func stopDiscovery() {
        mdnsBrowser.stopBrowsing()
        scannerState = "idle"
    }

    public func loadPayload(from extensionItems: [NSExtensionItem]) async {
        InstantShareLog.info("[Extension VM] loadPayload: \(extensionItems.count) extension items")
        isProcessing = true
        defer { isProcessing = false }
        do {
            nonisolated(unsafe) let items = extensionItems
            let envelope = try await InstantSharePayloadExtractor.extract(from: items)
            self.payloadEnvelope = envelope
            InstantShareLog.info("[Extension VM] payload extracted: type=\(envelope.payloadType)")
        } catch {
            InstantShareLog.error("[Extension VM] loadPayload failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    func selectDevice(_ device: InstantShareDiscoveredPC) {
        self.selectedDevice = device
        service.selectPC(device)
    }

    func performHandoff() throws {
        guard let envelope = payloadEnvelope else {
            throw InstantShareHandoffError.contextMissing
        }
        guard let pc = selectedDevice else {
            throw InstantShareHandoffError.contextMissing
        }
        let context = InstantShareHandoffContext(
            from: envelope,
            selectedDeviceID: pc.id,
            selectedDeviceName: pc.name,
            selectedDeviceHost: pc.host,
            selectedDevicePort: pc.port,
            isTrustedDevice: false
        )
        try context.persist()
    }
}
