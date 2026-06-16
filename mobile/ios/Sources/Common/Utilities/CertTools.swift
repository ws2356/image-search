//
//  CertTools.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/16.
//

import Foundation

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
