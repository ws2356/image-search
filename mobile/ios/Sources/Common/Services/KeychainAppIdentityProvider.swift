import Foundation
import Security
import CryptoKit

public protocol AppIdentityProviding: Sendable {
    func ensureIdentity() throws
}

public final class KeychainAppIdentityProvider: AppIdentityProviding {
    private static let keyLabel = "AuBackup App Identity"
    
    public init() {}

    enum IdentityError: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed
        case identityNotFound
        case publicKeyExportFailed

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Failed to generate EC keypair."
            case .certificateCreationFailed: return "Failed to create self-signed X.509 certificate."
            case .identityNotFound: return "Could not retrieve app identity."
            case .publicKeyExportFailed: return "Failed to export public key as PEM."
            }
        }
    }

    public func ensureIdentity() throws {
        if let _ = try? retrieveExistingIdentity() {
            return
        }
        try createIdentity()
    }

    private func retrieveExistingIdentity() throws -> SecIdentity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: Self.keyLabel,
            kSecReturnRef as String: true,
        ]
        var identityRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &identityRef)
        guard status == errSecSuccess, let secIdent = identityRef as! SecIdentity? else {
            throw IdentityError.identityNotFound
        }
        return secIdent
    }

    private func createIdentity() throws {
        for secClass in [kSecClassIdentity, kSecClassCertificate, kSecClassKey] {
            SecItemDelete([kSecClass: secClass, kSecAttrLabel: Self.keyLabel] as CFDictionary)
        }

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrLabel as String: Self.keyLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
        ]
        guard let privateSecKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, nil) else {
            throw IdentityError.keyGenerationFailed
        }
        guard let publicSecKey = SecKeyCopyPublicKey(privateSecKey) else {
            throw IdentityError.keyGenerationFailed
        }
        guard let rawPubKey = SecKeyCopyExternalRepresentation(publicSecKey, nil) as Data? else {
            throw IdentityError.keyGenerationFailed
        }

        let certificate = try buildSelfSignedCert(privateKey: privateSecKey, rawPubKey: rawPubKey)
        SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: Self.keyLabel] as CFDictionary, nil)
    }

    // MARK: - Certificate

    private func buildSelfSignedCert(privateKey: SecKey, rawPubKey: Data) throws -> SecCertificate {
        let issuer = _DistinguishedName(commonName: "AuBackup")
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .year, value: 10, to: notBefore)!
        let serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let spki = _encodeSubjectPublicKeyInfo(rawPubKey)
        let tbs = _encTBSCert(serial: serial, issuer: issuer, nb: notBefore, na: notAfter, subj: issuer, spki: spki)
        let sigAlgo = _encSigAlgo()
        let digest = SHA256.hash(data: tbs)
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureDigestX962SHA256, Data(digest) as CFData, nil) as Data? else {
            throw IdentityError.certificateCreationFailed
        }
        let sigVal = _tlv(0x03, Data([0x00]) + signature)
        let derCert = _tlv(0x30, tbs + sigAlgo + sigVal)
        guard let cert = SecCertificateCreateWithData(nil, derCert as CFData) else {
            throw IdentityError.certificateCreationFailed
        }
        return cert
    }

    // MARK: - ASN.1 helpers

    private func _tlv(_ tag: UInt8, _ value: Data) -> Data {
        _encodeASN1(tag: tag, value: value)
    }

    private func _encodeASN1(tag: UInt8, value: Data) -> Data {
        var result = Data([tag])
        if value.count < 128 {
            result.append(UInt8(value.count))
        } else {
            var lenBytes = Data()
            var rem = value.count
            while rem > 0 {
                lenBytes.insert(UInt8(rem & 0xFF), at: 0)
                rem >>= 8
            }
            result.append(UInt8(0x80 | lenBytes.count))
            result.append(lenBytes)
        }
        result.append(value)
        return result
    }

    private func _encodeSubjectPublicKeyInfo(_ rawPublicKey: Data) -> Data {
        let ecPubOID = Data([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
        let p256OID = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        let algoParams = _tlv(0x30, ecPubOID + p256OID)
        let pubKey = _tlv(0x03, Data([0x00]) + rawPublicKey)
        return _tlv(0x30, algoParams + pubKey)
    }

    private func _encTBSCert(serial: Data, issuer: _DistinguishedName, nb: Date, na: Date, subj: _DistinguishedName, spki: Data) -> Data {
        var inner = Data()
        inner += _encInt(serial)
        inner += _encSigAlgo()
        inner += issuer._encode()
        inner += _tlv(0x30, _encTime(nb) + _encTime(na))
        inner += subj._encode()
        inner += spki
        return _tlv(0x30, inner)
    }

    private func _encSigAlgo() -> Data {
        _tlv(0x30, Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
    }

    private func _encInt(_ v: Data) -> Data {
        var x = v
        if !x.isEmpty, x[0] & 0x80 != 0 { x.insert(0, at: 0) }
        return _tlv(0x02, x)
    }

    private func _encTime(_ d: Date) -> Data {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return _tlv(0x17, Data(f.string(from: d).utf8))
    }
}

// MARK: - DistinguishedName

private struct _DistinguishedName {
    let commonName: String

    func _encode() -> Data {
        let cnOID = Data([0x06, 0x03, 0x55, 0x04, 0x03])
        let cnValue = _encodeASN1(tag: 0x0C, value: Data(commonName.utf8))
        let cnAttr = _encodeASN1(tag: 0x30, value: cnOID + cnValue)
        let cnSet = _encodeASN1(tag: 0x31, value: cnAttr)
        return _encodeASN1(tag: 0x30, value: cnSet)
    }

    private func _encodeASN1(tag: UInt8, value: Data) -> Data {
        var result = Data([tag])
        if value.count < 128 {
            result.append(UInt8(value.count))
        } else {
            var lenBytes = Data()
            var rem = value.count
            while rem > 0 {
                lenBytes.insert(UInt8(rem & 0xFF), at: 0)
                rem >>= 8
            }
            result.append(UInt8(0x80 | lenBytes.count))
            result.append(lenBytes)
        }
        result.append(value)
        return result
    }
}
