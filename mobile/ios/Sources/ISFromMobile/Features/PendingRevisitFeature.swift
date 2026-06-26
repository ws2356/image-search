//
//  PendingRevisitFeature.swift
//  ISFromMobile
//
//  Attempts a "revisit" TLS transfer using previously-established trust.
//  On success → delegates to CompletionFeature; on failure → delegates to AuthFeature.
//
import ComposableArchitecture
import Common
import Foundation

@Reducer
public struct PendingRevisitFeature {
    @ObservableState
    public struct State: Equatable {
        public let payloadDescription: String

        public init(payloadDescription: String = "") {
            self.payloadDescription = payloadDescription
        }
    }

    @CasePathable
    public enum Action {
        case attemptRevisit
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case revisitSucceeded(payloadDescription: String)
            case revisitFailed
        }
    }

    @SharedReader(.instantShareContext) var context
    @Dependency(\.uploadClient) var uploadClient
    @Dependency(\.identityClient) var identityClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .attemptRevisit:
                let payloadDescription = state.payloadDescription
                return .run { [context = context, uploadClient = uploadClient, identityClient = identityClient] send in
                    let sessionId = context.sessionId
                    let deviceName = await identityClient.currentDeviceName()

                    guard let targetDevice = context.targetDevice else {
                        await send(.delegate(.revisitFailed))
                        return
                    }

                    let sharedItems = context.sharedItems

                    do {
                        switch sharedItems {
                        case .text(let text):
                            try await Retryable.withRetry(maxTimes: 3) {
                                try await uploadClient.uploadText(
                                    hosts: targetDevice.hosts,
                                    port: targetDevice.tlsPort,
                                    sessionID: sessionId,
                                    correlationID: sessionId,
                                    text: text,
                                    peerDeviceName: deviceName
                                )
                            }
                        case .images(let images):
                            if images.count == 1, let img = images.first {
                                try await Retryable.withRetry(maxTimes: 3) {
                                    try await uploadClient.uploadImage(
                                        hosts: targetDevice.hosts,
                                        port: targetDevice.tlsPort,
                                        sessionID: sessionId,
                                        correlationID: sessionId,
                                        fileURL: img.fileURL,
                                        contentType: img.contentType,
                                        filename: img.filename,
                                        peerDeviceName: deviceName
                                    )
                                }
                            } else {
                                try await Retryable.withRetry(maxTimes: 3) {
                                    try await uploadClient.uploadImages(
                                        hosts: targetDevice.hosts,
                                        port: targetDevice.tlsPort,
                                        sessionID: sessionId,
                                        correlationID: sessionId,
                                        urls: images.map { ($0.fileURL, $0.filename, $0.contentType) },
                                        peerDeviceName: deviceName
                                    )
                                }
                            }
                        case .files:
                            // Files not yet supported in revisit
                            await send(.delegate(.revisitFailed))
                            return
                        }
                        await send(.delegate(.revisitSucceeded(payloadDescription: payloadDescription)))
                    } catch {
                        await send(.delegate(.revisitFailed))
                    }
                }

            case .delegate:
                return .none
            }
        }
    }
}
