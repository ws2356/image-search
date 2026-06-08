import Foundation
import os.log

/// Lightweight diagnostic logger for instant-share flows.
///
/// Uses Apple's unified logging system (`os.log`) so messages appear in
/// Xcode console and `Console.app` with the `InstantShare` subsystem tag,
/// and also mirrors to `print` so messages always surface in the Xcode
/// debug console without needing a console filter.
///
/// This is intentionally separate from the production telemetry pipeline —
/// diagnostic logs are only for development debugging.
public enum LocalLog {
    private static let logger = OSLog(subsystem: "com.aubackup.instant-share", category: "diagnostic")

    public static func info(_ message: String) {
        os_log("%{public}@", log: logger, type: .info, message)
        print("[InstantShare] " + message)
    }

    public static func error(_ message: String) {
        os_log("%{public}@", log: logger, type: .error, message)
        print("[InstantShare][ERROR] " + message)
    }

    public static func debug(_ message: String) {
        os_log("%{public}@", log: logger, type: .debug, message)
        print("[InstantShare][DEBUG] " + message)
    }
}
