import CryptoKit
import Foundation
import XCTest
@testable import Common
@testable import ISFromPC
@testable import ISFromMobile
@testable import AlbumTransporterKit

final class InstantShareServicesTests: XCTestCase {
    func test_metadata_rejects_invalid_text_target() {
        let metadata = InstantShareMetadata(
            payloadClass: .text,
            targetIntent: .clipboardOrFile,
            trustMode: .firstShare
        )

        XCTAssertThrowsError(try metadata.validated())
    }

    func test_connection_config_builds_https_endpoints_for_ipv4_and_ipv6() throws {
        let connectionConfig = InstantShareConnectionConfig(
            sessionID: UUID().uuidString.lowercased(),
            mobilePort: 8443,
            mobileIPList: ["192.168.1.20", "10.0.0.1"],
            correlationID: UUID().uuidString.lowercased(),
            metadata: InstantShareMetadata(
                payloadClass: .text,
                targetIntent: .clipboardOnly,
                trustMode: .firstShare
            )
        )

        let endpointURLs = try connectionConfig.endpointURLs(path: InstantShareProtocol.trustHandshakePath)

        XCTAssertEqual(
            endpointURLs.map(\.absoluteString),
            [
                "https://192.168.1.20:8443/api/instant-share/v1/trust/handshake",
                "https://10.0.0.1:8443/api/instant-share/v1/trust/handshake",
            ]
        )
    }

    func test_trust_handshake_request_encodes_metadata_and_dh_material() throws {
        let request = InstantShareTrustHandshakeRequest(
            metadata: InstantShareMetadata(
                payloadClass: .text,
                targetIntent: .clipboardOnly,
                trustMode: .firstShare
            ),
            pcDHPublicKey: "desktop-dh-pub",
            pcNonce: "desktop-nonce"
        )

        let encodedData = try JSONEncoder().encode(request)
        let encodedPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )

        XCTAssertEqual(encodedPayload["flow_id"] as? String, InstantShareProtocol.flowID)
        XCTAssertEqual(encodedPayload["payload_class"] as? String, "text")
        XCTAssertEqual(encodedPayload["pc_dh_public_key"] as? String, "desktop-dh-pub")
        XCTAssertEqual(encodedPayload["pc_nonce"] as? String, "desktop-nonce")
    }

    func test_trust_session_protector_round_trips_payload() throws {
        let payload: [String: Any] = [
            "pc_public_key_pem": "desktop-public-key",
            "trust_mode": "first_share",
        ]
        let sessionKey = SymmetricKey(data: Data(repeating: 0x11, count: 32))

        let envelope = try InstantShareTrustSessionProtector.encryptPayloadObject(
            payload,
            sessionKey: sessionKey,
            nonceData: Data(repeating: 0x22, count: InstantShareProtocol.trustEnvelopeNonceBytes)
        )
        let decryptedPayload = try InstantShareTrustSessionProtector.decryptPayloadObject(
            envelope,
            sessionKey: sessionKey
        )

        XCTAssertEqual(envelope.schema, InstantShareProtocol.trustEnvelopeSchema)
        XCTAssertEqual(decryptedPayload["pc_public_key_pem"] as? String, "desktop-public-key")
        XCTAssertEqual(decryptedPayload["trust_mode"] as? String, "first_share")
    }

    func test_trust_session_protector_rejects_invalid_schema() {
        let envelope = InstantShareTrustEnvelope(
            schema: "dtis.invalid-envelope.v1",
            nonce: "AA",
            ciphertext: "BB"
        )
        let sessionKey = SymmetricKey(data: Data(repeating: 0x11, count: 32))

        XCTAssertThrowsError(
            try InstantShareTrustSessionProtector.decryptPayloadObject(
                envelope,
                sessionKey: sessionKey
            )
        )
    }
}

final class InstantShareTrustSessionManagerTests: XCTestCase {
    func test_is_not_established_before_handshake() {
        let manager = InstantShareTrustSessionManager()
        XCTAssertFalse(manager.isEstablished)
    }

    func test_handle_handshake_produces_valid_response_and_establishes_session() throws {
        let pcPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let pcPublicKey = pcPrivateKey.publicKey
        let pcNonce = Data(repeating: 0xAA, count: 32)
        let pcKdfContext = Data([UInt8](repeating: 0xDD, count: 16)).instantShareBase64URLEncodedString()
        let mobileNonce = Data([UInt8](repeating: 0xEE, count: 32)).instantShareBase64URLEncodedString()

        let manager = InstantShareTrustSessionManager()
        let response = try manager.handleHandshakeRequest(
            pcDHPublicKey: pcPublicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            pcNonce: pcNonce.instantShareBase64URLEncodedString(),
            pcKdfContext: pcKdfContext,
            mobileNonce: mobileNonce
        )

        XCTAssertFalse(response.mobileDHPublicKey.isEmpty)
        XCTAssertFalse(response.mobileNonce.isEmpty)
        XCTAssertFalse(response.kdfContext.isEmpty)
        XCTAssertTrue(manager.isEstablished)
    }

    func test_handshake_derives_matching_session_key_as_pc_peer() throws {
        let pcPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let pcPublicKey = pcPrivateKey.publicKey
        let pcNonce = Data(repeating: 0xBB, count: 32)
        let inputKdfContext = Data([UInt8](repeating: 0xDD, count: 16)).instantShareBase64URLEncodedString()
        let inputMobileNonce = Data([UInt8](repeating: 0xEE, count: 32)).instantShareBase64URLEncodedString()

        let manager = InstantShareTrustSessionManager()
        let response = try manager.handleHandshakeRequest(
            pcDHPublicKey: pcPublicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            pcNonce: pcNonce.instantShareBase64URLEncodedString(),
            pcKdfContext: inputKdfContext,
            mobileNonce: inputMobileNonce
        )

        let mobilePublicKeyData = try Data(instantShareBase64URLEncoded: response.mobileDHPublicKey)
        let mobilePublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: mobilePublicKeyData)
        let mobileNonce = try Data(instantShareBase64URLEncoded: response.mobileNonce)
        let kdfContext = try Data(instantShareBase64URLEncoded: response.kdfContext)

        let pcSharedSecret = try pcPrivateKey.sharedSecretFromKeyAgreement(with: mobilePublicKey)
        let pcDerivedKey = pcSharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pcNonce + mobileNonce,
            sharedInfo: Data("dtis.instant-share.trust-session.v1".utf8) + kdfContext,
            outputByteCount: 32
        )

        let testPayload: [String: Any] = ["test_key": "test_value"]
        let envelope = try manager.encryptResponse(testPayload)
        let decryptedByPC = try InstantShareTrustSessionProtector.decryptPayloadObject(
            envelope,
            sessionKey: pcDerivedKey
        )

        XCTAssertEqual(decryptedByPC["test_key"] as? String, "test_value")
    }

    func test_reject_invalid_pc_dh_public_key_length() {
        let manager = InstantShareTrustSessionManager()
        let shortKey = Data(repeating: 0x01, count: 16).instantShareBase64URLEncodedString()
        let nonce = Data(repeating: 0x02, count: 32).instantShareBase64URLEncodedString()
        let kdfContext = Data([UInt8](repeating: 0xDD, count: 16)).instantShareBase64URLEncodedString()
        let mobileNonce = Data([UInt8](repeating: 0xEE, count: 32)).instantShareBase64URLEncodedString()

        XCTAssertThrowsError(
            try manager.handleHandshakeRequest(pcDHPublicKey: shortKey, pcNonce: nonce, pcKdfContext: kdfContext, mobileNonce: mobileNonce)
        )
    }

    func test_reset_clears_session_key() throws {
        let pcPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let manager = InstantShareTrustSessionManager()
        let kdfContext = Data([UInt8](repeating: 0xDD, count: 16)).instantShareBase64URLEncodedString()
        let mobileNonce = Data([UInt8](repeating: 0xEE, count: 32)).instantShareBase64URLEncodedString()
        _ = try manager.handleHandshakeRequest(
            pcDHPublicKey: pcPrivateKey.publicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            pcNonce: Data(repeating: 0xCC, count: 32).instantShareBase64URLEncodedString(),
            pcKdfContext: kdfContext,
            mobileNonce: mobileNonce
        )
        XCTAssertTrue(manager.isEstablished)

        manager.reset()
        XCTAssertFalse(manager.isEstablished)
    }

    func test_decrypt_envelope_fails_without_handshake() {
        let manager = InstantShareTrustSessionManager()
        let envelope = InstantShareTrustEnvelope(schema: "test", nonce: "AA", ciphertext: "BB")
        XCTAssertThrowsError(try manager.decryptEnvelope(envelope))
    }
}

final class InstantSharePayloadExtractorTests: XCTestCase {
    func test_classify_text_types() {
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.plain-text"), .text)
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.utf8-plain-text"), .text)
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.url"), .text)
    }

    func test_classify_image_types() {
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.jpeg"), .image)
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.png"), .image)
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.heic"), .image)
    }

    func test_classify_video_types() {
        XCTAssertEqual(InstantSharePayloadExtractor.classify(typeIdentifier: "public.mpeg-4"), .video)
    }

    func test_classify_unknown_returns_nil() {
        XCTAssertNil(InstantSharePayloadExtractor.classify(typeIdentifier: "com.apple.application-bundle"))
    }

    func test_payload_envelope_text_target_intent() {
        let envelope = InstantSharePayloadEnvelope(
            payloadType: .text, textContent: "hello", fileURL: nil,
            filename: nil, contentType: "text/plain", fileSizeBytes: 5
        )
        XCTAssertEqual(envelope.targetIntent, "clipboard_only")
    }

    func test_payload_envelope_image_target_intent() {
        let envelope = InstantSharePayloadEnvelope(
            payloadType: .image, textContent: nil, fileURL: URL(string: "file:///tmp/test.jpg"),
            filename: "test.jpg", contentType: "public.jpeg", fileSizeBytes: 1024
        )
        XCTAssertEqual(envelope.targetIntent, "clipboard_or_file")
    }

    func test_batch_size_exceeded_error_description() {
        let error = InstantSharePayloadExtractorError.batchSizeExceeded(limit: 10)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("10"))
        XCTAssertTrue(error.errorDescription!.contains("items"))
    }

    func test_max_batch_size_constant() {
        XCTAssertEqual(InstantSharePayloadExtractor.maxBatchSize, 10)
    }
}

final class InstantShareHandoffContextTests: XCTestCase {
    func test_handoff_context_encodes_and_decodes() throws {
        let envelope = InstantSharePayloadEnvelope(
            payloadType: .text, textContent: "test message", fileURL: nil,
            filename: nil, contentType: "text/plain", fileSizeBytes: 12
        )
        let context = InstantShareHandoffContext(
            from: envelope,
            selectedDeviceID: "device-123",
            selectedDeviceName: "My Mac",
            isTrustedDevice: false
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(InstantShareHandoffContext.self, from: data)

        XCTAssertEqual(decoded.payloadType, "text")
        XCTAssertEqual(decoded.textContent, "test message")
        XCTAssertEqual(decoded.selectedDeviceID, "device-123")
        XCTAssertEqual(decoded.selectedDeviceName, "My Mac")
        XCTAssertFalse(decoded.isTrustedDevice)
    }

    func test_handoff_context_is_not_stale_when_recent() {
        let envelope = InstantSharePayloadEnvelope(
            payloadType: .text, textContent: "hi", fileURL: nil,
            filename: nil, contentType: "text/plain", fileSizeBytes: 2
        )
        let context = InstantShareHandoffContext(
            from: envelope, selectedDeviceID: nil, selectedDeviceName: nil, isTrustedDevice: false
        )
        XCTAssertFalse(context.isStale)
    }

    func test_handoff_context_file_url_round_trips() {
        let url = URL(string: "file:///tmp/test.jpg")!
        let envelope = InstantSharePayloadEnvelope(
            payloadType: .image, textContent: nil, fileURL: url,
            filename: "test.jpg", contentType: "public.jpeg", fileSizeBytes: 1024
        )
        let context = InstantShareHandoffContext(
            from: envelope, selectedDeviceID: nil, selectedDeviceName: nil, isTrustedDevice: false
        )
        XCTAssertEqual(context.fileURL, url)
    }
}

@MainActor
final class InstantShareExtensionViewModelBatchTests: XCTestCase {
    var viewModel: InstantShareExtensionViewModel!
    var service: InstantShareService!
    
    override func setUp() {
        super.setUp()
        service = InstantShareService()
        let browser = InstantShareMDNSBrowser()
        let localDeviceIdProvider = LocalDeviceIdentifierStore(userDefaults: .standard, installIDKey: LocalDeviceIdentifierStore.installIDKey, deviceUUIDKey: LocalDeviceIdentifierStore.deviceUUIDKey)
        let identityProvider = KeychainAppIdentityProvider(localDeviceIdentifierProvider: localDeviceIdProvider, userDefaults: .standard)
        viewModel = InstantShareExtensionViewModel(mdnsBrowser: browser, service: service, appIdentityProvider: identityProvider, deviceIdentifierProvider: localDeviceIdProvider)
    }
    
    override func tearDown() {
        viewModel = nil
        service = nil
        super.tearDown()
    }
    
    func test_viewModel_starts_with_empty_payload_envelopes() {
        XCTAssertTrue(viewModel.payloadEnvelopes.isEmpty)
        XCTAssertEqual(viewModel.totalImageCount, 0)
        XCTAssertEqual(viewModel.sentImageCount, 0)
    }
    
    func test_canSend_returns_false_when_no_payloads() {
        XCTAssertFalse(viewModel.canSend)
    }
    
    func test_canSend_returns_false_when_no_device_selected() {
        viewModel.payloadEnvelopes = [
            InstantSharePayloadEnvelope(
                payloadType: .image, textContent: nil,
                fileURL: URL(string: "file:///test.jpg"),
                filename: "test.jpg", contentType: "image/jpeg", fileSizeBytes: 1024
            )
        ]
        XCTAssertFalse(viewModel.canSend)
    }
    
    func test_batch_progress_computed_property() {
        viewModel.totalImageCount = 5
        viewModel.sentImageCount = 3
        let progress = viewModel.batchProgress
        XCTAssertEqual(progress, 0.6, accuracy: 0.01)
    }
    
    func test_batch_progress_zero_when_no_images() {
        viewModel.totalImageCount = 0
        viewModel.sentImageCount = 0
        XCTAssertEqual(viewModel.batchProgress, 0.0)
    }
    
    func test_batch_progress_handles_division_by_zero() {
        viewModel.totalImageCount = 0
        viewModel.sentImageCount = 5
        XCTAssertEqual(viewModel.batchProgress, 0.0)
    }
    
    func test_service_shared_images_defaults_to_empty() {
        XCTAssertTrue(service.sharedImages.isEmpty)
    }
    
    func test_service_set_shared_images_batch() {
        let images: [(fileURL: URL, filename: String, contentType: String)] = [
            (URL(string: "file:///a.jpg")!, "a.jpg", "image/jpeg"),
            (URL(string: "file:///b.jpg")!, "b.jpg", "image/png"),
        ]
        service.setSharedImages(images)
        XCTAssertEqual(service.sharedImages.count, 2)
        XCTAssertEqual(service.sharedImages[0].filename, "a.jpg")
        XCTAssertEqual(service.sharedImages[1].filename, "b.jpg")
    }
    
    func test_service_set_shared_image_append() {
        service.setSharedImage(fileURL: URL(string: "file:///a.jpg")!, filename: "a.jpg", contentType: "image/jpeg")
        service.setSharedImage(fileURL: URL(string: "file:///b.jpg")!, filename: "b.jpg", contentType: "image/png")
        XCTAssertEqual(service.sharedImages.count, 2)
    }
    
    func test_service_stop_session_clears_shared_images() {
        service.setSharedImage(fileURL: URL(string: "file:///a.jpg")!, filename: "a.jpg", contentType: "image/jpeg")
        XCTAssertEqual(service.sharedImages.count, 1)
        service.stopSession()
        XCTAssertTrue(service.sharedImages.isEmpty)
    }
}
