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
    var stashId: String
    var optCode: String
    public let id: String

    /// Parse from a universal link URL: https://dl.boldman.net/share?ips=...&port=...&stash=...&opt=...
    public init?(universalLinkURL: URL) {
        guard let host = universalLinkURL.host?.lowercased(),
              host == "dl.boldman.net" else {
            return nil
        }
        let path = universalLinkURL.path.lowercased()
        guard path == "/share" || path.hasPrefix("/share?") || path == "/share" else {
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
              let portStr = valueFor("port"),
              let stashId = valueFor("stash"),
              let optCode = valueFor("opt"),
              let port = Int(portStr) else {
            return nil
        }

        self.ips = ipsStr.split(separator: ",").map(String.init)
        self.port = port
        self.stashId = stashId
        self.optCode = optCode

        guard !ips.isEmpty, (1...65535).contains(port) else {
            return nil
        }
        
        self.id = stashId
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

