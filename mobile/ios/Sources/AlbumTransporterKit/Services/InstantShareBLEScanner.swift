import CoreBluetooth
import Foundation

/// Scans for PC-side instant-share BLE peripherals and provides a list of
/// discovered candidates for the debug UI to display.
///
/// The PC exposes a single GATT service with UUID `4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b`
/// and the name "instant-sharing" (see `InstantShareProtocol`).
struct InstantShareDiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String?
    let advertisementServiceUUIDStrings: [String]
    let rssi: Int
    let discoveredAt: Date
}

enum InstantShareBLEScannerState: Equatable, Sendable {
    case uninitialized
    case poweredOff
    case unauthorized
    case unsupported
    case idle
    case scanning
}

@MainActor
final class InstantShareBLEScanner: NSObject, ObservableObject {
    @Published private(set) var state: InstantShareBLEScannerState = .uninitialized
    @Published private(set) var discovered: [InstantShareDiscoveredPeripheral] = []

    private let serviceUUID = CBUUID(string: "4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b")
    private var centralManager: CBCentralManager?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var rssiByPeripheralID: [UUID: Int] = [:]
    private var nameByPeripheralID: [UUID: String] = [:]
    private var serviceUUIDsByPeripheralID: [UUID: [String]] = [:]
    private var discoveredAtByPeripheralID: [UUID: Date] = [:]
    private var isScanning = false

    override init() {
        super.init()
    }

    /// Initialize the BLE central manager. Must be called before `startScanning()`.
    /// On the first call, iOS will prompt the user for Bluetooth permission.
    func initialize() {
        guard centralManager == nil else { return }
        let manager = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: NSNumber(value: true),
        ])
        centralManager = manager
    }

    /// Start scanning for instant-share peripherals.
    func startScanning() {
        initialize()
        guard let manager = centralManager else { return }

        switch manager.state {
        case .poweredOn:
            break
        case .poweredOff:
            state = .poweredOff
            return
        case .unauthorized:
            state = .unauthorized
            return
        case .unsupported:
            state = .unsupported
            return
        case .resetting, .unknown:
            return
        @unknown default:
            return
        }

        guard !isScanning else { return }
        isScanning = true
        discovered = []
        peripheralsByID = [:]
        rssiByPeripheralID = [:]
        nameByPeripheralID = [:]
        serviceUUIDsByPeripheralID = [:]
        discoveredAtByPeripheralID = [:]

        manager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
        )
        state = .scanning
    }

    /// Stop scanning.
    func stopScanning() {
        guard let manager = centralManager else { return }
        manager.stopScan()
        isScanning = false
        if state == .scanning {
            state = .idle
        }
    }

    /// Look up the CBPeripheral for a discovered candidate. Must be called before
    /// disconnecting from the peripheral; the OS may prune unused references.
    func peripheral(for discovered: InstantShareDiscoveredPeripheral) -> CBPeripheral? {
        peripheralsByID[discovered.id]
    }
}

extension InstantShareBLEScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState: InstantShareBLEScannerState
        switch central.state {
        case .poweredOn:
            newState = .idle
        case .poweredOff:
            newState = .poweredOff
        case .unauthorized:
            newState = .unauthorized
        case .unsupported:
            newState = .unsupported
        case .resetting, .unknown:
            newState = .uninitialized
        @unknown default:
            newState = .uninitialized
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .idle:
                if self.isScanning {
                    self.state = .scanning
                } else {
                    self.state = .idle
                }
            default:
                self.state = newState
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let peripheralID = peripheral.identifier
        let peripheralName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let advertisedServiceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let rssiValue = RSSI.intValue
        let discoveredAt = Date()
        let advertisedUUIDStrings = advertisedServiceUUIDs.map { $0.uuidString }

        // CBPeripheral is not Sendable; the MainActor.assumeIsolated is not
        // appropriate here since this delegate callback is on the BLE queue.
        // We use a @unchecked Sendable wrapper to pass the peripheral across.
        let peripheralBox = UncheckedSendableBox(peripheral)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.peripheralsByID[peripheralID] = peripheralBox.value
            self.rssiByPeripheralID[peripheralID] = rssiValue
            if let peripheralName, !peripheralName.isEmpty {
                self.nameByPeripheralID[peripheralID] = peripheralName
            }
            self.serviceUUIDsByPeripheralID[peripheralID] = advertisedUUIDStrings
            self.discoveredAtByPeripheralID[peripheralID] = discoveredAt

            let resolvedName = self.nameByPeripheralID[peripheralID]
            let entry = InstantShareDiscoveredPeripheral(
                id: peripheralID,
                name: resolvedName,
                advertisementServiceUUIDStrings: advertisedUUIDStrings,
                rssi: rssiValue,
                discoveredAt: discoveredAt
            )

            if let index = self.discovered.firstIndex(where: { $0.id == peripheralID }) {
                self.discovered[index] = entry
            } else {
                self.discovered.append(entry)
                self.discovered.sort { $0.rssi > $1.rssi }
            }
        }
    }
}

private final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
