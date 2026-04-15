import SwiftUI

struct TransferSessionView: View {
    let snapshot: TransferSnapshot
    let onStop: () -> Void

    private var progressPercent: Int {
        Int(snapshot.progress * 100)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                transportBadge

                donutProgress

                statsGrid

                if let eta = snapshot.etaDescription {
                    VStack(spacing: 4) {
                        Text("Estimated time")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                        Text(eta)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x1C1C1E))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                }

                guidanceHint

                if snapshot.isIncompleteLibrary {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Only the subset currently granted by iOS is being transferred.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFFF3CD).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(spacing: 10) {
                    Button(action: onStop) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop Backup")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(Color(hex: 0xFF453A))
                        .background(Color(hex: 0xFFF1F0))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var transportBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.transport.systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(snapshot.transport.title)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(transportColor)
        .background(transportBackground)
        .clipShape(Capsule())
    }

    private var donutProgress: some View {
        return ZStack {
            Circle()
                .stroke(Color(hex: 0xE5E5EA), lineWidth: 12)

            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(
                    transportColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text("\(progressPercent)%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(snapshot.transferSpeedText ?? "0.00 MB/s")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
            }
        }
        .frame(width: 180, height: 180)
        .padding(.vertical, 8)
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statColumn(label: "Sent", value: "\(snapshot.transferredCount)", color: Color(hex: 0x30D158))
            Divider().frame(height: 40)
            statColumn(label: "Remaining", value: "\(snapshot.totalCount - snapshot.transferredCount)", color: Color(hex: 0x007AFF))
            Divider().frame(height: 40)
            statColumn(label: "Failed", value: "\(snapshot.failedCount)", color: Color(hex: 0xFF453A))
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .frame(maxWidth: .infinity)
    }

    private var guidanceHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: snapshot.transport == .usb ? "checkmark.circle.fill" : "bolt.horizontal.fill")
                .foregroundStyle(snapshot.transport == .usb ? Color(hex: 0x30D158) : Color(hex: 0x3B5FC0))
            Text(snapshot.guidanceMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(snapshot.transport == .usb ? Color(hex: 0xE6F9ED) : Color(hex: 0xEEF2FF))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var transportColor: Color {
        snapshot.transport == .usb ? Color(hex: 0x30D158) : Color(hex: 0x007AFF)
    }

    private var transportBackground: Color {
        snapshot.transport == .usb ? Color(hex: 0xE6F9ED) : Color(hex: 0xE8F4FD)
    }
}
