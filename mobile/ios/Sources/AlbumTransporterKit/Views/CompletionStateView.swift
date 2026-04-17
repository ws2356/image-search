import SwiftUI

struct CompletionStateView: View {
    let summary: CompletionSummary
    let onReturnHome: () -> Void

    var body: some View {
        completionScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    heroCircle(
                        icon: "checkmark",
                        gradient: [Color(hex: 0x34C759), Color(hex: 0x2A9D47)]
                    )

                    Text(summary.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text(summary.message)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                sessionSummaryCard

                greenInfoCallout

                ActionButton(title: "OK", icon: nil, style: .primary, action: onReturnHome)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionSummaryHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                summaryCell(
                    label: "Items backed up",
                    value: summary.itemsBackedUp.map(String.init) ?? "—",
                    icon: "photo.on.rectangle",
                    color: Color(hex: 0x007AFF)
                )
                summaryCell(
                    label: "Duration",
                    value: summary.durationDescription ?? "—",
                    icon: "clock",
                    color: Color(hex: 0xFF9F0A)
                )
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private func summaryCell(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1C1C1E))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var greenInfoCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color(hex: 0x30D158))
            Text("The desktop is now indexing your backed-up photos and videos. They'll appear in search results shortly.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x166534))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE6F9ED))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func completionScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16.4, *) {
            ScrollView {
                content()
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            ScrollView {
                content()
            }
        }
    }

    @ViewBuilder
    private var sessionSummaryHeader: some View {
        if #available(iOS 16.0, *) {
            Text("Session Summary")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
                .kerning(0.5)
        } else {
            Text("Session Summary")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
        }
    }
}
