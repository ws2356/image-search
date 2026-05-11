//
//  ViewModelProtocol.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/5/5.
//

enum PageResult: Equatable {
    case success
    case failure
    case cancel
}

enum PageTarget: Equatable {
    case primary
    case secondary
    case lowBatteryDeclined
    case removeTransferredMedia
    case keepOriginals
    case stopTransferConfirmed
}
