import CryptoKit
import Foundation
import OSLog
import Security

final class InstantShareIdentityManager {

    private static let log = OSLog(subsystem: "com.aubackup.instant-share", category: "identity")

    enum Error: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case certificateCreationFailed
        case identityNotFound
        case publicKeyExportFailed
        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Failed to generate EC keypair."
            case .certificateCreationFailed: return "Failed to create self-signed X.509 certificate."
            case .identityNotFound: return "Could not retrieve TLS identity."
            case .publicKeyExportFailed: return "Failed to export public key as PEM."
            }
        }
    }

    struct Identity {
        let secIdentity: SecIdentity
        let publicKeyPEM: String
    }

    private static let keyLabel = "AuBackup Instant Share TLS Identity"

    static func getOrCreateIdentity() throws -> Identity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keyLabel,
            kSecReturnRef as String: true,
        ]
        var identityRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &identityRef)
        if status == errSecSuccess, let secIdent = identityRef as! SecIdentity? {
            var cert: SecCertificate?
            SecIdentityCopyCertificate(secIdent, &cert)
            if let certificate = cert {
                let pem = try publicKeyPEM(from: certificate)
                return Identity(secIdentity: secIdent, publicKeyPEM: pem)
            }
        }
        return try buildEphemeralIdentity()
    }

    private static func buildEphemeralIdentity() throws -> Identity {
        for secClass in [kSecClassIdentity, kSecClassCertificate, kSecClassKey] {
            SecItemDelete([kSecClass: secClass, kSecAttrLabel: keyLabel] as CFDictionary)
        }

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrLabel as String: keyLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
        ]
        guard let privateSecKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, nil) else {
            throw Error.keyGenerationFailed
        }
        guard let publicSecKey = SecKeyCopyPublicKey(privateSecKey) else {
            throw Error.keyGenerationFailed
        }
        guard let rawPubKey = SecKeyCopyExternalRepresentation(publicSecKey, nil) as Data? else {
            throw Error.keyGenerationFailed
        }

        let certificate = try buildCertWithSecKey(privateKey: privateSecKey, rawPubKey: rawPubKey)
        SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: keyLabel] as CFDictionary, nil)

        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keyLabel,
            kSecReturnRef as String: true,
        ]
        var identityRef: CFTypeRef?
        let status = SecItemCopyMatching(identityQuery as CFDictionary, &identityRef)
        guard status == errSecSuccess, let secIdent = identityRef as! SecIdentity? else {
            throw Error.identityNotFound
        }
        let pem = try publicKeyPEM(from: certificate)
        return Identity(secIdentity: secIdent, publicKeyPEM: pem)
    }

    private static func buildCertWithSecKey(privateKey: SecKey, rawPubKey: Data) throws -> SecCertificate {
        let issuer = DistinguishedName(commonName: "AuBackup Instant Share")
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .day, value: 3650, to: notBefore)!
        let serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let spki = X509SelfSignedCertificate.encodeSubjectPublicKeyInfo(rawPubKey)
        let tbs = encTBSCert(serial: serial, issuer: issuer, nb: notBefore, na: notAfter, subj: issuer, spki: spki)
        let sigAlgo = encSigAlgo()
        let digest = SHA256.hash(data: tbs)
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureDigestX962SHA256, Data(digest) as CFData, nil) as Data? else {
            throw Error.certificateCreationFailed
        }
        let sigVal = tlv(0x03, Data([0x00]) + signature)
        let derCert = tlv(0x30, tbs + sigAlgo + sigVal)
        guard let cert = SecCertificateCreateWithData(nil, derCert as CFData) else {
            throw Error.certificateCreationFailed
        }
        return cert
    }

    // MARK: - Certificate

    private static func buildCert(privateKey: P256.Signing.PrivateKey, rawPubKey: Data) throws -> SecCertificate {
        let issuer = DistinguishedName(commonName: "AuBackup Instant Share")
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .day, value: 3650, to: notBefore)!
        let serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let spki = X509SelfSignedCertificate.encodeSubjectPublicKeyInfo(rawPubKey)
        let tbs = encTBSCert(serial: serial, issuer: issuer, nb: notBefore, na: notAfter, subj: issuer, spki: spki)
        let sigAlgo = encSigAlgo()
        let digest = SHA256.hash(data: tbs)
        let sig = try privateKey.signature(for: Data(digest))
        let derSig = raw2derSig(sig.rawRepresentation)
        let sigVal = tlv(0x03, Data([0x00]) + derSig)
        let derCert = tlv(0x30, tbs + sigAlgo + sigVal)
        guard let cert = SecCertificateCreateWithData(nil, derCert as CFData) else {
            throw Error.certificateCreationFailed
        }
        return cert
    }

    // MARK: - EC Private Key

    private static func encodeECPrivateKey(scalarData: Data, rawPubKey: Data) -> Data {
        tlv(0x30,
            tlv(0x02, Data([0x01])) +
            tlv(0x04, scalarData) +
            tlv(0xA1, tlv(0x03, Data([0x00]) + rawPubKey))
        )
    }

    // MARK: - PKCS#12

    private static let pkcs7OID = Data([0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x07,0x01])
    private static let shroudedKeyOID = Data([0x06,0x0B,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x0C,0x0A,0x01,0x01])
    private static let certBagOID = Data([0x06,0x0B,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x0C,0x0A,0x01,0x03])
    private static let x509OID = Data([0x06,0x0A,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x09,0x16,0x01])
    private static let localKeyOID = Data([0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x09,0x14])
    private static let friendlyOID = Data([0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x09,0x15])
    private static let ecPubOID = Data([0x06,0x07,0x2A,0x86,0x48,0xCE,0x3D,0x02,0x01])
    private static let p256OID = Data([0x06,0x08,0x2A,0x86,0x48,0xCE,0x3D,0x03,0x01,0x07])
    private static let sha256OID = Data([0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,0x01])
    private static let sha1OID = Data([0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A])

    private static func buildPKCS12(ecPrivateKey: Data, certificate: SecCertificate) -> Data {
        let certDER = SecCertificateCopyData(certificate) as Data
        let rawPK = SecCertificateCopyKey(certificate)!
        let rawKey = SecKeyCopyExternalRepresentation(rawPK, nil) as! Data
        let keyID = Data(Insecure.SHA1.hash(data: rawKey))
        let friendlyName = "id".data(using: .utf16BigEndian)!
        let localKey = tlv(0x30, localKeyOID + tlv(0x31, tlv(0x04, keyID)))
        let friendly = tlv(0x30, friendlyOID + tlv(0x31, tlv(0x1E, friendlyName)))
        let bagAttrs = tlv(0x31, localKey + friendly)

        let certVal = tlv(0x30, x509OID + tlv(0xA0, tlv(0x04, certDER)))
        let certSB = tlv(0x30, certBagOID + tlv(0xA0, certVal) + bagAttrs)

        let epkiAlgo = tlv(0x30, ecPubOID + p256OID)
        let epki = tlv(0x30, tlv(0x02, Data([0x00])) + epkiAlgo + tlv(0x04, ecPrivateKey))
        let keySB = tlv(0x30, shroudedKeyOID + tlv(0xA0, epki) + bagAttrs)

        let safeContents = tlv(0x30, certSB + keySB)
        let safeCI = tlv(0x30, pkcs7OID + tlv(0xA0, tlv(0x04, safeContents)))
        let authSafe = tlv(0x30, safeCI)
        let authCI = tlv(0x30, pkcs7OID + tlv(0xA0, tlv(0x04, authSafe)))

        let pfxBody = tlv(0x02, Data([0x03])) + authCI

        let macSalt = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        let macIterations: UInt32 = 1024
        let mac = computePKCS12Mac(password: Data([0x00, 0x00]), authSafeContent: authCI, salt: macSalt, iterations: macIterations)
        let macData = buildMacData(mac: mac, salt: macSalt, iterations: macIterations)

        return tlv(0x30, pfxBody + macData)
    }

    private static func computePKCS12Mac(password: Data, authSafeContent: Data, salt: Data, iterations: UInt32) -> Data {
        let hashLen = 20
        let id: UInt8 = 0x3D
        let d = Data(repeating: id, count: hashLen)

        var iData = salt
        withUnsafeBytes(of: UInt32(1).bigEndian) { iData.append(contentsOf: $0) }

        var key = Data(HMAC<Insecure.SHA1>.authenticationCode(for: d + iData, using: SymmetricKey(data: password)))
        for _ in 1..<iterations {
            key = Data(HMAC<Insecure.SHA1>.authenticationCode(for: key, using: SymmetricKey(data: password)))
        }

        return Data(HMAC<Insecure.SHA1>.authenticationCode(for: authSafeContent, using: SymmetricKey(data: key)))
    }

    private static func buildMacData(mac: Data, salt: Data, iterations: UInt32) -> Data {
        let sha1Algorithm = tlv(0x30, sha1OID + tlv(0x05, Data()))
        let digestInfo = tlv(0x30, sha1Algorithm + tlv(0x04, mac))
        let macSaltEncoded = tlv(0x04, salt)
        var iterBytes = withUnsafeBytes(of: iterations.bigEndian) { Data($0) }
        while iterBytes.first == 0, iterBytes.count > 1 {
            iterBytes = iterBytes.dropFirst()
        }
        let iterationsEncoded = tlv(0x02, iterBytes)
        return digestInfo + macSaltEncoded + iterationsEncoded
    }

    private static func pbkdf2(pwd: Data, salt: Data, iter: Int, len: Int) -> Data {
        var r = Data()
        var b: UInt32 = 1
        while r.count < len {
            var u = salt; u += withUnsafeBytes(of: b.bigEndian) { Data($0) }
            var t = Data(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: pwd)))
            var up = t
            for _ in 1..<iter {
                up = Data(HMAC<SHA256>.authenticationCode(for: up, using: SymmetricKey(data: pwd)))
                t = Data(zip(t, up).map(^))
            }
            r += t; b += 1
        }
        return r.prefix(len)
    }

    // MARK: - ASN.1 helpers

    private static func tlv(_ tag: UInt8, _ value: Data) -> Data {
        X509SelfSignedCertificate.encodeASN1(tag: tag, value: value)
    }

    private static func encTBSCert(serial: Data, issuer: DistinguishedName, nb: Date, na: Date, subj: DistinguishedName, spki: Data) -> Data {
        var inner = Data()
        inner += encInt(serial)
        inner += encSigAlgo()
        inner += issuer.encode()
        inner += tlv(0x30, encTime(nb) + encTime(na))
        inner += subj.encode()
        inner += spki
        return tlv(0x30, inner)
    }

    private static func encSigAlgo() -> Data {
        tlv(0x30, Data([0x06,0x08,0x2A,0x86,0x48,0xCE,0x3D,0x04,0x03,0x02]))
    }

    private static func encInt(_ v: Data) -> Data {
        var x = v; if !x.isEmpty, x[0] & 0x80 != 0 { x.insert(0, at: 0) }
        return tlv(0x02, x)
    }

    private static func encTime(_ d: Date) -> Data {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(f.string(from: d).utf8))
    }

    private static func raw2derSig(_ raw: Data) -> Data {
        let m = raw.count / 2
        return tlv(0x30, encECS(Data(raw.prefix(m))) + encECS(Data(raw.suffix(m))))
    }

    private static func encECS(_ b: Data) -> Data {
        var t = b; while t.first == 0, t.count > 1 { t = t.dropFirst() }
        if t.first! & 0x80 != 0 { t = Data([0x00]) + t }
        return tlv(0x02, t)
    }

    // MARK: - PEM

    static func certificatePEM() throws -> String {
        let identity = try getOrCreateIdentity()
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity.secIdentity, &cert)
        guard let certificate = cert else {
            throw Error.certificateCreationFailed
        }
        return try certificatePEM(from: certificate)
    }

    static func certificatePEM(from cert: SecCertificate) throws -> String {
        let derData = SecCertificateCopyData(cert) as Data
        let base64 = derData.base64EncodedString(options: .lineLength64Characters)
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n"
    }

    private static func publicKeyPEM(from cert: SecCertificate) throws -> String {
        guard let pk = SecCertificateCopyKey(cert),
              let raw = SecKeyCopyExternalRepresentation(pk, nil) as Data? else {
            throw Error.publicKeyExportFailed
        }
        let spki = buildSPKI(raw)
        return "-----BEGIN PUBLIC KEY-----\n\(spki.base64EncodedString(options: .lineLength64Characters))\n-----END PUBLIC KEY-----\n"
    }

    static func buildSPKI(_ raw: Data) -> Data {
        let a = tlv(0x30, Data([0x06,0x07,0x2A,0x86,0x48,0xCE,0x3D,0x02,0x01]) +
                         Data([0x06,0x08,0x2A,0x86,0x48,0xCE,0x3D,0x03,0x01,0x07]))
        return tlv(0x30, a + tlv(0x03, Data([0x00]) + raw))
    }
}

extension Data {
    func hexString() -> String { map { String(format: "%02x", $0) }.joined() }
}
