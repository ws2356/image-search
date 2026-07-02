import Foundation

protocol AppUpdateChecking: Sendable {
    func fetchVersionRequirement() async throws -> AppUpdateVersionRequirement
}

protocol AppVersionProviding: Sendable {
    func currentVersion() -> String?
}

struct BundleAppVersionProvider: AppVersionProviding {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func currentVersion() -> String? {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AppUpdatePrompt: Equatable, Sendable {
    let minimumVersion: String
    let required: Bool
    let appStoreURL: URL

    var title: String {
        required ? "Update Required" : "Update Available"
    }

    var message: String {
        if required {
            return "AuBackup \(minimumVersion) or later is required to continue. Update now from the App Store."
        }
        return "AuBackup \(minimumVersion) or later is available. Update now from the App Store."
    }
}

struct AppUpdateVersionRequirement: Equatable, Sendable {
    let minimumVersion: String
    let required: Bool

    func promptIfNeeded(currentVersion: String, appStoreURL: URL) -> AppUpdatePrompt? {
        guard let currentVersion = AppSemanticVersion(currentVersion),
              let minimumVersion = AppSemanticVersion(minimumVersion),
              currentVersion < minimumVersion
        else {
            return nil
        }

        return AppUpdatePrompt(
            minimumVersion: self.minimumVersion,
            required: required,
            appStoreURL: appStoreURL
        )
    }
}

struct AppSemanticVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ rawValue: String) {
        let segments = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)

        guard !segments.isEmpty else {
            return nil
        }

        var resolvedComponents: [Int] = []
        resolvedComponents.reserveCapacity(segments.count)
        for segment in segments {
            let numericPrefix = segment.prefix(while: \.isNumber)
            guard !numericPrefix.isEmpty, let value = Int(numericPrefix) else {
                return nil
            }
            resolvedComponents.append(value)
        }

        while resolvedComponents.count > 1, resolvedComponents.last == 0 {
            resolvedComponents.removeLast()
        }

        self.components = resolvedComponents
    }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<maxCount {
            let lhsValue = index < lhs.components.count ? lhs.components[index] : 0
            let rhsValue = index < rhs.components.count ? rhs.components[index] : 0
            if lhsValue != rhsValue {
                return lhsValue < rhsValue
            }
        }
        return false
    }
}

enum AppUpdateCheckError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case invalidStatusCode(Int)
    case invalidPayload
}

private struct AppUpdateFeaturesResponse: Decodable, Sendable {
    struct VersionResponse: Decodable, Sendable {
        let min: String
        let required: Bool
    }

    let version: VersionResponse
}

struct URLSessionAppUpdateChecker: AppUpdateChecking {
    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.boldman.net/aubackup/features")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func fetchVersionRequirement() async throws -> AppUpdateVersionRequirement {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateCheckError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppUpdateCheckError.invalidStatusCode(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(AppUpdateFeaturesResponse.self, from: data)
        let minimumVersion = decoded.version.min.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !minimumVersion.isEmpty, AppSemanticVersion(minimumVersion) != nil else {
            throw AppUpdateCheckError.invalidPayload
        }

        return AppUpdateVersionRequirement(
            minimumVersion: minimumVersion,
            required: decoded.version.required
        )
    }
}
