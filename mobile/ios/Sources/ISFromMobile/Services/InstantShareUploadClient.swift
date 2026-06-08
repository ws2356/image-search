import Foundation

enum InstantShareUploadClientError: Error, Sendable {
    case uploadFailed(String)
    case invalidResponse(String)
    case httpError(statusCode: Int, errorCode: String, message: String)
    case networkError(Error)
    case trustRequired
    case sessionNotFound
}

extension InstantShareUploadClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from PC: \(message)"
        case .httpError(let statusCode, let errorCode, let message):
            return "HTTP \(statusCode): [\(errorCode)] \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .trustRequired:
            return "Trust handshake must be completed before transfer"
        case .sessionNotFound:
            return "Session not found"
        }
    }
}

final class InstantShareUploadClient: Sendable {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval

    init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 30.0
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
    }

    func uploadText(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        text: String
    ) async throws {
        let requestBody: [String: Any] = ["text_utf8": text]

        let urlString = "http://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/text"
        guard let url = URL(string: urlString) else {
            throw InstantShareUploadClientError.uploadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw InstantShareUploadClientError.uploadFailed("Failed to encode request body: \(error)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw InstantShareUploadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareUploadClientError.uploadFailed("Non-HTTP response")
        }

        if httpResponse.statusCode == 403 {
            throw InstantShareUploadClientError.trustRequired
        }
        if httpResponse.statusCode == 404 {
            throw InstantShareUploadClientError.sessionNotFound
        }
        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareUploadClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }
    }

    func uploadImage(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        imageData: Data,
        contentType: String,
        filename: String?
    ) async throws {
        let urlString = "http://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/image"
        guard let url = URL(string: urlString) else {
            throw InstantShareUploadClientError.uploadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        if let filename {
            request.setValue(filename, forHTTPHeaderField: "X-Instant-Share-Filename")
        }
        request.httpBody = imageData
        request.timeoutInterval = timeoutInterval

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw InstantShareUploadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareUploadClientError.uploadFailed("Non-HTTP response")
        }

        if httpResponse.statusCode == 403 {
            throw InstantShareUploadClientError.trustRequired
        }
        if httpResponse.statusCode == 404 {
            throw InstantShareUploadClientError.sessionNotFound
        }
        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareUploadClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }
    }

    private func tryParseErrorBody(_ data: Data) -> (errorCode: String, message: String) {
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (errorCode: "UNKNOWN", message: "Unable to parse error response")
        }
        return (
            errorCode: decoded["error_code"] as? String ?? "UNKNOWN",
            message: decoded["message"] as? String ?? "Unknown error"
        )
    }
}