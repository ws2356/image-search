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


extension Container {
    public var localDeviceIdentityProvider: Factory<LocalDeviceIdentifierProviding> {
        self {
            LocalDeviceIdentifierStore(userDefaults: self.sharedStorageProvider().commonAppGroupUserDefaults,
                                       installIDKey: LocalDeviceIdentifierStore.installIDKey,
                                       deviceUUIDKey: LocalDeviceIdentifierStore.deviceUUIDKey) }
            .singleton
    }

    public var appIdentityProvider: Factory<AppIdentityProviding> {
        self { KeychainAppIdentityProvider(localDeviceIdentifierProvider: self.localDeviceIdentityProvider(),
                                           userDefaults: self.sharedStorageProvider().commonAppGroupUserDefaults) }
        .singleton
    }
    
    public var sharedStorageProvider: Factory<SharedStorageProtocol> {
        self { SharedStorageProvider() }
            .singleton
    }
}
