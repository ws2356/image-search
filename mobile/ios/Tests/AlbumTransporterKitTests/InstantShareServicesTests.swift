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