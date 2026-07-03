//
//  QRScanTipBuilder.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//
import SwiftUI

public struct QRScanTipBuilder {
    static public func buildBackupSessionScanTips() -> some View {
        buildScanTipsImpl {
            Self.buildBackupQRScanTipsContent()
        }
    }
    
    static public func buildInstantShareScanTips() -> some View {
        return buildScanTipsImpl {
            Self.buildInstantShareQRScanTipsContent()
        }
    }
    
    public static func buildGenericQRScanTips() -> some View {
        buildScanTipsImpl {
            Self.buildBackupQRScanTipsContent()
            Text("")
            Text("")
            Self.buildInstantShareQRScanTipsContent()
        }
    }

    static func buildScanTipsImpl(@ViewBuilder buildContent: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            buildContent()
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    static func buildBackupQRScanTipsContent() -> some View {
        Group {
            Text("Wanna back up your mobile album to PC?")
                .font(.system(size: 15, weight: .semibold))
            Text("1. Open https://aurora.boldman.net on your PC browser then install and launch AuSearch.")
            Text("2. Click 'Add Folder'.")
            Text("3. Select 'Mobile Device'.")
            Text("4. Scan the QR code.")
        }
    }
    
    static func buildInstantShareQRScanTipsContent() -> some View {
        Group {
            Text("Wanna receive text or files from your PC?")
                .font(.system(size: 15, weight: .semibold))
            Text("1. Download and install AuSearch from https://aurora.boldman.net")
            Text("2. (Optionally) Enable InstantShare extension: System Settings > General > Login Items & Extensions > Sharing > InstantShare.")
            Text("3. Right click text or file, then ‘Share > InstantShare’ to show the QR code.")
            Text("4. Scan the QR code.")
        }
    }
}
