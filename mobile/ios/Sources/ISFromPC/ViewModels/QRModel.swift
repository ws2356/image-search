//
//  QRModel.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//
import SwiftUI

public struct QRClaimPayload: Equatable, Sendable, Identifiable {
    var ips: [String]
    var port: Int
    var tlsPort: Int
    var sessionId: String
    var optCode: String
    var deviceId: String
    public let id: String

    /// Parse from a universal link URL.
    /// Format: https://dl.boldman.net/share?ips=...&p=...&sid=...&opt=...&did=...
    /// Also supports legacy format with port, stash params.
    public init?(universalLinkURL: URL) {
        guard let host = universalLinkURL.host?.lowercased(),
              host == "dl.boldman.net" else {
            return nil
        }
        let path = universalLinkURL.path.lowercased()
        guard path == "/share" || path.hasPrefix("/share?") else {
            return nil
        }
        guard let components = URLComponents(url: universalLinkURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        func valueFor(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let ipsStr = valueFor("ips"),
              let optCode = valueFor("opt") else {
            return nil
        }

        let portStr = valueFor("p") ?? valueFor("port")
        guard let portVal = portStr, let port = Int(portVal) else {
            return nil
        }

        let sessionId = valueFor("sid") ?? valueFor("stash")
        guard let unwrappedSessionId = sessionId, !unwrappedSessionId.isEmpty else {
            return nil
        }

        self.ips = ipsStr.split(separator: ",").map(String.init)
        self.port = port

        let tlsPortStr = valueFor("tls_p")
        guard let tlsPortVal = tlsPortStr, let tlsPort = Int(tlsPortVal), (1...65535).contains(tlsPort) else {
            return nil
        }
        self.tlsPort = tlsPort

        self.sessionId = unwrappedSessionId
        self.optCode = optCode
        self.deviceId = valueFor("did") ?? ""

        guard !ips.isEmpty, (1...65535).contains(port) else {
            return nil
        }

        self.id = unwrappedSessionId
    }
}

final class QRClaimResultBox: @unchecked Sendable, Equatable {
    let result: QRClaimResult

    init(_ result: QRClaimResult) {
        self.result = result
    }

    static func == (lhs: QRClaimResultBox, rhs: QRClaimResultBox) -> Bool {
        switch (lhs.result, rhs.result) {
        case (.text(let a), .text(let b)): return a == b
        case (.html(let a), .html(let b)): return a == b
        case (.image(let a, _, _), .image(let b, _, _)): return a == b
        case (.file(let a, _, _), .file(let b, _, _)): return a == b
        default: return false
        }
    }
}

