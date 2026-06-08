import CoreBluetooth
import Foundation
import Common

/// Scans for PC-side instant-share BLE peripherals and provides a list of
/// discovered candidates for the debug UI to display.
///
/// The PC exposes a single GATT service with UUID `4abf1c8a-6e2e-4cf2-bff7-6cbad77b0f8b`
/// and the name "instant-sharing" (see `InstantShareProtocol`).
public struct InstantShareDiscoveredPeripheral: Identifiable, Equatable {
    public let id: UUID
    public let name: String?
    public let advertisementServiceUUIDStrings: [String]
    public let rssi: Int
    public let discoveredAt: Date
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
public final class InstantShareBLEScanner: NSObject, ObservableObject {
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
    private var pendingScanRequest = false

    public override init() {
        super.init()
    }

    /// Initialize the BLE central manager. Must be called before `startScanning()`.
    /// On the first call, iOS will prompt the user for Bluetooth permission.
    func initialize() {
        LocalLog.info("[BLE Scanner] initialize() called, existing manager: \(centralManager != nil)")
        guard centralManager == nil else { return }
        let manager = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: NSNumber(value: true),
        ])
        centralManager = manager
        LocalLog.info("[BLE Scanner] CBCentralManager created, current state: \(manager.state.rawValue)")
    }

    /// Start scanning for instant-share peripherals.
    /// The actual scan only begins once the central manager reports
    /// `state == .poweredOn`. If the manager is not yet ready when this is
    /// called, the request is queued and fulfilled when the state transition
    /// arrives via `centralManagerDidUpdateState`.
    func startScanning() {
        LocalLog.info("[BLE Scanner] startScanning() called")
        initialize()
        pendingScanRequest = true
        attemptStartScan()
    }

    private func attemptStartScan() {
        guard pendingScanRequest else {
            LocalLog.info("[BLE Scanner] attemptStartScan: no pending request, ignoring")
            return
        }
        guard let manager = centralManager else {
            LocalLog.error("[BLE Scanner] attemptStartScan: centralManager is nil")
            return
        }

        let stateName = centralManagerStateName(manager.state)
        LocalLog.info("[BLE Scanner] attemptStartScan: current central state: \(stateName)")

        switch manager.state {
        case .poweredOn:
            break
        case .poweredOff:
            LocalLog.error("[BLE Scanner] Bluetooth is powered off")
            state = .poweredOff
            return
        case .unauthorized:
            LocalLog.error("[BLE Scanner] Bluetooth permission denied")
            state = .unauthorized
            return
        case .unsupported:
            LocalLog.error("[BLE Scanner] Bluetooth LE not supported on this device")
            state = .unsupported
            return
        case .resetting, .unknown:
            LocalLog.info("[BLE Scanner] state is \(stateName); will retry on next state update")
            return
        @unknown default:
            LocalLog.error("[BLE Scanner] Unknown central state")
            return
        }

        guard !isScanning else {
            LocalLog.info("[BLE Scanner] already scanning; skipping duplicate start")
            return
        }
        isScanning = true
        pendingScanRequest = false
        discovered = []
        peripheralsByID = [:]
        rssiByPeripheralID = [:]
        nameByPeripheralID = [:]
        serviceUUIDsByPeripheralID = [:]
        discoveredAtByPeripheralID = [:]

        LocalLog.info("[BLE Scanner] starting scan for service UUID: \(serviceUUID.uuidString)")
        manager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)]
        )
        state = .scanning
        LocalLog.info("[BLE Scanner] scan started, state set to .scanning")
    }

    private func centralManagerStateName(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        case .unknown: return "unknown"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }

    /// Stop scanning.
    func stopScanning() {
        LocalLog.info("[BLE Scanner] stopScanning() called")
        pendingScanRequest = false
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
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateName: String
        let centralIsPoweredOn: Bool
        switch central.state {
        case .poweredOn: stateName = "poweredOn"; centralIsPoweredOn = true
        case .poweredOff: stateName = "poweredOff"; centralIsPoweredOn = false
        case .unauthorized: stateName = "unauthorized"; centralIsPoweredOn = false
        case .unsupported: stateName = "unsupported"; centralIsPoweredOn = false
        case .resetting: stateName = "resetting"; centralIsPoweredOn = false
        case .unknown: stateName = "unknown"; centralIsPoweredOn = false
        @unknown default: stateName = "unknown(\(central.state.rawValue))"; centralIsPoweredOn = false
        }
        LocalLog.info("[BLE Scanner] centralManagerDidUpdateState: \(stateName)")
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
            LocalLog.info("[BLE Scanner] scanner.state set to: \(self.state)")

            if centralIsPoweredOn && self.pendingScanRequest {
                LocalLog.info("[BLE Scanner] central is poweredOn and scan is pending, fulfilling request")
                self.attemptStartScan()
            }
        }
    }

    nonisolated public func centralManager(
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

        LocalLog.info(
            "[BLE Scanner] didDiscover: id=\(peripheralID.uuidString.prefix(8))... " +
            "name=\(peripheralName ?? "<nil>") rssi=\(rssiValue) " +
            "serviceUUIDs=\(advertisedUUIDStrings.joined(separator: ","))"
        )

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
            LocalLog.info("[BLE Scanner] discovered count now: \(self.discovered.count)")
        }
    }
}

private final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
