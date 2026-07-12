//
//  TextPreviewContentResolver.swift
//  InstantShareKit
//
//  Created by OpenCode on 2026/7/13.
//  Resolves the text to display in a text-file card preview, whether from inline content or a downloaded file.
//

import Foundation

struct TextPreviewContentResolver {
    static let maxPreviewCharacterCount = 500
    static let maxPreviewFileSize = 1_048_576 // 1 MB

    static func resolve(
        inlineContent: String?,
        contentType: String,
        result: QRClaimResult?
    ) -> String? {
        let source: String? = {
            if let inlineContent, !inlineContent.isEmpty {
                return inlineContent
            }
            guard let result else { return nil }
            switch result {
            case .file(let url, let fileContentType, _):
                guard fileContentType.lowercased().hasPrefix("text/") else { return nil }
                return readPreviewText(from: url)
            default:
                return nil
            }
        }()

        guard let source else { return nil }
        return String(source.prefix(maxPreviewCharacterCount))
    }

    private static func readPreviewText(from url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size <= maxPreviewFileSize else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
