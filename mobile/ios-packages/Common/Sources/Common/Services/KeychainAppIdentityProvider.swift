import Foundation
import Security
import CryptoKit
import X509
import SwiftASN1

public protocol AppIdentityProviding: Sendable {
    func ensureSelfIdentity() async throws
    func selfCertificate() async throws -> SecCertificate
    func selfIdentity() async throws -> SecIdentity
    func signSessionID(_ sessionID: String) async throws -> (signature: String, algorithm: String)
    /// Returns the device UUID embedded in the self-signed identity certificate.
    /// This is the same UUID the PC will extract from the certificate during trust,
    /// so it must be used as ``X-Peer-Device-Id`` on transfer requests.
    func deviceUUID() async throws -> String
    
    func importPeerCertificate(_ cert: SecCertificate) async throws
    func importPeerCertificate(pem: String) async throws
    func peerCertificate(forPubkeyHash hash: Data) async throws -> SecCertificate?
    func peerCertificate(for cert: SecCertificate) async throws -> SecCertificate?
    func deletePeerCertificate(forPubkeyHash hash: Data) async throws
}

public extension AppIdentityProviding {
    func selfCertificatePEM() async throws -> String {
        let cert = try await selfCertificate()
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

let hasLaunchedKey = "hasLaunchedKey"

public actor KeychainAppIdentityProvider: AppIdentityProviding {
    private static let peerCertLabel = "AuSearch Trusted Device"

    private static let keyLabel = "AuBackup App Identity"
    private static let SELF_CERT_VERSION = 3
    private static let certVersionOID = ASN1ObjectIdentifier("2.25.37020860436019520")
    static let deviceIdOID = ASN1ObjectIdentifier("2.25.37020860436019521")
    
    static var sharedAccessGroup: String {
        return Bundle.main.object(
            forInfoDictionaryKey: "SharedKeychainAccessGroup"
        ) as! String
    }

    private let localDeviceIdentifierProvider: LocalDeviceIdentifierProviding
    
    private let userDefaults: UserDefaults

    public init(localDeviceIdentifierProvider: LocalDeviceIdentifierProviding, userDefaults: UserDefaults) {
        self.localDeviceIdentifierProvider = localDeviceIdentifierProvider
        self.userDefaults = userDefaults
    }

    enum IdentityError: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed
        case identityNotFound
        case certificateNotFound
        case privateKeyNotFound
        case publicKeyExportFailed
        case signatureCreationFailed

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Failed to generate EC keypair."
            case .certificateCreationFailed: return "Failed to create self-signed X.509 certificate."
            case .identityNotFound: return "Could not retrieve app identity."
            case .certificateNotFound: return "Could not extract certificate from app identity."
            case .privateKeyNotFound: return "Could not extract private key from app identity."
            case .publicKeyExportFailed: return "Failed to export public key as PEM."
            case .signatureCreationFailed: return "Failed to create session signature."
            }
        }
    }

    public func ensureSelfIdentity() async throws {
        try? await cleanupSelfIdentityAfterReinstall()
        
        LocalLog.info("Ensuring app identity...")
        if let identity = try? retrieveExistingIdentity() {
            LocalLog.info("Existing app identity found")
            try await migrateCertsIfNeeded(identity: identity)
            let deviceId1 = try? await self.localDeviceIdentifierProvider.currentIdentifier().deviceUUID
            let deviceId2 = try? await self.deviceUUID()
            LocalLog.info("[debug] deviceId1 \(deviceId1) == deviceId2 \(deviceId2)")
            return
        }
        LocalLog.info("No existing identity found, creating new self-signed certificate")
        try await createAndSaveIdentity()
        LocalLog.info("App identity created successfully")
        let deviceId1 = try? await self.localDeviceIdentifierProvider.currentIdentifier().deviceUUID
        let deviceId2 = try? await self.deviceUUID()
        LocalLog.info("[debug] deviceId1 \(deviceId1) == deviceId2 \(deviceId2)")
    }

    public func selfCertificate() async throws -> SecCertificate {
        let identity = try retrieveExistingIdentity()
        var cert: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &cert)
        guard status == errSecSuccess, let cert else {
            throw IdentityError.certificateNotFound
        }
        return cert
    }

    public nonisolated func selfIdentity() async throws -> SecIdentity {
        try retrieveExistingIdentity()
    }

    public func signSessionID(_ sessionID: String) async throws -> (signature: String, algorithm: String) {
        let identity = try await selfIdentity()
        var privateKey: SecKey?
        let status = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard status == errSecSuccess, let privateKey else {
            throw IdentityError.privateKeyNotFound
        }

        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            sessionID.data(using: .utf8)! as CFData,
            &error
        ) as Data? else {
            if let err = error?.takeRetainedValue() {
                LocalLog.error("[IdentityProvider] signature creation failed: \(err.localizedDescription)")
            }
            throw IdentityError.signatureCreationFailed
        }

        let base64url = signatureData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return (signature: base64url, algorithm: "ecdsa-sha256")
    }

    public func deviceUUID() async throws -> String {
        let cert = try await selfCertificate()
        guard let uuid = cert.deviceUUIDFromExtension(Self.deviceIdOID) else {
            throw IdentityError.certificateNotFound
        }
        return uuid
    }

    func cleanupSelfIdentityAfterReinstall() async throws {
        if self.userDefaults.bool(forKey: hasLaunchedKey) {
            return
        }
        self.userDefaults.set(true, forKey: hasLaunchedKey)

        LocalLog.info("Deleting app self identity from keychain...")
        var anyError: Error?
        
        // Delete identity (certificate + private key pair)
        let identityDeleteStatus = SecItemDelete([
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: Self.keyLabel,
            kSecAttrAccessGroup: Self.sharedAccessGroup] as CFDictionary)
        if identityDeleteStatus != errSecSuccess && identityDeleteStatus != errSecItemNotFound {
            LocalLog.error("[Keychain] deleteSelfIdentity: failed to delete identity, status=\(identityDeleteStatus)")
            anyError = KeychainError.deleteFailed(identityDeleteStatus)
        }
        
        // Delete certificate
        let certDeleteStatus = SecItemDelete([
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: Self.keyLabel,
            kSecAttrAccessGroup: Self.sharedAccessGroup] as CFDictionary)
        if certDeleteStatus != errSecSuccess && certDeleteStatus != errSecItemNotFound {
            LocalLog.error("[Keychain] deleteSelfIdentity: failed to delete certificate, status=\(certDeleteStatus)")
            anyError = KeychainError.deleteFailed(certDeleteStatus)
        }
        
        // Delete private key
        let keyDeleteStatus = SecItemDelete([
            kSecClass: kSecClassKey,
            kSecAttrLabel: Self.keyLabel,
            kSecAttrAccessGroup: Self.sharedAccessGroup] as CFDictionary)
        if keyDeleteStatus != errSecSuccess && keyDeleteStatus != errSecItemNotFound {
            LocalLog.error("[Keychain] deleteSelfIdentity: failed to delete private key, status=\(keyDeleteStatus)")
            anyError = KeychainError.deleteFailed(keyDeleteStatus)
        }
        
        if let error = anyError {
            throw error
        }
        LocalLog.info("App self identity deleted successfully")
    }

    private nonisolated func retrieveExistingIdentity() throws -> SecIdentity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: Self.keyLabel,
            kSecAttrAccessGroup as String: Self.sharedAccessGroup,
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
        return try await createIdentity(commonName: identifier.deviceName, deviceUUID: identifier.deviceUUID, isPersist: true)
    }

    private func migrateCertsIfNeeded(identity: SecIdentity) async throws {
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
        
        let deleteStatus = SecItemDelete([
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: Self.keyLabel,
            kSecAttrAccessGroup: Self.sharedAccessGroup] as CFDictionary)
        LocalLog.info("Deleted old cert from keychain (status: \(deleteStatus))")

        do {
            try await createAndSaveIdentity()
        } catch {
            LocalLog.error("Failed to createAndSaveIdentity: \(error.localizedDescription)")
        }
    }

    func createIdentity(commonName: String, deviceUUID: String, isPersist: Bool) async throws -> SecCertificate {
        for secClass in [kSecClassIdentity, kSecClassCertificate, kSecClassKey] {
            SecItemDelete([
                kSecClass: secClass,
                kSecAttrLabel: Self.keyLabel,
                kSecAttrAccessGroup: Self.sharedAccessGroup] as CFDictionary)
        }

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: isPersist,
                kSecAttrLabel as String: Self.keyLabel,
                kSecAttrAccessGroup as String: Self.sharedAccessGroup,
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
            commonName: commonName,
            deviceUUID: deviceUUID
        )
        if isPersist {
            SecItemAdd([
                kSecClass: kSecClassCertificate,
                kSecValueRef: certificate,
                kSecAttrLabel: Self.keyLabel,
                kSecAttrAccessGroup: Self.sharedAccessGroup] as CFDictionary, nil)
        }
        return certificate
    }

    public func importPeerCertificate(_ cert: SecCertificate) async throws {
        guard let hashData = cert.publicKeyHash else {
            throw KeychainError.unexpectedData
        }
        try? await deletePeerCertificate(forPubkeyHash: hashData)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: Self.peerCertLabel,
            kSecAttrAccessGroup as String: Self.sharedAccessGroup,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            LocalLog.error("[IdentityProvider] importPeerCertificate failed: \(status)")
            throw KeychainError.storeFailed(status)
        }
    }

    public func importPeerCertificate(pem: String) async throws {
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
        try await importPeerCertificate(cert)
    }

    public func peerCertificate(forPubkeyHash hash: Data) async throws -> SecCertificate? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrPublicKeyHash as String: hash,
            kSecAttrAccessGroup as String: Self.sharedAccessGroup,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let cert = result as! SecCertificate? else {
            return nil
        }
        return cert
    }

    public func peerCertificate(for cert: SecCertificate) async throws -> SecCertificate? {
        guard let hashData = cert.publicKeyHash else {
            return nil
        }
        return try await peerCertificate(forPubkeyHash: hashData)
    }

    public func deletePeerCertificate(forPubkeyHash hash: Data) async throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrPublicKeyHash as String: hash,
            kSecAttrAccessGroup as String: Self.sharedAccessGroup,
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        LocalLog.debug("[Keychain] deletePeerCertificate by publicKeyHash status=\(status)")
    }
    
    public func loadAllPeerCertificates() async throws -> [SecCertificate] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: Self.peerCertLabel,
            kSecAttrAccessGroup as String: Self.sharedAccessGroup,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let certs = result as? [SecCertificate] else {
            return []
        }
        return certs
    }
    
    // MARK: - Certificate

    private func buildSelfSignedCert(privateKey: SecKey, rawPubKey: Data, commonName: String, deviceUUID: String) throws -> SecCertificate {
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

        var idSerializer = DER.Serializer()
        try idSerializer.serialize(ASN1UTF8String(deviceUUID))
        let deviceIdExtension = Certificate.Extension(
            oid: Self.deviceIdOID,
            critical: false,
            value: idSerializer.serializedBytes[...]
        )

        let extensions = try Certificate.Extensions {
            BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            try ExtendedKeyUsage([.clientAuth])
            certVersionExtension
            deviceIdExtension
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
