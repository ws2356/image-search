import SwiftUI

struct PermissionsGateView: View {
    let summary: PermissionSummary
    let removeAfterBackupEnabled: Bool
    let onRemoveAfterBackupChanged: (Bool) -> Void
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    heroCircle(icon: "lock.shield.fill", gradient: [Color(hex: 0x007AFF), Color(hex: 0x0055D4)])

                    Text("Backup preflight")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text("Checking permissions before starting.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    PermissionRow(title: "Media Library", value: summary.mediaScope.title,
                                  icon: "photo.on.rectangle", isGranted: summary.mediaScope == .full)
                    Divider().padding(.leading, 42)
                    PermissionRow(title: "Notifications", value: summary.notificationsGranted ? "Granted" : "Will request",
                                  icon: "bell.badge", isGranted: summary.notificationsGranted)
                    Divider().padding(.leading, 42)
                    PermissionRow(title: "Power", value: summary.isCharging ? "Charging" : "On battery",
                                  icon: "battery.100.bolt", isGranted: summary.isCharging)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)

                if let excludedCategoryDescription = summary.excludedCategoryDescription {
                    infoBanner(message: excludedCategoryDescription, tint: Color(hex: 0x007AFF))
                }

                if summary.lowBatteryWarningNeeded && !summary.isCharging {
                    warningBanner(message: "Low battery — a dialog will appear before transfer starts.", tint: .orange)
                }

                removeAfterBackupCard

                VStack(spacing: 10) {
                    ActionButton(title: "Start Backup", icon: "arrow.up.circle.fill", style: .primary, action: onContinue)
                    ActionButton(title: "Cancel", style: .secondary, action: onBack)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .compatibleScrollBounceBasedOnSize()
    }

    private func infoBanner(message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE8F4FD))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func warningBanner(message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "battery.25")
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF3CD).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var removeAfterBackupCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { removeAfterBackupEnabled },
                    set: { onRemoveAfterBackupChanged($0) }
                )
            )
            .labelsHidden()
            .tint(Color(hex: 0x007AFF))

            VStack(alignment: .leading, spacing: 4) {
                Text("Remove images/videos after backup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text("After a successful upload, transferred items are moved to Recently Removed on this device.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}
