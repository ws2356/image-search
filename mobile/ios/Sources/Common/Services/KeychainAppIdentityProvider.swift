import Foundation
import Security
import CryptoKit

public protocol AppIdentityProviding: Sendable {
    func ensureSelfIdentity() async throws
    func selfCertificate() throws -> SecCertificate
    func selfPrivateKey() throws -> SecKey
    
    func importPeerCertificate(_ cert: SecCertificate, for peerDeviceID: String) async throws
    func importPeerCertificate(pem: String, for peerDeviceID: String) async throws
    func peerCertificate(for peerDeviceID: String) throws -> SecCertificate
    func deletePeerCertificate(for peerDeviceID: String) throws -> Void
}

public extension AppIdentityProviding {
    func selfCertificatePEM() throws -> String {
        let cert = try selfCertificate()
        let derData = SecCertificateCopyData(cert) as Data
        let base64 = derData.base64EncodedString(options: .lineLength64Characters)
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n"
    }
}

public enum KeychainError: Swift.Error, LocalizedError {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData

    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status): return "Keychain store failed: OSStatus \(status)"
        case .loadFailed(let status): return "Keychain load failed: OSStatus \(status)"
        case .deleteFailed(let status): return "Keychain delete failed: OSStatus \(status)"
        case .unexpectedData: return "Keychain returned unexpected data"
        }
    }
}

public final class KeychainAppIdentityProvider: AppIdentityProviding {
    private static func getPeerCertLabel(_ peerDeviceID: String) -> String {
        return "AuBackup Peer Certificate \(peerDeviceID)"
    }
    
    private static let keyLabel = "AuBackup App Identity"
    private let localDeviceIdentifierProvider: LocalDeviceIdentifierProviding

    public init(localDeviceIdentifierProvider: LocalDeviceIdentifierProviding) {
        self.localDeviceIdentifierProvider = localDeviceIdentifierProvider
    }

    enum IdentityError: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed
        case identityNotFound
        case certificateNotFound
        case privateKeyNotFound
        case publicKeyExportFailed

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Failed to generate EC keypair."
            case .certificateCreationFailed: return "Failed to create self-signed X.509 certificate."
            case .identityNotFound: return "Could not retrieve app identity."
            case .certificateNotFound: return "Could not extract certificate from app identity."
            case .privateKeyNotFound: return "Could not extract private key from app identity."
            case .publicKeyExportFailed: return "Failed to export public key as PEM."
            }
        }
    }

    public func ensureSelfIdentity() async throws {
        LocalLog.info("Ensuring app identity...")
        if let _ = try? retrieveExistingIdentity() {
            LocalLog.info("Existing app identity found")
            return
        }
        LocalLog.info("No existing identity found, creating new self-signed certificate")
        try await createAndSaveIdentity()
        LocalLog.info("App identity created successfully")
    }

    public func selfCertificate() throws -> SecCertificate {
        let identity = try retrieveExistingIdentity()
        var cert: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &cert)
        guard status == errSecSuccess, let cert else {
            throw IdentityError.certificateNotFound
        }
        return cert
    }

    public func selfPrivateKey() throws -> SecKey {
        let identity = try retrieveExistingIdentity()
        var key: SecKey?
        let status = SecIdentityCopyPrivateKey(identity, &key)
        guard status == errSecSuccess, let key else {
            throw IdentityError.privateKeyNotFound
        }
        return key
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

    private func createAndSaveIdentity() async throws -> SecCertificate {
        let identifier = await localDeviceIdentifierProvider.currentIdentifier()
        return try await createIdentity(commonName: identifier.deviceUUID, isPersist: true)
    }
    
    func createIdentity(commonName: String, isPersist: Bool) async throws -> SecCertificate {
        for secClass in [kSecClassIdentity, kSecClassCertificate, kSecClassKey] {
            SecItemDelete([kSecClass: secClass, kSecAttrLabel: Self.keyLabel] as CFDictionary)
        }

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: isPersist,
                kSecAttrLabel as String: Self.keyLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAlwaysThisDeviceOnly,
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

        let identifier = await localDeviceIdentifierProvider.currentIdentifier()
        let certificate = try buildSelfSignedCert(
            privateKey: privateSecKey,
            rawPubKey: rawPubKey,
            commonName: commonName
        )
        if isPersist {
            SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: Self.keyLabel] as CFDictionary, nil)
        }
        return certificate
    }

    public func importPeerCertificate(_ cert: SecCertificate, for peerDeviceID: String) async throws {
        let tag = peerDeviceID.data(using: .utf8)
        try? deletePeerCertificate(for: peerDeviceID)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: Self.getPeerCertLabel(peerDeviceID),
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    public func importPeerCertificate(pem: String, for peerDeviceID: String) async throws {
        let lines = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let der = Data(base64Encoded: lines.joined())
        guard let der else {
            throw KeychainError.unexpectedData
        }
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            throw KeychainError.unexpectedData
        }
        try await importPeerCertificate(cert, for: peerDeviceID)
    }

    public func peerCertificate(for peerDeviceID: String) throws -> SecCertificate {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.getPeerCertLabel(peerDeviceID),
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let cert = result as! SecCertificate? else {
            throw KeychainError.loadFailed(status)
        }
        return cert
    }

    public func deletePeerCertificate(for peerDeviceID: String) throws -> Void {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.getPeerCertLabel(peerDeviceID),
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
    
    // MARK: - Certificate

    private func buildSelfSignedCert(privateKey: SecKey, rawPubKey: Data, commonName: String) throws -> SecCertificate {
        let subject = _DistinguishedName(commonName: commonName)
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .year, value: 10, to: notBefore)!
        let serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let spki = _encodeSubjectPublicKeyInfo(rawPubKey)
        let tbs = _encTBSCert(serial: serial, issuer: subject, nb: notBefore, na: notAfter, subj: subject, spki: spki)
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

public func DebugPrintCert(_ cert: SecCertificate) {
    LocalLog.debug("================ [ 证书 ] ================")
    
    // A. 获取证书的主体摘要（通常是 Common Name）
    if let summary = SecCertificateCopySubjectSummary(cert) as String? {
        LocalLog.debug("🏷️ 证书名称: \(summary)")
    }
    
    // B. 获取证书的原始数据并计算指纹 (SHA-256)
    if let certData = SecCertificateCopyData(cert) as Data? {
        let sha256Hash = SHA256.hash(data: certData)
        // 转换为常见的 Hex 冒号分隔格式 (例如 AA:BB:CC...)
        let fingerprint = sha256Hash.map { String(format: "%02X", $0) }.joined(separator: ":")
        LocalLog.debug("🔒 证书指纹 (SHA-256):\n\(fingerprint)")
    }
    
    // C. 从证书中提取公钥并打印为 Base64 文本
    if let publicKey = SecCertificateCopyKey(cert) {
        var error: Unmanaged<CFError>?
        if let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? {
            // 打印成标准的 Base64 格式，方便拷贝到调试工具中比对
            let base64Key = keyData.base64EncodedString(options: .lineLength64Characters)
            LocalLog.debug("🔑 公钥 (Base64):\n\(base64Key)")
        } else if let err = error {
            LocalLog.debug("❌ 提取公钥数据失败: \(err.takeRetainedValue().localizedDescription)")
        }
    } else {
        LocalLog.debug("❌ 无法从该证书中解析出公钥")
    }
    LocalLog.debug("================================================\n")
}
