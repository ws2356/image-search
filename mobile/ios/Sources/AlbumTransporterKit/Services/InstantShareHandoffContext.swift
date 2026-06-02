import Foundation

struct InstantShareHandoffContext: Codable {
    let payloadType: String
    let textContent: String?
    let fileURLString: String?
    let filename: String?
    let contentType: String?
    let fileSizeBytes: Int64?
    let selectedDeviceID: String?
    let selectedDeviceName: String?
    let isTrustedDevice: Bool
    let createdAt: Date

    static let appGroupIdentifier = "group.com.aubackup.instant-share"
    static let handoffKey = "pending-instant-share-handoff"

    init(from envelope: InstantSharePayloadEnvelope, selectedDeviceID: String?, selectedDeviceName: String?, isTrustedDevice: Bool) {
        self.payloadType = envelope.payloadType.rawValue
        self.textContent = envelope.textContent
        self.fileURLString = envelope.fileURL?.absoluteString
        self.filename = envelope.filename
        self.contentType = envelope.contentType
        self.fileSizeBytes = envelope.fileSizeBytes
        self.selectedDeviceID = selectedDeviceID
        self.selectedDeviceName = selectedDeviceName
        self.isTrustedDevice = isTrustedDevice
        self.createdAt = Date()
    }

    func persist() throws {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            throw InstantShareHandoffError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(self)
        defaults.set(data, forKey: Self.handoffKey)
    }

    static func load() throws -> InstantShareHandoffContext? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw InstantShareHandoffError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: handoffKey) else { return nil }
        return try JSONDecoder().decode(InstantShareHandoffContext.self, from: data)
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.removeObject(forKey: handoffKey)
    }

    var isStale: Bool {
        Date().timeIntervalSince(createdAt) > 300
    }

    var fileURL: URL? {
        guard let urlString = fileURLString else { return nil }
        return URL(string: urlString)
    }
}

enum InstantShareHandoffError: Error, LocalizedError {
    case appGroupUnavailable
    case contextMissing
    case contextStale

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App group for instant-share handoff is not configured."
        case .contextMissing:
            return "No pending instant-share handoff context found."
        case .contextStale:
            return "The instant-share handoff context has expired."
        }
    }
}
