//
//  ISQRResultViewModel.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//

import SwiftUI

@MainActor
protocol ISQRDeliverDelegate {
    func onDeliverComplete() -> Void
}

@MainActor
class ISQRResultViewModel: ObservableObject {
    let delegate: ISQRDeliverDelegate
    init(delegate: ISQRDeliverDelegate) {
        self.delegate = delegate
    }
    
    func onComplete() -> Void {
        delegate.onDeliverComplete()
    }
}
