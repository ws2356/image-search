//
//  AuthFeature.swift
//  ISFromMobile
//
//  PIN input + trust handshake sequence.
//  On appear: handshake → apply (automatic, shows loading).
//  On PIN submit: confirm → authCompleted (upload delegated to TransferFeature).
//
import ComposableArchitecture
import Common
import Foundation

@Reducer
public struct AuthFeature {
    @ObservableState
    public struct State: Equatable {
        var pinCode: String = ""
        var errorMessage: String? = nil
        var isProcessing: Bool = false
        /// True while handshake+apply are in progress (auto-starts on appear).
        var isHandshaking: Bool = true

        public init(
            pinCode: String = "",
            errorMessage: String? = nil,
            isProcessing: Bool = false,
            isHandshaking: Bool = true
        ) {
            self.pinCode = pinCode
            self.errorMessage = errorMessage
            self.isProcessing = isProcessing
            self.isHandshaking = isHandshaking
        }
    }

    @CasePathable
    public enum Action {
        /// Auto-triggered from view .task — runs handshake + apply.
        case handshakeAndApply
        /// handshake + apply completed successfully, show PIN entry.
        case handshakeReady
        /// handshake + apply failed (non-recoverable).
        case handshakeFailed(String)

        case pinCodeChanged(String)
        case rejectPIN
        case pinMismatch
        case confirmResponse
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case authCompleted
            case authFailed(String)
            case authCancelled
        }
    }

    @SharedReader(.instantShareContext) var context
    @Dependency(\.trustClient) var trustClient
    @Dependency(\.trustSessionManager) var trustSessionManager
    @Dependency(\.identityClient) var identityClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // MARK: - Handshake + Apply (automatic on appear)

            case .handshakeAndApply:
                guard let targetDevice = context.targetDevice else {
                    state.errorMessage = "Missing device information."
                    state.isHandshaking = false
                    return .none
                }
                state.isHandshaking = true
                state.errorMessage = nil

                let sessionId = context.sessionId
                let hosts = targetDevice.hosts
                let port = targetDevice.port

                return .run { [sessionId, hosts, port, trustClient, context] send in
                    let _ = try await trustClient.handshake(
                        hosts: hosts, port: port,
                        sessionID: sessionId, correlationID: sessionId,
                        mobilePort: 1, mobileIPList: ["127.0.0.1"],
                        payloadClass: context.sharedItems.payloadClass,
                        targetIntent: context.sharedItems.targetIntent,
                        trustMode: "first_share"
                    )

                    try await trustClient.apply(
                        hosts: hosts, port: port,
                        sessionID: sessionId, correlationID: sessionId
                    )

                    await send(.handshakeReady)
                } catch: { error, send in
                    let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    await send(.handshakeFailed(msg))
                }

            case .handshakeReady:
                state.isHandshaking = false
                return .none

            case .handshakeFailed(let message):
                state.isHandshaking = false
                return .send(.delegate(.authFailed(message)))

            // MARK: - PIN Entry

            case .pinCodeChanged(let code):
                if code == state.pinCode {
                    return .none
                }
                state.pinCode = code
                state.errorMessage = nil
                state.isProcessing = false
                
                if code.count < 4 {
                    return .none
                }

                guard !state.pinCode.isEmpty,
                      let targetDevice = context.targetDevice else {
                    state.errorMessage = "Missing PIN or device information."
                    return .none
                }
                state.isProcessing = true
                state.errorMessage = nil

                let sessionId = context.sessionId
                let hosts = targetDevice.hosts
                let port = targetDevice.port

                return .run { [pinCode = state.pinCode, sessionId, hosts, port, identityClient, trustClient] send in
                    let myCert = try? await identityClient.selfCertificatePEM()

                    let peerCert = try await trustClient.confirm(
                        hosts: hosts, port: port,
                        sessionID: sessionId, correlationID: sessionId,
                        pinCode: pinCode,
                        deviceCertificatePEM: myCert
                    )

                    // Import peer certificate
                    if let peerCert {
                        try? await identityClient.importPeerCertificate(pem: peerCert)
                    }

                    await send(.confirmResponse)
                } catch: { error, send in
                    // PIN mismatch is recoverable
                    if let trustError = error as? InstantShareTrustClientError,
                       case .httpError(let statusCode, let errorCode, _) = trustError,
                       statusCode == 403 && errorCode == "PIN_MISMATCH_OR_REJECTED" {
                        await send(.pinMismatch)
                    } else {
                        let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                        await send(.delegate(.authFailed(msg)))
                    }
                }

            case .confirmResponse:
                state.isProcessing = false
                return .send(.delegate(.authCompleted))

            // MARK: - Cancel

            case .pinMismatch:
                state.pinCode = ""
                state.errorMessage = "PIN code is incorrect. Please try again."
                state.isProcessing = false
                return .none

            case .rejectPIN:
                trustSessionManager.reset()
                return .send(.delegate(.authCancelled))

            case .delegate:
                return .none
            }
        }
    }
}
