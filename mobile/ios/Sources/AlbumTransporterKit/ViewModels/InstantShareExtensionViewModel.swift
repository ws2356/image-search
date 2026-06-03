import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
public final class InstantShareExtensionViewModel: ObservableObject {
    @Published var scannerState: String = "idle"
    @Published var discoveredDevices: [InstantShareDiscoveredPeripheral] = []
    @Published public var selectedDevice: InstantShareDiscoveredPeripheral?
    @Published public var payloadEnvelope: InstantSharePayloadEnvelope?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false

    private let scanner: InstantShareBLEScanner
    private let service: InstantShareService
    private var cancellables: Set<AnyCancellable> = []

    public init(scanner: InstantShareBLEScanner, service: InstantShareService) {
        self.scanner = scanner
        self.service = service
        InstantShareLog.info("[Extension VM] init, subscribing to scanner.objectWillChange")
        scanner.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let count = self.scanner.discovered.count
                if count != self.discoveredDevices.count {
                    InstantShareLog.info(
                        "[Extension VM] scanner changed, copying discovered (\(count) devices) to discoveredDevices"
                    )
                }
                self.discoveredDevices = self.scanner.discovered
            }
            .store(in: &cancellables)
    }

    public func startDiscovery() {
        InstantShareLog.info("[Extension VM] startDiscovery() called")
        scannerState = "scanning"
        scanner.initialize()
        scanner.startScanning()
    }

    public func stopDiscovery() {
        scanner.stopScanning()
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

    func selectDevice(_ device: InstantShareDiscoveredPeripheral) {
        self.selectedDevice = device
    }

    func performHandoff() throws {
        guard let envelope = payloadEnvelope else {
            throw InstantShareHandoffError.contextMissing
        }
        let context = InstantShareHandoffContext(
            from: envelope,
            selectedDeviceID: selectedDevice?.id.uuidString,
            selectedDeviceName: selectedDevice?.name,
            isTrustedDevice: false
        )
        try context.persist()
    }
}
