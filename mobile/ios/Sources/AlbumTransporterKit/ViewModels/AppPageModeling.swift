@MainActor
protocol AppPageModeling: AnyObject {
    var homeSummary: HomeSummary { get }
    var pairingStatus: PairingStatus { get }
    var permissionSummary: PermissionSummary { get }
    var removeAfterBackupEnabled: Bool { get }
    var transferSnapshot: TransferSnapshot { get }
    var completionSummary: CompletionSummary { get }
    var scannedQRCodeValue: String { get set }

    func handleHomePrimaryAction() async
    func openScanFlow() async
    func beginPairing() async
    func returnHome() async
    func startBackup() async
    func setRemoveAfterBackupEnabled(_ isEnabled: Bool)
    func requestStopTransfer()
    func recordInteraction(name: String, location: String)
}

extension MobileAppModel: AppPageModeling {}

@MainActor
protocol PermissionsPageModeling: AppPageModeling {
    var isShowingLowBatteryWarning: Bool { get set }
    var isShowingMediaAccessAlert: Bool { get set }
    var isShowingRemoveAfterBackupPrompt: Bool { get set }
    var mediaAccessAlertMessage: String { get }

    func continuePastLowBatteryWarning() async
    func cancelBackupFromLowBatteryWarning() async
    func continueBackupFromMediaAccess() async
    func selectRemoveAfterBackupPreferenceAndContinue(_ isEnabled: Bool) async
    func recordDialogView(name: String)
}

extension MobileAppModel: PermissionsPageModeling {}

@MainActor
protocol TransferPageModeling: AppPageModeling {
    var isShowingStopConfirmation: Bool { get set }

    func confirmStopTransfer() async
    func recordDialogView(name: String)
}

extension MobileAppModel: TransferPageModeling {}
