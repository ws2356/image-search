import Foundation
import Security
import CryptoKit
import X509
import SwiftASN1

public protocol AppIdentityProviding: Sendable {
    func ensureSelfIdentity() async throws
    func selfCertificate() throws -> SecCertificate
    func selfIdentity() throws -> SecIdentity
    
    func importPeerCertificate(_ cert: SecCertificate, for peerDeviceID: String) async throws
    func importPeerCertificate(pem: String, for peerDeviceID: String) async throws
    func peerCertificate(for peerDeviceID: String) throws -> SecCertificate
    func deletePeerCertificate(for peerDeviceID: String, cert: SecCertificate?) throws -> Void
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
    private static let SELF_CERT_VERSION = 2
    private static let certVersionOID = ASN1ObjectIdentifier("2.25.37020860436019520")
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
        if let identity = try? retrieveExistingIdentity() {
            LocalLog.info("Existing app identity found")
            try migrateCertsIfNeeded(identity: identity)
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

    public func selfIdentity() throws -> SecIdentity {
        try retrieveExistingIdentity()
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

    private func migrateCertsIfNeeded(identity: SecIdentity) throws {
        var secCert: SecCertificate?
        var copyStatus = SecIdentityCopyCertificate(identity, &secCert)
        guard copyStatus == errSecSuccess, let secCert else {
            throw IdentityError.certificateNotFound
        }

        let derData = SecCertificateCopyData(secCert) as Data
        let cert = try Certificate(derEncoded: Array(derData))

        let currentVersion: Int
        if let ext = cert.extensions[oid: Self.certVersionOID] {
            currentVersion = (try? Int(derEncoded: ext.value)) ?? 0
        } else {
            currentVersion = 0
        }

        guard currentVersion < Self.SELF_CERT_VERSION else {
            LocalLog.info("Self cert is up to date (version \(currentVersion))")
            return
        }

        LocalLog.info("Self cert version \(currentVersion) < \(Self.SELF_CERT_VERSION), migration needed")

        var privateKey: SecKey?
        copyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard copyStatus == errSecSuccess, let privateKey else {
            throw IdentityError.privateKeyNotFound
        }
        guard let publicSecKey = SecCertificateCopyKey(secCert) else {
            throw IdentityError.publicKeyExportFailed
        }
        guard let rawPubKey = SecKeyCopyExternalRepresentation(publicSecKey, nil) as Data? else {
            throw IdentityError.publicKeyExportFailed
        }
        guard let commonName = SecCertificateCopySubjectSummary(secCert) as String? else {
            throw IdentityError.certificateNotFound
        }

        let newCert = try buildSelfSignedCert(
            privateKey: privateKey,
            rawPubKey: rawPubKey,
            commonName: commonName
        )

        let deleteStatus = SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: Self.keyLabel] as CFDictionary)
        LocalLog.info("Deleted old cert from keychain (status: \(deleteStatus))")

        let addStatus = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: newCert, kSecAttrLabel: Self.keyLabel] as CFDictionary, nil)
        LocalLog.info("Added migrated cert to keychain (status: \(addStatus))")

        LocalLog.info("Self cert migrated from version \(currentVersion) to \(Self.SELF_CERT_VERSION)")
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
        try? deletePeerCertificate(for: peerDeviceID, cert: cert)
        
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

    public func deletePeerCertificate(for peerDeviceID: String, cert: SecCertificate?) throws -> Void {
        if let cert {
            guard let publicKey = SecCertificateCopyKey(cert) else {
                throw KeychainError.unexpectedData
            }
            guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                throw KeychainError.unexpectedData
            }
            let publicKeyHash = Data(Insecure.SHA1.hash(data: keyData))
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecAttrPublicKeyHash as String: publicKeyHash,
            ]
            let status = SecItemDelete(deleteQuery as CFDictionary)
            LocalLog.debug("[Keychain] deletePeerCertificate by publicKeyHash status=\(status)")
        } else {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: Self.getPeerCertLabel(peerDeviceID),
            ]
            let status = SecItemDelete(deleteQuery as CFDictionary)
            LocalLog.debug("[Keychain] deletePeerCertificate by label status=\(status)")
        }
    }
    
    // MARK: - Certificate

    private func buildSelfSignedCert(privateKey: SecKey, rawPubKey: Data, commonName: String) throws -> SecCertificate {
        let p256PubKey = try P256.Signing.PublicKey(x963Representation: rawPubKey)

        let serialNumber = Certificate.SerialNumber()
        let dn = try DistinguishedName { CommonName(commonName) }
        let now = Date().addingTimeInterval(-3600.0 * 24.0)
        let notAfter = Calendar.current.date(byAdding: .day, value: 364, to: now)!

        var extSerializer = DER.Serializer()
        try extSerializer.serialize(Int(Self.SELF_CERT_VERSION))
        let certVersionExtension = Certificate.Extension(
            oid: Self.certVersionOID,
            critical: false,
            value: extSerializer.serializedBytes[...]
        )

        let extensions = try Certificate.Extensions {
            BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            try ExtendedKeyUsage([.clientAuth])
            certVersionExtension
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: serialNumber,
            publicKey: Certificate.PublicKey(p256PubKey),
            notValidBefore: now,
            notValidAfter: notAfter,
            issuer: dn,
            subject: dn,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: try Certificate.PrivateKey(privateKey)
        )

        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let derData = Data(serializer.serializedBytes)

        guard let secCert = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw IdentityError.certificateCreationFailed
        }
        return secCert
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
