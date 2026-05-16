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

enum HomePageError: Error, Equatable {
    case unknown
}

struct HomePageResult {
    let result: Result<Void, HomePageError>
}

enum ScanningPageError: Error, Equatable {
    case scannerFailed
    case unknown
}

struct ScanningPageResult {
    let result: Result<String, ScanningPageError>  // Success contains scanned QR string
}

enum PairingPageError: Error, Equatable {
    case pairingFailed
    case cancelled
    case unknown
}

struct PairingPageResult {
    let result: Result<Void, PairingPageError>
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
