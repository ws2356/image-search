//
//  TransferFeature.swift
//  ISFromMobile
//
//  Upload progress spinner; auto-navigates to CompletionFeature on success.
//  Replaces the transferring phase.
//
import ComposableArchitecture
import Common
import Foundation

@Reducer
public struct TransferFeature {
    @ObservableState
    public struct State: Equatable {
        var progress: Float = 0

        public init(progress: Float = 0) {
            self.progress = progress
        }
    }

    @CasePathable
    public enum Action {
        case startTransfer
        case transferCompleted
        case transferFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case transferSucceeded
            case transferFailed(String)
        }
    }

    @SharedReader(.instantShareContext) var context
    @Dependency(\.uploadClient) var uploadClient
    @Dependency(\.identityClient) var identityClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startTransfer:
                guard let targetDevice = context.targetDevice else {
                    return .send(.delegate(.transferFailed("No target device")))
                }

                let sessionId = context.sessionId
                let hosts = targetDevice.hosts
                let tlsPort = targetDevice.tlsPort

                return .run { [identityClient, uploadClient, context] send in
                    let deviceName = await identityClient.currentDeviceName()

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
                        break
                    }

                    await send(.transferCompleted)
                } catch: { error, send in
                    let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    await send(.transferFailed(msg))
                }

            case .transferCompleted:
                return .send(.delegate(.transferSucceeded))

            case .transferFailed(let message):
                return .send(.delegate(.transferFailed(message)))

            case .delegate:
                return .none
            }
        }
    }
}
