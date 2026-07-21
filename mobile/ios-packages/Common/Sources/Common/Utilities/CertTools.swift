//
//  CertTools.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/16.
//

import CryptoKit
import Foundation
import SwiftASN1
import X509

extension SecCertificate {
    public var commonName: String? {
        var cfName: CFString?

        let status = SecCertificateCopyCommonName(self, &cfName)

        guard status == errSecSuccess else {
            LocalLog.error("[cert] no commonName found in cert: \(self)")
            return nil
        }

        return cfName as String?
    }

    public var publicKeyHash: Data? {
        guard let publicKey = SecCertificateCopyKey(self) else {
            return nil
        }
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        return Data(Insecure.SHA1.hash(data: keyData))
    }

    public func certVersionFromExtension(_ versionOID: ASN1ObjectIdentifier) -> Int? {
        guard let derData = SecCertificateCopyData(self) as Data?,
              let cert = try? Certificate(derEncoded: Array(derData)),
              let ext = cert.extensions[oid: versionOID] else {
            return nil
        }
        return try? Int(derEncoded: ext.value)
    }

    public func deviceUUIDFromExtension(_ deviceIdOID: ASN1ObjectIdentifier) -> String? {
        guard let derData = SecCertificateCopyData(self) as Data?,
              let cert = try? Certificate(derEncoded: Array(derData)),
              let ext = cert.extensions[oid: deviceIdOID] else {
            return nil
        }
        let bytes = Array(ext.value)
        // Skip DER tag (1 byte) and length (1-2 bytes); remainder is UTF-8 content
        guard bytes.count > 2 else { return nil }
        let firstLength = Int(bytes[1])
        let contentStart: Int
        if firstLength < 128 {
            contentStart = 2
        } else {
            let numLengthBytes = firstLength - 128
            contentStart = 2 + numLengthBytes
        }
        guard contentStart < bytes.count else { return nil }
        return String(bytes: bytes[contentStart...], encoding: .utf8)
    }
    
    public static func fromPEM(_ pem: String) -> SecCertificate? {
        let lines = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let der = Data(base64Encoded: lines.joined()),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            return nil
        }
        return cert
    }
}
