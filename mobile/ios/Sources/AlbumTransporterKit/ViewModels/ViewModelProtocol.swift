//
//  ViewModelProtocol.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/5/5.
//

enum PageResult {
    case success
    case failure
    case cancel
}

enum PageTarget {
    case primary
    case secondary
}

protocol ViewModelProtocol {
    func onPageResult(_ result: PageResult, target: PageTarget?)
}
