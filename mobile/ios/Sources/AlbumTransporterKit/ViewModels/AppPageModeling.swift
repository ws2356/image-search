import Foundation

@MainActor
protocol AppPageModeling: AnyObject {
    var homeSummary: HomeSummary { get }
    var backupFlowState: MobileBackupFlowState { get }
    var pairingStatus: PairingStatus { get }
    var permissionSummary: PermissionSummary { get }
    var removeAfterBackupEnabled: Bool { get }
    var transferServiceForPageModels: TransferService { get }
    var errorSummary: ErrorSummary { get }
    var scannedQRCodeValue: String { get set }

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async
    func setRemoveAfterBackupEnabled(_ isEnabled: Bool)
    func requestStopTransfer()
    func recordInteraction(name: String, location: String)
}

extension MobileAppModel: AppPageModeling {}

@MainActor
protocol PermissionsPageModeling: AppPageModeling {
    var permissionSummary: PermissionSummary { get set }
    var permissionService: PermissionService { get }

    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes)
    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes)
    func persistSnapshot()
    func abortPreflightAndReturnHome(reason: String) async
    func recordDialogView(name: String)
}

extension MobileAppModel: PermissionsPageModeling {}

@MainActor
protocol TransferPageModeling: AppPageModeling {
    var route: AppRoute { get }
    var transferServiceForTransferView: TransferService { get }
    func recordDialogView(name: String)
    func persistSnapshot()
}

extension MobileAppModel: TransferPageModeling {}
