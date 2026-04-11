import CryptoKit
import Foundation

struct URLSessionPairingBootstrapClient: PairingBootstrapClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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
            (data, response) = try await session.data(for: urlRequest)
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
}

struct DesktopBootstrapPairingService: PairingService {
    let bootstrapClient: PairingBootstrapClient
    let identityProvider: LocalDeviceIdentityProviding
    let trustedDesktopStore: TrustedDesktopStore

    init(
        bootstrapClient: PairingBootstrapClient,
        identityProvider: LocalDeviceIdentityProviding,
        trustedDesktopStore: TrustedDesktopStore
    ) {
        self.bootstrapClient = bootstrapClient
        self.identityProvider = identityProvider
        self.trustedDesktopStore = trustedDesktopStore
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
                  let desktopName = response.desktopName,
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
}

private struct PairingBootstrapAttempt {
    let endpoint: URL
    let response: PairingClaimResponse
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
