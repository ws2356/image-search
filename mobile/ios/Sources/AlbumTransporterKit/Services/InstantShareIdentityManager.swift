import CryptoKit
import Foundation
import Security

final class InstantShareIdentityManager {

    enum Error: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed
        case identityNotFound
        case publicKeyExportFailed

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Failed to generate EC keypair in keychain."
            case .certificateCreationFailed: return "Failed to create self-signed X.509 certificate."
            case .identityNotFound: return "Could not retrieve TLS identity from keychain."
            case .publicKeyExportFailed: return "Failed to export public key as PEM."
            }
        }
    }

    private static let keychainTag = "com.aubackup.instant-share.tls".data(using: .utf8)!
    private static let keychainLabel = "AuBackup Instant Share TLS Identity"

    struct Identity {
        let secIdentity: SecIdentity
        let publicKeyPEM: String
    }

    /// Get or create the per-device TLS identity. On first call, generates an
    /// EC P-256 keypair and self-signed certificate in the keychain. Subsequent
    /// calls return the persisted identity.
    static func getOrCreateIdentity() throws -> Identity {
        if let existing = try loadIdentity() {
            return existing
        }
        return try createAndStoreIdentity()
    }

    // MARK: - Load

    private static func loadIdentity() throws -> Identity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keychainLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }

        let identity = item as! SecIdentity

        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let cert else { return nil }

        let publicKeyPEM = try publicKeyPEM(from: cert)

        return Identity(secIdentity: identity, publicKeyPEM: publicKeyPEM)
    }

    // MARK: - Create

    private static func createAndStoreIdentity() throws -> Identity {
        // 1. Generate EC P-256 keypair in keychain
        let privateKeyParams: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: keychainTag,
            kSecAttrLabel as String: keychainLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecReturnRef as String: true,
        ]
        let keyParams: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: privateKeyParams,
        ]
        var secPrivateKey: SecKey?
        let status = SecKeyGeneratePair(keyParams as CFDictionary, &secPrivateKey, nil)
        guard status == errSecSuccess, let privateKey = secPrivateKey else {
            throw Error.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw Error.keyGenerationFailed
        }

        // 2. Build self-signed X.509 certificate
        let certificate = try buildSelfSignedCert(privateKey: privateKey, publicKey: publicKey)

        // 3. Add certificate to keychain
        let certDER = SecCertificateCopyData(certificate) as Data
        let certAttrs: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueData as String: certDER,
            kSecAttrLabel as String: keychainLabel,
        ]
        var addStatus = SecItemAdd(certAttrs as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: keychainLabel,
            ]
            SecItemDelete(delQuery as CFDictionary)
            addStatus = SecItemAdd(certAttrs as CFDictionary, nil)
        }
        guard addStatus == errSecSuccess else {
            throw Error.certificateCreationFailed
        }

        // 4. Retrieve identity (keychain auto-links cert + private key)
        return try loadIdentity()!
    }

    // MARK: - Certificate building

    private static func buildSelfSignedCert(privateKey: SecKey, publicKey: SecKey) throws -> SecCertificate {
        let issuer = DistinguishedName(commonName: "AuBackup Instant Share")
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .day, value: 3650, to: notBefore)!
        let serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

        guard let spkiData = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data else {
            throw Error.certificateCreationFailed
        }
        let spki = X509SelfSignedCertificate.encodeSubjectPublicKeyInfo(spkiData)

        let tbs = encodeTBSCertificate(
            serialNumber: serial,
            issuer: issuer,
            notBefore: notBefore,
            notAfter: notAfter,
            subject: issuer,
            spki: spki
        )

        let sigAlgo = encodeAlgorithmIdentifier()
        let toSign = tbs

        guard let rawSig = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            toSign as CFData,
            nil
        ) as Data? else {
            throw Error.certificateCreationFailed
        }

        let derSig = rawECDSASignatureToDER(rawSig)
        let sigValue = X509SelfSignedCertificate.encodeASN1(
            tag: 0x03, value: Data([0x00]) + derSig
        )

        let inner = tbs + sigAlgo + sigValue
        let derCert = X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: inner)

        guard let cert = SecCertificateCreateWithData(nil, derCert as CFData) else {
            throw Error.certificateCreationFailed
        }
        return cert
    }

    private static func encodeTBSCertificate(
        serialNumber: Data,
        issuer: DistinguishedName,
        notBefore: Date,
        notAfter: Date,
        subject: DistinguishedName,
        spki: Data
    ) -> Data {
        var inner = Data()
        inner += X509SelfSignedCertificate.encodeASN1(
            tag: 0xA0, value: X509SelfSignedCertificate.tlv(tag: 0x02, value: Data([0x01]))
        )
        inner += encodeInteger(serialNumber)
        inner += encodeAlgorithmIdentifier()
        inner += issuer.encode()
        let validity = encodeTime(notBefore) + encodeTime(notAfter)
        inner += X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: validity)
        inner += subject.encode()
        inner += spki
        return X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: inner)
    }

    private static func encodeAlgorithmIdentifier() -> Data {
        let oid = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02])
        return X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: oid)
    }

    private static func encodeInteger(_ value: Data) -> Data {
        var v = value
        if !v.isEmpty, (v[0] & 0x80) != 0 {
            v.insert(0x00, at: 0)
        }
        return X509SelfSignedCertificate.encodeASN1(tag: 0x02, value: v)
    }

    private static func encodeTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return X509SelfSignedCertificate.encodeASN1(
            tag: 0x17, value: Data(formatter.string(from: date).utf8)
        )
    }

    // Convert raw 64-byte ECDSA signature (r||s) to DER-encoded Ecdsa-Sig-Value
    private static func rawECDSASignatureToDER(_ raw: Data) -> Data {
        let r = raw.prefix(raw.count / 2)
        let s = raw.suffix(raw.count / 2)
        let rEnc = encodeECDSASigInteger(r)
        let sEnc = encodeECDSASigInteger(s)
        let inner = rEnc + sEnc
        return X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: inner)
    }

    private static func encodeECDSASigInteger(_ bytes: Data) -> Data {
        var trimmed = bytes
        while trimmed.first == 0, trimmed.count > 1 {
            trimmed = trimmed.dropFirst()
        }
        if (trimmed.first! & 0x80) != 0 {
            trimmed = Data([0x00]) + trimmed
        }
        return X509SelfSignedCertificate.encodeASN1(tag: 0x02, value: trimmed)
    }

    // MARK: - Public key PEM

    private static func publicKeyPEM(from certificate: SecCertificate) throws -> String {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            throw Error.publicKeyExportFailed
        }
        guard let rawKey = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data else {
            throw Error.publicKeyExportFailed
        }
        let spki = InstantShareIdentityManager.buildSPKI(from: rawKey)
        let base64 = spki.base64EncodedString(options: [.lineLength64Characters])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----\n"
    }

    static func buildSPKI(from rawPublicKey: Data) -> Data {
        let ecPubOID = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
        let p256OID = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        let algo = X509SelfSignedCertificate.encodeASN1(
            tag: 0x30, value: ecPubOID + p256OID
        )
        let pub = X509SelfSignedCertificate.encodeASN1(
            tag: 0x03, value: Data([0x00]) + rawPublicKey
        )
        return X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: algo + pub)
    }
}
