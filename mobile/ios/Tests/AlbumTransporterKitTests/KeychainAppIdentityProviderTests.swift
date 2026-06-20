import Foundation
import Security
import XCTest
@testable import Common

final class KeychainAppIdentityProviderTests: XCTestCase {
    private var provider: KeychainAppIdentityProvider!
    private let testPeerID = "test-peer-device"

    override func setUp() async throws {
        try await super.setUp()
        provider = KeychainAppIdentityProvider(
            localDeviceIdentifierProvider: LocalDeviceIdentifierStore(deviceUUIDKey: "test-peer-provider-uuid")
        )
    }

    override func tearDown() async throws {
        provider = nil
        try await super.tearDown()
    }

    func test_importPeerCertificate_secCertificate_roundTrip() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, deviceUUID: UUID().uuidString, isPersist: false)
        let pubkeyHash = try XCTUnwrap(selfCert.publicKeyHash)

        try await provider.importPeerCertificate(selfCert)
        let retrieved = try XCTUnwrap(provider.peerCertificate(forPubkeyHash: pubkeyHash))

        let originalKeyData = try publicKeyData(from: selfCert)
        let retrievedKeyData = try publicKeyData(from: retrieved)
        XCTAssertEqual(originalKeyData, retrievedKeyData)
    }

    func test_importPeerCertificate_pem_roundTrip() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, deviceUUID: UUID().uuidString, isPersist: false)

        let pem = derDataToPem(try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?))
        try await provider.importPeerCertificate(pem: pem)
        let retrieved = try XCTUnwrap(provider.peerCertificate(for: selfCert))

        let originalKeyData = try publicKeyData(from: selfCert)
        let retrievedKeyData = try publicKeyData(from: retrieved)
        XCTAssertEqual(originalKeyData, retrievedKeyData)
    }

    func test_importPeerCertificate_pem_overwritesExisting() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, deviceUUID: UUID().uuidString, isPersist: false)
        let pem = derDataToPem(try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?))

        try await provider.importPeerCertificate(pem: pem)
        try await provider.importPeerCertificate(pem: pem)
        let retrieved = try XCTUnwrap(provider.peerCertificate(for: selfCert))

        let originalKeyData = try publicKeyData(from: selfCert)
        let retrievedKeyData = try publicKeyData(from: retrieved)
        XCTAssertEqual(originalKeyData, retrievedKeyData)
    }

    func test_peerCertificate_notFound_returnsNil() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: "unknown-peer", deviceUUID: UUID().uuidString, isPersist: false)
        // Use a random hash that won't match
        let randomHash = Data(repeating: 0, count: 20)
        XCTAssertNil(try provider.peerCertificate(forPubkeyHash: randomHash))
    }

    func test_importPeerCertificate_invalidPem_throws() async {
        do {
            try await provider.importPeerCertificate(pem: "not-a-valid-pem")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is KeychainError)
        }
    }

    func test_deletePeerCertificate_byPubkeyHash() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, deviceUUID: UUID().uuidString, isPersist: false)
        let pubkeyHash = try XCTUnwrap(selfCert.publicKeyHash)

        try await provider.importPeerCertificate(selfCert)
        XCTAssertNotNil(try provider.peerCertificate(forPubkeyHash: pubkeyHash))

        try provider.deletePeerCertificate(forPubkeyHash: pubkeyHash)
        XCTAssertNil(try provider.peerCertificate(forPubkeyHash: pubkeyHash))
    }

    func test_loadAllPeerCertificates() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, deviceUUID: UUID().uuidString, isPersist: false)
        try await provider.importPeerCertificate(selfCert)

        let allCerts = try provider.loadAllPeerCertificates()
        XCTAssertFalse(allCerts.isEmpty)
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
