import Foundation

final class PersistentOTLPRequestStore: @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(signal: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = baseDirectory
            .appendingPathComponent("AlbumTransporterTelemetry", isDirectory: true)
            .appendingPathComponent(signal, isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func enqueue(payload: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = directoryURL.appendingPathComponent("\(Date().timeIntervalSince1970)-\(UUID().uuidString.lowercased()).json")
        do {
            try payload.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func drain(send: (Data) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fileURLs = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        var drainedAll = true
        for fileURL in fileURLs {
            guard let payload = try? Data(contentsOf: fileURL) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            guard send(payload) else {
                drainedAll = false
                break
            }

            try? fileManager.removeItem(at: fileURL)
        }

        return drainedAll
    }
}
