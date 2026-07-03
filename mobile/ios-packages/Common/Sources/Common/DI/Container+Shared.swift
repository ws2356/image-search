//
//  Container+Shared.swift
//  ISFromMobile
//
//  Registers dependencies shared by both the main app (AlbumTransporterKit)
//  and the Share Extension so that both targets get the same singleton instances
//  per process and read/write the same App Group UserDefaults.
//
import Foundation
import Factory
import Common

extension Container {
    public var localDeviceIdentityProvider: Factory<LocalDeviceIdentifierProviding> {
        self {
            LocalDeviceIdentifierStore(userDefaults: self.sharedStorageProvider().appGroupUserDefaults,
                                       installIDKey: LocalDeviceIdentifierStore.installIDKey,
                                       deviceUUIDKey: LocalDeviceIdentifierStore.deviceUUIDKey) }
            .singleton
    }

    public var appIdentityProvider: Factory<AppIdentityProviding> {
        self { KeychainAppIdentityProvider(localDeviceIdentifierProvider: self.localDeviceIdentityProvider(),
                                           userDefaults: self.sharedStorageProvider().appGroupUserDefaults) }
        .singleton
    }
    
    public var sharedStorageProvider: Factory<SharedStorageProtocol> {
        self { SharedStorageProvider() }
            .singleton
    }
}
