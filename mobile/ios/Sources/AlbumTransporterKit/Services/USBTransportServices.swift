import CryptoKit
import Foundation
import OSLog
@preconcurrency import Network

enum MobileTransportProtocol {
    static let schema = "dtis.mobile-transport.v1"
    static let authChallengeOperation = "transport.auth.challenge"
    static let authChallengeBodySchema = "dtis.mobile-pairing.v1"
    static let pairingClaimOperation = "pairing.claim"
    static let pairingStateOperation = "pairing.state"
    static let pairingCapabilityExchangeOperation = "pairing.capabilities"
    static let capabilityExchangeOperation = "capabilities.exchange"
    static let updatePromptOperation = "update.prompt"
    static let transferStartOperation = "transfer.start"
    static let transferExistenceOperation = "transfer.existence"
    static let transferAssetOperation = "transfer.asset"
    static let transferCompleteOperation = "transfer.complete"
    static let transferAssetChunkSizeBytes = TransferAssetStreamProtocol.chunkSizeBytes
    static let transferAssetStreamStateField = "stream_state"
    static let transferAssetStreamStateStart = "start"
    static let transferAssetStreamStateComplete = "complete"
    static let transferAssetBinaryFrameVersion: UInt8 = 1
    static let transferAssetBinaryFrameRequestIDLength = 36
    static let transferAssetBinaryFrameHeaderLength = 42
}

func buildDesktopUSBAuthDigest(oneTimePasscode: String, rand: String) -> String {
    let digest = SHA256.hash(data: Data((oneTimePasscode + rand).utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
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

private enum USBTransportDebugLogger {
    private static let logger = Logger(
        subsystem: "AlbumTransporterKit.MobileFolder",
        category: "USBTransport"
    )

    static func debug(_ message: String) {
        #if DEBUG
        return
        #endif
        logger.debug("\(message, privacy: .public)")
        appendToDiagnosticsFile(level: "DEBUG", message: message)
    }

    static func info(_ message: String) {
        #if DEBUG
        return
        #endif
        logger.info("\(message, privacy: .public)")
        appendToDiagnosticsFile(level: "INFO", message: message)
    }

    static func warning(_ message: String) {
        #if DEBUG
        return
        #endif
        logger.warning("\(message, privacy: .public)")
        appendToDiagnosticsFile(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        #if DEBUG
        return
        #endif
        logger.error("\(message, privacy: .public)")
        appendToDiagnosticsFile(level: "ERROR", message: message)
    }

    static func describe(_ error: Error) -> String {
        if let transferError = error as? TransferClientError {
            return "TransferClientError: \(transferError.message)"
        }
        if let runtimeError = error as? USBTransportRuntimeError {
            return "USBTransportRuntimeError: \(runtimeError.localizedDescription)"
        }
        let nsError = error as NSError
        return "\(type(of: error)): \(error.localizedDescription) [\(nsError.domain)#\(nsError.code)]"
    }

    private static func appendToDiagnosticsFile(level: String, message: String) {
        let sanitizedMessage = message.replacingOccurrences(of: "\n", with: "\\n")
        let line = "\(Date().formatted(.iso8601)) [\(level)] \(sanitizedMessage)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let fileURL = try diagnosticsFileURL()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer {
                    try? fileHandle.close()
                }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            logger.error("USB debug file write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func diagnosticsFileURL() throws -> URL {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupportURL.appendingPathComponent("usb_transport_debug.log")
    }
}

private func nanoseconds(from seconds: TimeInterval) -> UInt64 {
    let clampedSeconds = max(seconds, 0)
    let nanoseconds = clampedSeconds * 1_000_000_000
    if nanoseconds >= Double(UInt64.max) {
        return UInt64.max
    }
    return UInt64(nanoseconds.rounded())
}

private func normalizedCapabilityExchangeFlags(_ capabilityFlags: [String: Int]) -> [String: Int] {
    var normalizedFlags: [String: Int] = [:]
    for (capabilityName, capabilityValue) in capabilityFlags {
        let trimmedCapabilityName = capabilityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCapabilityName.isEmpty, capabilityValue == 1 else {
            continue
        }
        normalizedFlags[trimmedCapabilityName] = 1
    }
    return normalizedFlags
}

actor USBWebSocketTransportRuntime {
    private static let bootstrapPortFallbackWindow = 20
    private static let forcedRestartCooldownSeconds: TimeInterval = 1.5
    private var listener: NWListener?
    private var activeListenerID: UUID?
    private var activeConnection: NWConnection?
    private var isActiveConnectionReady = false
    private var isConnectionAuthenticated = false
    private var bootstrapSessionID: String?
    private var bootstrapOneTimePasscode: String?
    private var bootstrapPort: Int?
    private var activeListenerPort: Int?
    private var lastForcedRestartAt: Date?
    private var pendingResponses: [String: CheckedContinuation<USBTransportRuntimeResponse, Error>] = [:]
    private var activeStreamingRequestIDs: Set<String> = []
    private let queue = DispatchQueue(label: "AlbumTransporterKit.USBTransportRuntime")

    deinit {
        listener?.cancel()
        activeConnection?.cancel()
    }

    func prepareBootstrap(
        sessionID: String,
        oneTimePasscode: String,
        suggestedPort: Int,
        forceRestart: Bool = false
    ) throws {
        guard (1 ... 65_535).contains(suggestedPort) else {
            throw USBTransportRuntimeError.invalidSuggestedPort
        }

        USBTransportDebugLogger.info(
            "USBRuntime/prepareBootstrap session_id=\(sessionID) suggested_port=\(suggestedPort) force_restart=\(forceRestart)"
        )

        let hasMatchingBootstrap = bootstrapSessionID == sessionID
            && bootstrapOneTimePasscode == oneTimePasscode
            && bootstrapPort == suggestedPort

        if forceRestart,
           hasMatchingBootstrap,
           listener != nil,
           let lastForcedRestartAt,
           Date().timeIntervalSince(lastForcedRestartAt) < Self.forcedRestartCooldownSeconds
        {
            USBTransportDebugLogger.debug(
                "USBRuntime/prepareBootstrap_force_restart_suppressed "
                    + "session_id=\(sessionID) suggested_port=\(suggestedPort)"
            )
            return
        }

        if !forceRestart,
           hasMatchingBootstrap,
           listener != nil
        {
            USBTransportDebugLogger.debug(
                "USBRuntime/prepareBootstrap_reused session_id=\(sessionID) suggested_port=\(suggestedPort)"
            )
            return
        }

        if forceRestart {
            lastForcedRestartAt = Date()
        }
        resetRuntimeState()
        bootstrapSessionID = sessionID
        bootstrapOneTimePasscode = oneTimePasscode
        bootstrapPort = suggestedPort
        try startListener(near: suggestedPort)
    }

    func sendRequest<Request: Encodable & Sendable>(
        operation: String,
        bodySchema: String,
        request: Request,
        additionalBodyFields: [String: Any] = [:],
        timeout: TimeInterval = 3
    ) async throws -> USBTransportRuntimeResponse {
        let connection = try await waitForReadyConnection(timeout: timeout)
        let requestID = UUID().uuidString.lowercased()
        let envelopeData = try encodeEnvelope(
            operation: operation,
            requestID: requestID,
            bodySchema: bodySchema,
            request: request,
            additionalBodyFields: additionalBodyFields
        )
        try await sendText(
            envelopeData,
            on: connection,
            timeout: timeout
        )
        return try await awaitResponse(
            requestID: requestID,
            operation: operation,
            timeout: timeout
        )
    }

    func beginStreamingRequest<Request: Encodable & Sendable>(
        operation: String,
        bodySchema: String,
        request: Request,
        chunkSizeBytes: Int,
        additionalBodyFields: [String: Any] = [:],
        timeout: TimeInterval = 3
    ) async throws -> String {
        let connection = try await waitForReadyConnection(timeout: timeout)
        let requestID = UUID().uuidString.lowercased()
        var bodyFields = additionalBodyFields
        bodyFields[MobileTransportProtocol.transferAssetStreamStateField] = MobileTransportProtocol.transferAssetStreamStateStart
        bodyFields["chunk_size"] = chunkSizeBytes
        let envelopeData = try encodeEnvelope(
            operation: operation,
            requestID: requestID,
            bodySchema: bodySchema,
            request: request,
            additionalBodyFields: bodyFields
        )
        try await sendText(
            envelopeData,
            on: connection,
            timeout: timeout
        )
        activeStreamingRequestIDs.insert(requestID)
        return requestID
    }

    func sendStreamingBinaryChunk(
        requestID: String,
        chunk: Data,
        timeout: TimeInterval = 3
    ) async throws {
        guard activeStreamingRequestIDs.contains(requestID) else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        guard chunk.count <= MobileTransportProtocol.transferAssetChunkSizeBytes + MobilePayloadEncryptionProtocol.binaryChunkOverheadBytes else {
            throw USBTransportRuntimeError.sendFailed(
                message: "Desktop USB transport chunk exceeded the maximum \(MobileTransportProtocol.transferAssetChunkSizeBytes)-byte limit."
            )
        }
        let connection = try await waitForReadyConnection(timeout: timeout)
        let framedChunk = try encodeTransferAssetBinaryFrame(
            requestID: requestID,
            chunk: chunk
        )
        try await sendBinary(
            framedChunk,
            on: connection,
            timeout: timeout
        )
    }

    func finishStreamingRequest(
        operation: String,
        requestID: String,
        timeout: TimeInterval = 3
    ) async throws -> USBTransportRuntimeResponse {
        guard activeStreamingRequestIDs.contains(requestID) else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        let connection = try await waitForReadyConnection(timeout: timeout)
        let completionEnvelopeData = try encodeEnvelope(
            operation: operation,
            requestID: requestID,
            bodySchema: TransferProtocol.schema,
            rawBody: [
                MobileTransportProtocol.transferAssetStreamStateField: MobileTransportProtocol.transferAssetStreamStateComplete,
            ]
        )
        try await sendText(
            completionEnvelopeData,
            on: connection,
            timeout: timeout
        )
        defer {
            activeStreamingRequestIDs.remove(requestID)
        }
        return try await awaitResponse(
            requestID: requestID,
            operation: operation,
            timeout: timeout
        )
    }

    func abortStreamingRequest(requestID: String) {
        activeStreamingRequestIDs.remove(requestID)
    }

    func reset() {
        resetRuntimeState()
    }

    func isConnected() -> Bool {
        activeConnection != nil && isActiveConnectionReady && isConnectionAuthenticated
    }

    func hasPreparedBootstrap(sessionID: String, suggestedPort: Int) -> Bool {
        bootstrapSessionID == sessionID && bootstrapPort == suggestedPort && listener != nil
    }

    func listenerPort() -> Int? {
        activeListenerPort
    }

    private func resetRuntimeState() {
        listener?.cancel()
        listener = nil
        activeListenerID = nil
        activeConnection?.cancel()
        activeConnection = nil
        isActiveConnectionReady = false
        isConnectionAuthenticated = false
        activeStreamingRequestIDs.removeAll(keepingCapacity: false)
        bootstrapSessionID = nil
        bootstrapOneTimePasscode = nil
        bootstrapPort = nil
        activeListenerPort = nil
        failAllPendingResponses(with: USBTransportRuntimeError.connectionUnavailable)
    }

    private func startListener(near suggestedPort: Int) throws {
        var lastError: USBTransportRuntimeError?
        for candidatePort in candidateBootstrapPorts(around: suggestedPort) {
            do {
                try startListener(on: candidatePort)
                activeListenerPort = candidatePort
                USBTransportDebugLogger.info(
                    "USBRuntime/listener_started requested_port=\(suggestedPort) active_port=\(candidatePort)"
                )
                return
            } catch let error as USBTransportRuntimeError {
                lastError = error
                USBTransportDebugLogger.warning(
                    "USBRuntime/listener_candidate_failed requested_port=\(suggestedPort) candidate_port=\(candidatePort) error=\(error.localizedDescription)"
                )
                continue
            }
        }
        throw lastError ?? USBTransportRuntimeError.listenerStartFailed(
            message: "Desktop USB transport listener could not bind any bootstrap port candidates."
        )
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
            let listenerID = UUID()
            listener.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleListenerState(state, listenerID: listenerID)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.acceptConnection(connection, listenerID: listenerID)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            activeListenerID = listenerID
        } catch {
            throw USBTransportRuntimeError.listenerStartFailed(message: error.localizedDescription)
        }
    }

    private func candidateBootstrapPorts(around suggestedPort: Int) -> [Int] {
        var candidatePorts: [Int] = [suggestedPort]
        for offset in 1 ... Self.bootstrapPortFallbackWindow {
            let higherPort = suggestedPort + offset
            if higherPort <= 65_535 {
                candidatePorts.append(higherPort)
            }
            let lowerPort = suggestedPort - offset
            if lowerPort >= 1 {
                candidatePorts.append(lowerPort)
            }
        }
        return candidatePorts
    }

    private func handleListenerState(_ state: NWListener.State, listenerID: UUID) {
        guard activeListenerID == listenerID else {
            USBTransportDebugLogger.debug("USBRuntime/listener_state_ignored_stale \(String(describing: state))")
            return
        }
        USBTransportDebugLogger.debug("USBRuntime/listener_state \(String(describing: state))")
        switch state {
        case .failed(let error):
            listener = nil
            activeListenerID = nil
            activeListenerPort = nil
            failAllPendingResponses(
                with: USBTransportRuntimeError.listenerStartFailed(message: error.localizedDescription)
            )
        case .cancelled:
            listener = nil
            activeListenerID = nil
            activeListenerPort = nil
        default:
            break
        }
    }

    private func acceptConnection(_ connection: NWConnection, listenerID: UUID) {
        guard activeListenerID == listenerID else {
            USBTransportDebugLogger.debug("USBRuntime/accept_connection_ignored_stale_listener")
            connection.cancel()
            return
        }
        USBTransportDebugLogger.info("USBRuntime/accept_connection")
        activeConnection?.cancel()
        activeConnection = connection
        isActiveConnectionReady = false
        isConnectionAuthenticated = false
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
            USBTransportDebugLogger.info("USBRuntime/connection_ready authenticated=\(isConnectionAuthenticated)")
        case .failed(let error):
            isActiveConnectionReady = false
            isConnectionAuthenticated = false
            activeConnection = nil
            activeStreamingRequestIDs.removeAll(keepingCapacity: false)
            failAllPendingResponses(with: USBTransportRuntimeError.sendFailed(message: error.localizedDescription))
            USBTransportDebugLogger.warning("USBRuntime/connection_failed error=\(error.localizedDescription)")
        case .cancelled:
            isActiveConnectionReady = false
            isConnectionAuthenticated = false
            activeConnection = nil
            activeStreamingRequestIDs.removeAll(keepingCapacity: false)
            failAllPendingResponses(with: USBTransportRuntimeError.connectionUnavailable)
            USBTransportDebugLogger.warning("USBRuntime/connection_cancelled")
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
    ) async {
        guard activeConnection === connection else {
            return
        }

        if let error {
            isActiveConnectionReady = false
            isConnectionAuthenticated = false
            activeConnection = nil
            activeStreamingRequestIDs.removeAll(keepingCapacity: false)
            failAllPendingResponses(with: USBTransportRuntimeError.sendFailed(message: error.localizedDescription))
            USBTransportDebugLogger.warning("USBRuntime/receive_error error=\(error.localizedDescription)")
            return
        }

        if let data, !data.isEmpty {
            do {
                if try await handleDesktopAuthChallengeIfNeeded(
                    on: connection,
                    data: data
                ) {
                    receiveNextMessage(from: connection)
                    return
                }
            } catch {
                USBTransportDebugLogger.warning(
                    "USBRuntime/auth_challenge_failure error=\(USBTransportDebugLogger.describe(error))"
                )
                isConnectionAuthenticated = false
                activeStreamingRequestIDs.removeAll(keepingCapacity: false)
            }
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

    private func handleDesktopAuthChallengeIfNeeded(
        on connection: NWConnection,
        data: Data
    ) async throws -> Bool {
        guard let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        guard envelope["schema"] as? String == MobileTransportProtocol.schema else {
            return false
        }
        guard envelope["operation"] as? String == MobileTransportProtocol.authChallengeOperation else {
            return false
        }
        guard let requestID = envelope["request_id"] as? String, !requestID.isEmpty else {
            return false
        }
        guard let body = envelope["body"] as? [String: Any] else {
            return false
        }

        let challengeResult = evaluateDesktopAuthChallenge(body: body)
        let responseBody: [String: Any]
        let statusCode: Int
            if challengeResult.accepted {
                statusCode = 200
                responseBody = [
                    "schema": MobileTransportProtocol.schema,
                    "status": "accepted",
                    "proof": challengeResult.proof,
                ]
                isConnectionAuthenticated = true
                USBTransportDebugLogger.info("USBRuntime/auth_challenge_accepted session_id=\(sidOrUnknown(body))")
            } else {
                statusCode = 401
                responseBody = [
                    "schema": MobileTransportProtocol.schema,
                    "status": "rejected",
                    "message": challengeResult.message,
                ]
                isConnectionAuthenticated = false
                activeStreamingRequestIDs.removeAll(keepingCapacity: false)
                failAllPendingResponses(with: USBTransportRuntimeError.connectionUnavailable)
                USBTransportDebugLogger.warning(
                    "USBRuntime/auth_challenge_rejected session_id=\(sidOrUnknown(body)) message=\(challengeResult.message)"
                )
            }

        let responseEnvelope = [
            "schema": MobileTransportProtocol.schema,
            "request_id": requestID,
            "status_code": statusCode,
            "body": responseBody,
        ] as [String: Any]
        guard JSONSerialization.isValidJSONObject(responseEnvelope) else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        let responseData = try JSONSerialization.data(withJSONObject: responseEnvelope, options: [])
        try await sendText(
            responseData,
            on: connection,
            timeout: 1
        )
        return true
    }

    private func evaluateDesktopAuthChallenge(
        body: [String: Any]
    ) -> (accepted: Bool, proof: String, message: String) {
        guard
            let sid = body["sid"] as? String,
            !sid.isEmpty,
            let rand = body["rand"] as? String,
            !rand.isEmpty
        else {
            return (
                accepted: false,
                proof: "",
                message: "Desktop challenge payload is missing required fields."
            )
        }
        guard let bootstrapSessionID, sid == bootstrapSessionID else {
            return (
                accepted: false,
                proof: "",
                message: "Desktop challenge session id does not match the active QR bootstrap session."
            )
        }
        guard let bootstrapOneTimePasscode else {
            return (
                accepted: false,
                proof: "",
                message: "Mobile runtime is missing bootstrap auth material."
            )
        }

        let expectedDigest = buildDesktopUSBAuthDigest(
            oneTimePasscode: bootstrapOneTimePasscode,
            rand: rand
        )
        return (
            accepted: true,
            proof: expectedDigest,
            message: "accepted"
        )
    }

    private func encodeTransferAssetBinaryFrame(
        requestID: String,
        chunk: Data
    ) throws -> Data {
        guard requestID.utf8.count == MobileTransportProtocol.transferAssetBinaryFrameRequestIDLength else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        guard chunk.count <= MobileTransportProtocol.transferAssetChunkSizeBytes + MobilePayloadEncryptionProtocol.binaryChunkOverheadBytes else {
            throw USBTransportRuntimeError.sendFailed(
                message: "Desktop USB transport chunk exceeded the maximum \(MobileTransportProtocol.transferAssetChunkSizeBytes)-byte limit."
            )
        }
        guard chunk.count <= Int(UInt32.max) else {
            throw USBTransportRuntimeError.sendFailed(
                message: "Desktop USB transport chunk length exceeded framing limits."
            )
        }

        var header = Data(capacity: MobileTransportProtocol.transferAssetBinaryFrameHeaderLength)
        header.append(MobileTransportProtocol.transferAssetBinaryFrameVersion)
        header.append(contentsOf: requestID.utf8)

        var payloadLength = UInt32(chunk.count).bigEndian
        withUnsafeBytes(of: &payloadLength) { buffer in
            header.append(contentsOf: buffer)
        }

        header.append(0) // Reserved flags byte.
        header.append(chunk)
        return header
    }

    private func waitForReadyConnection(timeout: TimeInterval) async throws -> NWConnection {
        let deadline = Date().timeIntervalSince1970 + max(timeout, 0)
        while Date().timeIntervalSince1970 < deadline {
            if let activeConnection, isActiveConnectionReady, isConnectionAuthenticated {
                return activeConnection
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        USBTransportDebugLogger.warning(
            "USBRuntime/waitForReadyConnection_timeout timeout_seconds=\(timeout) active_listener_port=\(activeListenerPort ?? -1) is_ready=\(isActiveConnectionReady) authenticated=\(isConnectionAuthenticated)"
        )
        throw USBTransportRuntimeError.connectionUnavailable
    }

    private func sidOrUnknown(_ body: [String: Any]) -> String {
        (body["sid"] as? String) ?? "-"
    }

    private func sendText(
        _ envelopeData: Data,
        on connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        try await sendWebSocketMessage(
            envelopeData,
            opcode: .text,
            identifierPrefix: "mobile-transport",
            on: connection,
            timeout: timeout
        )
    }

    private func sendBinary(
        _ data: Data,
        on connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        try await sendWebSocketMessage(
            data,
            opcode: .binary,
            identifierPrefix: "mobile-transport-binary",
            on: connection,
            timeout: timeout
        )
    }

    private func sendWebSocketMessage(
        _ data: Data,
        opcode: NWProtocolWebSocket.Opcode,
        identifierPrefix: String,
        on connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ result: Result<Void, Error>) {
                lock.lock()
                guard !resumed else {
                    lock.unlock()
                    return
                }
                resumed = true
                lock.unlock()
                continuation.resume(with: result)
            }

            let timeoutSeconds = max(timeout, 0.001)
            let timeoutWorkItem = DispatchWorkItem {
                resumeOnce(
                    .failure(
                        USBTransportRuntimeError.sendFailed(
                            message: "Desktop USB transport send timed out."
                        )
                    )
                )
            }
            queue.asyncAfter(
                deadline: .now() + max(timeoutSeconds, 0.001),
                execute: timeoutWorkItem
            )

            let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
            let context = NWConnection.ContentContext(
                identifier: "\(identifierPrefix)-\(UUID().uuidString.lowercased())",
                metadata: [metadata]
            )
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    timeoutWorkItem.cancel()
                    if let error {
                        resumeOnce(
                            .failure(
                                USBTransportRuntimeError.sendFailed(
                                    message: error.localizedDescription
                                )
                            )
                        )
                    } else {
                        resumeOnce(.success(()))
                    }
                }
            )
        }
    }

    private func awaitResponse(
        requestID: String,
        operation: String,
        timeout: TimeInterval
    ) async throws -> USBTransportRuntimeResponse {
        try await withCheckedThrowingContinuation { continuation in
            pendingResponses[requestID] = continuation
            Task {
                try? await Task.sleep(nanoseconds: nanoseconds(from: timeout))
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
        request: Request,
        additionalBodyFields: [String: Any] = [:]
    ) throws -> Data {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(request)
        guard var bodyValue = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] else {
            throw USBTransportRuntimeError.invalidEnvelope
        }
        for (key, value) in additionalBodyFields {
            bodyValue[key] = value
        }
        return try encodeEnvelope(
            operation: operation,
            requestID: requestID,
            bodySchema: bodySchema,
            rawBody: bodyValue
        )
    }

    private func encodeEnvelope(
        operation: String,
        requestID: String,
        bodySchema: String,
        rawBody: [String: Any]
    ) throws -> Data {
        let envelope: [String: Any] = [
            "schema": MobileTransportProtocol.schema,
            "operation": operation,
            "request_id": requestID,
            "body_schema": bodySchema,
            "body": rawBody,
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
    let telemetryClient: TelemetryClient
    let responseTimeout: TimeInterval

    init(
        runtime: USBWebSocketTransportRuntime,
        telemetryClient: TelemetryClient = NoOpTelemetryClient(),
        responseTimeout: TimeInterval = 1.2
    ) {
        self.runtime = runtime
        self.telemetryClient = telemetryClient
        self.responseTimeout = responseTimeout
    }

    func exchangePairingCapabilities(
        using payload: PairingQRCodePayload,
        request: PairingCapabilityExchangeRequest
    ) async throws -> PairingCapabilityExchangeResponse {
        try await sendPairingRequest(
            using: payload,
            operation: MobileTransportProtocol.pairingCapabilityExchangeOperation,
            request: request,
            bodySchema: PairingCapabilityExchangeProtocol.schema,
            responseType: PairingCapabilityExchangeResponse.self,
            expectedSchema: PairingCapabilityExchangeProtocol.schema
        )
    }

    func claimPairing(
        using payload: PairingQRCodePayload,
        request: PairingClaimRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        try await sendPairingRequest(
            using: payload,
            operation: MobileTransportProtocol.pairingClaimOperation,
            request: request,
            bodySchema: PairingProtocol.schema,
            responseType: PairingClaimResponse.self,
            expectedSchema: PairingProtocol.schema,
            encryptionTrustKeyBase64: encryptionTrustKeyBase64,
            encryptionSessionID: request.sessionID,
            encryptionPlatform: request.platform
        )
    }

    func fetchPairingState(
        using payload: PairingQRCodePayload,
        request: PairingStateRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        try await sendPairingRequest(
            using: payload,
            operation: MobileTransportProtocol.pairingStateOperation,
            request: request,
            bodySchema: PairingProtocol.schema,
            responseType: PairingClaimResponse.self,
            expectedSchema: PairingProtocol.schema,
            encryptionTrustKeyBase64: encryptionTrustKeyBase64,
            encryptionSessionID: request.sessionID
        )
    }

    func prepareUSBTransportIfNeeded(using payload: PairingQRCodePayload) async throws {
        guard let suggestedUSBPort = payload.suggestedUSBPort else {
            throw PairingServiceError.transport(message: "The QR payload is missing the USB bootstrap port.")
        }
        let shouldForceRestart = !(await runtime.isConnected())
        USBTransportDebugLogger.info(
            "PairingUSB/prepare session_id=\(payload.sessionID) suggested_port=\(suggestedUSBPort) force_restart=\(shouldForceRestart)"
        )
        try await runtime.prepareBootstrap(
            sessionID: payload.sessionID,
            oneTimePasscode: payload.oneTimePasscode,
            suggestedPort: suggestedUSBPort,
            forceRestart: shouldForceRestart
        )
    }

    private func sendPairingRequest<RequestBody: Encodable & Sendable, ResponseBody: Decodable & PairingSchemaResponse>(
        using payload: PairingQRCodePayload,
        operation: String,
        request: RequestBody,
        bodySchema: String,
        responseType: ResponseBody.Type,
        expectedSchema: String,
        encryptionTrustKeyBase64: String? = nil,
        encryptionSessionID: String? = nil,
        encryptionPlatform: String? = nil
    ) async throws -> ResponseBody {
        do {
            try await prepareUSBTransportIfNeeded(using: payload)
            let additionalFields = traceContextPayloadFields(await telemetryClient.currentTraceContext())
            let runtimeResponse: USBTransportRuntimeResponse
            if let encryptionTrustKeyBase64 {
                guard let encryptionSessionID else {
                    throw PairingServiceError.transport(
                        message: "Desktop USB pairing encryption is missing session context."
                    )
                }
                let encryptedRequest = try encryptedPairingRequest(
                    request,
                    trustKeyBase64: encryptionTrustKeyBase64,
                    sessionID: encryptionSessionID,
                    platform: encryptionPlatform
                )
                runtimeResponse = try await runtime.sendRequest(
                    operation: operation,
                    bodySchema: bodySchema,
                    request: encryptedRequest,
                    additionalBodyFields: additionalFields,
                    timeout: responseTimeout
                )
            } else {
                runtimeResponse = try await runtime.sendRequest(
                    operation: operation,
                    bodySchema: bodySchema,
                    request: request,
                    additionalBodyFields: additionalFields,
                    timeout: responseTimeout
                )
            }
            let responseData = try decodePairingResponsePayloadData(
                runtimeResponse.bodyData,
                encryptionTrustKeyBase64: encryptionTrustKeyBase64
            )
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(
                responseType,
                from: responseData
            )
            guard decodedResponse.schema == expectedSchema else {
                throw PairingServiceError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(runtimeResponse.statusCode) {
                return decodedResponse
            }
            if let pairingResponse = decodedResponse as? PairingClaimResponse {
                switch pairingResponse.backupState {
                case .pairingExpired:
                    throw PairingServiceError.expired(message: pairingResponse.message)
                case .pairingCompleted:
                    throw PairingServiceError.invalidAcceptedResponse
                case .pendingPairing, .pairingMismatched, .pairingStopped:
                    throw PairingServiceError.rejected(message: pairingResponse.message)
                }
            }
            throw PairingServiceError.rejected(message: decodedResponse.message)
        } catch let error as PairingServiceError {
            throw error
        } catch let error as USBTransportRuntimeError {
            throw PairingServiceError.transport(message: error.localizedDescription)
        } catch {
            throw PairingServiceError.transport(message: error.localizedDescription)
        }
    }

    private func decodePairingResponsePayloadData(
        _ data: Data,
        encryptionTrustKeyBase64: String?
    ) throws -> Data {
        guard let encryptionTrustKeyBase64 else {
            return data
        }
        guard let encryptedResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PairingServiceError.decoding(message: "Desktop USB pairing response is not a JSON object.")
        }
        guard MobilePayloadEncryption.isEncryptedPayload(encryptedResponse) else {
            throw PairingServiceError.decoding(message: "Desktop USB pairing response must be encrypted.")
        }
        let decryptedPayload = try MobilePayloadEncryption.decryptPayloadObject(
            encryptedResponse,
            trustKeyBase64: encryptionTrustKeyBase64
        )
        guard JSONSerialization.isValidJSONObject(decryptedPayload) else {
            throw PairingServiceError.decoding(message: "Desktop USB pairing response payload is invalid.")
        }
        return try JSONSerialization.data(withJSONObject: decryptedPayload, options: [])
    }

    private func encryptedPairingRequest<RequestBody: Encodable & Sendable>(
        _ requestBody: RequestBody,
        trustKeyBase64: String,
        sessionID: String,
        platform: String?
    ) throws -> MobileEncryptedPayload {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(requestBody)
        guard let bodyValue = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] else {
            throw PairingServiceError.transport(message: "Desktop USB pairing request body could not be encoded.")
        }
        return try MobilePayloadEncryption.encryptPayloadObject(
            bodyValue,
            trustKeyBase64: trustKeyBase64,
            sessionID: sessionID,
            platform: platform
        )
    }
}

private struct USBTransferAssetUploadRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustProof: String
    var assetID: String
    var assetVersion: String
    var contentSHA1: String
    var fileSize: Int
    var filename: String
    var mediaType: String
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustProof = "trust_proof"
        case assetID = "asset_id"
        case assetVersion = "asset_version"
        case contentSHA1 = "sha1"
        case fileSize = "file_size"
        case filename
        case mediaType = "media_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct WebSocketMobileTransferClient: MobileTransferClient, ChunkProgressMobileTransferClient, MobileCapabilityExchangeClient, MobileUpdatePromptClient, USBTransportConnectivityChecking {
    let runtime: USBWebSocketTransportRuntime
    let telemetryClient: TelemetryClient
    let responseTimeout: TimeInterval

    init(
        runtime: USBWebSocketTransportRuntime,
        telemetryClient: TelemetryClient = NoOpTelemetryClient(),
        responseTimeout: TimeInterval = 6
    ) {
        self.runtime = runtime
        self.telemetryClient = telemetryClient
        self.responseTimeout = responseTimeout
    }

    func prepareUSBTransportIfNeeded(for desktop: TrustedDesktopRecord) async throws {
        guard
            let oneTimePasscode = desktop.usbOneTimePasscode,
            let suggestedPort = desktop.usbSuggestedPort
        else {
            return
        }
        let shouldForceRestart = !(await runtime.isConnected())
        USBTransportDebugLogger.info(
            "TransferUSB/prepare session_id=\(desktop.lastSessionID) suggested_port=\(suggestedPort) force_restart=\(shouldForceRestart)"
        )
        try await runtime.prepareBootstrap(
            sessionID: desktop.lastSessionID,
            oneTimePasscode: oneTimePasscode,
            suggestedPort: suggestedPort,
            forceRestart: shouldForceRestart
        )
    }

    func recoverUSBTransportAfterForegroundResume(for desktop: TrustedDesktopRecord) async {
        guard
            let oneTimePasscode = desktop.usbOneTimePasscode,
            let suggestedPort = desktop.usbSuggestedPort
        else {
            return
        }
        if await runtime.isConnected() {
            return
        }
        do {
            try await runtime.prepareBootstrap(
                sessionID: desktop.lastSessionID,
                oneTimePasscode: oneTimePasscode,
                suggestedPort: suggestedPort,
                forceRestart: true
            )
            USBTransportDebugLogger.info(
                "WebSocketMobileTransferClient/recoverUSBTransportAfterForegroundResume "
                    + "session_id=\(desktop.lastSessionID) suggested_port=\(suggestedPort)"
            )
        } catch {
            USBTransportDebugLogger.warning(
                "WebSocketMobileTransferClient/recoverUSBTransportAfterForegroundResume_failed "
                    + "session_id=\(desktop.lastSessionID) suggested_port=\(suggestedPort) "
                    + "error=\(USBTransportDebugLogger.describe(error))"
            )
        }
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        try await prepareUSBTransportIfNeeded(for: desktop)
        var request = TransferStartRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            totalAssets: totalAssets
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferStart,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferStartOperation,
            request: request,
            responseType: TransferServerResponse.self,
            desktop: desktop
        )
        switch response.status {
        case .accepted:
            return
        case .rejected:
            throw response.rejectionError
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
        try await prepareUSBTransportIfNeeded(for: desktop)
        var request = TransferExistenceRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            assets: candidates
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferExistence,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferExistenceOperation,
            request: request,
            responseType: TransferExistenceResponse.self,
            desktop: desktop
        )
        switch response.status {
        case .checked:
            return Dictionary(uniqueKeysWithValues: response.matches.map { ($0.assetID, $0) })
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        }
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
            onChunkTransferred: nil
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse {
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
            onChunkTransferred: onChunkTransferred
        )
    }

    private func uploadAssetInternal(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        onChunkTransferred: (@Sendable (Int) async -> Void)?
    ) async throws -> TransferServerResponse {
        try await prepareUSBTransportIfNeeded(for: desktop)
        var request = USBTransferAssetUploadRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            assetID: asset.descriptor.assetID,
            assetVersion: asset.descriptor.assetVersion,
            contentSHA1: asset.contentSHA1,
            fileSize: asset.fileSize,
            filename: asset.descriptor.filename,
            mediaType: asset.descriptor.mediaType,
            createdAt: asset.descriptor.createdAt,
            updatedAt: asset.descriptor.updatedAt
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferAsset,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        do {
            let plaintextChunkSizeBytes = transferAssetChunkSizeBytes(for: desktop)
            let traceFields = traceContextPayloadFields(await telemetryClient.currentTraceContext())
            let requestID: String
            if desktop.encryptionEnabled {
                requestID = try await runtime.beginStreamingRequest(
                    operation: MobileTransportProtocol.transferAssetOperation,
                    bodySchema: TransferProtocol.schema,
                    request: try encryptedTransferRequest(
                        request,
                        desktop: desktop,
                        traceFields: traceFields
                    ),
                    chunkSizeBytes: plaintextChunkSizeBytes,
                    additionalBodyFields: [:],
                    timeout: responseTimeout
                )
            } else {
                requestID = try await runtime.beginStreamingRequest(
                    operation: MobileTransportProtocol.transferAssetOperation,
                    bodySchema: TransferProtocol.schema,
                    request: request,
                    chunkSizeBytes: plaintextChunkSizeBytes,
                    additionalBodyFields: traceFields,
                    timeout: responseTimeout
                )
            }
            do {
                try await TransferAssetChunkStreamer.streamFile(
                    fileURL: asset.fileURL,
                    expectedSizeBytes: asset.fileSize,
                    chunkSizeBytes: plaintextChunkSizeBytes
                ) { chunkData in
                    let payloadChunk: Data
                    if desktop.encryptionEnabled {
                        do {
                            payloadChunk = try MobilePayloadEncryption.encryptBinaryChunk(
                                chunkData,
                                trustKeyBase64: desktop.sharedKeyBase64
                            )
                        } catch {
                            throw TransferClientError.transport(message: "Desktop transfer could not encrypt USB chunk payload.")
                        }
                    } else {
                        payloadChunk = chunkData
                    }
                    try await runtime.sendStreamingBinaryChunk(
                        requestID: requestID,
                        chunk: payloadChunk,
                        timeout: responseTimeout
                    )
                    if let onChunkTransferred {
                        await onChunkTransferred(chunkData.count)
                    }
                }
                let runtimeResponse = try await runtime.finishStreamingRequest(
                    operation: MobileTransportProtocol.transferAssetOperation,
                    requestID: requestID,
                    timeout: responseTimeout
                )
                let responseData = try decodeTransferResponsePayloadData(
                    runtimeResponse.bodyData,
                    desktop: desktop
                )
                let decodedResponse = try JSONDecoder.pairingDecoder.decode(
                    TransferServerResponse.self,
                    from: responseData
                )
                guard decodedResponse.schema == TransferProtocol.schema else {
                    throw TransferClientError.unsupportedResponseSchema
                }
                guard (200 ..< 300).contains(runtimeResponse.statusCode) else {
                    throw decodedResponse.rejectionError
                }
                switch decodedResponse.status {
                case .stored, .skipped:
                    return decodedResponse
                case .rejected:
                    throw decodedResponse.rejectionError
                case .accepted, .completed:
                    throw TransferClientError.rejected(message: "Desktop returned an unexpected transfer asset response.")
                }
            } catch {
                await runtime.abortStreamingRequest(requestID: requestID)
                throw error
            }
        } catch let error as TransferClientError {
            throw error
        } catch let error as TransferAssetChunkStreamError {
            throw TransferClientError.transport(message: error.message)
        } catch let error as USBTransportRuntimeError {
            throw TransferClientError.transport(message: error.localizedDescription)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
    }

    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse {
        try await prepareUSBTransportIfNeeded(for: desktop)
        var request = TransferCompleteRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            transferredCount: transferredCount,
            failedCount: failedCount,
            interruptionReason: interruptionReason
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferComplete,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.transferCompleteOperation,
            request: request,
            responseType: TransferServerResponse.self,
            desktop: desktop
        )
        switch response.status {
        case .completed:
            return response
        case .rejected:
            throw response.rejectionError
        case .accepted, .stored, .skipped:
            throw TransferClientError.rejected(message: "Desktop returned an unexpected transfer completion response.")
        }
    }

    func exchangeCapabilities(
        _ mobileCapabilities: [String: Int],
        desktop: TrustedDesktopRecord
    ) async throws -> CapabilityExchangeResponse {
        try await prepareUSBTransportIfNeeded(for: desktop)
        var request = CapabilityExchangeRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            capabilities: normalizedCapabilityExchangeFlags(mobileCapabilities)
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.capabilityExchange,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.capabilityExchangeOperation,
            request: request,
            responseType: CapabilityExchangeResponse.self,
            bodySchema: CapabilityExchangeProtocol.schema,
            expectedSchema: CapabilityExchangeProtocol.schema,
            desktop: desktop
        )
        switch response.status {
        case .accepted:
            return response
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        }
    }

    func sendUpdatePrompt(
        required: Bool,
        bodyText: String?,
        updateDestination: String?,
        desktop: TrustedDesktopRecord
    ) async throws -> UpdatePromptResponse {
        try await prepareUSBTransportIfNeeded(for: desktop)
        var request = UpdatePromptRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            required: required,
            bodyText: bodyText,
            updateDestination: updateDestination
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.updatePrompt,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let response = try await sendTransferEnvelope(
            operation: MobileTransportProtocol.updatePromptOperation,
            request: request,
            responseType: UpdatePromptResponse.self,
            bodySchema: UpdatePromptProtocol.schema,
            expectedSchema: UpdatePromptProtocol.schema,
            desktop: desktop
        )
        switch response.status {
        case .accepted:
            return response
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        }
    }

    func isUSBTransportConnected() async -> Bool {
        await runtime.isConnected()
    }

    private func sendTransferEnvelope<RequestBody: Encodable & Sendable, ResponseBody: TransferSchemaResponse>(
        operation: String,
        request: RequestBody,
        responseType: ResponseBody.Type,
        bodySchema: String = TransferProtocol.schema,
        expectedSchema: String = TransferProtocol.schema,
        desktop: TrustedDesktopRecord
    ) async throws -> ResponseBody {
        do {
            let traceFields = traceContextPayloadFields(await telemetryClient.currentTraceContext())
            let runtimeResponse: USBTransportRuntimeResponse
            if desktop.encryptionEnabled {
                runtimeResponse = try await runtime.sendRequest(
                    operation: operation,
                    bodySchema: bodySchema,
                    request: try encryptedTransferRequest(
                        request,
                        desktop: desktop,
                        traceFields: traceFields
                    ),
                    additionalBodyFields: [:],
                    timeout: responseTimeout
                )
            } else {
                runtimeResponse = try await runtime.sendRequest(
                    operation: operation,
                    bodySchema: bodySchema,
                    request: request,
                    additionalBodyFields: traceFields,
                    timeout: responseTimeout
                )
            }
            let responseData = try decodeTransferResponsePayloadData(
                runtimeResponse.bodyData,
                desktop: desktop
            )
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(responseType, from: responseData)
            guard decodedResponse.schema == expectedSchema else {
                throw TransferClientError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(runtimeResponse.statusCode) {
                return decodedResponse
            }
            if let transferResponse = decodedResponse as? TransferServerResponse {
                throw transferResponse.rejectionError
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

    private func decodeTransferResponsePayloadData(
        _ data: Data,
        desktop: TrustedDesktopRecord
    ) throws -> Data {
        guard desktop.encryptionEnabled else {
            return data
        }
        guard let encryptedResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransferClientError.decoding(message: "Desktop USB transfer response is not a JSON object.")
        }
        guard MobilePayloadEncryption.isEncryptedPayload(encryptedResponse) else {
            throw TransferClientError.decoding(message: "Desktop USB transfer response must be encrypted.")
        }
        let decryptedPayload = try MobilePayloadEncryption.decryptPayloadObject(
            encryptedResponse,
            trustKeyBase64: desktop.sharedKeyBase64
        )
        guard JSONSerialization.isValidJSONObject(decryptedPayload) else {
            throw TransferClientError.decoding(message: "Desktop USB transfer response payload is invalid.")
        }
        return try JSONSerialization.data(withJSONObject: decryptedPayload, options: [])
    }

    private func encryptedTransferRequest<RequestBody: Encodable & Sendable>(
        _ request: RequestBody,
        desktop: TrustedDesktopRecord,
        traceFields: [String: Any]
    ) throws -> MobileEncryptedPayload {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(request)
        guard var bodyValue = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] else {
            throw TransferClientError.transport(message: "Desktop transfer request body could not be encoded.")
        }
        for (key, value) in traceFields {
            bodyValue[key] = value
        }
        return try MobilePayloadEncryption.encryptPayloadObject(
            bodyValue,
            trustKeyBase64: desktop.sharedKeyBase64,
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID
        )
    }

    private func transferAssetChunkSizeBytes(for desktop: TrustedDesktopRecord) -> Int {
        guard desktop.encryptionEnabled else {
            return MobileTransportProtocol.transferAssetChunkSizeBytes
        }
        return max(
            1,
            MobileTransportProtocol.transferAssetChunkSizeBytes
                - MobilePayloadEncryptionProtocol.binaryChunkOverheadBytes
        )
    }
}

actor AdaptiveMobileTransferClient: ChunkProgressPreferredTransportMobileTransferClient, MobileCapabilityExchangeClient, MobileUpdatePromptClient, TransferTransportResolving, TransferLiveTransportResolving, USBTransportForegroundRecovering, USBTransportConnectivityChecking {
    private static let preferredTransportRetryCooldownSeconds: TimeInterval = 0.5
    let lanClient: MobileTransferClient
    let usbClient: MobileTransferClient
    private var lastResolvedTransportByDesktopID: [String: TransferTransport] = [:]
    private var unavailablePreferredTransportRetryDeadlinesByDesktopID: [String: [String: Date]] = [:]

    init(
        lanClient: MobileTransferClient,
        usbClient: MobileTransferClient
    ) {
        self.lanClient = lanClient
        self.usbClient = usbClient
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        unavailablePreferredTransportRetryDeadlinesByDesktopID.removeValue(forKey: desktop.desktopIDForRouting)
        try await executeWithFallback(
            operationName: MobileTransportProtocol.transferStartOperation,
            desktop: desktop,
            usbOperation: {
                let usbDesktop = desktopWithResolvedTransport(desktop, transport: .usb)
                try await usbClient.startSession(desktop: usbDesktop, totalAssets: totalAssets)
            },
            lanOperation: {
                let lanDesktop = desktopWithResolvedTransport(desktop, transport: .lan)
                try await lanClient.startSession(desktop: lanDesktop, totalAssets: totalAssets)
            }
        )
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        try await lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: nil
        )
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> [String: TransferAssetExistenceMatch] {
        try await executeWithFallback(
            operationName: MobileTransportProtocol.transferExistenceOperation,
            desktop: desktop,
            preferredTransport: preferredTransport,
            usbOperation: {
                let usbDesktop = desktopWithResolvedTransport(desktop, transport: .usb)
                return try await usbClient.lookupExistingAssets(candidates, desktop: usbDesktop)
            },
            lanOperation: {
                let lanDesktop = desktopWithResolvedTransport(desktop, transport: .lan)
                return try await lanClient.lookupExistingAssets(candidates, desktop: lanDesktop)
            }
        )
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        try await uploadAsset(
            asset,
            desktop: desktop,
            preferredTransport: nil
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse {
        try await uploadAssetWithChunkProgress(
            asset,
            desktop: desktop,
            preferredTransport: nil,
            onChunkTransferred: onChunkTransferred
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> TransferServerResponse {
        try await uploadAssetWithChunkProgress(
            asset,
            desktop: desktop,
            preferredTransport: preferredTransport,
            onChunkTransferred: nil
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse {
        try await uploadAssetWithChunkProgress(
            asset,
            desktop: desktop,
            preferredTransport: preferredTransport,
            onChunkTransferred: onChunkTransferred
        )
    }

    private func uploadAssetWithChunkProgress(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?,
        onChunkTransferred: (@Sendable (Int) async -> Void)?
    ) async throws -> TransferServerResponse {
        try await executeWithFallback(
            operationName: MobileTransportProtocol.transferAssetOperation,
            desktop: desktop,
            preferredTransport: preferredTransport,
            usbOperation: {
                let usbDesktop = desktopWithResolvedTransport(desktop, transport: .usb)
                if let onChunkTransferred,
                   let chunkClient = usbClient as? any ChunkProgressMobileTransferClient
                {
                    return try await chunkClient.uploadAsset(
                        asset,
                        desktop: usbDesktop,
                        onChunkTransferred: onChunkTransferred
                    )
                }
                return try await usbClient.uploadAsset(asset, desktop: usbDesktop)
            },
            lanOperation: {
                let lanDesktop = desktopWithResolvedTransport(desktop, transport: .lan)
                if let onChunkTransferred,
                   let chunkClient = lanClient as? any ChunkProgressMobileTransferClient
                {
                    return try await chunkClient.uploadAsset(
                        asset,
                        desktop: lanDesktop,
                        onChunkTransferred: onChunkTransferred
                    )
                }
                return try await lanClient.uploadAsset(asset, desktop: lanDesktop)
            }
        )
    }

    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse {
        try await executeWithFallback(
            operationName: MobileTransportProtocol.transferCompleteOperation,
            desktop: desktop,
            usbOperation: {
                let usbDesktop = desktopWithResolvedTransport(desktop, transport: .usb)
                return try await usbClient.completeSession(
                    desktop: usbDesktop,
                    transferredCount: transferredCount,
                    failedCount: failedCount,
                    interruptionReason: interruptionReason
                )
            },
            lanOperation: {
                let lanDesktop = desktopWithResolvedTransport(desktop, transport: .lan)
                return try await lanClient.completeSession(
                    desktop: lanDesktop,
                    transferredCount: transferredCount,
                    failedCount: failedCount,
                    interruptionReason: interruptionReason
                )
            }
        )
    }

    func exchangeCapabilities(
        _ mobileCapabilities: [String: Int],
        desktop: TrustedDesktopRecord
    ) async throws -> CapabilityExchangeResponse {
        let normalizedCapabilities = normalizedCapabilityExchangeFlags(mobileCapabilities)
        return try await executeWithFallback(
            operationName: MobileTransportProtocol.capabilityExchangeOperation,
            desktop: desktop,
            usbOperation: {
                guard let usbCapabilityClient = usbClient as? any MobileCapabilityExchangeClient else {
                    throw TransferClientError.transport(message: "USB capability exchange transport is unavailable.")
                }
                let usbDesktop = desktopWithResolvedTransport(desktop, transport: .usb)
                return try await usbCapabilityClient.exchangeCapabilities(normalizedCapabilities, desktop: usbDesktop)
            },
            lanOperation: {
                guard let lanCapabilityClient = lanClient as? any MobileCapabilityExchangeClient else {
                    throw TransferClientError.transport(message: "LAN capability exchange transport is unavailable.")
                }
                let lanDesktop = desktopWithResolvedTransport(desktop, transport: .lan)
                return try await lanCapabilityClient.exchangeCapabilities(normalizedCapabilities, desktop: lanDesktop)
            }
        )
    }

    func sendUpdatePrompt(
        required: Bool,
        bodyText: String?,
        updateDestination: String?,
        desktop: TrustedDesktopRecord
    ) async throws -> UpdatePromptResponse {
        try await executeWithFallback(
            operationName: MobileTransportProtocol.updatePromptOperation,
            desktop: desktop,
            usbOperation: {
                guard let usbUpdateClient = usbClient as? any MobileUpdatePromptClient else {
                    throw TransferClientError.transport(message: "USB update prompt transport is unavailable.")
                }
                let usbDesktop = desktopWithResolvedTransport(desktop, transport: .usb)
                return try await usbUpdateClient.sendUpdatePrompt(
                    required: required,
                    bodyText: bodyText,
                    updateDestination: updateDestination,
                    desktop: usbDesktop
                )
            },
            lanOperation: {
                guard let lanUpdateClient = lanClient as? any MobileUpdatePromptClient else {
                    throw TransferClientError.transport(message: "LAN update prompt transport is unavailable.")
                }
                let lanDesktop = desktopWithResolvedTransport(desktop, transport: .lan)
                return try await lanUpdateClient.sendUpdatePrompt(
                    required: required,
                    bodyText: bodyText,
                    updateDestination: updateDestination,
                    desktop: lanDesktop
                )
            }
        )
    }

    func resolveDesktopTransport(for desktop: TrustedDesktopRecord) async -> TransferTransport {
        if await isUSBTransportConnected() {
            return .usb
        }
        if let resolvedTransport = lastResolvedTransportByDesktopID[desktop.desktopIDForRouting] {
            return resolvedTransport
        }
        return desktop.transport
    }

    func resolveLiveTransports(for desktop: TrustedDesktopRecord) async -> [TransferTransport] {
        var liveTransports: [TransferTransport] = []
        if await isUSBTransportConnected() {
            liveTransports.append(.usb)
        }
        if canAttemptPreferredTransport(.lan, desktop: desktop) {
            liveTransports.append(.lan)
        }
        if !liveTransports.isEmpty {
            return liveTransports
        }
        if let resolvedTransport = lastResolvedTransportByDesktopID[desktop.desktopIDForRouting] {
            return [resolvedTransport]
        }
        return [desktop.transport]
    }

    func isUSBTransportConnected() async -> Bool {
        guard let usbConnectivity = usbClient as? USBTransportConnectivityChecking else {
            return false
        }
        return await usbConnectivity.isUSBTransportConnected()
    }

    func recoverUSBTransportAfterForegroundResume(for desktop: TrustedDesktopRecord) async {
        guard let usbForegroundRecovery = usbClient as? any USBTransportForegroundRecovering else {
            return
        }
        await usbForegroundRecovery.recoverUSBTransportAfterForegroundResume(for: desktop)
    }

    private func executeWithFallback<Result>(
        operationName: String,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport? = nil,
        usbOperation: () async throws -> Result,
        lanOperation: () async throws -> Result
    ) async throws -> Result {
        let selectedTransport: TransferTransport
        if let preferredTransport {
            if canAttemptPreferredTransport(preferredTransport, desktop: desktop) {
                selectedTransport = preferredTransport
            } else {
                selectedTransport = preferredTransport == .usb ? .lan : .usb
            }
        } else {
            selectedTransport = await resolveDesktopTransport(for: desktop)
        }

        switch selectedTransport {
        case .usb:
            do {
                let result = try await usbOperation()
                clearPreferredTransportUnavailable(.usb, desktop: desktop)
                if preferredTransport == nil {
                    recordResolvedTransport(
                        desktop: desktop,
                        transport: .usb,
                        operationName: operationName,
                        reason: "usb_success"
                    )
                }
                return result
            } catch {
                if preferredTransport == .usb {
                    markPreferredTransportUnavailable(.usb, desktop: desktop)
                }
                USBTransportDebugLogger.warning(
                    "AdaptiveTransfer/fallback "
                        + "desktop_id=\(desktop.desktopIDForRouting) "
                        + "operation=\(operationName) from=usb to=lan "
                        + "error=\(USBTransportDebugLogger.describe(error))"
                )
                let result = try await lanOperation()
                clearPreferredTransportUnavailable(.lan, desktop: desktop)
                recordResolvedTransport(
                    desktop: desktop,
                    transport: .lan,
                    operationName: operationName,
                    reason: "usb_fallback_lan_success"
                )
                return result
            }
        case .lan:
            do {
                let result = try await lanOperation()
                clearPreferredTransportUnavailable(.lan, desktop: desktop)
                if preferredTransport == nil {
                    recordResolvedTransport(
                        desktop: desktop,
                        transport: .lan,
                        operationName: operationName,
                        reason: "lan_success"
                    )
                }
                return result
            } catch {
                if preferredTransport == .lan {
                    markPreferredTransportUnavailable(.lan, desktop: desktop)
                }
                USBTransportDebugLogger.warning(
                    "AdaptiveTransfer/fallback "
                        + "desktop_id=\(desktop.desktopIDForRouting) "
                        + "operation=\(operationName) from=lan to=usb "
                        + "error=\(USBTransportDebugLogger.describe(error))"
                )
                let result = try await usbOperation()
                clearPreferredTransportUnavailable(.usb, desktop: desktop)
                recordResolvedTransport(
                    desktop: desktop,
                    transport: .usb,
                    operationName: operationName,
                    reason: "lan_fallback_usb_success"
                )
                return result
            }
        }
    }

    private func recordResolvedTransport(
        desktop: TrustedDesktopRecord,
        transport: TransferTransport,
        operationName: String,
        reason: String
    ) {
        let desktopID = desktop.desktopIDForRouting
        let previousTransport = lastResolvedTransportByDesktopID[desktopID]
        lastResolvedTransportByDesktopID[desktopID] = transport
        if previousTransport == transport {
            return
        }

        if let previousTransport {
            USBTransportDebugLogger.info(
                "AdaptiveTransfer/transport_switch "
                    + "desktop_id=\(desktopID) "
                    + "operation=\(operationName) "
                    + "from=\(previousTransport.rawValue) "
                    + "to=\(transport.rawValue) "
                    + "reason=\(reason)"
            )
            return
        }
        USBTransportDebugLogger.info(
            "AdaptiveTransfer/transport_selected "
                + "desktop_id=\(desktopID) "
                + "operation=\(operationName) "
                + "transport=\(transport.rawValue) "
                + "reason=\(reason)"
        )
    }

    private func desktopWithResolvedTransport(
        _ desktop: TrustedDesktopRecord,
        transport: TransferTransport
    ) -> TrustedDesktopRecord {
        var resolvedDesktop = desktop
        resolvedDesktop.transport = transport
        return resolvedDesktop
    }

    private func canAttemptPreferredTransport(
        _ transport: TransferTransport,
        desktop: TrustedDesktopRecord
    ) -> Bool {
        let desktopID = desktop.desktopIDForRouting
        guard
            let deadline = unavailablePreferredTransportRetryDeadlinesByDesktopID[desktopID]?[transport.rawValue]
        else {
            return true
        }
        return Date() >= deadline
    }

    private func markPreferredTransportUnavailable(
        _ transport: TransferTransport,
        desktop: TrustedDesktopRecord
    ) {
        let desktopID = desktop.desktopIDForRouting
        var retryDeadlines = unavailablePreferredTransportRetryDeadlinesByDesktopID[desktopID, default: [:]]
        retryDeadlines[transport.rawValue] = Date()
            .addingTimeInterval(Self.preferredTransportRetryCooldownSeconds)
        unavailablePreferredTransportRetryDeadlinesByDesktopID[desktopID] = retryDeadlines
    }

    private func clearPreferredTransportUnavailable(
        _ transport: TransferTransport,
        desktop: TrustedDesktopRecord
    ) {
        let desktopID = desktop.desktopIDForRouting
        guard
            var retryDeadlines = unavailablePreferredTransportRetryDeadlinesByDesktopID[desktopID]
        else {
            return
        }
        retryDeadlines.removeValue(forKey: transport.rawValue)
        if retryDeadlines.isEmpty {
            unavailablePreferredTransportRetryDeadlinesByDesktopID.removeValue(forKey: desktopID)
        } else {
            unavailablePreferredTransportRetryDeadlinesByDesktopID[desktopID] = retryDeadlines
        }
    }
}

private extension TrustedDesktopRecord {
    var desktopIDForRouting: String {
        if desktopDeviceID.isEmpty {
            return lastSessionID
        }
        return desktopDeviceID
    }
}
