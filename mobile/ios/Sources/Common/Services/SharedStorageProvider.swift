//
//  SharedStorageProvider.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/23.
//

import Foundation

public protocol SharedStorageProtocol {
    var appGroupUserDefaults: UserDefaults { get }
}

let appGroupIdentifier = "group.com.aubackup.instant-share"

public class SharedStorageProvider: SharedStorageProtocol {
    public let appGroupUserDefaults: UserDefaults = .init(suiteName: appGroupIdentifier)!
}
