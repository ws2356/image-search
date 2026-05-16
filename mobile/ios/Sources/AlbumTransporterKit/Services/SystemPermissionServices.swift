import Foundation
import Photos
import UIKit

actor SystemPermissionService: PermissionService {
    private var isRemoveAfterBackupEnabled = false

    func loadPermissionSummary() async -> PermissionSummary {
        let mediaAuthorization = currentMediaAuthorization()
        let batteryState = currentBatteryState()

        return PermissionSummary(
            mediaScope: permissionScope(for: mediaAuthorization),
            lowBatteryWarningNeeded: batteryState.lowBatteryWarningNeeded,
            isCharging: batteryState.isCharging
        )
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
    }

    func requestMediaAccess() async -> PermissionScope {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        return permissionScope(for: status)
    }

    private func currentMediaAuthorization() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func permissionScope(for authorizationStatus: PHAuthorizationStatus) -> PermissionScope {
        switch authorizationStatus {
        case .authorized:
            return .full
        case .limited:
            return .limited
        default:
            return .denied
        }
    }

    private func currentBatteryState() -> (lowBatteryWarningNeeded: Bool, isCharging: Bool) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        let isCharging = batteryState == .charging || batteryState == .full
        let lowBattery = batteryLevel >= 0 && batteryLevel < 0.2 && !isCharging
        return (lowBattery, isCharging)
    }
}
