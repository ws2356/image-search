import Foundation
import PhotosUI
import SwiftUI
import Factory

struct InstantShareDebugView: View {
    @StateObject private var viewModel: InstantShareDebugViewModel

    init() {
        let service = Container.shared.instantShareService()
        _viewModel = StateObject(wrappedValue: InstantShareDebugViewModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard
                discoveryCard
                sharedPayloadCard
                configurationCard
                startSessionCard
                if let pin = viewModel.service.currentPIN {
                    pinDisplayCard(pin: pin)
                }
                statusLogCard
                endpointsCard
                protocolCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(hex: 0xF7F9FC).ignoresSafeArea())
        .navigationTitle("Instant Share")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showingImagePicker) {
            ImagePicker { result in
                viewModel.handleImagePicked(result)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        StatusCard(
            title: "iPhone-side Instant Share",
            subtitle: "Discover a PC, select a payload, and start the share-and-forget flow.",
            systemImage: "dot.radiowaves.left.and.right"
        ) {
            HStack(spacing: 12) {
                MetricPill(title: "Payload", value: payloadTitle(viewModel.payloadClass))
                MetricPill(title: "Trust", value: trustModeTitle(viewModel.trustMode))
                MetricPill(title: "Target", value: targetIntentTitle(viewModel.targetIntent))
            }
        }
    }

    // MARK: - mDNS Discovery

    private var discoveryCard: some View {
        StatusCard(
            title: "1. Discover PCs",
            subtitle: "Browse for nearby PCs advertising _instantshare._tcp via mDNS.",
            systemImage: "antenna.radiowaves.left.and.right"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ActionButton(
                        title: viewModel.service.mdnsBrowser.state == .browsing ? "Stop Browse" : "Start Browse",
                        icon: viewModel.service.mdnsBrowser.state == .browsing ? "stop.fill" : "magnifyingglass",
                        style: viewModel.service.mdnsBrowser.state == .browsing ? .destructive : .primary,
                        action: {
                            if viewModel.service.mdnsBrowser.state == .browsing {
                                viewModel.stopDiscovery()
                            } else {
                                viewModel.startDiscovery()
                            }
                        }
                    )
                    scannerStateBadge
                }

                if !viewModel.service.mdnsBrowser.discovered.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Discovered PCs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                        ForEach(viewModel.service.mdnsBrowser.discovered) { pc in
                            discoveredPCRow(pc)
                        }
                    }
                } else if viewModel.service.mdnsBrowser.state == .browsing {
                    Text("Browsing...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
            }
        }
    }

    private var scannerStateBadge: some View {
        let (label, color) = scannerStateInfo
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }

    private var scannerStateInfo: (String, Color) {
        switch viewModel.service.mdnsBrowser.state {
        case .idle: return ("Idle", Color(hex: 0x8E8E93))
        case .browsing: return ("Browsing", Color(hex: 0x30D158))
        case .stopped: return ("Stopped", Color(hex: 0xD70015))
        }
    }

    private func discoveredPCRow(_ pc: InstantShareDiscoveredPC) -> some View {
        let isSelected = viewModel.service.selectedPC?.id == pc.id
        return Button(action: { viewModel.selectPC(pc) }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(hex: 0x30D158) : Color(hex: 0x8E8E93))
                VStack(alignment: .leading, spacing: 4) {
                    Text(pc.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    Text("\(pc.host):\(pc.port) · ID: \(String(pc.id.prefix(8)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isSelected ? Color(hex: 0xEAF9EE) : Color(hex: 0xF2F2F7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Payload

    private var sharedPayloadCard: some View {
        StatusCard(
            title: "2. Shared Payload",
            subtitle: "What the PC will receive.",
            systemImage: "square.and.arrow.up"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.payloadClass == .text {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                        TextEditor(text: $viewModel.sharedText)
                            .font(.system(size: 14))
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(8)
                            .background(Color(hex: 0xF2F2F7))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    HStack(spacing: 12) {
                        if let data = viewModel.selectedImageData,
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.selectedImageFilename ?? "photo.jpg")
                                    .font(.system(size: 14, weight: .medium))
                                Text("\(data.count) bytes")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0x6E6E73))
                            }
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(Color(hex: 0x8E8E93))
                            Text("No image selected")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: 0x6E6E73))
                        }
                        Spacer(minLength: 0)
                        ActionButton(
                            title: "Pick",
                            icon: "photo.on.rectangle",
                            style: .secondary,
                            action: { viewModel.showingImagePicker = true }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Configuration

    private var configurationCard: some View {
        StatusCard(
            title: "3. Connection Config",
            subtitle: "Edit the fields below to mirror the BLE bootstrap payload the desktop receives.",
            systemImage: "server.rack"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                InstantShareDebugField(title: "Session ID", text: $viewModel.sessionID)
                InstantShareDebugField(title: "Correlation ID", text: $viewModel.correlationID)
                InstantShareDebugField(title: "Mobile Port", text: $viewModel.mobilePort, keyboardType: .numberPad)
                InstantShareDebugField(
                    title: "Mobile IP List",
                    text: $viewModel.mobileIPList,
                    placeholder: "192.168.1.20, 127.0.0.1"
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

                if let message = viewModel.validationMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xD70015))
                }
            }
        }
    }

    // MARK: - Start Session

    private var startSessionCard: some View {
        StatusCard(
            title: "4. Start Session",
            subtitle: "Begin HTTPS server, generate PIN, and write ConnectionConfig to the selected PC.",
            systemImage: "play.circle.fill"
        ) {
            VStack(spacing: 10) {
                if viewModel.isSessionActive {
                    ActionButton(
                        title: "Stop Session",
                        icon: "stop.fill",
                        style: .destructive,
                        action: viewModel.stopSession
                    )
                } else {
                    ActionButton(
                        title: "Start Instant Share",
                        icon: "paperplane.fill",
                        style: .primary,
                        action: {
                            Task { await viewModel.startSession() }
                        }
                    )
                    .disabled(viewModel.service.selectedPC == nil || viewModel.validationMessage != nil)
                }
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xD70015))
                }
            }
        }
    }

    // MARK: - PIN

    private func pinDisplayCard(pin: String) -> some View {
        VStack(spacing: 12) {
            Text("Compare this PIN with the one shown on the PC. Confirm when they match.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
            Text(pin)
                .font(.system(size: 42, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: 0x1C1C1E))
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color(hex: 0xFFF3CD))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xFF9F0A), lineWidth: 1.5)
        )
    }

    // MARK: - Status Log

    private var statusLogCard: some View {
        StatusCard(
            title: "Status Log",
            subtitle: "Live events from the instant-share session.",
            systemImage: "terminal"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.service.statusLog.isEmpty {
                    Text("No events yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                } else {
                    ForEach(viewModel.service.statusLog.suffix(20).reversed(), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x1C1C1E))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Endpoints

    private var endpointsCard: some View {
        StatusCard(
            title: "Derived Endpoints",
            subtitle: "The exact URLs the PC client will target after BLE bootstrap.",
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
                                    .font(.system(size: 12, design: .monospaced))
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

    // MARK: - Protocol

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

    // MARK: - Helpers

    private func payloadTitle(_ payloadClass: InstantSharePayloadClass) -> String {
        switch payloadClass {
        case .text: return "Text"
        case .image: return "Image"
        }
    }

    private func trustModeTitle(_ trustMode: InstantShareTrustMode) -> String {
        switch trustMode {
        case .firstShare: return "First Share"
        case .trustedDirect: return "Trusted"
        }
    }

    private func targetIntentTitle(_ targetIntent: InstantShareTargetIntent) -> String {
        switch targetIntent {
        case .clipboardOnly: return "Clipboard Only"
        case .clipboardOrFile: return "Clipboard or File"
        }
    }
}

// MARK: - Subviews

struct InstantShareDebugField: View {
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

struct InstantShareDebugReadOnlyRow: View {
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

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    let onPicked: (PHPickerResult) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (PHPickerResult) -> Void

        init(onPicked: @escaping (PHPickerResult) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            if let result = results.first {
                onPicked(result)
            }
        }
    }
}
