import CryptoKit
import Foundation
import Security

enum X509SelfSignedCertificate {

    /// DER-encode an ASN.1 TLV.
    static func encodeASN1(tag: UInt8, value: Data) -> Data {
        var result = Data([tag])
        if value.count < 128 {
            result.append(UInt8(value.count))
        } else {
            var lenBytes = Data()
            var rem = value.count
            while rem > 0 {
                lenBytes.insert(UInt8(rem & 0xFF), at: 0)
                rem >>= 8
            }
            result.append(UInt8(0x80 | lenBytes.count))
            result.append(lenBytes)
        }
        result.append(value)
        return result
    }

    /// Convenience: DER-encode an ASN.1 INTEGER TLV.
    static func tlv(tag: UInt8, value: Data) -> Data {
        return encodeASN1(tag: tag, value: value)
    }

    /// Build SubjectPublicKeyInfo for an EC P-256 raw public key.
    static func encodeSubjectPublicKeyInfo(_ rawPublicKey: Data) -> Data {
        let ecPubOID = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
        let p256OID = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        let algoParams = encodeASN1(tag: 0x30, value: ecPubOID + p256OID)
        let pubKey = encodeASN1(tag: 0x03, value: Data([0x00]) + rawPublicKey)
        return encodeASN1(tag: 0x30, value: algoParams + pubKey)
    }
}

// MARK: - DistinguishedName

struct DistinguishedName {
    let commonName: String

    func encode() -> Data {
        let cnOID = Data([0x06, 0x03, 0x55, 0x04, 0x03])
        let cnValue = X509SelfSignedCertificate.encodeASN1(
            tag: 0x0C,
            value: Data(commonName.utf8)
        )
        let cnSet = X509SelfSignedCertificate.encodeASN1(
            tag: 0x31,
            value: cnOID + cnValue
        )
        return X509SelfSignedCertificate.encodeASN1(tag: 0x30, value: cnSet)
    }
}
