//
//  LocalDeviceIdentifierStore.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/12.
//
import Combine
import Foundation
import UIKit

public protocol LocalDeviceIdentifierProviding: Sendable {
    func currentIdentifier() async -> LocalDeviceIdentifier
}

public struct LocalDeviceIdentifier: Codable, Equatable, Sendable {
    public let installID: String
    public let deviceUUID: String
    public let deviceName: String
    public let platform: String
    
    public init(installID: String, deviceUUID: String, deviceName: String, platform: String) {
        self.installID = installID
        self.deviceUUID = deviceUUID
        self.deviceName = deviceName
        self.platform = platform
    }
}

public actor LocalDeviceIdentifierStore: LocalDeviceIdentifierProviding {
    private let userDefaults: UserDefaults
    private let installIDKey: String
    private let deviceUUIDKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        installIDKey: String = "albumtransporter.install-id",
        deviceUUIDKey: String = "albumtransporter.device-uuid"
    ) {
        self.userDefaults = userDefaults
        self.installIDKey = installIDKey
        self.deviceUUIDKey = deviceUUIDKey
    }

    public func currentIdentifier() async -> LocalDeviceIdentifier {
        let installID = storedValue(forKey: installIDKey)
        let deviceUUID = storedValue(forKey: deviceUUIDKey)
        return LocalDeviceIdentifier(
            installID: installID,
            deviceUUID: deviceUUID,
            deviceName: currentDeviceName(),
            platform: "ios"
        )
    }

    private func storedValue(forKey key: String) -> String {
        if let existingValue = userDefaults.string(forKey: key), !existingValue.isEmpty {
            return existingValue
        }

        let generatedValue = UUID().uuidString.lowercased()
        userDefaults.set(generatedValue, forKey: key)
        return generatedValue
    }

    private func currentDeviceName() -> String {
        UIDevice.current.name
    }
}

