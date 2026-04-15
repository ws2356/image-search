@MainActor
protocol AppPageModeling: AnyObject {
    var homeSummary: HomeSummary { get }
    var pairingStatus: PairingStatus { get }
    var permissionSummary: PermissionSummary { get }
    var transferSnapshot: TransferSnapshot { get }
    var completionSummary: CompletionSummary { get }
    var scannedQRCodeValue: String { get set }

    func handleHomePrimaryAction() async
    func openScanFlow() async
    func beginPairing() async
    func returnHome() async
    func startBackup() async
    func requestStopTransfer()
}

extension MobileAppModel: AppPageModeling {}
