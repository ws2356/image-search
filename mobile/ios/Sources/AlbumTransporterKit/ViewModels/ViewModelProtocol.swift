//
//  ViewModelProtocol.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/5/5.
//

enum PageTarget: Equatable {
    case primary
    case secondary
    case stopTransferConfirmed
}

// MARK: - Page-Specific Result Types

enum HomeClickTarget: Equatable, Sendable {
    case backupScan
    case genericScan
}

enum HomePageError: Error, Equatable {
    case unknown
}

struct HomePageResult {
    let result: Result<HomeClickTarget, HomePageError>
}

enum ScanningPageError: Error, Equatable {
    case cancel
    case scannerFailed
    case unknown
}

struct ScanningPageResult {
    let result: Result<String, ScanningPageError>  // Success contains scanned QR string
}

struct PairingPageResult {
    let result: Result<PairingResponse, PairingError>

    init(result: Result<PairingResponse, PairingError>) {
        self.result = result
    }
}

enum PermissionsPageError: Error, Equatable {
    case preflightFailed
    case lowBatteryDeclined
    case permissionsCancelled
    case unknown
}

struct PermissionsPageResult {
    let result: Result<Void, PermissionsPageError>
}

enum TransferPageError: Error, Equatable {
    case transferFailed
    case stopConfirmed
    case unknown
}

struct TransferPageResult {
    let result: Result<Void, TransferPageError>
    let target: PageTarget?
}

enum GenericQRScanPageError: Error, Equatable {
    case cancel
    case scannerFailed
    case unknown
}

struct GenericQRScanPageResult {
    let result: Result<String, GenericQRScanPageError>
}

enum CompletionPageError: Error, Equatable {
    case completionFailed
    case unknown
}

struct CompletionPageResult {
    let result: Result<Void, CompletionPageError>
}

enum ErrorPageError: Error, Equatable {
    case unknown
}

struct ErrorPageResult {
    let result: Result<Void, ErrorPageError>
}
