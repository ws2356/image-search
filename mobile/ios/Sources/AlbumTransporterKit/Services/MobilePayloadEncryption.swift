import CryptoKit
import Foundation

enum MobilePayloadEncryptionProtocol {
    static let schema = "dtis.mobile-encryption.v1"
    static let keyDerivationContext = "dtis.mobile-encryption.key.v1"
    static let capabilityName = "encryption"
    static let binaryChunkVersion: UInt8 = 1
    static let binaryNonceBytes = 12
    static let binaryTagBytes = 16
    static let binaryChunkOverheadBytes = 1 + binaryNonceBytes + binaryTagBytes
}

struct MobileEncryptedPayload: Codable, Sendable {
    var schema = MobilePayloadEncryptionProtocol.schema
    var nonce: String
    var ciphertext: String
    var sessionID: String
    var deviceUUID: String?
    var platform: String?

    enum CodingKeys: String, CodingKey {
        case schema
        case nonce
        case ciphertext
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case platform
    }
}

enum MobilePayloadEncryptionError: Error, Sendable {
    case invalidTrustKey
    case invalidPlaintextJSONObject
    case invalidEncryptedPayload
    case invalidEncryptedPayloadType
    case invalidEncryptedPayloadField(String)
    case decryptionFailed
}

enum MobilePayloadEncryption {
    static func isEncryptedPayload(_ payload: [String: Any]) -> Bool {
        payload["schema"] as? String == MobilePayloadEncryptionProtocol.schema
    }

    static func encryptPayloadObject(
        _ payload: [String: Any],
        trustKeyBase64: String,
        sessionID: String,
        deviceUUID: String? = nil,
        platform: String? = nil
    ) throws -> MobileEncryptedPayload {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw MobilePayloadEncryptionError.invalidPlaintextJSONObject
        }
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: try deriveKey(trustKeyBase64: trustKeyBase64), nonce: nonce)
        guard let combinedCiphertext = sealedBox.combined else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayload
        }
        let nonceData = Data(nonce)
        let ciphertextData = combinedCiphertext.dropFirst(nonceData.count)
        return MobileEncryptedPayload(
            nonce: nonceData.mobileBase64URLEncodedString(),
            ciphertext: Data(ciphertextData).mobileBase64URLEncodedString(),
            sessionID: sessionID,
            deviceUUID: deviceUUID,
            platform: platform
        )
    }

    static func decryptPayloadObject(
        _ encryptedPayload: [String: Any],
        trustKeyBase64: String
    ) throws -> [String: Any] {
        guard isEncryptedPayload(encryptedPayload) else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayload
        }
        guard let nonceRawValue = encryptedPayload["nonce"] as? String, !nonceRawValue.isEmpty else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayloadField("nonce")
        }
        guard let ciphertextRawValue = encryptedPayload["ciphertext"] as? String, !ciphertextRawValue.isEmpty else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayloadField("ciphertext")
        }
        let nonceData = try Data(mobileBase64URLEncoded: nonceRawValue)
        let ciphertextData = try Data(mobileBase64URLEncoded: ciphertextRawValue)
        let combinedData = nonceData + ciphertextData
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        } catch {
            throw MobilePayloadEncryptionError.decryptionFailed
        }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: try deriveKey(trustKeyBase64: trustKeyBase64))
        } catch {
            throw MobilePayloadEncryptionError.decryptionFailed
        }
        let decoded = try JSONSerialization.jsonObject(with: plaintext)
        guard let payload = decoded as? [String: Any] else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayloadType
        }
        return payload
    }

    static func encryptBinaryChunk(
        _ chunk: Data,
        trustKeyBase64: String
    ) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(chunk, using: try deriveKey(trustKeyBase64: trustKeyBase64), nonce: nonce)
        guard let combinedCiphertext = sealedBox.combined else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayload
        }
        let nonceData = Data(nonce)
        let ciphertextData = combinedCiphertext.dropFirst(nonceData.count)
        return Data([MobilePayloadEncryptionProtocol.binaryChunkVersion]) + nonceData + ciphertextData
    }

    static func deriveKey(trustKeyBase64: String) throws -> SymmetricKey {
        let normalizedTrustKey = trustKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTrustKey.isEmpty else {
            throw MobilePayloadEncryptionError.invalidTrustKey
        }
        let keyMaterial = "\(MobilePayloadEncryptionProtocol.keyDerivationContext)\n\(normalizedTrustKey)"
        let digest = SHA256.hash(data: Data(keyMaterial.utf8))
        return SymmetricKey(data: Data(digest))
    }
}

private extension Data {
    init(mobileBase64URLEncoded value: String) throws {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayload
        }
        let base64Value = normalizedValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64Value.count % 4) % 4)
        guard let decodedData = Data(base64Encoded: base64Value + padding) else {
            throw MobilePayloadEncryptionError.invalidEncryptedPayload
        }
        self = decodedData
    }

    func mobileBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
