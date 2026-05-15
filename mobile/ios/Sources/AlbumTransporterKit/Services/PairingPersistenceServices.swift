import Foundation
import UIKit
import Combine

actor UserDefaultsBackupSessionStore: BackupSessionStore {
    private let userDefaults: UserDefaults
    private let backupSessionKey: String

    init(
        userDefaults: UserDefaults = .standard,
        backupSessionKey: String = "albumtransporter.backup-session"
    ) {
        self.userDefaults = userDefaults
        self.backupSessionKey = backupSessionKey
    }

    func loadBackupSession() async -> BackupSession? {
        guard let data = userDefaults.data(forKey: backupSessionKey) else {
            return nil
        }

        do {
            return try JSONDecoder.pairingDecoder.decode(BackupSession.self, from: data)
        } catch {
            return nil
        }
    }

    func saveBackupSession(_ session: BackupSession?) async {
        guard let session else {
            userDefaults.removeObject(forKey: backupSessionKey)
            return
        }

        do {
            let encodedSession = try JSONEncoder.pairingEncoder.encode(session)
            userDefaults.set(encodedSession, forKey: backupSessionKey)
        } catch {
            assertionFailure("Failed to encode backup session: \(error)")
        }
    }
}

@MainActor
final class DefaultBackupSessionProvider: BackupSessionProviding {
    @Published private var currentBackupSession: BackupSession?

    private let store: BackupSessionStore
    private var hasLoaded = false

    init(store: BackupSessionStore) {
        self.store = store
    }

    var backupSession: BackupSession? {
        currentBackupSession
    }

    var backupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        $currentBackupSession.eraseToAnyPublisher()
    }

    func load() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        currentBackupSession = await store.loadBackupSession()
    }

    func saveBackupSession(_ session: BackupSession?) async {
        currentBackupSession = session
        let store = store
        Task.detached(priority: .utility) {
            await store.saveBackupSession(session)
        }
    }
}

actor UserDefaultsTrustedDesktopStore: TrustedDesktopStore {
    private let userDefaults: UserDefaults
    private let recordKey: String

    init(
        userDefaults: UserDefaults = .standard,
        recordKey: String = "albumtransporter.trusted-desktop"
    ) {
        self.userDefaults = userDefaults
        self.recordKey = recordKey
    }

    func loadTrustedDesktop() async -> TrustedDesktopRecord? {
        guard let data = userDefaults.data(forKey: recordKey) else {
            return nil
        }

        do {
            return try JSONDecoder.pairingDecoder.decode(TrustedDesktopRecord.self, from: data)
        } catch {
            assertionFailure("Failed to decode trusted desktop record: \(error)")
            return nil
        }
    }

    func saveTrustedDesktop(_ record: TrustedDesktopRecord) async {
        do {
            let encodedRecord = try JSONEncoder.pairingEncoder.encode(record)
            userDefaults.set(encodedRecord, forKey: recordKey)
        } catch {
            assertionFailure("Failed to encode trusted desktop record: \(error)")
        }
    }
}

actor UserDefaultsLocalDeviceIdentityStore: LocalDeviceIdentityProviding {
    private let userDefaults: UserDefaults
    private let installIDKey: String
    private let deviceUUIDKey: String

    init(
        userDefaults: UserDefaults = .standard,
        installIDKey: String = "albumtransporter.install-id",
        deviceUUIDKey: String = "albumtransporter.device-uuid"
    ) {
        self.userDefaults = userDefaults
        self.installIDKey = installIDKey
        self.deviceUUIDKey = deviceUUIDKey
    }

    func currentIdentity() async -> LocalDeviceIdentity {
        let installID = storedValue(forKey: installIDKey)
        let deviceUUID = storedValue(forKey: deviceUUIDKey)
        return LocalDeviceIdentity(
            installID: installID,
            deviceUUID: deviceUUID,
            deviceName: currentDeviceName(),
            platform: "ios"
        )
    }

    private func storedValue(forKey key: String) -> String {
        if let existingValue = userDefaults.string(forKey: key), !existingValue.isEmpty {
            return existingValue
        }

        let generatedValue = UUID().uuidString.lowercased()
        userDefaults.set(generatedValue, forKey: key)
        return generatedValue
    }

    private func currentDeviceName() -> String {
        UIDevice.current.name
    }
}

extension JSONEncoder {
    static let pairingEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(PairingDateCodec.string(from: date))
        }
        return encoder
    }()
}

extension JSONDecoder {
    static let pairingDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let decodedDate = PairingDateCodec.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid pairing date '\(value)'.")
            }
            return decodedDate
        }
        return decoder
    }()
}
