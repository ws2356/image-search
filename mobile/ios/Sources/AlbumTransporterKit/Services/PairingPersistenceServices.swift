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
    @Published private var _currentBackupSession: BackupSession?
    @Published private var _lastBackupSession: BackupSession?

    private let store: BackupSessionStore
    private var hasLoaded = false

    /// States that represent a terminated session and should be persisted as `lastBackupSession`.
    private static let terminatingStatuses: Set<MobileBackupFlowState> = [
        .transferCompleted, .transferFailed, .transferStopped,
        .pairingFailed, .pairingStopped, .pairingExpired
    ]

    init(store: BackupSessionStore) {
        self.store = store
    }

    var currentBackupSession: BackupSession? { _currentBackupSession }

    var currentBackupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        $_currentBackupSession.eraseToAnyPublisher()
    }

    var lastBackupSession: BackupSession? { _lastBackupSession }

    var lastBackupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        $_lastBackupSession.eraseToAnyPublisher()
    }

    func load() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        _lastBackupSession = await store.loadBackupSession()
        BackupSessionDebugLogger.debug(
            "Backup session provider loaded last_status=\(_lastBackupSession?.status.rawValue ?? "none") session_id_present=\(!(_lastBackupSession?.sessionID ?? "").isEmpty)"
        )
    }

    func saveBackupSession(_ session: BackupSession?) async {
        _currentBackupSession = session
        BackupSessionDebugLogger.debug(
            "Backup session provider accepted update status=\(session?.status.rawValue ?? "none") session_id_present=\(!(session?.sessionID ?? "").isEmpty)"
        )
        guard let session, Self.terminatingStatuses.contains(session.status) else {
            return
        }
        _lastBackupSession = session
        let store = store
        Task(priority: .utility) {
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
