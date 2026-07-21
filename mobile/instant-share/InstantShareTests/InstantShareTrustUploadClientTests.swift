import CryptoKit
import XCTest

@testable import ISFromMobile

final class InstantShareTrustClientTests: XCTestCase {
    private var trustSessionManager: InstantShareTrustSessionManager!

    override func setUp() {
        super.setUp()
        trustSessionManager = InstantShareTrustSessionManager()
    }

    override func tearDown() {
        trustSessionManager = nil
        super.tearDown()
    }

    func testTrustSessionManagerGeneratesPublicKey() {
        XCTAssertFalse(trustSessionManager.publicKeyBase64URL.isEmpty)
    }

    func testTrustSessionManagerIsNotEstablishedBeforeHandshake() {
        XCTAssertFalse(trustSessionManager.isEstablished)
    }

    func testTrustSessionManagerResetClearsKey() {
        let originalKey = trustSessionManager.publicKeyBase64URL
        trustSessionManager.reset()
        XCTAssertNotEqual(trustSessionManager.publicKeyBase64URL, originalKey)
        XCTAssertFalse(trustSessionManager.isEstablished)
    }

    func testTrustEnvelopeEncryptionDecryption() throws {
        let alice = InstantShareTrustSessionManager()
        let alicePublicKeyBase64 = alice.publicKeyBase64URL

        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        let pcPublicKeyData = ephemeralKey.publicKey.rawRepresentation
        let pcNonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let pcKdfContext = Data([UInt8](repeating: 0xDD, count: 16)).instantShareBase64URLEncodedString()
        let mobileNonce = Data([UInt8](repeating: 0xEE, count: 32)).instantShareBase64URLEncodedString()

        let handshakeResponse = try alice.handleHandshakeRequest(
            pcDHPublicKey: pcPublicKeyData.instantShareBase64URLEncodedString(),
            pcNonce: pcNonce.instantShareBase64URLEncodedString(),
            pcKdfContext: pcKdfContext,
            mobileNonce: mobileNonce
        )

        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(
            with: try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(instantShareBase64URLEncoded: handshakeResponse.mobileDHPublicKey))
        )
        let kdfContextData = try Data(instantShareBase64URLEncoded: handshakeResponse.kdfContext)
        let sessionKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pcNonce + (try Data(instantShareBase64URLEncoded: handshakeResponse.mobileNonce)),
            sharedInfo: Data("dtis.instant-share.trust-session.v1".utf8) + kdfContextData,
            outputByteCount: 32
        )

        let payload: [String: Any] = ["action": "request_pin"]
        let envelope = try InstantShareTrustSessionProtector.encryptPayloadObject(payload, sessionKey: sessionKey)
        let decrypted = try InstantShareTrustSessionProtector.decryptPayloadObject(envelope, sessionKey: sessionKey)
        XCTAssertEqual(decrypted["action"] as? String, "request_pin")
    }
}

final class InstantShareUploadClientErrorTests: XCTestCase {
    func testUploadClientErrorDescriptions() {
        let trustRequired = InstantShareUploadClientError.trustRequired
        XCTAssertNotNil(trustRequired.errorDescription)
        XCTAssertTrue(trustRequired.errorDescription!.contains("Trust"))

        let sessionNotFound = InstantShareUploadClientError.sessionNotFound
        XCTAssertNotNil(sessionNotFound.errorDescription)

        let uploadFailed = InstantShareUploadClientError.uploadFailed("test")
        XCTAssertNotNil(uploadFailed.errorDescription)
    }
}

final class InstantShareTrustClientErrorTests: XCTestCase {
    func testTrustClientErrorDescriptions() {
        let handshakeFailed = InstantShareTrustClientError.handshakeFailed("test")
        XCTAssertNotNil(handshakeFailed.errorDescription)

        let applyFailed = InstantShareTrustClientError.applyFailed("test")
        XCTAssertNotNil(applyFailed.errorDescription)

        let confirmFailed = InstantShareTrustClientError.confirmFailed("test")
        XCTAssertNotNil(confirmFailed.errorDescription)

        let sessionKeyNotEstablished = InstantShareTrustClientError.sessionKeyNotEstablished
        XCTAssertNotNil(sessionKeyNotEstablished.errorDescription)

        let httpError = InstantShareTrustClientError.httpError(statusCode: 400, errorCode: "INVALID_REQUEST", message: "Bad request")
        XCTAssertNotNil(httpError.errorDescription)
        XCTAssertTrue(httpError.errorDescription!.contains("400"))
    }
}
