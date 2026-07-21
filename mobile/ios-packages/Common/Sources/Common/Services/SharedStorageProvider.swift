//
//  SharedStorageProvider.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/23.
//

import Foundation

public protocol SharedStorageProtocol {
    var commonAppGroupUserDefaults: UserDefaults { get }
    var snapgetAppGroupUserDefaults: UserDefaults { get }
    var hasCompletedSession: Bool { get set }
}

let appGroupIdentifier = "group.net.boldman.common"
let snapgetAppGroupIdentifier = "group.net.boldman.snapget"

public class SharedStorageProvider: SharedStorageProtocol {
    public let commonAppGroupUserDefaults: UserDefaults = .init(suiteName: appGroupIdentifier)!
    public let snapgetAppGroupUserDefaults: UserDefaults = .init(suiteName: snapgetAppGroupIdentifier)!

    public var hasCompletedSession: Bool {
        get { snapgetAppGroupUserDefaults.bool(forKey: "hasCompletedSession") }
        set { snapgetAppGroupUserDefaults.set(newValue, forKey: "hasCompletedSession") }
    }

    public init() {}
}
