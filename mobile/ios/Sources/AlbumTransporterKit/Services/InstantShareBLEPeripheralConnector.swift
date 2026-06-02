import CoreBluetooth
import Foundation

/// Connects to a discovered PC peripheral, discovers the instant-sharing GATT
/// service, and writes the ConnectionConfig characteristic to bootstrap the
/// transport.
@MainActor
final class InstantShareBLEPeripheralConnector: NSObject, ObservableObject {
    enum ConnectorError: Error, LocalizedError {
        case characteristicNotFound
        case serviceNotFound
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .characteristicNotFound:
                return "PC peripheral did not expose the ConnectionConfig characteristic."
            case .serviceNotFound:
                return "PC peripheral did not expose the instant-sharing service."
            case .writeFailed(let inner):
                return "BLE write failed: \(inner.localizedDescription)"
            }
        }
    }

    enum ConnectorState: Equatable {
        case idle
        case connecting
        case discoveringServices
        case writingConnectionConfig
        case completed
        case failed(String)
    }

    @Published private(set) var state: ConnectorState = .idle

    private let serviceUUID = CBUUID(string: "4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b")
    private let connectionConfigUUID = CBUUID(string: "8c1f1c8a-6e2e-4cf2-bff7-6cbad77b0f8b")
    private var peripheral: CBPeripheral?
    private var connectionConfigContinuation: CheckedContinuation<Void, Error>?

    func connect(
        peripheral: CBPeripheral,
        connectionConfig: InstantShareConnectionConfig
    ) async throws {
        state = .connecting
        self.peripheral = peripheral
        peripheral.delegate = self

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionConfigContinuation = continuation
            peripheral.discoverServices([self.serviceUUID])
        }

        state = .writingConnectionConfig
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            throw ConnectorError.serviceNotFound
        }
        peripheral.discoverCharacteristics([connectionConfigUUID], for: service)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionConfigContinuation = continuation
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == connectionConfigUUID }) else {
            throw ConnectorError.characteristicNotFound
        }

        let payload = try JSONEncoder().encode(connectionConfig)
        peripheral.writeValue(payload, for: characteristic, type: .withResponse)

        state = .completed
    }
}

extension InstantShareBLEPeripheralConnector: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            Task { @MainActor in
                self.connectionConfigContinuation?.resume(throwing: ConnectorError.writeFailed(error))
                self.connectionConfigContinuation = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.connectionConfigContinuation?.resume(throwing: ConnectorError.writeFailed(error))
                self.connectionConfigContinuation = nil
                self.state = .failed(error.localizedDescription)
            }
            return
        }
        Task { @MainActor in
            self.connectionConfigContinuation?.resume()
            self.connectionConfigContinuation = nil
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.state = .failed(error.localizedDescription)
            }
        }
    }
}
