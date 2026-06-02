import CryptoKit
import Foundation
import XCTest
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

final class InstantShareHTTPRequestParserTests: XCTestCase {
    func test_parse_post_request_with_json_body() {
        let rawHTTP = "POST /api/instant-share/v1/trust/handshake HTTP/1.1\r\n" +
            "Content-Type: application/json\r\n" +
            "X-Session-Id: abc-123\r\n" +
            "Content-Length: 27\r\n" +
            "\r\n" +
            "{\"flow_id\":\"instant_share\"}"

        let data = Data(rawHTTP.utf8)
        let request = InstantShareHTTPRequest.parse(from: data)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/api/instant-share/v1/trust/handshake")
        XCTAssertEqual(request?.headers["Content-Type"], "application/json")
        XCTAssertEqual(request?.headers["X-Session-Id"], "abc-123")
        XCTAssertEqual(request?.jsonBody?["flow_id"] as? String, "instant_share")
    }

    func test_parse_request_without_body() {
        let rawHTTP = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(rawHTTP.utf8)
        let request = InstantShareHTTPRequest.parse(from: data)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/health")
        XCTAssertTrue(request?.body.isEmpty ?? false)
        XCTAssertNil(request?.jsonBody)
    }

    func test_parse_returns_nil_for_incomplete_headers() {
        let incomplete = "POST /test HTTP/1.1\r\nContent-Length: 10"
        let data = Data(incomplete.utf8)
        let request = InstantShareHTTPRequest.parse(from: data)
        XCTAssertNil(request)
    }

    func test_parse_returns_nil_for_incomplete_body() {
        let rawHTTP = "POST /test HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort"
        let data = Data(rawHTTP.utf8)
        let request = InstantShareHTTPRequest.parse(from: data)
        XCTAssertNil(request)
    }

    func test_response_serialize_includes_status_and_headers() {
        let response = InstantShareHTTPResponse.json(status: 200, body: ["ack": true])
        let serialized = response.serialize()
        let serializedString = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedString.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(serializedString.contains("Content-Type: application/json"))
        XCTAssertTrue(serializedString.contains("Connection: close"))
    }

    func test_bad_request_response_includes_error_code() {
        let response = InstantShareHTTPResponse.badRequest(errorCode: "PAYLOAD_UNREADABLE", message: "Bad data")
        let serialized = response.serialize()
        let serializedString = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(serializedString.contains("400 Bad Request"))
        XCTAssertTrue(serializedString.contains("PAYLOAD_UNREADABLE"))
    }
}