import Foundation
import UIKit
import Combine
import OSLog

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
            BackupSessionDebugLogger.debug("Backup session load found no persisted record key=\(backupSessionKey)")
            return nil
        }

        do {
            let session = try JSONDecoder.pairingDecoder.decode(BackupSession.self, from: data)
            BackupSessionDebugLogger.debug(
                "Backup session load succeeded key=\(backupSessionKey) status=\(session.status.rawValue) session_id_present=\((session.sessionID?.isEmpty == false)) desktop_name_present=\(!(session.desktopName ?? "").isEmpty)"
            )
            return session
        } catch {
            BackupSessionDebugLogger.error(
                "Backup session load failed key=\(backupSessionKey) error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    func saveBackupSession(_ session: BackupSession?) async {
        guard let session else {
            userDefaults.removeObject(forKey: backupSessionKey)
            BackupSessionDebugLogger.debug("Backup session cleared key=\(backupSessionKey)")
            return
        }

        do {
            let encodedSession = try JSONEncoder.pairingEncoder.encode(session)
            userDefaults.set(encodedSession, forKey: backupSessionKey)
            BackupSessionDebugLogger.debug(
                "Backup session save succeeded key=\(backupSessionKey) status=\(session.status.rawValue) session_id_present=\((session.sessionID?.isEmpty == false)) desktop_name_present=\(!(session.desktopName ?? "").isEmpty)"
            )
        } catch {
            BackupSessionDebugLogger.error(
                "Backup session save failed key=\(backupSessionKey) status=\(session.status.rawValue) error=\(error.localizedDescription)"
            )
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
        BackupSessionDebugLogger.debug(
            "Backup session provider loaded status=\(currentBackupSession?.status.rawValue ?? "none") session_id_present=\(!(currentBackupSession?.sessionID ?? "").isEmpty)"
        )
    }

    func saveBackupSession(_ session: BackupSession?) async {
        currentBackupSession = session
        BackupSessionDebugLogger.debug(
            "Backup session provider accepted update status=\(session?.status.rawValue ?? "none") session_id_present=\(!(session?.sessionID ?? "").isEmpty)"
        )
        let store = store
        Task.detached(priority: .utility) {
            await store.saveBackupSession(session)
        }
    }
}

private enum BackupSessionDebugLogger {
    private static let logger = Logger(
        subsystem: "AlbumTransporterKit.Pairing",
        category: "BackupSession"
    )

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
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
