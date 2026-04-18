import CryptoKit
import Foundation
import OSLog

struct URLSessionPairingBootstrapClient: PairingBootstrapClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func primeInternetAccess() async {
        guard let warmupURL = URL(string: "https://dl.boldman.net/") else {
            return
        }

        var request = URLRequest(url: warmupURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2
        _ = try? await session.data(for: request)
    }

    func claimPairing(at endpoint: URL, request: PairingClaimRequest) async throws -> PairingClaimResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 5
        urlRequest.httpBody = try JSONEncoder.pairingEncoder.encode(request)

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
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(PairingClaimResponse.self, from: data)
            guard decodedResponse.schema == PairingProtocol.schema else {
                throw PairingServiceError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(httpResponse.statusCode) {
                return decodedResponse
            }

            switch decodedResponse.status {
            case .expired:
                throw PairingServiceError.expired(message: decodedResponse.message)
            case .accepted:
                throw PairingServiceError.invalidAcceptedResponse
            case .rejected:
                throw PairingServiceError.rejected(message: decodedResponse.message)
            }
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
}

struct DesktopBootstrapPairingService: PairingService {
    let bootstrapClient: PairingBootstrapClient
    let usbBootstrapClient: PairingUSBBootstrapClient?
    let capabilityExchangeClient: (any MobileCapabilityExchangeClient)?
    let identityProvider: LocalDeviceIdentityProviding
    let trustedDesktopStore: TrustedDesktopStore

    init(
        bootstrapClient: PairingBootstrapClient,
        usbBootstrapClient: PairingUSBBootstrapClient? = nil,
        capabilityExchangeClient: (any MobileCapabilityExchangeClient)? = nil,
        identityProvider: LocalDeviceIdentityProviding,
        trustedDesktopStore: TrustedDesktopStore
    ) {
        self.bootstrapClient = bootstrapClient
        self.usbBootstrapClient = usbBootstrapClient
        self.capabilityExchangeClient = capabilityExchangeClient
        self.identityProvider = identityProvider
        self.trustedDesktopStore = trustedDesktopStore
    }

    func primeNetworkAccess() async {
        await bootstrapClient.primeInternetAccess()
    }

    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        let identity = await identityProvider.currentIdentity()
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
            let response = attempt.response
            switch response.status {
            case .accepted:
                break
            case .expired:
                throw PairingServiceError.expired(message: response.message)
            case .rejected:
                throw PairingServiceError.rejected(message: response.message)
            }

            guard let sessionID = response.sessionID,
                  let desktopDeviceID = response.desktopDeviceID,
                  let desktopName = normalizedDesktopDisplayName(response.desktopName),
                  let serverNonce = response.serverNonce,
                  let pairedAt = response.pairedAt
            else {
                throw PairingServiceError.invalidAcceptedResponse
            }

            let sharedKeyBase64 = derivePairingKeyBase64(
                payload: payload,
                identity: identity,
                desktopDeviceID: desktopDeviceID,
                clientNonce: clientNonce,
                serverNonce: serverNonce
            )
            let transport = TransferTransport(rawValue: response.transport ?? TransferTransport.lan.rawValue) ?? .lan
            let trustedRecord = TrustedDesktopRecord(
                desktopDeviceID: desktopDeviceID,
                desktopName: desktopName,
                endpointURL: attempt.endpoint,
                mobileDeviceUUID: identity.deviceUUID,
                sharedKeyBase64: sharedKeyBase64,
                transport: transport,
                lastSessionID: sessionID,
                pairedAt: pairedAt
            )
            await trustedDesktopStore.saveTrustedDesktop(trustedRecord)
#if DEBUG
            if let capabilityExchangeClient {
                Self.startDebugCapabilityExchangeBurst(
                    using: capabilityExchangeClient,
                    desktop: trustedRecord
                )
            }
#endif

            return PairingStatus(
                phase: .paired,
                desktopName: desktopName,
                sessionID: sessionID,
                transport: transport,
                message: response.message
            )
        } catch let error as PairingServiceError {
            return PairingStatus(
                phase: error.phase,
                desktopName: nil,
                sessionID: nil,
                transport: nil,
                message: error.message
            )
        } catch {
            return PairingStatus(
                phase: .failed,
                desktopName: nil,
                sessionID: nil,
                transport: nil,
                message: "Desktop pairing failed: \(error.localizedDescription)"
            )
        }
    }

    private func claimPairing(
        using payload: PairingQRCodePayload,
        request: PairingClaimRequest
    ) async throws -> PairingBootstrapAttempt {
        var retryableError: PairingServiceError?

        if let usbBootstrapClient, payload.suggestedUSBPort != nil {
            do {
                let response = try await usbBootstrapClient.claimPairing(using: payload, request: request)
                return PairingBootstrapAttempt(endpoint: payload.bootstrapURL, response: response)
            } catch let error as PairingServiceError {
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
                let response = try await bootstrapClient.claimPairing(at: endpoint, request: request)
                return PairingBootstrapAttempt(endpoint: endpoint, response: response)
            } catch let error as PairingServiceError {
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

    private func derivePairingKeyBase64(
        payload: PairingQRCodePayload,
        identity: LocalDeviceIdentity,
        desktopDeviceID: String,
        clientNonce: String,
        serverNonce: String
    ) -> String {
        let material = [
            PairingProtocol.schema,
            payload.sessionID,
            payload.oneTimePasscode,
            identity.deviceUUID,
            identity.platform,
            clientNonce,
            serverNonce,
            desktopDeviceID,
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8))
        return Data(digest).base64URLEncodedString()
    }

#if DEBUG
    private static func startDebugCapabilityExchangeBurst(
        using client: any MobileCapabilityExchangeClient,
        desktop: TrustedDesktopRecord
    ) {
        Task.detached(priority: .background) {
            PairingDebugLogger.debug(
                "PairingDebug/capability_exchange: starting burst session_id=\(desktop.lastSessionID) "
                    + "transport=\(desktop.transport.rawValue) requests=10"
            )

            for requestIndex in 1 ... 10 {
                let capabilityPayload = debugCapabilityPayload(
                    requestIndex: requestIndex,
                    desktop: desktop
                )
                do {
                    let response = try await client.exchangeCapabilities(capabilityPayload, desktop: desktop)
                    PairingDebugLogger.debug(
                        "PairingDebug/capability_exchange: request=\(requestIndex)/10 "
                            + "status=\(response.status.rawValue) "
                            + "sent_capabilities=\(capabilityPayload.keys.sorted()) "
                            + "received_capabilities=\((response.capabilities ?? [:]).keys.sorted()) "
                            + "session_id=\(desktop.lastSessionID)"
                    )
                } catch {
                    PairingDebugLogger.error(
                        "PairingDebug/capability_exchange: request=\(requestIndex)/10 failed "
                            + "session_id=\(desktop.lastSessionID) error=\(error.localizedDescription)"
                    )
                }

                if requestIndex < 10 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            PairingDebugLogger.debug(
                "PairingDebug/capability_exchange: completed burst session_id=\(desktop.lastSessionID)"
            )
        }
    }

    private static func debugCapabilityPayload(
        requestIndex: Int,
        desktop: TrustedDesktopRecord
    ) -> [String: Int] {
        [
            "debug.mobile.capability.burst": 1,
            "debug.mobile.capability.request_\(requestIndex)": 1,
            "debug.mobile.transport.\(desktop.transport.rawValue)": 1,
        ]
    }
#endif
}

private struct PairingBootstrapAttempt {
    let endpoint: URL
    let response: PairingClaimResponse
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

private extension PairingServiceError {
    var phase: PairingPhase {
        switch self {
        case .expired:
            return .expired
        default:
            return .failed
        }
    }

    var message: String {
        switch self {
        case .invalidHTTPResponse:
            return "Desktop pairing returned an invalid network response."
        case .unsupportedResponseSchema:
            return "Desktop pairing returned an unsupported response schema."
        case .invalidAcceptedResponse:
            return "Desktop pairing returned an incomplete acceptance payload."
        case .rejected(let message), .expired(let message), .transport(let message), .decoding(let message):
            return message
        }
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
