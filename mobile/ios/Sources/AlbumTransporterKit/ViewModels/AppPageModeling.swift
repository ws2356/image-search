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

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async
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
