import Foundation

struct InstantShareDebugEndpointRow: Identifiable, Equatable {
    let id: String
    let title: String
    let urls: [String]
}

struct InstantShareDebugProtocolRow: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

@MainActor
final class InstantShareDebugViewModel: ObservableObject {
    @Published var sessionID: String
    @Published var correlationID: String
    @Published var mobilePort: String
    @Published var mobileIPList: String
    @Published var payloadClass: InstantSharePayloadClass
    @Published var trustMode: InstantShareTrustMode

    init() {
        let sampleConfiguration = Self.sampleConnectionConfig()
        sessionID = sampleConfiguration.sessionID
        correlationID = sampleConfiguration.correlationID
        mobilePort = String(sampleConfiguration.mobilePort)
        mobileIPList = sampleConfiguration.mobileIPList.joined(separator: ", ")
        payloadClass = sampleConfiguration.metadata.payloadClass
        trustMode = sampleConfiguration.metadata.trustMode
    }

    var targetIntent: InstantShareTargetIntent {
        payloadClass == .text ? .clipboardOnly : .clipboardOrFile
    }

    var validationMessage: String? {
        do {
            _ = try currentConnectionConfig().validated()
            return nil
        } catch {
            return Self.render(error: error)
        }
    }

    var endpointRows: [InstantShareDebugEndpointRow] {
        do {
            let connectionConfig = try currentConnectionConfig().validated()
            return try [
                InstantShareDebugEndpointRow(
                    id: "trust-handshake",
                    title: "Trust handshake",
                    urls: connectionConfig.endpointURLs(path: InstantShareProtocol.trustHandshakePath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "trust-apply",
                    title: "Trust apply",
                    urls: connectionConfig.endpointURLs(path: InstantShareProtocol.trustApplyPath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "trust-confirm",
                    title: "Trust confirm",
                    urls: connectionConfig.endpointURLs(path: InstantShareProtocol.trustConfirmPath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "payload",
                    title: payloadClass == .text ? "Text payload" : "Image payload",
                    urls: connectionConfig.endpointURLs(path: activePayloadPath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "delivery-result",
                    title: "Delivery result",
                    urls: connectionConfig.endpointURLs(path: InstantShareProtocol.deliveryResultPath).map(\.absoluteString)
                ),
            ]
        } catch {
            return []
        }
    }

    var protocolRows: [InstantShareDebugProtocolRow] {
        [
            InstantShareDebugProtocolRow(id: "schema", title: "Schema", value: InstantShareProtocol.schema),
            InstantShareDebugProtocolRow(id: "flow-id", title: "Flow ID", value: InstantShareProtocol.flowID),
            InstantShareDebugProtocolRow(id: "api-prefix", title: "API Prefix", value: InstantShareProtocol.apiPrefix),
            InstantShareDebugProtocolRow(id: "target-intent", title: "Target Intent", value: targetIntent.rawValue),
            InstantShareDebugProtocolRow(id: "trust-envelope", title: "Trust Envelope", value: InstantShareProtocol.trustEnvelopeSchema),
        ]
    }

    func loadSampleConfiguration() {
        let sampleConfiguration = Self.sampleConnectionConfig(
            payloadClass: payloadClass,
            trustMode: trustMode
        )
        sessionID = sampleConfiguration.sessionID
        correlationID = sampleConfiguration.correlationID
        mobilePort = String(sampleConfiguration.mobilePort)
        mobileIPList = sampleConfiguration.mobileIPList.joined(separator: ", ")
        payloadClass = sampleConfiguration.metadata.payloadClass
        trustMode = sampleConfiguration.metadata.trustMode
    }

    private var activePayloadPath: String {
        payloadClass == .text ? InstantShareProtocol.payloadTextPath : InstantShareProtocol.payloadImagePath
    }

    private func currentConnectionConfig() throws -> InstantShareConnectionConfig {
        guard let parsedPort = Int(mobilePort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw InstantShareServiceError.invalidPort
        }
        return InstantShareConnectionConfig(
            sessionID: sessionID.trimmingCharacters(in: .whitespacesAndNewlines),
            mobilePort: parsedPort,
            mobileIPList: parsedIPList(),
            correlationID: correlationID.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: InstantShareMetadata(
                payloadClass: payloadClass,
                targetIntent: targetIntent,
                trustMode: trustMode
            )
        )
    }

    private func parsedIPList() -> [String] {
        mobileIPList
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func render(error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }

    private static func sampleConnectionConfig(
        payloadClass: InstantSharePayloadClass = .text,
        trustMode: InstantShareTrustMode = .firstShare
    ) -> InstantShareConnectionConfig {
        InstantShareConnectionConfig(
            sessionID: "83a637dd-e57a-4e71-a2f3-34db1d0b2811",
            mobilePort: 8443,
            mobileIPList: ["192.168.1.20", "fe80::10"],
            correlationID: "f7f0ff11-1bdf-472f-aaf9-801c4b0f31d4",
            metadata: InstantShareMetadata(
                payloadClass: payloadClass,
                targetIntent: payloadClass == .text ? .clipboardOnly : .clipboardOrFile,
                trustMode: trustMode
            )
        )
    }
}