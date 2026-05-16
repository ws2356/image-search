import Foundation

@MainActor
protocol AppPageModeling: AnyObject {
    var backupSessionProvider: BackupSessionProviding { get }
    var backupFlowState: MobileBackupFlowState { get }
    var pairingStatus: PairingStatus { get }
    var permissionService: PermissionService { get }
    var transferServiceForPageModels: TransferService { get }
    var errorSummary: ErrorSummary { get }
    var route: AppRoute { get }
    var scannedQRCodeValue: String { get set }

    // Legacy method (for backward compatibility during migration)
    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async
    
    // New page-specific result handlers
    func onHomeCompleted(with result: HomePageResult) async
    func onScanningCompleted(with result: ScanningPageResult) async
    func onPairingCompleted(with result: PairingPageResult) async
    func onPermissionsCompleted(with result: PermissionsPageResult) async
    func onTransferCompleted(with result: TransferPageResult) async
    func onCompletionCompleted(with result: CompletionPageResult) async
    func onErrorCompleted(with result: ErrorPageResult) async
    
    func requestStopTransfer()
}

extension MobileAppModel: AppPageModeling {}

@MainActor
protocol PermissionsPageModeling: AppPageModeling {
    var pairingService: PairingService { get }
    func abortPreflightAndReturnHome(reason: String) async
}

extension MobileAppModel: PermissionsPageModeling {}

@MainActor
protocol PairingPageModeling: AppPageModeling {
    var pairingService: PairingService { get }
    func handleInvalidPairingPayload(message: String)
    func handlePairingAttemptCompleted(_ result: PairingStatus) async
}

extension MobileAppModel: PairingPageModeling {}

@MainActor
protocol TransferPageModeling: AppPageModeling {
    var transferServiceForTransferView: TransferService { get }
}

extension MobileAppModel: TransferPageModeling {}
