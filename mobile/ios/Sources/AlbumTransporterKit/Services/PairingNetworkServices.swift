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
        urlRequest.httpBody = try JSONEncoder.pairingEncoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)
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
    let now: @Sendable () -> Date

    init(
        bootstrapClient: PairingBootstrapClient,
        identityProvider: LocalDeviceIdentityProviding,
        trustedDesktopStore: TrustedDesktopStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.bootstrapClient = bootstrapClient
        self.identityProvider = identityProvider
        self.trustedDesktopStore = trustedDesktopStore
        self.now = now
    }

    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        guard payload.expiresAt > now() else {
            return PairingStatus(
                phase: .expired,
                desktopName: nil,
                sessionID: nil,
                transport: nil,
                message: "This QR code has already expired. Refresh it on desktop and scan again."
            )
        }

        let identity = await identityProvider.currentIdentity()
        let clientNonce = UUID().uuidString.lowercased()
        let request = PairingClaimRequest(
            pairingID: payload.pairingID,
            tokenID: payload.tokenID,
            secret: payload.secret,
            platform: identity.platform,
            deviceUUID: identity.deviceUUID,
            deviceName: identity.deviceName,
            installID: identity.installID,
            clientNonce: clientNonce
        )

        do {
            let response = try await bootstrapClient.claimPairing(at: payload.bootstrapURL, request: request)
            guard response.status == .accepted,
                  let sessionID = response.sessionID,
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
                endpointURL: payload.bootstrapURL,
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

    private func derivePairingKeyBase64(
        payload: PairingQRCodePayload,
        identity: LocalDeviceIdentity,
        desktopDeviceID: String,
        clientNonce: String,
        serverNonce: String
    ) -> String {
        let material = [
            PairingProtocol.schema,
            payload.pairingID,
            payload.tokenID,
            payload.secret,
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

private extension PairingServiceError {
    var phase: PairingPhase {
        switch self {
        case .expiredQRCode, .expired:
            return .expired
        default:
            return .failed
        }
    }

    var message: String {
        switch self {
        case .expiredQRCode:
            return "This QR code has already expired. Refresh it on desktop and scan again."
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
