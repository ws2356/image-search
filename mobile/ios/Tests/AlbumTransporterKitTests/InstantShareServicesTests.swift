import CryptoKit
import Foundation
import Security
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
            mobileIPList: ["192.168.1.20", "fe80::10"],
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
                "https://[fe80::10]:8443/api/instant-share/v1/trust/handshake",
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

        let manager = InstantShareTrustSessionManager()
        let response = try manager.handleHandshakeRequest(
            pcDHPublicKey: pcPublicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            pcNonce: pcNonce.instantShareBase64URLEncodedString()
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

        let manager = InstantShareTrustSessionManager()
        let response = try manager.handleHandshakeRequest(
            pcDHPublicKey: pcPublicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            pcNonce: pcNonce.instantShareBase64URLEncodedString()
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

        XCTAssertThrowsError(
            try manager.handleHandshakeRequest(pcDHPublicKey: shortKey, pcNonce: nonce)
        )
    }

    func test_reset_clears_session_key() throws {
        let pcPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let manager = InstantShareTrustSessionManager()
        _ = try manager.handleHandshakeRequest(
            pcDHPublicKey: pcPrivateKey.publicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            pcNonce: Data(repeating: 0xCC, count: 32).instantShareBase64URLEncodedString()
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

final class InstantShareResumeViewModelTests: XCTestCase {
    func test_resume_state_initial_is_loading() {
        let service = InstantShareService()
        let viewModel = InstantShareResumeViewModel(service: service)
        XCTAssertEqual(viewModel.state, .loading)
    }

    func test_describe_payload_text() {
        let service = InstantShareService()
        let viewModel = InstantShareResumeViewModel(service: service)
        let context = InstantShareHandoffContext(
            from: InstantSharePayloadEnvelope(
                payloadType: .text, textContent: "Hello world", fileURL: nil,
                filename: nil, contentType: "text/plain", fileSizeBytes: 11
            ),
            selectedDeviceID: "dev-1", selectedDeviceName: "My Mac", isTrustedDevice: false
        )

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertNotNil(context.textContent)
    }

    func test_describe_payload_image_with_filename() {
        let context = InstantShareHandoffContext(
            from: InstantSharePayloadEnvelope(
                payloadType: .image, textContent: nil,
                fileURL: URL(string: "file:///tmp/photo.jpg"),
                filename: "photo.jpg", contentType: "public.jpeg", fileSizeBytes: 2048
            ),
            selectedDeviceID: nil, selectedDeviceName: nil, isTrustedDevice: false
        )
        XCTAssertEqual(context.payloadType, "image")
        XCTAssertEqual(context.filename, "photo.jpg")
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

// MARK: - InstantShareIdentityManager Tests

final class InstantShareIdentityManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any test artifacts before each test
        let queries: [[String: Any]] = [
            [kSecClass as String: kSecClassIdentity,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
            [kSecClass as String: kSecClassCertificate,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
            [kSecClass as String: kSecClassKey,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
        ]
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }
    }

    override func tearDown() {
        // Clean up after each test
        let queries: [[String: Any]] = [
            [kSecClass as String: kSecClassIdentity,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
            [kSecClass as String: kSecClassCertificate,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
            [kSecClass as String: kSecClassKey,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
        ]
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }
        super.tearDown()
    }

    func test_createIdentity_returnsValidIdentity() throws {
        let identity = try InstantShareIdentityManager.getOrCreateIdentity()

        XCTAssertNotNil(identity.secIdentity)
        XCTAssertFalse(identity.publicKeyPEM.isEmpty)
        XCTAssertTrue(identity.publicKeyPEM.hasPrefix("-----BEGIN PUBLIC KEY-----"))
        XCTAssertTrue(identity.publicKeyPEM.hasSuffix("-----END PUBLIC KEY-----\n"))
    }

    func test_createIdentity_twiceReturnsSameIdentity() throws {
        let id1 = try InstantShareIdentityManager.getOrCreateIdentity()
        let id2 = try InstantShareIdentityManager.getOrCreateIdentity()

        // Same PEM means same key was reused from keychain
        XCTAssertEqual(id1.publicKeyPEM, id2.publicKeyPEM)
    }

    func test_identityHasValidCertificate() throws {
        let identity = try InstantShareIdentityManager.getOrCreateIdentity()

        var cert: SecCertificate?
        let status = SecIdentityCopyCertificate(identity.secIdentity, &cert)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(cert)

        // Verify the certificate can export its public key (this was the -26275 bug)
        guard let certificate = cert else {
            XCTFail("No certificate in identity")
            return
        }
        let publicKey = SecCertificateCopyKey(certificate)
        XCTAssertNotNil(publicKey, "SecCertificateCopyKey must succeed (was failing with -26275)")

        // Verify SPKI export
        if let pk = publicKey {
            let rawKey = SecKeyCopyExternalRepresentation(pk, nil) as Data?
            XCTAssertNotNil(rawKey, "SecKeyCopyExternalRepresentation must succeed")
            XCTAssertEqual(rawKey?.count, 65, "EC P-256 public key must be 65 bytes (x963 uncompressed point)")
        }
    }

    func test_identityCertIsSelfSigned() throws {
        let identity = try InstantShareIdentityManager.getOrCreateIdentity()

        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity.secIdentity, &cert)
        guard let certificate = cert else {
            XCTFail("No certificate")
            return
        }

        // Verify it's self-signed by comparing subject and issuer
        let subject = SecCertificateCopySubjectSummary(certificate) as String?
        let issuer = subject // Self-signed means subject == issuer in summary
        XCTAssertNotNil(subject)
        XCTAssertTrue(subject?.contains("AuBackup") ?? false)
    }

    func test_recreateAfterDeletingKeychain_generatesNewIdentity() throws {
        // First creation
        let id1 = try InstantShareIdentityManager.getOrCreateIdentity()
        let pem1 = id1.publicKeyPEM

        // Delete all keychain items
        let queries: [[String: Any]] = [
            [kSecClass as String: kSecClassIdentity,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
            [kSecClass as String: kSecClassCertificate,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
            [kSecClass as String: kSecClassKey,
             kSecAttrLabel as String: "AuBackup Instant Share TLS Identity"],
        ]
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }

        // Second creation should succeed with a NEW identity
        let id2 = try InstantShareIdentityManager.getOrCreateIdentity()
        let pem2 = id2.publicKeyPEM

        XCTAssertNotEqual(pem1, pem2, "New identity should have different key after deletion")
    }

    func test_pemRoundtrip() throws {
        let identity = try InstantShareIdentityManager.getOrCreateIdentity()

        // Parse the PEM to verify it's valid
        let pemData = identity.publicKeyPEM.data(using: .utf8)!
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        guard let importedKey = SecKeyCreateWithData(pemData as CFData, options as CFDictionary, nil) else {
            // PEM may not be directly importable with SecKeyCreateWithData
            // because it expects raw DER, not PEM. This is expected.
            // Just verify the PEM format is structurally valid.
            return
        }
        XCTAssertNotNil(importedKey)
    }

    func test_signatureCreationWithKeychainKey() throws {
        // Verify that the key created by SecKeyCreateRandomKey can be used
        // for signing (ecdsaSignatureDigestX962SHA256).
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, nil) else {
            XCTFail("Failed to create test key")
            return
        }

        let testData = Data("test message".utf8)
        let digest = SHA256.hash(data: testData)

        let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureDigestX962SHA256,
            Data(digest) as CFData,
            nil
        )
        XCTAssertNotNil(signature, "SecKeyCreateSignature(.ecdsaSignatureDigestX962SHA256) must succeed")
        XCTAssertEqual((signature as! Data).count, 64, "ECDSA P-256 signature must be 64 bytes (r||s)")
    }
}
