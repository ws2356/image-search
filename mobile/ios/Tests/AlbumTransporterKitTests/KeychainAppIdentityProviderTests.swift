import Foundation
import Security
import XCTest
@testable import Common

final class KeychainAppIdentityProviderTests: XCTestCase {
    private var provider: KeychainAppIdentityProvider!
    private let testPeerID = "test-peer-device"
    private let testPeerID2 = "test-peer-device-2"

    override func setUp() async throws {
        try await super.setUp()
        provider = KeychainAppIdentityProvider(
            localDeviceIdentifierProvider: LocalDeviceIdentifierStore(deviceUUIDKey: "test-peer-provider-uuid")
        )
    }

    override func tearDown() async throws {
        try? provider.deletePeerCertificate(for: testPeerID, cert: nil)
        try? provider.deletePeerCertificate(for: testPeerID2, cert: nil)
        provider = nil
        try await super.tearDown()
    }

    func test_importPeerCertificate_secCertificate_roundTrip() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, isPersist: false)

        try await provider.importPeerCertificate(selfCert, for: testPeerID)
        let retrieved = try provider.peerCertificate(for: testPeerID)

        let originalKeyData = try publicKeyData(from: selfCert)
        let retrievedKeyData = try publicKeyData(from: retrieved)
        XCTAssertEqual(originalKeyData, retrievedKeyData)
    }

    func test_importPeerCertificate_pem_roundTrip() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, isPersist: false)

        let pem = derDataToPem(try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?))
        try await provider.importPeerCertificate(pem: pem, for: testPeerID)
        let retrieved = try provider.peerCertificate(for: testPeerID)

        let originalKeyData = try publicKeyData(from: selfCert)
        let retrievedKeyData = try publicKeyData(from: retrieved)
        XCTAssertEqual(originalKeyData, retrievedKeyData)
    }

    func test_importPeerCertificate_pem_overwritesExisting() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, isPersist: false)
        let pem = derDataToPem(try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?))

        try await provider.importPeerCertificate(pem: pem, for: testPeerID)
        try await provider.importPeerCertificate(pem: pem, for: testPeerID)
        let retrieved = try provider.peerCertificate(for: testPeerID)

        let originalKeyData = try publicKeyData(from: selfCert)
        let retrievedKeyData = try publicKeyData(from: retrieved)
        XCTAssertEqual(originalKeyData, retrievedKeyData)
    }

    func test_peerCertificate_notFound_throws() {
        XCTAssertThrowsError(try provider.peerCertificate(for: "non-existent-peer"))
    }

    func test_importPeerCertificate_invalidPem_throws() async {
        do {
            try await provider.importPeerCertificate(pem: "not-a-valid-pem", for: testPeerID)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is KeychainError)
        }
    }

    // MARK: - Helpers

    private func derDataToPem(_ derData: Data) -> String {
        let base64 = derData.base64EncodedString(options: .lineLength64Characters)
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----"
    }

    private func publicKeyData(from cert: SecCertificate) throws -> Data {
        guard let publicKey = SecCertificateCopyKey(cert) else {
            throw KeychainError.unexpectedData
        }
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw KeychainError.unexpectedData
        }
        return keyData
    }
}
