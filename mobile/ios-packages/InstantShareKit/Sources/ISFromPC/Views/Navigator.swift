//
//  Navigator.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//

import SwiftUI

@MainActor
public protocol Navigator {
    func requestExit() -> Void
}

@MainActor
public protocol NavigatorFactory {
    func createNavigator() -> Navigator
}
