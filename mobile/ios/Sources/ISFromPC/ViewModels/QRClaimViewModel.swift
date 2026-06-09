//
//  QRClaimViewModel.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//

import SwiftUI

@MainActor
public class QRClaimViewModel: ObservableObject {
    let qrClaimPayload: QRClaimPayload
    init(qrClaimPayload: QRClaimPayload) {
        self.qrClaimPayload = qrClaimPayload
    }
    
    func claimQR(_ payload: QRClaimPayload) async {
        let client = QRTriggerDownloadClient()
        do {
            let result = try await client.claim(
                hosts: payload.ips,
                port: payload.port,
                stashId: payload.stashId,
                optCode: payload.optCode
            )
        } catch {
        }
    }

}
