import Foundation
import XCTest
@testable import AlbumTransporterKit

final class USBTransportServicesTests: XCTestCase {
    func test_usb_runtime_accepts_python_desktop_auth_challenge() async throws {
        let runtime = USBWebSocketTransportRuntime()
        let sessionID = "mobile-functional-session-001"
        let oneTimePasscode = "482913"
        let challengeRand = "functional-rand-001"

        let port = try await prepareRuntimeForFunctionalChallenge(
            runtime: runtime,
            sessionID: sessionID,
            oneTimePasscode: oneTimePasscode
        )
        defer {
            Task {
                await runtime.reset()
            }
        }

        let result = try runPythonDesktopChallengeScript(
            port: port,
            sessionID: sessionID,
            oneTimePasscode: oneTimePasscode,
            challengeRand: challengeRand
        )
        XCTAssertEqual(result.terminationStatus, 0, result.outputSummary)
    }

    func test_build_desktop_usb_auth_digest_matches_sha256_material() {
        let digest = buildDesktopUSBAuthDigest(
            oneTimePasscode: "482913",
            rand: "rand-001"
        )

        XCTAssertEqual(
            digest,
            "4d0e4431843a8a654a39e4eaba0f2dc841ddd9407984ec86db4806c0e60ed0ce"
        )
    }

    func test_adaptive_mobile_transfer_client_prefers_usb_for_usb_transport() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient()
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 3)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(usbStartCalls, 1)
        XCTAssertEqual(lanStartCalls, 0)
    }

    func test_adaptive_mobile_transfer_client_falls_back_to_lan_when_usb_throws() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient(
            startSessionError: TransferClientError.transport(message: "USB disconnected")
        )
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 5)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(usbStartCalls, 1)
        XCTAssertEqual(lanStartCalls, 1)
    }

    func test_adaptive_mobile_transfer_client_retries_usb_after_transient_fallback() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = FlakyUSBTransferClient(failuresRemaining: 1)
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 5)
        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 5)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(usbStartCalls, 2)
        XCTAssertEqual(lanStartCalls, 1)
    }

    func test_adaptive_mobile_transfer_client_uses_lan_for_lan_transport() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient()
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .lan)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 1)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(lanStartCalls, 1)
        XCTAssertEqual(usbStartCalls, 0)
    }

    func test_adaptive_mobile_transfer_client_prefers_connected_usb_even_for_lan_record() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient(usbConnected: true)
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .lan)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 1)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        let resolvedTransport = await adaptiveClient.resolveDesktopTransport(for: desktop)
        XCTAssertEqual(lanStartCalls, 0)
        XCTAssertEqual(usbStartCalls, 1)
        XCTAssertEqual(resolvedTransport, .usb)
    }

    func test_adaptive_mobile_transfer_client_skips_preferred_lan_after_initial_lan_failure() async throws {
        let lanClient = RecordingTransferClient(
            lookupError: TransferClientError.transport(message: "LAN unavailable")
        )
        let usbClient = RecordingTransferClient()
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)
        let candidates = [
            TransferAssetExistenceCandidate(
                assetID: "ph://asset-001",
                contentSHA1: "sha1-001",
                fileSize: 42,
                createdAt: Date(timeIntervalSince1970: 1_776_123_610)
            ),
        ]

        _ = try await adaptiveClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: .lan
        )
        _ = try await adaptiveClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: .lan
        )
        _ = try await adaptiveClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: .lan
        )

        let lanLookupCalls = await lanClient.lookupCalls()
        let usbLookupCalls = await usbClient.lookupCalls()
        XCTAssertEqual(lanLookupCalls, 1)
        XCTAssertEqual(usbLookupCalls, 3)
    }

    func test_adaptive_mobile_transfer_client_retries_preferred_lan_after_cooldown_when_recovered() async throws {
        let lanClient = RecordingTransferClient(
            lookupError: TransferClientError.transport(message: "LAN unavailable"),
            lookupFailuresRemaining: 1
        )
        let usbClient = RecordingTransferClient()
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)
        let candidates = [
            TransferAssetExistenceCandidate(
                assetID: "ph://asset-001",
                contentSHA1: "sha1-001",
                fileSize: 42,
                createdAt: Date(timeIntervalSince1970: 1_776_123_610)
            ),
        ]

        _ = try await adaptiveClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: .lan
        )
        _ = try await adaptiveClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: .lan
        )
        try await Task.sleep(nanoseconds: 600_000_000)
        _ = try await adaptiveClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: .lan
        )

        let lanLookupCalls = await lanClient.lookupCalls()
        let usbLookupCalls = await usbClient.lookupCalls()
        XCTAssertEqual(lanLookupCalls, 2)
        XCTAssertEqual(usbLookupCalls, 2)
    }

    private func trustedDesktop(transport: TransferTransport) -> TrustedDesktopRecord {
        TrustedDesktopRecord(
            desktopDeviceID: "desktop-device-001",
            desktopName: "Studio Mac",
            endpointURL: URL(string: "http://127.0.0.1:38933/api/mobile/pairing/claim")!,
            mobileDeviceUUID: "ios-device-001",
            sharedKeyBase64: "shared-key-001",
            transport: transport,
            lastSessionID: "pairing-demo-001",
            pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
        )
    }

    private func prepareRuntimeForFunctionalChallenge(
        runtime: USBWebSocketTransportRuntime,
        sessionID: String,
        oneTimePasscode: String
    ) async throws -> Int {
        for _ in 0 ..< 20 {
            let candidatePort = Int.random(in: 45_000 ... 60_000)
            do {
                try await runtime.prepareBootstrap(
                    sessionID: sessionID,
                    oneTimePasscode: oneTimePasscode,
                    suggestedPort: candidatePort
                )
                return candidatePort
            } catch let error as USBTransportRuntimeError {
                switch error {
                case .listenerStartFailed:
                    continue
                default:
                    throw error
                }
            }
        }
        throw TransferClientError.transport(
            message: "Failed to allocate a USB runtime listener port for functional testing."
        )
    }

    private func runPythonDesktopChallengeScript(
        port: Int,
        sessionID: String,
        oneTimePasscode: String,
        challengeRand: String
    ) throws -> ProcessResult {
        let script = """
import hashlib
import json
import sys
import time

from websockets.sync.client import connect

port = int(sys.argv[1])
session_id = sys.argv[2]
one_time_passcode = sys.argv[3]
challenge_rand = sys.argv[4]

expected_proof = hashlib.sha256(f"{one_time_passcode}{challenge_rand}".encode("utf-8")).hexdigest()
envelope = {
    "schema": "dtis.mobile-transport.v1",
    "operation": "transport.auth.challenge",
    "request_id": "pc-functional-challenge-001",
    "body_schema": "dtis.mobile-pairing.v1",
    "body": {
        "schema": "dtis.mobile-pairing.v1",
        "sid": session_id,
        "rand": challenge_rand,
    },
}

last_error = None
for _ in range(40):
    try:
        with connect(f"ws://127.0.0.1:{port}") as websocket:
            websocket.send(json.dumps(envelope, separators=(",", ":"), sort_keys=True))
            response = json.loads(websocket.recv())
            if response.get("status_code") != 200:
                raise RuntimeError(f"unexpected status: {response}")
            body = response.get("body")
            if not isinstance(body, dict):
                raise RuntimeError(f"missing body: {response}")
            if body.get("status") != "accepted":
                raise RuntimeError(f"unexpected body status: {response}")
            if body.get("proof") != expected_proof:
                raise RuntimeError(f"proof mismatch: expected {expected_proof}, got {body.get('proof')}")
            print("handshake-ok")
            sys.exit(0)
    except Exception as exc:
        last_error = exc
        time.sleep(0.05)

raise SystemExit(f"handshake failed: {last_error}")
"""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3.10",
            "-c",
            script,
            String(port),
            sessionID,
            oneTimePasscode,
            challengeRand,
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            terminationStatus: process.terminationStatus,
            outputSummary: """
stdout:
\(String(decoding: stdoutData, as: UTF8.self))
stderr:
\(String(decoding: stderrData, as: UTF8.self))
"""
        )
    }
}

private struct ProcessResult {
    let terminationStatus: Int32
    let outputSummary: String
}

private actor RecordingTransferClient: MobileTransferClient, USBTransportConnectivityChecking {
    private let startSessionError: Error?
    private let lookupError: Error?
    private var lookupFailuresRemaining: Int?
    private let usbConnected: Bool
    private var startCallCount = 0
    private var lookupCallCount = 0

    init(
        startSessionError: Error? = nil,
        lookupError: Error? = nil,
        lookupFailuresRemaining: Int? = nil,
        usbConnected: Bool = false
    ) {
        self.startSessionError = startSessionError
        self.lookupError = lookupError
        self.lookupFailuresRemaining = lookupFailuresRemaining
        self.usbConnected = usbConnected
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        startCallCount += 1
        if let startSessionError {
            throw startSessionError
        }
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        lookupCallCount += 1
        if let failuresRemaining = lookupFailuresRemaining {
            if failuresRemaining > 0 {
                lookupFailuresRemaining = failuresRemaining - 1
                throw lookupError ?? TransferClientError.transport(message: "Synthetic lookup failure")
            }
        } else if let lookupError {
            throw lookupError
        }
        return [:]
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .stored,
            message: "stored",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: "2026-04/\(asset.descriptor.filename)"
        )
    }

    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse {
        TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .completed,
            message: "completed",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: nil
        )
    }

    func startCalls() -> Int {
        startCallCount
    }

    func lookupCalls() -> Int {
        lookupCallCount
    }

    func isUSBTransportConnected() async -> Bool {
        usbConnected
    }
}

private actor FlakyUSBTransferClient: MobileTransferClient, USBTransportConnectivityChecking {
    private var failuresRemaining: Int
    private var startCallCount = 0

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        startCallCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw TransferClientError.transport(message: "USB disconnected")
        }
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        [:]
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .stored,
            message: "stored",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: "2026-04/\(asset.descriptor.filename)"
        )
    }

    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse {
        TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .completed,
            message: "completed",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: nil
        )
    }

    func startCalls() -> Int {
        startCallCount
    }

    func isUSBTransportConnected() async -> Bool {
        true
    }
}
