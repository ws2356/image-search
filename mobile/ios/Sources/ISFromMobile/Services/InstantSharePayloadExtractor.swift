import Foundation
import UIKit
import UniformTypeIdentifiers

public enum InstantSharePayloadType: String, Codable {
    case text
    case image
    case video
    case file
}

public struct InstantSharePayloadEnvelope: Codable {
    public let payloadType: InstantSharePayloadType
    public let textContent: String?
    public let fileURL: URL?
    public let filename: String?
    public let contentType: String?
    public let fileSizeBytes: Int64?

    public var targetIntent: String {
        switch payloadType {
        case .text: return "clipboard_only"
        case .image: return "clipboard_or_file"
        case .video, .file: return "file_only"
        }
    }
}

enum InstantSharePayloadExtractorError: Error, LocalizedError {
    case noSupportedItems
    case unreadableContent(String)
    case unsupportedType(String)

    var errorDescription: String? {
        switch self {
        case .noSupportedItems:
            return "No supported content was found in the share."
        case .unreadableContent(let reason):
            return "Unable to read shared content: \(reason)"
        case .unsupportedType(let type):
            return "This content type is not supported for instant sharing: \(type)"
        }
    }
}

struct InstantSharePayloadExtractor {
    static let supportedTextTypes: Set<String> = [
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier,
        UTType.url.identifier,
    ]

    static let supportedImageTypes: Set<String> = [
        UTType.image.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.heic.identifier,
        UTType.webP.identifier,
    ]

    static let supportedVideoTypes: Set<String> = [
        UTType.movie.identifier,
        UTType.video.identifier,
        UTType.mpeg4Movie.identifier,
        UTType.quickTimeMovie.identifier,
    ]

    static func classify(typeIdentifier: String) -> InstantSharePayloadType? {
        if supportedTextTypes.contains(typeIdentifier) { return .text }
        if supportedImageTypes.contains(typeIdentifier) { return .image }
        if supportedVideoTypes.contains(typeIdentifier) { return .video }
        if UTType(typeIdentifier)?.conforms(to: .data) == true { return .file }
        return nil
    }

    static func extract(from extensionItems: [NSExtensionItem]) async throws -> InstantSharePayloadEnvelope {
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let textEnvelope = try await extractText(from: provider) {
                    return textEnvelope
                }
                if let imageEnvelope = try await extractMedia(from: provider, preferredType: .image) {
                    return imageEnvelope
                }
                if let videoEnvelope = try await extractMedia(from: provider, preferredType: .video) {
                    return videoEnvelope
                }
                if let fileEnvelope = try await extractFile(from: provider) {
                    return fileEnvelope
                }
            }
        }
        throw InstantSharePayloadExtractorError.noSupportedItems
    }

    private static func loadItem(provider: NSItemProvider, typeIdentifier: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let item = item {
                    nonisolated(unsafe) let unsafeItem = item as Any
                    continuation.resume(returning: unsafeItem)
                } else {
                    continuation.resume(throwing: InstantSharePayloadExtractorError.unreadableContent("loadItem returned nil"))
                }
            }
        }
    }

    private static func extractText(from provider: NSItemProvider) async throws -> InstantSharePayloadEnvelope? {
        let matchingType = supportedTextTypes.first { provider.hasItemConformingToTypeIdentifier($0) }
        guard let typeIdentifier = matchingType else { return nil }

        let result = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
        let text: String
        if let string = result as? String {
            text = string
        } else if let url = result as? URL {
            text = url.absoluteString
        } else if let data = result as? Data, let decoded = String(data: data, encoding: .utf8) {
            text = decoded
        } else {
            throw InstantSharePayloadExtractorError.unreadableContent("text provider returned unexpected type")
        }
        return InstantSharePayloadEnvelope(
            payloadType: .text,
            textContent: text,
            fileURL: nil,
            filename: nil,
            contentType: "text/plain",
            fileSizeBytes: Int64(text.utf8.count)
        )
    }

    private static func extractMedia(
        from provider: NSItemProvider,
        preferredType: InstantSharePayloadType
    ) async throws -> InstantSharePayloadEnvelope? {
        let typeSet: Set<String> = preferredType == .image ? supportedImageTypes : supportedVideoTypes
        let matchingType = typeSet.first { provider.hasItemConformingToTypeIdentifier($0) }
        guard let typeIdentifier = matchingType else { return nil }

        let result = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
        let fileURL: URL
        if let url = result as? URL {
            fileURL = url
        } else if let data = result as? Data {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(preferredType == .image ? "jpg" : "mp4")
            try data.write(to: tempURL)
            fileURL = tempURL
        } else if let image = result as? UIImage, let data = image.pngData() {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            try data.write(to: tempURL)
            fileURL = tempURL
        } else {
            throw InstantSharePayloadExtractorError.unreadableContent("media provider returned unexpected type")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return InstantSharePayloadEnvelope(
            payloadType: preferredType,
            textContent: nil,
            fileURL: fileURL,
            filename: fileURL.lastPathComponent,
            contentType: typeIdentifier,
            fileSizeBytes: fileSize
        )
    }

    private static func extractFile(from provider: NSItemProvider) async throws -> InstantSharePayloadEnvelope? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }

        let result = try await loadItem(provider: provider, typeIdentifier: UTType.data.identifier)
        guard let url = result as? URL else {
            return nil
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return InstantSharePayloadEnvelope(
            payloadType: .file,
            textContent: nil,
            fileURL: url,
            filename: url.lastPathComponent,
            contentType: UTType(filenameExtension: url.pathExtension)?.identifier ?? "application/octet-stream",
            fileSizeBytes: fileSize
        )
    }
}
