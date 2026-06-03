import CoreBluetooth
import Foundation

/// Connects to a discovered PC peripheral, discovers the instant-sharing GATT
/// service, reads the DeviceName and DeviceSignature characteristics, and
/// writes the ConnectionConfig characteristic to bootstrap the transport.
@MainActor
final class InstantShareBLEPeripheralConnector: NSObject, ObservableObject {
    enum ConnectorError: Error, LocalizedError {
        case characteristicNotFound(String)
        case serviceNotFound
        case readFailed(String)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .characteristicNotFound(let name):
                return "PC peripheral did not expose the \(name) characteristic."
            case .serviceNotFound:
                return "PC peripheral did not expose the instant-sharing service."
            case .readFailed(let name):
                return "BLE read of \(name) failed."
            case .writeFailed(let inner):
                return "BLE write failed: \(inner.localizedDescription)"
            }
        }
    }

    enum ConnectorState: Equatable {
        case idle
        case connecting
        case discoveringServices
        case discoveringCharacteristics
        case readingCharacteristics
        case writingConnectionConfig
        case completed
        case failed(String)
    }

    @Published private(set) var state: ConnectorState = .idle
    @Published private(set) var deviceName: String?
    @Published private(set) var deviceSignature: InstantShareDeviceSignature?

    private let serviceUUID = CBUUID(string: "4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b")
    private let deviceNameCharUUID = CBUUID(string: "a1b2c3d4-1111-2222-3333-444455556601")
    private let deviceSignatureCharUUID = CBUUID(string: "a1b2c3d4-1111-2222-3333-444455556602")
    private let connectionConfigUUID = CBUUID(string: "8c1f1c8a-6e2e-4cf2-bff7-6cbad77b0f8b")

    private var peripheral: CBPeripheral?
    private var continuation: CheckedContinuation<InstantSharePeripheralInfo, Error>?

    func connect(
        peripheral: CBPeripheral,
        connectionConfig: InstantShareConnectionConfig
    ) async throws -> InstantSharePeripheralInfo {
        state = .connecting
        self.peripheral = peripheral
        peripheral.delegate = self

        let info: InstantSharePeripheralInfo = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<InstantSharePeripheralInfo, Error>) in
            self.continuation = cont
            peripheral.discoverServices([self.serviceUUID])
        }

        let payload = try JSONEncoder().encode(connectionConfig)
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == connectionConfigUUID }) else {
            throw ConnectorError.characteristicNotFound("ConnectionConfig")
        }
        state = .writingConnectionConfig
        peripheral.writeValue(payload, for: characteristic, type: .withResponse)

        state = .completed
        return info
    }

    fileprivate func finishWithError(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        state = .failed(error.localizedDescription)
    }

    fileprivate func finishWithErrorMessage(_ message: String) {
        let error = NSError(
            domain: "InstantShareBLEPeripheralConnector",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        continuation?.resume(throwing: error)
        continuation = nil
        state = .failed(message)
    }

    fileprivate func handleServiceDiscovered(_ peripheral: CBPeripheral) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            finishWithError(ConnectorError.serviceNotFound)
            return
        }
        state = .discoveringCharacteristics
        peripheral.discoverCharacteristics(
            [deviceNameCharUUID, deviceSignatureCharUUID, connectionConfigUUID],
            for: service
        )
    }

    fileprivate func handleCharacteristicsDiscovered(_ peripheral: CBPeripheral) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            finishWithError(ConnectorError.serviceNotFound)
            return
        }
        let chars = service.characteristics ?? []
        guard let nameChar = chars.first(where: { $0.uuid == deviceNameCharUUID }) else {
            finishWithError(ConnectorError.characteristicNotFound("DeviceName"))
            return
        }
        guard let sigChar = chars.first(where: { $0.uuid == deviceSignatureCharUUID }) else {
            finishWithError(ConnectorError.characteristicNotFound("DeviceSignature"))
            return
        }
        state = .readingCharacteristics
        peripheral.readValue(for: nameChar)
        peripheral.readValue(for: sigChar)
    }

    fileprivate func handleValueUpdate(_ characteristic: CBCharacteristic) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case deviceNameCharUUID:
            deviceName = String(data: data, encoding: .utf8)
        case deviceSignatureCharUUID:
            if let parsed = try? JSONDecoder().decode(InstantShareDeviceSignature.self, from: data) {
                deviceSignature = parsed
            }
        default:
            return
        }
        checkAllReadsComplete()
    }

    private func checkAllReadsComplete() {
        guard let peripheral = peripheral,
              let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
              let chars = service.characteristics else {
            return
        }
        let nameChar = chars.first(where: { $0.uuid == deviceNameCharUUID })
        let sigChar = chars.first(where: { $0.uuid == deviceSignatureCharUUID })
        guard let nameChar, let sigChar else { return }
        guard nameChar.value != nil, sigChar.value != nil else { return }
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        let info = InstantSharePeripheralInfo(
            deviceName: deviceName,
            deviceSignature: deviceSignature
        )
        continuation.resume(returning: info)
    }
}

struct InstantShareDeviceSignature: Codable, Equatable, Sendable {
    let signature: String
    let signatureKeyID: String
    let timestampMS: Int64

    enum CodingKeys: String, CodingKey {
        case signature
        case signatureKeyID = "signature_key_id"
        case timestampMS = "timestamp_ms"
    }
}

struct InstantSharePeripheralInfo: Equatable, Sendable {
    let deviceName: String?
    let deviceSignature: InstantShareDeviceSignature?
}

extension InstantShareBLEPeripheralConnector: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let errorBox = UncheckedSendableBox(error)
            Task { @MainActor [weak self] in
                self?.finishWithError(ConnectorError.writeFailed(errorBox.value))
            }
            return
        }
        let peripheralBox = UncheckedSendableBox(peripheral)
        Task { @MainActor [weak self] in
            self?.handleServiceDiscovered(peripheralBox.value)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            let errorBox = UncheckedSendableBox(error)
            Task { @MainActor [weak self] in
                self?.finishWithError(ConnectorError.writeFailed(errorBox.value))
            }
            return
        }
        let peripheralBox = UncheckedSendableBox(peripheral)
        Task { @MainActor [weak self] in
            self?.handleCharacteristicsDiscovered(peripheralBox.value)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            let charUUIDString = characteristic.uuid.uuidString
            let errorBox = UncheckedSendableBox(error)
            Task { @MainActor [weak self] in
                let name: String
                if charUUIDString == self?.deviceNameCharUUID.uuidString {
                    name = "DeviceName"
                } else {
                    name = "DeviceSignature"
                }
                self?.finishWithError(ConnectorError.readFailed(name))
                _ = errorBox
            }
            return
        }
        let charBox = UncheckedSendableBox(characteristic)
        Task { @MainActor [weak self] in
            self?.handleValueUpdate(charBox.value)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            let errorBox = UncheckedSendableBox(error)
            Task { @MainActor [weak self] in
                self?.state = .failed(errorBox.value.localizedDescription)
            }
        }
    }
}

private final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
