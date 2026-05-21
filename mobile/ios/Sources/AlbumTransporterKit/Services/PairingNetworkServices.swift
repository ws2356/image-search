import CryptoKit
import Foundation
import OSLog

struct URLSessionPairingBootstrapClient: PairingBootstrapClient {
    let session: URLSession
    let telemetryClient: TelemetryClient

    init(session: URLSession = .shared, telemetryClient: TelemetryClient = NoOpTelemetryClient()) {
        self.session = session
        self.telemetryClient = telemetryClient
    }

    func primeInternetAccess() async {
        guard let warmupURL = URL(string: "https://www.baidu.com") else {
            return
        }

        var request = URLRequest(url: warmupURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2
        _ = try? await session.data(for: request)
    }

    func claimPairing(
        at endpoint: URL,
        request: PairingClaimRequest
    ) async throws -> PairingClaimResponse {
        return try await postPairingRequest(
            at: endpoint,
            requestBody: request,
            responseType: PairingClaimResponse.self,
            expectedSchema: PairingProtocol.schema
        )
    }

    func fetchPairingState(
        at endpoint: URL,
        request: PairingStateRequest
    ) async throws -> PairingClaimResponse {
        guard let stateEndpoint = endpoint.pairingStateURL else {
            throw PairingServiceError.transport(message: "Desktop pairing state endpoint is invalid.")
        }
        return try await postPairingRequest(
            at: stateEndpoint,
            requestBody: request,
            responseType: PairingClaimResponse.self,
            expectedSchema: PairingProtocol.schema
        )
    }

    private func postPairingRequest<RequestBody: Encodable, ResponseBody: Decodable & PairingSchemaResponse>(
        at endpoint: URL,
        requestBody: RequestBody,
        responseType: ResponseBody.Type,
        expectedSchema: String
    ) async throws -> ResponseBody {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 5
        urlRequest.httpBody = try await encodeRequestBody(requestBody)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await requestWithLocalNetworkRetry(urlRequest, endpoint: endpoint)
        } catch let error as PairingServiceError {
            throw error
        } catch {
            throw PairingServiceError.transport(message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PairingServiceError.invalidHTTPResponse
        }

        do {
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(responseType, from: data)
            guard decodedResponse.schema == expectedSchema else {
                throw PairingServiceError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(httpResponse.statusCode) {
                return decodedResponse
            }
            if let pairingClaimResponse = decodedResponse as? PairingClaimResponse {
                switch pairingClaimResponse.backupState {
                case .pairingExpired:
                    throw PairingServiceError.expired(message: pairingClaimResponse.message)
                case .pairingCompleted:
                    throw PairingServiceError.invalidAcceptedResponse
                case .pendingPairing, .pairingMismatched, .pairingStopped:
                    throw PairingServiceError.rejected(message: pairingClaimResponse.message)
                }
            }
            throw PairingServiceError.rejected(message: "Desktop pairing request failed.")
        } catch let error as PairingServiceError {
            throw error
        } catch {
            throw PairingServiceError.decoding(message: error.localizedDescription)
        }
    }

    private func requestWithLocalNetworkRetry(
        _ request: URLRequest,
        endpoint: URL
    ) async throws -> (Data, URLResponse) {
        let isLocalEndpoint = endpoint.isLikelyLocalNetworkEndpoint
        let maxAttempts = isLocalEndpoint ? 10 : 1
        var attemptRequest = request
        if isLocalEndpoint {
            attemptRequest.timeoutInterval = 1
        }

        for attempt in 1 ... maxAttempts {
            do {
                return try await session.data(for: attemptRequest)
            } catch let error as URLError {
                let shouldRetry = isLocalEndpoint &&
                    error.isLikelyLocalNetworkPermissionError &&
                    attempt < maxAttempts
                if shouldRetry {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }

                if isLocalEndpoint && error.isLikelyLocalNetworkPermissionError {
                    throw PairingServiceError.transport(message: Self.localNetworkPermissionFailureMessage)
                }
                throw PairingServiceError.transport(message: error.localizedDescription)
            } catch {
                let nsError = error as NSError
                let shouldRetry = isLocalEndpoint &&
                    nsError.isLikelyLocalNetworkPermissionError &&
                    attempt < maxAttempts
                if shouldRetry {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }

                if isLocalEndpoint && nsError.isLikelyLocalNetworkPermissionError {
                    throw PairingServiceError.transport(message: Self.localNetworkPermissionFailureMessage)
                }
                throw PairingServiceError.transport(message: error.localizedDescription)
            }
        }

        throw PairingServiceError.transport(message: Self.localNetworkPermissionFailureMessage)
    }

    private static let localNetworkPermissionFailureMessage =
        "Local Network access is required before pairing can continue. Allow access in iOS Settings, then scan the desktop QR code again."

    private func encodeRequestBody<RequestBody: Encodable>(
        _ requestBody: RequestBody
    ) async throws -> Data {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(requestBody)
        guard var bodyValue = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] else {
            throw PairingServiceError.transport(message: "Desktop pairing request body could not be encoded.")
        }
        for (key, value) in traceContextPayloadFields(await telemetryClient.currentTraceContext()) {
            bodyValue[key] = value
        }
        guard JSONSerialization.isValidJSONObject(bodyValue) else {
            throw PairingServiceError.transport(message: "Desktop pairing request body is invalid.")
        }
        return try JSONSerialization.data(withJSONObject: bodyValue, options: [])
    }
}

struct DesktopBootstrapPairingService: PairingService {
    private static let pairingStatePollIntervalNanoseconds: UInt64 = 2_000_000_000
    private static let strictSecurityPairingFailureMessage =
        "The desktop does not support encrypted transport. Update the desktop app and try again."

    let bootstrapClient: PairingBootstrapClient
    let usbBootstrapClient: PairingUSBBootstrapClient?
    let capabilityExchangeClient: (any MobileCapabilityExchangeClient)?
    let updatePromptClient: (any MobileUpdatePromptClient)?
    let identityProvider: LocalDeviceIdentityProviding
    let trustedDesktopStore: TrustedDesktopStore

    init(
        bootstrapClient: PairingBootstrapClient,
        usbBootstrapClient: PairingUSBBootstrapClient? = nil,
        capabilityExchangeClient: (any MobileCapabilityExchangeClient)? = nil,
        updatePromptClient: (any MobileUpdatePromptClient)? = nil,
        identityProvider: LocalDeviceIdentityProviding,
        trustedDesktopStore: TrustedDesktopStore
    ) {
        self.bootstrapClient = bootstrapClient
        self.usbBootstrapClient = usbBootstrapClient
        self.capabilityExchangeClient = capabilityExchangeClient
        self.updatePromptClient = updatePromptClient
        self.identityProvider = identityProvider
        self.trustedDesktopStore = trustedDesktopStore
    }

    func primeNetworkAccess() async {
        await bootstrapClient.primeInternetAccess()
    }

    func startPairing(using payload: PairingQRCodePayload) async -> Result<PairingResponse, PairingError> {
        let identity = await identityProvider.currentIdentity()
        let pairingKeyBase64 = derivePairingKeyBase64(
            payload: payload,
            platform: identity.platform
        )
        let clientNonce = UUID().uuidString.lowercased()
        let request = PairingClaimRequest(
            sessionID: payload.sessionID,
            oneTimePasscode: payload.oneTimePasscode,
            platform: identity.platform,
            deviceUUID: identity.deviceUUID,
            deviceName: identity.deviceName,
            installID: identity.installID,
            clientNonce: clientNonce
        )

        do {
            let attempt = try await claimPairing(using: payload, request: request)
            var response = attempt.response
            switch response.backupState {
            case .pendingPairing, .pairingMismatched:
                response = try await waitForPairingResolution(
                    using: payload,
                    attempt: attempt,
                    request: PairingStateRequest(
                        sessionID: request.sessionID,
                        deviceUUID: request.deviceUUID
                    )
                )
            case .pairingCompleted:
                break
            case .pairingExpired:
                throw PairingServiceError.expired(message: response.message)
            case .pairingStopped:
                return .failure(.rejected(message: response.message))
            }

            guard response.backupState == .pairingCompleted else {
                return .failure(.rejected(message: response.message))
            }

            guard let sessionID = response.sessionID,
                  let desktopDeviceID = response.desktopDeviceID,
                  let desktopName = normalizedDesktopDisplayName(response.desktopName),
                  let pairedAt = response.pairedAt
            else {
                throw PairingServiceError.invalidAcceptedResponse
            }

            let transport = TransferTransport(rawValue: response.transport ?? TransferTransport.lan.rawValue) ?? .lan
            var trustedRecord = TrustedDesktopRecord(
                desktopDeviceID: desktopDeviceID,
                desktopName: desktopName,
                endpointURL: attempt.endpoint,
                mobileDeviceUUID: identity.deviceUUID,
                sharedKeyBase64: pairingKeyBase64,
                transport: transport,
                lastSessionID: sessionID,
                usbOneTimePasscode: payload.oneTimePasscode,
                usbSuggestedPort: payload.suggestedUSBPort,
                pairedAt: pairedAt,
                strictSecurityEnabled: payload.strictSecurityEnabled
            )
            trustedRecord = try await applyPostPairingCapabilitiesIfNeeded(trustedRecord)
            await trustedDesktopStore.saveTrustedDesktop(trustedRecord)

            return .success(
                PairingResponse(
                    sessionID: sessionID,
                    desktopName: desktopName,
                    transport: transport
                )
            )
        } catch let error as PairingServiceError {
            return .failure(PairingError(error))
        } catch {
            return .failure(.transport(message: error.localizedDescription))
        }
    }

    private func claimPairing(
        using payload: PairingQRCodePayload,
        request: PairingClaimRequest
    ) async throws -> PairingBootstrapAttempt {
        var retryableError: PairingServiceError?
        PairingDebugLogger.debug(
            "Starting pairing claim session_id=\(payload.sessionID) usb_candidate=\(payload.suggestedUSBPort != nil) lan_endpoint_count=\(payload.bootstrapURLs.count)"
        )
        if let usbBootstrapClient, payload.suggestedUSBPort != nil {
            do {
                PairingDebugLogger.debug(
                    "Attempting USB pairing claim session_id=\(payload.sessionID) suggested_usb_port=\(payload.suggestedUSBPort ?? 0)"
                )
                let response = try await usbBootstrapClient.claimPairing(
                    using: payload,
                    request: request
                )
                PairingDebugLogger.debug(
                    "USB pairing claim completed session_id=\(payload.sessionID) backup_state=\(response.backupState.rawValue)"
                )
                return PairingBootstrapAttempt(
                    endpoint: payload.bootstrapURL,
                    response: response,
                    transport: .usb
                )
            } catch let error as PairingServiceError {
                PairingDebugLogger.error(
                    "USB pairing claim failed session_id=\(payload.sessionID) error=\(error.localizedDescription)"
                )
                switch error {
                case .expired, .rejected:
                    throw error
                default:
                    retryableError = error
                }
            } catch {
                retryableError = .transport(message: error.localizedDescription)
            }
        }

        // Try each advertised endpoint because desktops may be reachable on only one LAN.
        for endpoint in payload.bootstrapURLs {
            do {
                PairingDebugLogger.debug(
                    "Attempting LAN pairing claim session_id=\(payload.sessionID) endpoint=\(endpoint.absoluteString)"
                )
                let response = try await bootstrapClient.claimPairing(
                    at: endpoint,
                    request: request
                )
                return PairingBootstrapAttempt(
                    endpoint: endpoint,
                    response: response,
                    transport: .lan
                )
            } catch let error as PairingServiceError {
                PairingDebugLogger.error(
                    "LAN pairing claim failed session_id=\(payload.sessionID) endpoint=\(endpoint.absoluteString) error=\(error.localizedDescription)"
                )
                switch error {
                case .expired, .rejected:
                    throw error
                default:
                    retryableError = error
                }
            } catch {
                retryableError = .transport(message: error.localizedDescription)
            }
        }

        throw retryableError ?? PairingServiceError.transport(
            message: "Desktop pairing could not reach any advertised endpoint."
        )
    }

    private func waitForPairingResolution(
        using payload: PairingQRCodePayload,
        attempt: PairingBootstrapAttempt,
        request: PairingStateRequest
    ) async throws -> PairingClaimResponse {
        var pollAttempt = 0
        while true {
            pollAttempt += 1
            let stateResponse: PairingClaimResponse
            switch attempt.transport {
            case .usb:
                guard let usbBootstrapClient else {
                    throw PairingServiceError.transport(message: "Desktop USB pairing state polling is unavailable.")
                }
                PairingDebugLogger.debug(
                    "Polling USB pairing state session_id=\(payload.sessionID) attempt=\(pollAttempt)"
                )
                stateResponse = try await usbBootstrapClient.fetchPairingState(
                    using: payload,
                    request: request
                )
            case .lan:
                PairingDebugLogger.debug(
                    "Polling LAN pairing state session_id=\(payload.sessionID) endpoint=\(attempt.endpoint.absoluteString) attempt=\(pollAttempt)"
                )
                stateResponse = try await bootstrapClient.fetchPairingState(
                    at: attempt.endpoint,
                    request: request
                )
            }
            PairingDebugLogger.debug(
                "Pairing state poll returned session_id=\(payload.sessionID) attempt=\(pollAttempt) state=\(stateResponse.backupState.rawValue)"
            )

            switch stateResponse.backupState {
            case .pairingCompleted, .pairingStopped:
                return stateResponse
            case .pairingExpired:
                throw PairingServiceError.expired(message: stateResponse.message)
            case .pendingPairing, .pairingMismatched:
                try? await Task.sleep(nanoseconds: Self.pairingStatePollIntervalNanoseconds)
            }
        }
    }

    private func derivePairingKeyBase64(
        payload: PairingQRCodePayload,
        platform: String
    ) -> String {
        let material = [
            PairingProtocol.schema,
            payload.sessionID,
            payload.oneTimePasscode,
            platform,
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private func applyPostPairingCapabilitiesIfNeeded(
        _ desktop: TrustedDesktopRecord
    ) async throws -> TrustedDesktopRecord {
        guard let capabilityExchangeClient else {
            if desktop.strictSecurityEnabled {
                throw PairingServiceError.rejected(message: Self.strictSecurityPairingFailureMessage)
            }
            return desktop
        }
        var updatedDesktop = desktop
        do {
            let response = try await capabilityExchangeClient.exchangeCapabilities(
                [MobileTransferCapabilities.encryption: 1],
                desktop: desktop
            )
            updatedDesktop.encryptionEnabled =
                (response.capabilities?[MobileTransferCapabilities.encryption] ?? 0) == 1
            if updatedDesktop.strictSecurityEnabled, !updatedDesktop.encryptionEnabled {
                throw PairingServiceError.rejected(message: Self.strictSecurityPairingFailureMessage)
            }
            return updatedDesktop
        } catch {
            if desktop.strictSecurityEnabled {
                throw PairingServiceError.rejected(message: Self.strictSecurityPairingFailureMessage)
            }
            return desktop
        }
    }

}


private struct PairingBootstrapAttempt {
    let endpoint: URL
    let response: PairingClaimResponse
    let transport: TransferTransport
}

private enum PairingDebugLogger {
    private static let logger = Logger(
        subsystem: "AlbumTransporterKit.Pairing",
        category: "CapabilityExchange"
    )

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension URL {
    var pairingStateURL: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/mobile/pairing/state"
        components.query = nil
        components.fragment = nil
        return components.url
    }
    var isLikelyLocalNetworkEndpoint: Bool {
        guard let host else {
            return false
        }

        let normalizedHost = host.lowercased()
        if normalizedHost == "localhost" || normalizedHost.hasSuffix(".local") || normalizedHost == "::1" {
            return true
        }

        let octets = normalizedHost.split(separator: ".")
        guard octets.count == 4,
              let firstOctet = Int(octets[0]),
              let secondOctet = Int(octets[1])
        else {
            return false
        }

        if firstOctet == 10 || firstOctet == 127 || firstOctet == 192 && secondOctet == 168 {
            return true
        }
        return firstOctet == 172 && (16 ... 31).contains(secondOctet)
    }
}

private extension URLError {
    var isLikelyLocalNetworkPermissionError: Bool {
        switch code {
        case .notConnectedToInternet,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .timedOut:
            return true
        default:
            return false
        }
    }
}

private extension NSError {
    var isLikelyLocalNetworkPermissionError: Bool {
        if domain == NSURLErrorDomain {
            let urlErrorCode = URLError.Code(rawValue: code)
            switch urlErrorCode {
            case .notConnectedToInternet,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .timedOut,
                 .cannotLoadFromNetwork:
                return true
            default:
                return false
            }
        }

        if domain == NSPOSIXErrorDomain {
            switch code {
            case Int(EPERM), Int(EACCES), Int(ENETDOWN), Int(ENETUNREACH), Int(EHOSTUNREACH):
                return true
            default:
                return false
            }
        }

        return false
    }
}
