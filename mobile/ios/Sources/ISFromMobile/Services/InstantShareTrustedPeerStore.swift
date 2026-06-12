import Foundation
import Security

enum InstantShareTrustedPeerStoreError: Swift.Error, LocalizedError {
    case storeFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let msg): return "Failed to store trusted peer certificate: \(msg)"
        case .loadFailed(let msg): return "Failed to load trusted peer certificate: \(msg)"
        }
    }
}

enum InstantShareTrustedPeerStore {

    private static let label = "AuSearch Trusted Device"

    static func store(peerDeviceID: String, certificatePEM: String) throws {
        let service = "com.aubackup.trusted-device.\(peerDeviceID)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: peerDeviceID,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(certificatePEM.utf8),
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw InstantShareTrustedPeerStoreError.storeFailed(
                "SecItemAdd returned \(status)"
            )
        }
    }

    static func load(peerDeviceID: String) -> String? {
        let service = "com.aubackup.trusted-device.\(peerDeviceID)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: peerDeviceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
