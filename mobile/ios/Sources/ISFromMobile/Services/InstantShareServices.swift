import CryptoKit
import Foundation
import Network

enum InstantShareProtocol {
    static let schema = "dtis.instant-share.v1"
    static let flowID = "instant_share"
    static let version = "1.0"
    static let apiPrefix = "/api/instant-share/v1"
    static let trustHandshakePath = "/trust/handshake"
    static let trustApplyPath = "/trust/apply"
    static let trustConfirmPath = "/trust/confirm"
    static let transferTextPath = "/transfer/text"
    static let transferImagePath = "/transfer/image"
    static let transferDownloadPath = "/transfer/download"
    static let payloadTextPath = "/payload/text"
    static let payloadImagePath = "/payload/image"
    static let deliveryResultPath = "/delivery-result"
    static let trustEnvelopeSchema = "dtis.instant-share.trust-envelope.v1"
    static let trustEnvelopeNonceBytes = 12
}

enum InstantSharePayloadClass: String, Codable, Sendable, CaseIterable {
    case text
    case link
    case image
}

enum InstantShareTargetIntent: String, Codable, Sendable, CaseIterable {
    case clipboardOnly = "clipboard_only"
    case clipboardOrFile = "clipboard_or_file"
}

enum InstantShareTrustMode: String, Codable, Sendable, CaseIterable {
    case firstShare = "first_share"
    case trustedDirect = "trusted_direct"
}

enum InstantShareSessionState: String, Codable, Sendable {
    case bootstrapped
    case queued
    case negotiating
    case transferring
    case delivering
    case done
    case failed
    case timedOut = "timed_out"
    case aborted
}

enum InstantShareServiceError: Error, Sendable {
    case invalidFlowID
    case invalidSessionID
    case invalidCorrelationID
    case invalidPort
    case missingIPAddresses
    case invalidIPAddress(String)
    case invalidTargetIntent(payloadClass: InstantSharePayloadClass, targetIntent: InstantShareTargetIntent)
    case invalidTrustEnvelope
    case invalidTrustEnvelopeField(String)
    case invalidPlaintextJSONObject
    case decryptionFailed
}

extension InstantShareServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidFlowID:
            return "Instant-share flow_id is invalid."
        case .invalidSessionID:
            return "Instant-share session_id is invalid."
        case .invalidCorrelationID:
            return "Instant-share correlation_id is invalid."
        case .invalidPort:
            return "Instant-share mobile_port must be in range 1...65535."
        case .missingIPAddresses:
            return "Instant-share requires at least one mobile IP address."
        case .invalidIPAddress(let value):
            return "Instant-share mobile_ip_list contains an invalid address: \(value)."
        case .invalidTargetIntent(let payloadClass, let targetIntent):
            return "Instant-share target_intent=\(targetIntent.rawValue) is invalid for payload_class=\(payloadClass.rawValue)."
        case .invalidTrustEnvelope:
            return "Instant-share trust envelope is invalid."
        case .invalidTrustEnvelopeField(let fieldName):
            return "Instant-share trust envelope field '\(fieldName)' is invalid."
        case .invalidPlaintextJSONObject:
            return "Instant-share trust payload is not a valid JSON object."
        case .decryptionFailed:
            return "Instant-share trust envelope could not be decrypted."
        }
    }
}

/// Inlined metadata fields used by request structs.
/// flowID is always InstantShareProtocol.flowID.
struct InstantShareTrustHandshakeRequest: Encodable, Sendable, Equatable {
    var flowID = InstantShareProtocol.flowID
    var payloadClass: String
    var targetIntent: String
    var trustMode: String
    var pcDHPublicKey: String
    var pcNonce: String

    enum CodingKeys: String, CodingKey {
        case flowID = "flow_id"
        case payloadClass = "payload_class"
        case targetIntent = "target_intent"
        case trustMode = "trust_mode"
        case pcDHPublicKey = "pc_dh_public_key"
        case pcNonce = "pc_nonce"
    }
}

struct InstantShareTrustHandshakeResponse: Codable, Sendable, Equatable {
    var mobileDHPublicKey: String
    var mobileNonce: String
    var kdfContext: String

    enum CodingKeys: String, CodingKey {
        case mobileDHPublicKey = "mobile_dh_public_key"
        case mobileNonce = "mobile_nonce"
        case kdfContext = "kdf_context"
    }
}

struct InstantShareTrustApplyPayload: Encodable, Sendable, Equatable {
    var flowID = InstantShareProtocol.flowID
    var payloadClass: String
    var targetIntent: String
    var trustMode: String
    var encryptedPayload: String
    var encryptionAlgorithm: String
    var keyID: String?

    enum CodingKeys: String, CodingKey {
        case flowID = "flow_id"
        case payloadClass = "payload_class"
        case targetIntent = "target_intent"
        case trustMode = "trust_mode"
        case encryptedPayload = "encrypted_payload"
        case encryptionAlgorithm = "encryption_alg"
        case keyID = "key_id"
    }
}

struct InstantShareTrustConfirmPayload: Encodable, Sendable, Equatable {
    var flowID = InstantShareProtocol.flowID
    var payloadClass: String
    var targetIntent: String
    var trustMode: String
    var pcPublicKeyPEM: String

    enum CodingKeys: String, CodingKey {
        case flowID = "flow_id"
        case payloadClass = "payload_class"
        case targetIntent = "target_intent"
        case trustMode = "trust_mode"
        case pcPublicKeyPEM = "pc_public_key_pem"
    }
}

struct InstantShareTrustEnvelope: Codable, Sendable, Equatable {
    var schema = InstantShareProtocol.trustEnvelopeSchema
    var nonce: String
    var ciphertext: String
}

enum InstantShareTrustSessionProtector {
    static func encryptPayloadObject(
        _ payload: [String: Any],
        sessionKey: SymmetricKey,
        nonceData: Data? = nil
    ) throws -> InstantShareTrustEnvelope {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw InstantShareServiceError.invalidPlaintextJSONObject
        }
        let nonce: AES.GCM.Nonce
        if let nonceData {
            guard nonceData.count == InstantShareProtocol.trustEnvelopeNonceBytes else {
                throw InstantShareServiceError.invalidTrustEnvelopeField("nonce")
            }
            nonce = try AES.GCM.Nonce(data: nonceData)
        } else {
            nonce = AES.GCM.Nonce()
        }
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sealedBox = try AES.GCM.seal(plaintext, using: sessionKey, nonce: nonce)
        guard let combinedCiphertext = sealedBox.combined else {
            throw InstantShareServiceError.invalidTrustEnvelope
        }
        let resolvedNonceData = Data(nonce)
        let ciphertextData = combinedCiphertext.dropFirst(resolvedNonceData.count)
        return InstantShareTrustEnvelope(
            nonce: resolvedNonceData.instantShareBase64URLEncodedString(),
            ciphertext: Data(ciphertextData).instantShareBase64URLEncodedString()
        )
    }

    static func decryptPayloadObject(
        _ envelope: InstantShareTrustEnvelope,
        sessionKey: SymmetricKey
    ) throws -> [String: Any] {
        guard envelope.schema == InstantShareProtocol.trustEnvelopeSchema else {
            throw InstantShareServiceError.invalidTrustEnvelope
        }
        let nonceData = try Data(instantShareBase64URLEncoded: envelope.nonce)
        guard nonceData.count == InstantShareProtocol.trustEnvelopeNonceBytes else {
            throw InstantShareServiceError.invalidTrustEnvelopeField("nonce")
        }
        let ciphertextData = try Data(instantShareBase64URLEncoded: envelope.ciphertext)
        let combinedData = nonceData + ciphertextData
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        } catch {
            throw InstantShareServiceError.decryptionFailed
        }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: sessionKey)
        } catch {
            throw InstantShareServiceError.decryptionFailed
        }
        let decodedPayload = try JSONSerialization.jsonObject(with: plaintext)
        guard let payload = decodedPayload as? [String: Any] else {
            throw InstantShareServiceError.invalidTrustEnvelope
        }
        return payload
    }
}

extension Data {
    init(instantShareBase64URLEncoded value: String) throws {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            throw InstantShareServiceError.invalidTrustEnvelope
        }
        let base64Value = normalizedValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64Value.count % 4) % 4)
        guard let decodedData = Data(base64Encoded: base64Value + padding) else {
            throw InstantShareServiceError.invalidTrustEnvelope
        }
        self = decodedData
    }

    func instantShareBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
