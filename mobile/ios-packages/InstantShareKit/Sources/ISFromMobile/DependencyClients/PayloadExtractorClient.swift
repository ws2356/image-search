//
//  PayloadExtractorClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping InstantSharePayloadExtractor.
//  Direct static method call — no instance needed.
//
import ComposableArchitecture
import Foundation

#if os(iOS)
@DependencyClient
struct PayloadExtractorClient {
    var extract: @Sendable @MainActor (_ extensionItems: [NSExtensionItem]) async throws -> [InstantSharePayloadEnvelope]
}

extension PayloadExtractorClient: DependencyKey {
    static let liveValue = PayloadExtractorClient(
        extract: { items in
            try await InstantSharePayloadExtractor.extract(from: items)
        }
    )
}

extension DependencyValues {
    var payloadExtractor: PayloadExtractorClient {
        get { self[PayloadExtractorClient.self] }
        set { self[PayloadExtractorClient.self] = newValue }
    }
}
#endif
