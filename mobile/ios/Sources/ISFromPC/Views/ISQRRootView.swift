//
//  ISQRRootView.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//
import SwiftUI

public struct ISQRRootView: View {
    @Environment(\.dismiss) private var dismiss
    
    let qrPayload: QRClaimPayload
    
    public init(qrPayload: QRClaimPayload) {
        self.qrPayload = qrPayload
    }
    
    public var body: some View {
    }
}
