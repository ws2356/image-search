import SwiftUI

#if os(iOS)
struct FileTypeBadge: View {
    let entryType: String
    let filename: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.chip)
                .fill(backgroundColor)
                .frame(width: 40, height: 40)

            Text(badgeText)
                .font(.system(size: 9, weight: .black))
                .tracking(0.5)
                .foregroundStyle(foregroundColor)
        }
    }

    private var badgeText: String {
        switch entryType.lowercased() {
        case "text": return "TXT"
        case "html": return "HTML"
        case "link": return "LINK"
        default:
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".png") { return "PNG" }
            if lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") { return "JPG" }
            if lowercased.hasSuffix(".pdf") { return "PDF" }
            if lowercased.hasSuffix(".zip") { return "ZIP" }
            if lowercased.hasSuffix(".txt") { return "TXT" }
            if lowercased.hasSuffix(".doc") || lowercased.hasSuffix(".docx") { return "DOC" }
            if lowercased.hasSuffix(".xls") || lowercased.hasSuffix(".xlsx") { return "XLS" }
            return "FILE"
        }
    }

    private var backgroundColor: Color {
        switch entryType.lowercased() {
        case "text", "html": return DesignSystem.Colors.primary.opacity(0.1)
        case "link": return DesignSystem.Colors.success.opacity(0.1)
        default:
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") {
                return DesignSystem.Colors.success.opacity(0.2)
            }
            if lowercased.hasSuffix(".pdf") {
                return DesignSystem.Colors.primary.opacity(0.2)
            }
            return DesignSystem.Colors.secondaryText.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch entryType.lowercased() {
        case "text", "html": return DesignSystem.Colors.primary
        case "link": return DesignSystem.Colors.success
        default:
            let lowercased = filename.lowercased()
            if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") {
                return DesignSystem.Colors.success
            }
            if lowercased.hasSuffix(".pdf") {
                return DesignSystem.Colors.primary
            }
            return DesignSystem.Colors.secondaryText
        }
    }
}
#endif
