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

    func exchangePairingCapabilities(
        at endpoint: URL,
        request: PairingCapabilityExchangeRequest
    ) async throws -> PairingCapabilityExchangeResponse {
        guard let capabilityEndpoint = endpoint.pairingCapabilityExchangeURL else {
            throw PairingServiceError.transport(message: "Desktop pairing capability endpoint is invalid.")
        }
        return try await postPairingRequest(
            at: capabilityEndpoint,
            requestBody: request,
            responseType: PairingCapabilityExchangeResponse.self,
            expectedSchema: PairingCapabilityExchangeProtocol.schema
        )
    }

    func claimPairing(
        at endpoint: URL,
        request: PairingClaimRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        try await postPairingRequest(
            at: endpoint,
            requestBody: request,
            responseType: PairingClaimResponse.self,
            expectedSchema: PairingProtocol.schema,
            encryptionTrustKeyBase64: encryptionTrustKeyBase64,
            encryptionSessionID: request.sessionID,
            encryptionPlatform: request.platform
        )
    }

    func fetchPairingState(
        at endpoint: URL,
        request: PairingStateRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        guard let stateEndpoint = endpoint.pairingStateURL else {
            throw PairingServiceError.transport(message: "Desktop pairing state endpoint is invalid.")
        }
        return try await postPairingRequest(
            at: stateEndpoint,
            requestBody: request,
            responseType: PairingClaimResponse.self,
            expectedSchema: PairingProtocol.schema,
            encryptionTrustKeyBase64: encryptionTrustKeyBase64,
            encryptionSessionID: request.sessionID
        )
    }

    private func postPairingRequest<RequestBody: Encodable, ResponseBody: Decodable & PairingSchemaResponse>(
        at endpoint: URL,
        requestBody: RequestBody,
        responseType: ResponseBody.Type,
        expectedSchema: String,
        encryptionTrustKeyBase64: String? = nil,
        encryptionSessionID: String? = nil,
        encryptionDeviceUUID: String? = nil,
        encryptionPlatform: String? = nil
    ) async throws -> ResponseBody {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 5
        urlRequest.httpBody = try await encodeRequestBody(
            requestBody,
            encryptionTrustKeyBase64: encryptionTrustKeyBase64,
            encryptionSessionID: encryptionSessionID,
            encryptionDeviceUUID: encryptionDeviceUUID,
            encryptionPlatform: encryptionPlatform
        )

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
            let responseData = try decodeResponsePayloadData(
                data,
                encryptionTrustKeyBase64: encryptionTrustKeyBase64
            )
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(responseType, from: responseData)
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
            if let capabilityResponse = decodedResponse as? PairingCapabilityExchangeResponse {
                throw PairingServiceError.rejected(message: capabilityResponse.message)
            }
            throw PairingServiceError.rejected(message: "Desktop pairing request failed.")
        } catch let error as PairingServiceError {
            throw error
        } catch {
            throw PairingServiceError.decoding(message: error.localizedDescription)
        }
    }

    private func decodeResponsePayloadData(
        _ data: Data,
        encryptionTrustKeyBase64: String?
    ) throws -> Data {
        guard let encryptionTrustKeyBase64 else {
            return data
        }
        guard let encryptedResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PairingServiceError.decoding(message: "Desktop pairing response is not a JSON object.")
        }
        guard MobilePayloadEncryption.isEncryptedPayload(encryptedResponse) else {
            throw PairingServiceError.decoding(message: "Desktop pairing response must be encrypted.")
        }
        let decryptedPayload = try MobilePayloadEncryption.decryptPayloadObject(
            encryptedResponse,
            trustKeyBase64: encryptionTrustKeyBase64
        )
        guard JSONSerialization.isValidJSONObject(decryptedPayload) else {
            throw PairingServiceError.decoding(message: "Desktop pairing response payload is invalid.")
        }
        return try JSONSerialization.data(withJSONObject: decryptedPayload, options: [])
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
        _ requestBody: RequestBody,
        encryptionTrustKeyBase64: String? = nil,
        encryptionSessionID: String? = nil,
        encryptionDeviceUUID: String? = nil,
        encryptionPlatform: String? = nil
    ) async throws -> Data {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(requestBody)
        guard var bodyValue = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] else {
            throw PairingServiceError.transport(message: "Desktop pairing request body could not be encoded.")
        }
        for (key, value) in traceContextPayloadFields(await telemetryClient.currentTraceContext()) {
            bodyValue[key] = value
        }
        if let encryptionTrustKeyBase64 {
            guard let encryptionSessionID else {
                throw PairingServiceError.transport(message: "Desktop pairing encryption is missing session context.")
            }
            let encryptedPayload = try MobilePayloadEncryption.encryptPayloadObject(
                bodyValue,
                trustKeyBase64: encryptionTrustKeyBase64,
                sessionID: encryptionSessionID,
                deviceUUID: encryptionDeviceUUID,
                platform: encryptionPlatform
            )
            let encryptedBody = try JSONEncoder.pairingEncoder.encode(encryptedPayload)
            guard let encryptedBodyValue = try JSONSerialization.jsonObject(with: encryptedBody) as? [String: Any] else {
                throw PairingServiceError.transport(message: "Desktop pairing request body could not be encrypted.")
            }
            bodyValue = encryptedBodyValue
        }
        guard JSONSerialization.isValidJSONObject(bodyValue) else {
            throw PairingServiceError.transport(message: "Desktop pairing request body is invalid.")
        }
        return try JSONSerialization.data(withJSONObject: bodyValue, options: [])
    }
}

struct DesktopBootstrapPairingService: PairingService {
    private static let pairingStatePollIntervalNanoseconds: UInt64 = 2_000_000_000

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
            let trustedRecord = TrustedDesktopRecord(
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
                encryptionEnabled: attempt.encryptionEnabled
            )
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
        let pairingKeyBase64 = derivePairingKeyBase64(
            payload: payload,
            platform: request.platform
        )

        if let usbBootstrapClient, payload.suggestedUSBPort != nil {
            do {
                PairingDebugLogger.debug(
                    "Attempting USB pairing claim session_id=\(payload.sessionID) suggested_usb_port=\(payload.suggestedUSBPort ?? 0)"
                )
                let encryptionEnabled = try await negotiatePairingEncryptionOverUSB(
                    payload: payload,
                    request: request,
                    usbBootstrapClient: usbBootstrapClient
                )
                let response = try await usbBootstrapClient.claimPairing(
                    using: payload,
                    request: request,
                    encryptionTrustKeyBase64: encryptionEnabled ? pairingKeyBase64 : nil
                )
                PairingDebugLogger.debug(
                    "USB pairing claim completed session_id=\(payload.sessionID) backup_state=\(response.backupState.rawValue)"
                )
                return PairingBootstrapAttempt(
                    endpoint: payload.bootstrapURL,
                    response: response,
                    transport: .usb,
                    encryptionEnabled: encryptionEnabled,
                    encryptionTrustKeyBase64: encryptionEnabled ? pairingKeyBase64 : nil
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
                let encryptionEnabled = try await negotiatePairingEncryptionOverLAN(
                    endpoint: endpoint,
                    request: request
                )
                let response = try await bootstrapClient.claimPairing(
                    at: endpoint,
                    request: request,
                    encryptionTrustKeyBase64: encryptionEnabled ? pairingKeyBase64 : nil
                )
                return PairingBootstrapAttempt(
                    endpoint: endpoint,
                    response: response,
                    transport: .lan,
                    encryptionEnabled: encryptionEnabled,
                    encryptionTrustKeyBase64: encryptionEnabled ? pairingKeyBase64 : nil
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
                    request: request,
                    encryptionTrustKeyBase64: attempt.encryptionTrustKeyBase64
                )
            case .lan:
                PairingDebugLogger.debug(
                    "Polling LAN pairing state session_id=\(payload.sessionID) endpoint=\(attempt.endpoint.absoluteString) attempt=\(pollAttempt)"
                )
                stateResponse = try await bootstrapClient.fetchPairingState(
                    at: attempt.endpoint,
                    request: request,
                    encryptionTrustKeyBase64: attempt.encryptionTrustKeyBase64
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

    private func negotiatePairingEncryptionOverLAN(
        endpoint: URL,
        request: PairingClaimRequest
    ) async throws -> Bool {
        do {
            let response = try await bootstrapClient.exchangePairingCapabilities(
                at: endpoint,
                request: PairingCapabilityExchangeRequest(
                    sessionID: request.sessionID,
                    oneTimePasscode: request.oneTimePasscode,
                    platform: request.platform,
                    capabilities: [MobilePayloadEncryptionProtocol.capabilityName: 1]
                )
            )
            if response.status != .accepted {
                return false
            }
            return (response.capabilities[MobilePayloadEncryptionProtocol.capabilityName] ?? 0) == 1
        } catch {
            return false
        }
    }

    private func negotiatePairingEncryptionOverUSB(
        payload: PairingQRCodePayload,
        request: PairingClaimRequest,
        usbBootstrapClient: PairingUSBBootstrapClient
    ) async throws -> Bool {
        do {
            let response = try await usbBootstrapClient.exchangePairingCapabilities(
                using: payload,
                request: PairingCapabilityExchangeRequest(
                    sessionID: request.sessionID,
                    oneTimePasscode: request.oneTimePasscode,
                    platform: request.platform,
                    capabilities: [MobilePayloadEncryptionProtocol.capabilityName: 1]
                )
            )
            if response.status != .accepted {
                return false
            }
            return (response.capabilities[MobilePayloadEncryptionProtocol.capabilityName] ?? 0) == 1
        } catch {
            return false
        }
    }

}


private struct PairingBootstrapAttempt {
    let endpoint: URL
    let response: PairingClaimResponse
    let transport: TransferTransport
    let encryptionEnabled: Bool
    let encryptionTrustKeyBase64: String?
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

    var pairingCapabilityExchangeURL: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = PairingCapabilityExchangeProtocol.exchangePath
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
