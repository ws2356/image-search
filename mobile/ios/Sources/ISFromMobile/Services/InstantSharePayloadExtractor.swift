import Foundation
import UIKit
import UniformTypeIdentifiers

public enum InstantSharePayloadType: String, Codable {
    case text
    case link
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
        case .text, .link: return "clipboard_only"
        case .image: return "clipboard_or_file"
        case .video, .file: return "file_only"
        }
    }
}

enum InstantSharePayloadExtractorError: Error, LocalizedError {
    case noSupportedItems
    case unreadableContent(String)
    case unsupportedType(String)
    case batchSizeExceeded(limit: Int)

    var errorDescription: String? {
        switch self {
        case .noSupportedItems:
            return "No supported content was found in the share."
        case .unreadableContent(let reason):
            return "Unable to read shared content: \(reason)"
        case .unsupportedType(let type):
            return "This content type is not supported for instant sharing: \(type)"
        case .batchSizeExceeded(let limit):
            return "Cannot share more than \(limit) items at once."
        }
    }
}

struct InstantSharePayloadExtractor {
    static let maxBatchSize = 10

    static let supportedTextTypes: Set<String> = [
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier,
    ]

    static let supportedLinkTypes: Set<String> = [
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
        if supportedLinkTypes.contains(typeIdentifier) { return .link }
        if supportedImageTypes.contains(typeIdentifier) { return .image }
        if supportedVideoTypes.contains(typeIdentifier) { return .video }
        if UTType(typeIdentifier)?.conforms(to: .data) == true { return .file }
        return nil
    }

    static func extract(from extensionItems: [NSExtensionItem]) async throws -> [InstantSharePayloadEnvelope] {
        var envelopes: [InstantSharePayloadEnvelope] = []
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let textEnvelope = try await extractText(from: provider) {
                    envelopes.append(textEnvelope)
                    continue
                }
                if let linkEnvelope = try await extractLink(from: provider) {
                    envelopes.append(linkEnvelope)
                    continue
                }
                if let imageEnvelope = try await extractMedia(from: provider, preferredType: .image) {
                    envelopes.append(imageEnvelope)
                    continue
                }
                if let videoEnvelope = try await extractMedia(from: provider, preferredType: .video) {
                    envelopes.append(videoEnvelope)
                    continue
                }
                if let fileEnvelope = try await extractFile(from: provider) {
                    envelopes.append(fileEnvelope)
                }
            }
        }
        guard !envelopes.isEmpty else {
            throw InstantSharePayloadExtractorError.noSupportedItems
        }
        guard envelopes.count <= Self.maxBatchSize else {
            throw InstantSharePayloadExtractorError.batchSizeExceeded(limit: Self.maxBatchSize)
        }
        return envelopes
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

    private static func loadInPlaceFile(provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        continuation.resume(returning: tempURL)
                    } catch {
                        continuation.resume(throwing: InstantSharePayloadExtractorError.unreadableContent(
                            "Failed to copy in-place file: \(error.localizedDescription)"
                        ))
                    }
                } else {
                    continuation.resume(throwing: InstantSharePayloadExtractorError.unreadableContent(
                        "loadInPlaceFileRepresentation returned nil"
                    ))
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

    private static func extractLink(from provider: NSItemProvider) async throws -> InstantSharePayloadEnvelope? {
        let matchingType = supportedLinkTypes.first { provider.hasItemConformingToTypeIdentifier($0) }
        guard let typeIdentifier = matchingType else { return nil }

        let result = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
        let urlString: String
        if let url = result as? URL {
            urlString = url.absoluteString
        } else if let string = result as? String {
            urlString = string
        } else {
            throw InstantSharePayloadExtractorError.unreadableContent("link provider returned unexpected type")
        }
        return InstantSharePayloadEnvelope(
            payloadType: .link,
            textContent: urlString,
            fileURL: nil,
            filename: nil,
            contentType: "text/uri-list",
            fileSizeBytes: Int64(urlString.utf8.count)
        )
    }

    private static func extractMedia(
        from provider: NSItemProvider,
        preferredType: InstantSharePayloadType
    ) async throws -> InstantSharePayloadEnvelope? {
        let typeSet: Set<String> = preferredType == .image ? supportedImageTypes : supportedVideoTypes
        let matchingType = typeSet.first { provider.hasItemConformingToTypeIdentifier($0) }
        guard let typeIdentifier = matchingType else { return nil }

        let fileURL: URL
        do {
            fileURL = try await loadInPlaceFile(provider: provider, typeIdentifier: typeIdentifier)
        } catch {
            let result = try await loadItem(provider: provider, typeIdentifier: typeIdentifier)
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

        let url: URL
        do {
            url = try await loadInPlaceFile(provider: provider, typeIdentifier: UTType.data.identifier)
        } catch {
            let result = try await loadItem(provider: provider, typeIdentifier: UTType.data.identifier)
            guard let fallbackURL = result as? URL else { return nil }
            url = fallbackURL
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
