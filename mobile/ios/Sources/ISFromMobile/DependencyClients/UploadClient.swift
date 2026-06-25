//
//  UploadClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping InstantShareUploadClient.
//  Singleton in liveValue — InstantShareUploadClient is compiler-verified Sendable
//  (checked). All properties are let, zero mutable state. The singleton references
//  Container.shared.appIdentityProvider() (a cross-target singleton).
//
import ComposableArchitecture
import Common
import Factory
import Foundation

@DependencyClient
struct UploadClient {
    var uploadText: @Sendable (
        _ hosts: [String],
        _ port: Int,
        _ sessionID: String,
        _ correlationID: String,
        _ text: String,
        _ peerDeviceName: String?
    ) async throws -> Void

    var uploadImage: @Sendable (
        _ hosts: [String],
        _ port: Int,
        _ sessionID: String,
        _ correlationID: String,
        _ fileURL: URL,
        _ contentType: String,
        _ filename: String?,
        _ peerDeviceName: String?
    ) async throws -> Void

    var uploadImages: @Sendable (
        _ hosts: [String],
        _ port: Int,
        _ sessionID: String,
        _ correlationID: String,
        _ urls: [(fileURL: URL, filename: String, contentType: String)],
        _ peerDeviceName: String?
    ) async throws -> Void
}

extension UploadClient: DependencyKey {
    static let liveValue = {
        let client = InstantShareUploadClient(
            appIdentityProvider: Container.shared.appIdentityProvider()
        )
        return UploadClient(
            uploadText: { try await client.uploadText(
                hosts: $0, port: $1, sessionID: $2, correlationID: $3,
                text: $4, peerDeviceName: $5
            ) },
            uploadImage: { try await client.uploadImage(
                hosts: $0, port: $1, sessionID: $2, correlationID: $3,
                fileURL: $4, contentType: $5, filename: $6, peerDeviceName: $7
            ) },
            uploadImages: { try await client.uploadImages(
                hosts: $0, port: $1, sessionID: $2, correlationID: $3,
                urls: $4, peerDeviceName: $5
            ) }
        )
    }()
}

extension DependencyValues {
    var uploadClient: UploadClient {
        get { self[UploadClient.self] }
        set { self[UploadClient.self] = newValue }
    }
}
