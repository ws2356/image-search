import Foundation
import UIKit

public enum QRTriggerDownloadClientError: Error, Sendable {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, message: String)
    case invalidOptCode
    case stashExpired
    case stashNotFound
    case serverError(String)
    case allHostsFailed([Error])
    case invalidResponse
}

extension QRTriggerDownloadClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .invalidOptCode:
            return "Invalid code. Make sure the code on your Mac screen is correct."
        case .stashExpired:
            return "This share has expired. Please share the data again from your Mac."
        case .stashNotFound:
            return "Share not found. It may have been cancelled."
        case .serverError(let message):
            return "Something went wrong. Please try again. (\(message))"
        case .allHostsFailed(let errors):
            return "Could not connect to your Mac. Make sure both devices are on the same Wi-Fi network."
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

public enum QRClaimResult: Sendable {
    case text(String)
    case image(fileURL: URL, contentType: String, filename: String?)
    case file(fileURL: URL, contentType: String, filename: String?)
}

public final class QRTriggerDownloadClient: Sendable {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval
    private let apiPath = "/api/instant-share/v1/qr-claim"

    public init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 30.0
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
    }

    public func claim(
        hosts: [String],
        port: Int,
        stashId: String,
        optCode: String
    ) async throws -> QRClaimResult {
        let requestBody: [String: Any] = [
            "stash_id": stashId,
            "opt": optCode,
        ]

        var lastErrors: [Error] = []

        for host in hosts {
            do {
                return try await attemptClaim(
                    host: host,
                    port: port,
                    requestBody: requestBody
                )
            } catch {
                lastErrors.append(error)
                continue
            }
        }

        if let lastError = lastErrors.last as? QRTriggerDownloadClientError,
           case .httpError = lastError {
            throw lastError
        }

        throw QRTriggerDownloadClientError.allHostsFailed(lastErrors)
    }

    private func attemptClaim(
        host: String,
        port: Int,
        requestBody: [String: Any]
    ) async throws -> QRClaimResult {
        let urlString = "http://\(host):\(port)\(apiPath)"
        guard let url = URL(string: urlString) else {
            throw QRTriggerDownloadClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw QRTriggerDownloadClientError.httpError(statusCode: 0, message: "Failed to encode request")
        }

        let (tempFileURL, response): (URL, URLResponse)
        do {
            (tempFileURL, response) = try await urlSession.download(for: request)
        } catch {
            throw QRTriggerDownloadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.invalidOptCode
        case 404:
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.stashNotFound
        case 410:
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.stashExpired
        case 400..<500:
            let tempData = try? Data(contentsOf: tempFileURL)
            cleanupTempFile(tempFileURL)
            let message = parseErrorMessage(tempData ?? Data()) ?? "Client error"
            throw QRTriggerDownloadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        default:
            let tempData = try? Data(contentsOf: tempFileURL)
            cleanupTempFile(tempFileURL)
            let message = parseErrorMessage(tempData ?? Data()) ?? "Server error"
            throw QRTriggerDownloadClientError.serverError(message)
        }

        return try await parseClaimResponse(tempFileURL: tempFileURL, response: httpResponse)
    }

    private func parseClaimResponse(tempFileURL: URL, response: HTTPURLResponse) async throws -> QRClaimResult {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.invalidResponse
        }

        let lowercasedContentType = contentType.lowercased()

        if lowercasedContentType.hasPrefix("text/") {
            let data = try Data(contentsOf: tempFileURL)
            cleanupTempFile(tempFileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw QRTriggerDownloadClientError.invalidResponse
            }
            return .text(text)
        }

        let filename = response.value(forHTTPHeaderField: "X-Original-Filename")

        if lowercasedContentType.hasPrefix("image/") {
            let fileURL = try persistToDocuments(tempFileURL, filename: filename, prefix: "image")
            return .image(fileURL: fileURL, contentType: contentType, filename: filename)
        }

        if lowercasedContentType == "application/octet-stream" {
            let fileURL = try persistToDocuments(tempFileURL, filename: filename, prefix: "file")
            return .file(fileURL: fileURL, contentType: contentType, filename: filename)
        }

        cleanupTempFile(tempFileURL)
        throw QRTriggerDownloadClientError.invalidResponse
    }

    private func persistToDocuments(_ tempFileURL: URL, filename: String?, prefix: String) throws -> URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        let subDir = documentsDir.appendingPathComponent("QRDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let fileName = filename ?? "\(prefix)_\(Int(Date().timeIntervalSince1970))"
        let destURL = subDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }

        try FileManager.default.moveItem(at: tempFileURL, to: destURL)
        return destURL
    }

    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return decoded["error"] as? String
    }
}
