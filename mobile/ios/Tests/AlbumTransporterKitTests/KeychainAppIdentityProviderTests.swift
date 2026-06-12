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
        try? deletePeerCertificate(for: testPeerID)
        try? deletePeerCertificate(for: testPeerID2)
        provider = nil
        try await super.tearDown()
    }

    func test_importPeerCertificate_secCertificate_roundTrip() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, isPersist: false)

        try await provider.importPeerCertificate(selfCert, for: testPeerID)
        let retrieved = try provider.peerCertificate(for: testPeerID)

        let originalData = try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?)
        let retrievedData = try XCTUnwrap(SecCertificateCopyData(retrieved) as Data?)
        XCTAssertEqual(originalData, retrievedData)
    }

    func test_importPeerCertificate_pem_roundTrip() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, isPersist: false)
        let derData = try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?)

        let pem = derDataToPem(derData)
        try await provider.importPeerCertificate(pem: pem, for: testPeerID)
        let retrieved = try provider.peerCertificate(for: testPeerID)

        let retrievedData = try XCTUnwrap(SecCertificateCopyData(retrieved) as Data?)
        XCTAssertEqual(derData, retrievedData)
    }

    func test_importPeerCertificate_pem_overwritesExisting() async throws {
        try await provider.ensureSelfIdentity()
        let selfCert = try await provider.createIdentity(commonName: testPeerID, isPersist: false)
        let derData = try XCTUnwrap(SecCertificateCopyData(selfCert) as Data?)
        let pem = derDataToPem(derData)

        try await provider.importPeerCertificate(pem: pem, for: testPeerID)
        try await provider.importPeerCertificate(pem: pem, for: testPeerID)
        let retrieved = try provider.peerCertificate(for: testPeerID)
        let retrievedData = try XCTUnwrap(SecCertificateCopyData(retrieved) as Data?)
        XCTAssertEqual(derData, retrievedData)
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

    private func deletePeerCertificate(for peerDeviceID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrApplicationTag as String: peerDeviceID.data(using: .utf8) as Any,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func derDataToPem(_ derData: Data) -> String {
        let base64 = derData.base64EncodedString(options: .lineLength64Characters)
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----"
    }
}
