//
//  QRClaimViewModel.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//

import SwiftUI

@MainActor
public class ISQRRootViewModel: ObservableObject {
    let qrClaimPayload: QRClaimPayload
    init(qrClaimPayload: QRClaimPayload) {
        self.qrClaimPayload = qrClaimPayload
    }
}
