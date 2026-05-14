import Foundation

@MainActor
protocol AppPageModeling: AnyObject {
    var homeSummary: HomeSummary { get }
    var backupFlowState: MobileBackupFlowState { get }
    var pairingStatus: PairingStatus { get }
    var permissionSummary: PermissionSummary { get }
    var transferServiceForPageModels: TransferService { get }
    var errorSummary: ErrorSummary { get }
    var scannedQRCodeValue: String { get set }

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async
    func requestStopTransfer()
}

extension MobileAppModel: AppPageModeling {}

@MainActor
protocol PermissionsPageModeling: AppPageModeling {
    var permissionSummary: PermissionSummary { get set }
    var permissionService: PermissionService { get }
    func persistSnapshot()
    func abortPreflightAndReturnHome(reason: String) async
}

extension MobileAppModel: PermissionsPageModeling {}

@MainActor
protocol PairingPageModeling: AppPageModeling {
    var route: AppRoute { get }
    var qrCodePayloadDecoderForPairingPage: QRCodePayloadDecoding { get }
    var pairingServiceForPairingPage: PairingService { get }
    func persistSnapshot()
    func handleInvalidPairingPayload(message: String)
    func handlePairingAttemptCompleted(_ result: PairingStatus) async
}

extension MobileAppModel: PairingPageModeling {}

@MainActor
protocol TransferPageModeling: AppPageModeling {
    var route: AppRoute { get }
    var permissionService: PermissionService { get }
    var transferServiceForTransferView: TransferService { get }
    func persistSnapshot()
}

extension MobileAppModel: TransferPageModeling {}
