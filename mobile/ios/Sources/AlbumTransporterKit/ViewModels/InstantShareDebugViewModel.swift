import Combine
import Foundation
import PhotosUI
import SwiftUI

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
    @Published var sharedText: String = "Hello from iPhone!"
    @Published var selectedImageData: Data?
    @Published var selectedImageFilename: String?
    @Published var selectedImageContentType: String?
    @Published var isSessionActive: Bool = false
    @Published var showingImagePicker: Bool = false
    @Published var lastError: String?

    let service: InstantShareService

    init(service: InstantShareService) {
        self.service = service
        let sample = Self.sampleConnectionConfig()
        self.sessionID = sample.sessionID
        self.correlationID = sample.correlationID
        self.mobilePort = String(sample.mobilePort)
        self.mobileIPList = sample.mobileIPList.joined(separator: ", ")
        self.payloadClass = sample.metadata.payloadClass
        self.trustMode = sample.metadata.trustMode
    }

    var targetIntent: InstantShareTargetIntent {
        payloadClass == .text ? .clipboardOnly : .clipboardOrFile
    }

    var validationMessage: String? {
        do {
            _ = try currentConnectionConfig().validated()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    var endpointRows: [InstantShareDebugEndpointRow] {
        do {
            let config = try currentConnectionConfig().validated()
            return try [
                InstantShareDebugEndpointRow(
                    id: "trust-handshake",
                    title: "Trust handshake",
                    urls: config.endpointURLs(path: InstantShareProtocol.trustHandshakePath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "trust-apply",
                    title: "Trust apply",
                    urls: config.endpointURLs(path: InstantShareProtocol.trustApplyPath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "trust-confirm",
                    title: "Trust confirm",
                    urls: config.endpointURLs(path: InstantShareProtocol.trustConfirmPath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "payload",
                    title: payloadClass == .text ? "Text payload" : "Image payload",
                    urls: config.endpointURLs(path: activePayloadPath).map(\.absoluteString)
                ),
                InstantShareDebugEndpointRow(
                    id: "delivery-result",
                    title: "Delivery result",
                    urls: config.endpointURLs(path: InstantShareProtocol.deliveryResultPath).map(\.absoluteString)
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

    // MARK: - Actions

    func loadSampleConfiguration() {
        let sample = Self.sampleConnectionConfig(payloadClass: payloadClass, trustMode: trustMode)
        sessionID = sample.sessionID
        correlationID = sample.correlationID
        mobilePort = String(sample.mobilePort)
        mobileIPList = sample.mobileIPList.joined(separator: ", ")
    }

    func startDiscovery() {
        service.startDiscovery()
    }

    func stopDiscovery() {
        service.stopDiscovery()
    }

    func selectPC(_ pc: InstantShareDiscoveredPC) {
        service.selectPC(pc)
    }

    func setSharedText(_ text: String) {
        service.setSharedText(text)
    }

    func setSharedImage(data: Data, filename: String, contentType: String) {
        service.setSharedImage(data: data, filename: filename, contentType: contentType)
    }

    func startSession() async {
        do {
            let config = try currentConnectionConfig().validated()
            service.setSharedText(sharedText)
            if let imageData = selectedImageData, let filename = selectedImageFilename, let contentType = selectedImageContentType {
                service.setSharedImage(data: imageData, filename: filename, contentType: contentType)
            }
            try await service.startSession(connectionConfig: config)
            isSessionActive = true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func stopSession() {
        service.stopSession()
        isSessionActive = false
    }

    func handleImagePicked(_ result: PHPickerResult) {
        let provider = result.itemProvider
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                guard let image = image as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.85) else { return }
                let filename = "shared-photo-\(Int(Date().timeIntervalSince1970)).jpg"
                Task { @MainActor in
                    self?.selectedImageData = data
                    self?.selectedImageFilename = filename
                    self?.selectedImageContentType = "image/jpeg"
                }
            }
        }
    }

    // MARK: - Helpers

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

    static func sampleConnectionConfig(
        payloadClass: InstantSharePayloadClass = .text,
        trustMode: InstantShareTrustMode = .firstShare
    ) -> InstantShareConnectionConfig {
        InstantShareConnectionConfig(
            sessionID: UUID().uuidString.lowercased(),
            mobilePort: 8443,
            mobileIPList: ["127.0.0.1"],
            correlationID: UUID().uuidString.lowercased(),
            metadata: InstantShareMetadata(
                payloadClass: payloadClass,
                targetIntent: payloadClass == .text ? .clipboardOnly : .clipboardOrFile,
                trustMode: trustMode
            )
        )
    }
}
