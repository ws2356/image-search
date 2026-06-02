import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class InstantShareExtensionViewModel: ObservableObject {
    @Published var scannerState: String = "idle"
    @Published var discoveredDevices: [InstantShareDiscoveredPeripheral] = []
    @Published var selectedDevice: InstantShareDiscoveredPeripheral?
    @Published var payloadEnvelope: InstantSharePayloadEnvelope?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false

    private let scanner: InstantShareBLEScanner
    private let service: InstantShareService

    init(scanner: InstantShareBLEScanner, service: InstantShareService) {
        self.scanner = scanner
        self.service = service
    }

    func startDiscovery() {
        scannerState = "scanning"
        scanner.initialize()
        scanner.startScanning()
    }

    func stopDiscovery() {
        scanner.stopScanning()
        scannerState = "idle"
    }

    func loadPayload(from extensionItems: [NSExtensionItem]) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let envelope = try await InstantSharePayloadExtractor.extract(from: extensionItems)
            self.payloadEnvelope = envelope
        } catch {
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
