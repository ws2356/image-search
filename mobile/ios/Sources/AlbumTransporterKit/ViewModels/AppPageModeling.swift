import Foundation

@MainActor
protocol AppPageModeling: AnyObject {
    var backupSessionProvider: BackupSessionProviding { get }
    var backupFlowState: MobileBackupFlowState { get }
    var permissionService: PermissionService { get }
    var transferService: TransferService { get }
    var route: AppRoute { get }
    
    // New page-specific result handlers
    func onHomeCompleted(with result: HomePageResult) async
    func onScanningCompleted(with result: ScanningPageResult) async
    func onPairingCompleted(with result: PairingPageResult) async
    func onPermissionsCompleted(with result: PermissionsPageResult) async
    func onTransferCompleted(with result: TransferPageResult) async
    func onCompletionCompleted(with result: CompletionPageResult) async
    func onErrorCompleted(with result: ErrorPageResult) async
    func onQRClaimScanned(_ payload: QRClaimPayload) async
    func onQRClaimDismissed() async
}

extension MobileAppModel: AppPageModeling {}

@MainActor
protocol PermissionsPageModeling: AppPageModeling {
    var pairingService: PairingService { get }
}

extension MobileAppModel: PermissionsPageModeling {}

@MainActor
protocol PairingPageModeling: AppPageModeling {
    var pairingService: PairingService { get }
}

extension MobileAppModel: PairingPageModeling {}

@MainActor
protocol TransferPageModeling: AppPageModeling {}

extension MobileAppModel: TransferPageModeling {}
