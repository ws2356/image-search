//
//  AuthFeature.swift
//  ISFromMobile
//
//  PIN input + trust handshake (handshake → apply → confirm) + upload after PIN confirm.
//  Replaces the awaitingPinInput phase.
//
import ComposableArchitecture
import Common
import Foundation

@Reducer
struct AuthFeature {
    @ObservableState
    struct State: Equatable {
        var pinCode: String = ""
        var errorMessage: String? = nil
        var isProcessing: Bool = false
    }

    @CasePathable
    enum Action {
        case pinCodeChanged(String)
        case confirmPIN
        case rejectPIN
        case confirmResponse
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case authCompleted
            case authFailed(String)
            case authCancelled
        }
    }

    @SharedReader(.instantShareContext) var context
    @Dependency(\.trustClient) var trustClient
    @Dependency(\.uploadClient) var uploadClient
    @Dependency(\.trustSessionManager) var trustSessionManager
    @Dependency(\.identityClient) var identityClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pinCodeChanged(let code):
                state.pinCode = code
                state.errorMessage = nil
                return .none

            case .confirmPIN:
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
                let tlsPort = targetDevice.tlsPort

                return .run { [pinCode = state.pinCode] send in
                    let deviceName = await identityClient.currentDeviceName()
                    let myCert = try? await identityClient.selfCertificatePEM()

                    // Trust handshake: handshake → apply → confirm
                    let handshakeResponse = try await trustClient.handshake(
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

                    // Upload the content
                    let sharedItems = context.sharedItems
                    switch sharedItems {
                    case .text(let text):
                        try await uploadClient.uploadText(
                            hosts: hosts, port: tlsPort,
                            sessionID: sessionId, correlationID: sessionId,
                            text: text,
                            peerDeviceName: deviceName
                        )
                    case .images(let images):
                        if images.count == 1, let img = images.first {
                            try await uploadClient.uploadImage(
                                hosts: hosts, port: tlsPort,
                                sessionID: sessionId, correlationID: sessionId,
                                fileURL: img.fileURL,
                                contentType: img.contentType,
                                filename: img.filename,
                                peerDeviceName: deviceName
                            )
                        } else {
                            try await uploadClient.uploadImages(
                                hosts: hosts, port: tlsPort,
                                sessionID: sessionId, correlationID: sessionId,
                                urls: images.map { ($0.fileURL, $0.filename, $0.contentType) },
                                peerDeviceName: deviceName
                            )
                        }
                    case .files:
                        // Files not yet supported
                        break
                    }

                    await send(.confirmResponse)
                } catch: { error, send in
                    // PIN mismatch is recoverable
                    if let trustError = error as? InstantShareTrustClientError,
                       case .httpError(let statusCode, let errorCode, _) = trustError,
                       statusCode == 403 && errorCode == "PIN_MISMATCH_OR_REJECTED" {
                        await send(.pinCodeChanged(""))  // Clear PIN
                        await send(.pinCodeChanged(""))  // Dummy to trigger state update
                    } else {
                        let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                        await send(.delegate(.authFailed(msg)))
                    }
                }

            case .confirmResponse:
                state.isProcessing = false
                return .send(.delegate(.authCompleted))

            case .rejectPIN:
                trustSessionManager.reset()
                return .send(.delegate(.authCancelled))

            case .delegate:
                return .none
            }
        }
    }
}
