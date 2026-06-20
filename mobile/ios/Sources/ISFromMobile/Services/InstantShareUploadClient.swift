import Foundation
import Common

enum InstantShareUploadClientError: Error, Sendable {
    case uploadFailed(String)
    case invalidResponse(String)
    case httpError(statusCode: Int, errorCode: String, message: String)
    case networkError(Error)
    case trustRequired
    case sessionNotFound
    case tlsVerificationFailed(String)
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
        case .tlsVerificationFailed(let message):
            return "TLS verification failed: \(message)"
        }
    }
}

final class InstantShareUploadClient: Sendable {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval
    private let appIdentityProvider: AppIdentityProviding

    init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 30.0,
        appIdentityProvider: AppIdentityProviding
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
        self.appIdentityProvider = appIdentityProvider
    }

    func uploadText(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        text: String,
        peerDeviceName: String? = nil
    ) async throws {
        let requestBody: [String: Any] = ["text_utf8": text]

        let urlString = "https://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/text"
        guard let url = URL(string: urlString) else {
            throw InstantShareUploadClientError.uploadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval
        if let peerDeviceName {
            request.setValue(peerDeviceName, forHTTPHeaderField: "X-Peer-Device-Name")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw InstantShareUploadClientError.uploadFailed("Failed to encode request body: \(error)")
        }

        let delegate = TlsTrustDelegate(
            appIdentityProvider: appIdentityProvider
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request, delegate: delegate)
        } catch {
            LocalLog.debug("[UploadClient] uploadText network error: \(error.localizedDescription)")
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
        fileURL: URL,
        contentType: String,
        filename: String?,
        peerDeviceName: String? = nil
    ) async throws {
        let urlString = "https://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/image"
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
        if let peerDeviceName {
            request.setValue(peerDeviceName, forHTTPHeaderField: "X-Peer-Device-Name")
        }
        request.setValue("1", forHTTPHeaderField: "X-Image-Count")
        request.timeoutInterval = timeoutInterval

        try await performImageUpload(request: request, fileURL: fileURL)
    }

    /// Core upload logic shared by single and batch image uploads.
    /// Sets up the TLS delegate, performs the upload, and validates the response.
    private func performImageUpload(request: URLRequest, fileURL: URL) async throws {
        let delegate = TlsTrustDelegate(
            appIdentityProvider: appIdentityProvider
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.upload(for: request, fromFile: fileURL, delegate: delegate)
        } catch {
            LocalLog.error("[UploadClient] uploadImage network error: \(error.localizedDescription)")
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

    /// Uploads multiple images sequentially within the same session.
    /// Each request includes an `X-Image-Count` header set to the total batch size.
    /// Stops on the first error — already-uploaded images remain on the PC.
    func uploadImages(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        urls: [(fileURL: URL, filename: String, contentType: String)],
        peerDeviceName: String? = nil
    ) async throws {
        let urlString = "https://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/image"
        guard let url = URL(string: urlString) else {
            throw InstantShareUploadClientError.uploadFailed("Invalid URL: \(urlString)")
        }

        let imageCount = urls.count

        for (_, item) in urls.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(item.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
            request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
            request.setValue(item.filename, forHTTPHeaderField: "X-Instant-Share-Filename")
            request.setValue(String(imageCount), forHTTPHeaderField: "X-Image-Count")
            if let peerDeviceName {
                request.setValue(peerDeviceName, forHTTPHeaderField: "X-Peer-Device-Name")
            }
            request.timeoutInterval = timeoutInterval

            try await performImageUpload(request: request, fileURL: item.fileURL)
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
