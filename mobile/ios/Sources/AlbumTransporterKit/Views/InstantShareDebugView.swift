import SwiftUI

struct InstantShareDebugView: View {
    @StateObject private var viewModel = InstantShareDebugViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard
                configurationCard
                validationCard
                endpointsCard
                protocolCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(hex: 0xF7F9FC).ignoresSafeArea())
        .navigationTitle("Instant Share")
        .navigationBarTitleDisplayMode(.inline)
        .compatibleScrollBounceBasedOnSize()
    }

    private var headerCard: some View {
        StatusCard(
            title: "iPhone-side Instant Share",
            subtitle: "Validate connection config fields and preview the HTTPS endpoints that the PC will call.",
            systemImage: "dot.radiowaves.left.and.right"
        ) {
            HStack(spacing: 12) {
                MetricPill(title: "Payload", value: payloadTitle(viewModel.payloadClass))
                MetricPill(title: "Trust", value: trustModeTitle(viewModel.trustMode))
                MetricPill(title: "Target", value: targetIntentTitle(viewModel.targetIntent))
            }
        }
    }

    private var configurationCard: some View {
        StatusCard(
            title: "Connection Config",
            subtitle: "Edit the fields below to mirror the BLE bootstrap payload the desktop runtime receives.",
            systemImage: "server.rack"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                InstantShareDebugField(title: "Session ID", text: $viewModel.sessionID)
                InstantShareDebugField(title: "Correlation ID", text: $viewModel.correlationID)
                InstantShareDebugField(title: "Mobile Port", text: $viewModel.mobilePort, keyboardType: .numberPad)
                InstantShareDebugField(
                    title: "Mobile IP List",
                    text: $viewModel.mobileIPList,
                    placeholder: "192.168.1.20, fe80::10"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Payload Class")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6E6E73))

                    Picker("Payload Class", selection: $viewModel.payloadClass) {
                        ForEach(InstantSharePayloadClass.allCases, id: \.rawValue) { payloadClass in
                            Text(payloadTitle(payloadClass)).tag(payloadClass)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Trust Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x6E6E73))

                    Picker("Trust Mode", selection: $viewModel.trustMode) {
                        ForEach(InstantShareTrustMode.allCases, id: \.rawValue) { trustMode in
                            Text(trustModeTitle(trustMode)).tag(trustMode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                InstantShareDebugReadOnlyRow(
                    title: "Target Intent",
                    value: targetIntentTitle(viewModel.targetIntent)
                )

                ActionButton(
                    title: "Load Sample Config",
                    icon: "arrow.counterclockwise",
                    style: .secondary,
                    action: viewModel.loadSampleConfiguration
                )
            }
        }
    }

    private var validationCard: some View {
        Group {
            if let validationMessage = viewModel.validationMessage {
                InstantShareDebugBanner(
                    title: "Config needs attention",
                    message: validationMessage,
                    color: Color(hex: 0xFFF3CD),
                    accent: Color(hex: 0xFF9F0A),
                    symbol: "exclamationmark.triangle.fill"
                )
            } else {
                InstantShareDebugBanner(
                    title: "Config is valid",
                    message: "This payload can derive iPhone HTTPS endpoints for the current instant-share slice.",
                    color: Color(hex: 0xEAF9EE),
                    accent: Color(hex: 0x30D158),
                    symbol: "checkmark.seal.fill"
                )
            }
        }
    }

    private var endpointsCard: some View {
        StatusCard(
            title: "Derived Endpoints",
            subtitle: "These are the concrete URLs the PC-side instant-share client will target after BLE bootstrap.",
            systemImage: "network"
        ) {
            if viewModel.endpointRows.isEmpty {
                Text("Fix the connection config above to generate endpoint URLs.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x6E6E73))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.endpointRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x1C1C1E))
                            ForEach(row.urls, id: \.self) { url in
                                Text(url)
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color(hex: 0x0060DF))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var protocolCard: some View {
        StatusCard(
            title: "Protocol Snapshot",
            subtitle: "Static values from the current iOS instant-share service layer.",
            systemImage: "doc.text.magnifyingglass"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.protocolRows) { row in
                    InstantShareDebugReadOnlyRow(title: row.title, value: row.value)
                }
            }
        }
    }

    private func payloadTitle(_ payloadClass: InstantSharePayloadClass) -> String {
        switch payloadClass {
        case .text:
            return "Text"
        case .image:
            return "Image"
        }
    }

    private func trustModeTitle(_ trustMode: InstantShareTrustMode) -> String {
        switch trustMode {
        case .firstShare:
            return "First Share"
        case .trustedDirect:
            return "Trusted"
        }
    }

    private func targetIntentTitle(_ targetIntent: InstantShareTargetIntent) -> String {
        switch targetIntent {
        case .clipboardOnly:
            return "Clipboard Only"
        case .clipboardOrFile:
            return "Clipboard or File"
        }
    }
}

private struct InstantShareDebugField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(hex: 0xF2F2F7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct InstantShareDebugReadOnlyRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: 0x1C1C1E))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct InstantShareDebugBanner: View {
    let title: String
    let message: String
    let color: Color
    let accent: Color
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x555555))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    NavigationStack {
        InstantShareDebugView()
    }
}
#endif