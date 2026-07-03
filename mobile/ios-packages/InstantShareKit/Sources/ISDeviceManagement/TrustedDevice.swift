import Foundation

public struct TrustedDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let pubkeyHash: Data

    public init(id: String, name: String, pubkeyHash: Data) {
        self.id = id
        self.name = name
        self.pubkeyHash = pubkeyHash
    }
}
