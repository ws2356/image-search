//
//  SharedStorageProvider.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/23.
//

import Foundation

public protocol SharedStorageProtocol {
    var commonAppGroupUserDefaults: UserDefaults { get }
}

let appGroupIdentifier = "group.net.boldman.common"

public class SharedStorageProvider: SharedStorageProtocol {
    public let commonAppGroupUserDefaults: UserDefaults = .init(suiteName: appGroupIdentifier)!
}
