import Foundation
import UIKit

enum QRTriggerDownloadClientError: Error, Sendable {
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
    var errorDescription: String? {
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

enum QRClaimResult: Sendable {
    case text(String)
    case image(Data, contentType: String, filename: String?)
}

final class QRTriggerDownloadClient: Sendable {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval
    private let apiPath = "/api/instant-share/v1/qr-claim"

    init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 30.0
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
    }

    func claim(
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

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
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
            throw QRTriggerDownloadClientError.invalidOptCode
        case 404:
            throw QRTriggerDownloadClientError.stashNotFound
        case 410:
            throw QRTriggerDownloadClientError.stashExpired
        case 400..<500:
            let message = parseErrorMessage(data) ?? "Client error"
            throw QRTriggerDownloadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        default:
            let message = parseErrorMessage(data) ?? "Server error"
            throw QRTriggerDownloadClientError.serverError(message)
        }

        return try parseClaimResponse(data: data, response: httpResponse)
    }

    private func parseClaimResponse(data: Data, response: HTTPURLResponse) throws -> QRClaimResult {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        let lowercasedContentType = contentType.lowercased()

        if lowercasedContentType.hasPrefix("text/") {
            guard let text = String(data: data, encoding: .utf8) else {
                throw QRTriggerDownloadClientError.invalidResponse
            }
            return .text(text)
        }

        if lowercasedContentType.hasPrefix("image/") {
            let filename = response.value(forHTTPHeaderField: "X-Original-Filename")
            return .image(data, contentType: contentType, filename: filename)
        }

        throw QRTriggerDownloadClientError.invalidResponse
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return decoded["error"] as? String
    }
}
