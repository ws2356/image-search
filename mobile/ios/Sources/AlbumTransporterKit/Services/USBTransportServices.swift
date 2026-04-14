import Foundation
@preconcurrency import Network

enum MobileTransportProtocol {
    static let schema = "dtis.mobile-transport.v1"
    static let pairingClaimOperation = "pairing.claim"
    static let transferStartOperation = "transfer.start"
    static let transferExistenceOperation = "transfer.existence"
    static let transferAssetOperation = "transfer.asset"
    static let transferCompleteOperation = "transfer.complete"
}

enum USBTransportRuntimeError: Error, Sendable {
    case invalidSuggestedPort
    case listenerStartFailed(message: String)
    case connectionUnavailable
    case sendFailed(message: String)
    case responseTimedOut(operation: String)
    case invalidEnvelope
    case invalidResponseBody

    var localizedDescription: String {
        switch self {
        case .invalidSuggestedPort:
            return "The QR payload includes an invalid USB bootstrap port."
        case .listenerStartFailed(let message):
            return "The USB WebSocket listener could not start: \(message)"
        case .connectionUnavailable:
            return "Desktop USB transport is not connected yet."
        case .sendFailed(let message):
            return "Desktop USB transport send failed: \(message)"
        case .responseTimedOut(let operation):
            return "Desktop USB transport timed out while waiting for \(operation)."
        case .invalidEnvelope:
            return "Desktop USB transport returned an invalid envelope."
        case .invalidResponseBody:
            return "Desktop USB transport returned an invalid response body."
        }
    }
}

struct USBTransportRuntimeResponse: Sendable {
    let statusCode: Int
    let bodyData: Data
}

private struct USBTransportEnvelopeResponse: Sendable {
    let requestID: String
    let statusCode: Int
    let bodyData: Data
}

actor USBWebSocketTransportRuntime {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var isActiveConnectionReady = false
    private var bootstrapSessionID: String?
    private var bootstrapOneTimePasscode: String?
    private var bootstrapPort: Int?
    private var pendingResponses: [String: CheckedContinuation<USBTransportRuntimeResponse, Error>] = [:]
    private let queue = DispatchQueue(label: "AlbumTransporterKit.USBTransportRuntime")

    deinit {
        listener?.cancel()
        activeConnection?.cancel()
    }

    func prepareBootstrap(
        sessionID: String,
        oneTimePasscode: String,
        suggestedPort: Int
    ) throws {
        guard (1 ... 65_535).contains(suggestedPort) else {
            throw USBTransportRuntimeError.invalidSuggestedPort
        }

        if bootstrapSessionID == sessionID,
           bootstrapOneTimePasscode == oneTimePasscode,
           bootstrapPort == suggestedPort,
           listener != nil
        {
            return
        }

        resetRuntimeState()
        bootstrapSessionID = sessionID
        bootstrapOneTimePasscode = oneTimePasscode
        bootstrapPort = suggestedPort
        try startListener(on: suggestedPort)
    }

    func sendRequest<Request: Encodable & Sendable>(
        operation: String,
        bodySchema: String,
        request: Request,
        timeout: Duration = .seconds(3)
    ) async throws -> USBTransportRuntimeResponse {
        let connection = try await waitForReadyConnection(timeout: timeout)
        let requestID = UUID().uuidString.lowercased()
        let envelopeData = try encodeEnvelope(
            operation: operation,
            requestID: requestID,
            bodySchema: bodySchema,
            request: request
        )
        try await sendText(envelopeData, on: connection)
        return try await awaitResponse(
            requestID: requestID,
            operation: operation,
            timeout: timeout
        )
    }

    func reset() {
        resetRuntimeState()
    }

    private func resetRuntimeState() {
        listener?.cancel()
        listener = nil
        activeConnection?.cancel()
        activeConnection = nil
        isActiveConnectionReady = false
        bootstrapSessionID = nil
        bootstrapOneTimePasscode = nil
        bootstrapPort = nil
        failAllPendingResponses(with: USBTransportRuntimeError.connectionUnavailable)
    }

    private func startListener(on port: Int) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw USBTransportRuntimeError.invalidSuggestedPort
        }

        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        do {
            let listener = try NWListener(using: parameters, on: endpointPort)
            listener.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.acceptConnection(connection)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            throw USBTransportRuntimeError.listenerStartFailed(message: error.localizedDescription)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            listener = nil
            failAllPendingResponses(
                with: USBTransportRuntimeError.listenerStartFailed(message: error.localizedDescription)
            )
        case .cancelled:
            listener = nil
        default:
            break
        }
    }

    private func acceptConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection
        isActiveConnectionReady = false
        connection.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleConnectionState(state, for: connection)
            }
        }
        connection.start(queue: queue)
        receiveNextMessage(from: connection)
    }

    private func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection) {
        guard activeConnection === connection else {
            return
        }

        switch state {
        case .ready:
            isActiveConnectionReady = true
        case .failed(let error):
            isActiveConnectionReady = false
            activeConnection = nil
            failAllPendingResponses(with: USBTransportRuntimeError.sendFailed(message: error.localizedDescription))
        case .cancelled:
            isActiveConnectionReady = false
            activeConnection = nil
            failAllPendingResponses(with: USBTransportRuntimeError.connectionUnavailable)
        default:
            break
        }
    }

    private func receiveNextMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task {
                await self?.handleReceivedMessage(
                    on: connection,
                    data: data,
                    error: error
                )
            }
        }
    }

    private func handleReceivedMessage(
        on connection: NWConnection,
        data: Data?,
        error: NWError?
    ) {
        guard activeConnection === connection else {
            return
        }

        if let error {
            isActiveConnectionReady = false
            activeConnection = nil
            failAllPendingResponses(with: USBTransportRuntimeError.sendFailed(message: error.localizedDescription))
            return
        }

        if let data, !data.isEmpty {
            do {
                let envelopeResponse = try parseEnvelopeResponse(data)
                if let continuation = pendingResponses.removeValue(forKey: envelopeResponse.requestID) {
                    continuation.resume(
                        returning: USBTransportRuntimeResponse(
                            statusCode: envelopeResponse.statusCode,
                            bodyData: envelopeResponse.bodyData
                        )
                    )
                }
            } catch {
                // Ignore invalid or unrelated messages while keeping the connection alive.
            }
        }

        receiveNextMessage(from: connection)
    }

    private func waitForReadyConnection(timeout: Duration) async throws -> NWConnection {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let activeConnection, isActiveConnectionReady {
                return activeConnection
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw USBTransportRuntimeError.connectionUnavailable
    }

    private func sendText(_ envelopeData: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(
                identifier: "mobile-transport-\(UUID().uuidString.lowercased())",
                metadata: [metadata]
            )
            connection.send(
                content: envelopeData,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(
                            throwing: USBTransportRuntimeError.sendFailed(message: error.localizedDescription)
                        )
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            )
        }
    }

    private func awaitResponse(
        requestID: String,
        operation: String,
        timeout: Duration
    ) async throws -> USBTransportRuntimeResponse {
        try await withCheckedThrowingContinuation { continuation in
            pendingResponses[requestID] = continuation
            Task {
                try? await Task.sleep(for: timeout)
                self.timeoutPendingResponse(
                    requestID: requestID,
                    operation: operation
                )
            }
        }
    }

    private func timeoutPendingResponse(requestID: String, operation: String) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: USBTransportRuntimeError.responseTimedOut(operation: operation))
    }

    private func failAllPendingResponses(with error: Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func encodeEnvelope<Request: Encodable & Sendable>(
        operation: String,
        requestID: String,
        bodySchema: String,
        request: Request
    ) throws -> Data {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(request)
        let bodyValue = try JSONSerialization.jsonObject(with: encodedBody)
        let envelope: [String: Any] = [
            "schema": MobileTransportProtocol.schema,
            "operation": operation,
            "request_id": requestID,
            "body_schema": bodySchema,
            "body": bodyValue,
        ]
        guard JSONSerialization.isValidJSONObject(envelope) else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        return try JSONSerialization.data(withJSONObject: envelope, options: [])
    }

    private func parseEnvelopeResponse(_ data: Data) throws -> USBTransportEnvelopeResponse {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        guard envelope["schema"] as? String == MobileTransportProtocol.schema else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        guard let requestID = envelope["request_id"] as? String, !requestID.isEmpty else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        guard let statusCode = envelope["status_code"] as? Int else {
            throw USBTransportRuntimeError.invalidEnvelope
        }

        let rawBodyValue = envelope["body"] ?? [:]
        guard JSONSerialization.isValidJSONObject(rawBodyValue) else {
            throw USBTransportRuntimeError.invalidResponseBody
        }
        let bodyData = try JSONSerialization.data(withJSONObject: rawBodyValue, options: [])
        return USBTransportEnvelopeResponse(
            requestID: requestID,
            statusCode: statusCode,
            bodyData: bodyData
        )
    }
}

struct WebSocketPairingUSBBootstrapClient: PairingUSBBootstrapClient {
    let runtime: USBWebSocketTransportRuntime
    let responseTimeout: Duration

    init(
        runtime: USBWebSocketTransportRuntime,
        responseTimeout: Duration = .milliseconds(1200)
    ) {
        self.runtime = runtime
        self.responseTimeout = responseTimeout
    }

    func claimPairing(using payload: PairingQRCodePayload, request: PairingClaimRequest) async throws -> PairingClaimResponse {
        guard let suggestedUSBPort = payload.suggestedUSBPort else {
            throw PairingServiceError.transport(message: "The QR payload is missing the USB bootstrap port.")
        }

        do {
            try await runtime.prepareBootstrap(
                sessionID: payload.sessionID,
                oneTimePasscode: payload.oneTimePasscode,
                suggestedPort: suggestedUSBPort
            )
            let runtimeResponse = try await runtime.sendRequest(
                operation: MobileTransportProtocol.pairingClaimOperation,
                bodySchema: PairingProtocol.schema,
                request: request,
                timeout: responseTimeout
            )
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(
                PairingClaimResponse.self,
                from: runtimeResponse.bodyData
            )
            guard decodedResponse.schema == PairingProtocol.schema else {
                throw PairingServiceError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(runtimeResponse.statusCode) {
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
        } catch let error as USBTransportRuntimeError {
            throw PairingServiceError.transport(message: error.localizedDescription)
        } catch {
            throw PairingServiceError.transport(message: error.localizedDescription)
        }
    }
}

private struct USBTransferAssetUploadRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var assetID: String
    var assetVersion: String
    var contentSHA1: String
    var fileSize: Int
    var filename: String
    var mediaType: String
    var createdAt: Date?
    var updatedAt: Date?
    var fileDataBase64: String

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustKey = "trust_key"
        case assetID = "asset_id"
        case assetVersion = "asset_version"
        case contentSHA1 = "sha1"
        case fileSize = "file_size"
        case filename
        case mediaType = "media_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case fileDataBase64 = "file_data_base64"
    }
}

struct WebSocketMobileTransferClient: MobileTransferClient {
    let runtime: USBWebSocketTransportRuntime
    let responseTimeout: Duration

    init(
        runtime: USBWebSocketTransportRuntime,
        responseTimeout: Duration = .seconds(6)
    ) {
        self.runtime = runtime
        self.responseTimeout = responseTimeout
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        let request = TransferStartRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            totalAssets: totalAssets
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferStartOperation,
            request: request,
            responseType: TransferServerResponse.self
        )
        switch response.status {
        case .accepted:
            return
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        case .stored, .skipped, .completed:
            throw TransferClientError.rejected(message: "Desktop returned an unexpected transfer start response.")
        }
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        guard !candidates.isEmpty else {
            return [:]
        }
        let request = TransferExistenceRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            assets: candidates
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferExistenceOperation,
            request: request,
            responseType: TransferExistenceResponse.self
        )
        switch response.status {
        case .checked:
            return Dictionary(uniqueKeysWithValues: response.matches.map { ($0.assetID, $0) })
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        }
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: asset.fileURL, options: [.mappedIfSafe])
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }

        let request = USBTransferAssetUploadRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            assetID: asset.descriptor.assetID,
            assetVersion: asset.descriptor.assetVersion,
            contentSHA1: asset.contentSHA1,
            fileSize: asset.fileSize,
            filename: asset.descriptor.filename,
            mediaType: asset.descriptor.mediaType,
            createdAt: asset.descriptor.createdAt,
            updatedAt: asset.descriptor.updatedAt,
            fileDataBase64: fileData.base64EncodedString()
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferAssetOperation,
            request: request,
            responseType: TransferServerResponse.self
        )
        switch response.status {
        case .stored, .skipped:
            return response
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        case .accepted, .completed:
            throw TransferClientError.rejected(message: "Desktop returned an unexpected transfer asset response.")
        }
    }

    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse {
        let request = TransferCompleteRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            transferredCount: transferredCount,
            failedCount: failedCount
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferCompleteOperation,
            request: request,
            responseType: TransferServerResponse.self
        )
        switch response.status {
        case .completed:
            return response
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        case .accepted, .stored, .skipped:
            throw TransferClientError.rejected(message: "Desktop returned an unexpected transfer completion response.")
        }
    }

    private func sendTransferEnvelope<RequestBody: Encodable & Sendable, ResponseBody: TransferSchemaResponse>(
        operation: String,
        request: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        do {
            let runtimeResponse = try await runtime.sendRequest(
                operation: operation,
                bodySchema: TransferProtocol.schema,
                request: request,
                timeout: responseTimeout
            )
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(responseType, from: runtimeResponse.bodyData)
            guard decodedResponse.schema == TransferProtocol.schema else {
                throw TransferClientError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(runtimeResponse.statusCode) {
                return decodedResponse
            }
            throw TransferClientError.rejected(message: decodedResponse.message)
        } catch let error as TransferClientError {
            throw error
        } catch let error as USBTransportRuntimeError {
            throw TransferClientError.transport(message: error.localizedDescription)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
    }
}

struct AdaptiveMobileTransferClient: MobileTransferClient {
    let lanClient: MobileTransferClient
    let usbClient: MobileTransferClient

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        try await executeWithFallback(
            desktop: desktop,
            usbOperation: {
                try await usbClient.startSession(desktop: desktop, totalAssets: totalAssets)
            },
            lanOperation: {
                try await lanClient.startSession(desktop: desktop, totalAssets: totalAssets)
            }
        )
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        try await executeWithFallback(
            desktop: desktop,
            usbOperation: {
                try await usbClient.lookupExistingAssets(candidates, desktop: desktop)
            },
            lanOperation: {
                try await lanClient.lookupExistingAssets(candidates, desktop: desktop)
            }
        )
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        try await executeWithFallback(
            desktop: desktop,
            usbOperation: {
                try await usbClient.uploadAsset(asset, desktop: desktop)
            },
            lanOperation: {
                try await lanClient.uploadAsset(asset, desktop: desktop)
            }
        )
    }

    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse {
        try await executeWithFallback(
            desktop: desktop,
            usbOperation: {
                try await usbClient.completeSession(
                    desktop: desktop,
                    transferredCount: transferredCount,
                    failedCount: failedCount
                )
            },
            lanOperation: {
                try await lanClient.completeSession(
                    desktop: desktop,
                    transferredCount: transferredCount,
                    failedCount: failedCount
                )
            }
        )
    }

    private func executeWithFallback<Result>(
        desktop: TrustedDesktopRecord,
        usbOperation: () async throws -> Result,
        lanOperation: () async throws -> Result
    ) async throws -> Result {
        guard desktop.transport == .usb else {
            return try await lanOperation()
        }

        do {
            return try await usbOperation()
        } catch {
            return try await lanOperation()
        }
    }
}
