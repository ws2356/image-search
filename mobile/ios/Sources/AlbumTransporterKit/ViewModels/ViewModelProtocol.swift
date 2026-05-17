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
    case invalidQR(detail: QRCodePayloadDecoderError)
    case pairingFailed
    case unexpectedPhase
    case cancelled
    case unknown
    
    var title: String {
        switch self {
        case .invalidQR(let detail):
            return detail.title
        case .pairingFailed:
            return "Pairing Failed"
        case .unexpectedPhase:
            return "Unexpected Pairing Status"
        case .cancelled:
            return "Pairing Cancelled"
        case .unknown:
            return "Unknown Pairing Error"
        }
    }

    var message: String {
        switch self {
        case .invalidQR(let detail):
            return detail.message
        case .pairingFailed:
            return "Pairing failed. Please try again."
        case .unexpectedPhase:
            return "Unexpected pairing status. Please try again."
        case .cancelled:
            return "Pairing was cancelled."
        case .unknown:
            return "An unknown error occurred during pairing."
        }
    }
}

struct PairingPageResult {
    let result: Result<Void, PairingPageError>
    let pairingStatus: PairingStatus?
    
    init(result: Result<Void, PairingPageError>, pairingStatus: PairingStatus? = nil) {
        self.result = result
        self.pairingStatus = pairingStatus
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
