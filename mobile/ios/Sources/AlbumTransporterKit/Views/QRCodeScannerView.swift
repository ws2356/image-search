import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit

private enum QRCodeScannerAccessState: Equatable {
    case requesting
    case ready
    case denied
    case unavailable(String)
}

struct LiveQRCodeScannerScreen: View {
    let status: PairingStatus
    @Binding var scannedQRCodeValue: String
    let onStartPairing: () -> Void
    let onBack: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var accessState: QRCodeScannerAccessState = .requesting
    @State private var lastSubmittedValue = ""

    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = resolvedSafeAreaInsets(from: geometry)
            let scanRect = scannerRect(in: geometry, safeAreaInsets: safeAreaInsets)

            ZStack {
                scannerBackground

                ScannerMaskOverlay(size: geometry.size, scanRect: scanRect)

                VStack(spacing: 0) {
                    topBar(topInset: safeAreaInsets.top)
                    Spacer()
                    instructionBanner(bottomInset: safeAreaInsets.bottom)
                }

                switch accessState {
                case .ready:
                    EmptyView()
                case .requesting:
                    statusPanel {
                        ProgressView()
                            .tint(.white)
                        Text("Requesting camera access…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                case .denied:
                    statusPanel {
                        Text("Camera access is turned off. Enable it in Settings to scan desktop QR codes.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            openURL(settingsURL)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0x007AFF))
                    }
                case .unavailable(let message):
                    statusPanel {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: status.phase) { _, newPhase in
            guard newPhase != .pairing else {
                return
            }
            if scannedQRCodeValue != lastSubmittedValue {
                lastSubmittedValue = scannedQRCodeValue
            }
        }
        .task {
            await prepareCameraAccess()
        }
    }

    @ViewBuilder
    private var scannerBackground: some View {
        if accessState == .ready {
            QRCodeCameraScannerView(
                onScannedValue: handleScannedValue,
                onError: handleScannerError
            )
            .ignoresSafeArea()
        } else {
            Color.black
                .ignoresSafeArea()
        }
    }

    private func topBar(topInset: CGFloat) -> some View {
        ZStack {
            Text("Scan QR Code")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Button("Cancel") {
                    onBack()
                }
                .buttonStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(.white)

                Spacer()

                Image(systemName: "lightbulb")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.top, topInset + 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(0.55),
                    .black.opacity(0.20),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func instructionBanner(bottomInset: CGFloat) -> some View {
        Text("Point at the QR code shown on your PC screen")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.60))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.bottom, max(bottomInset + 24, 32))
    }

    private func statusPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 28)
    }

    private func scannerRect(in geometry: GeometryProxy, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let frameWidth = min(geometry.size.width * 0.62, 240)
        let originX = (geometry.size.width - frameWidth) / 2
        let originY = max(safeAreaInsets.top + 120, geometry.size.height * 0.24)
        return CGRect(x: originX, y: originY, width: frameWidth, height: frameWidth)
    }

    private func resolvedSafeAreaInsets(from geometry: GeometryProxy) -> UIEdgeInsets {
        let geometryInsets = geometry.safeAreaInsets
        let keyWindowInsets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return UIEdgeInsets(
            top: max(geometryInsets.top, keyWindowInsets.top),
            left: max(geometryInsets.leading, keyWindowInsets.left),
            bottom: max(geometryInsets.bottom, keyWindowInsets.bottom),
            right: max(geometryInsets.trailing, keyWindowInsets.right)
        )
    }

    private func handleScannedValue(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        scannedQRCodeValue = trimmedValue
        guard status.phase != .pairing, lastSubmittedValue != trimmedValue else {
            return
        }

        lastSubmittedValue = trimmedValue
        onStartPairing()
    }

    private func handleScannerError(_ message: String) {
        accessState = .unavailable(message)
    }

    private func prepareCameraAccess() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            accessState = .unavailable("Camera scanning is unavailable on this device.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            accessState = .ready

        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            accessState = granted ? .ready : .denied

        case .denied, .restricted:
            accessState = .denied

        @unknown default:
            accessState = .unavailable("Camera scanning is unavailable right now.")
        }
    }
}

private struct ScannerMaskOverlay: View {
    let size: CGSize
    let scanRect: CGRect

    var body: some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(
                    in: scanRect,
                    cornerSize: CGSize(width: 16, height: 16),
                    style: .continuous
                )
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: scanRect.width, height: scanRect.height)
                .position(x: scanRect.midX, y: scanRect.midY)

            CornerMarker()
                .position(x: scanRect.minX + 14, y: scanRect.minY + 14)
            CornerMarker()
                .rotationEffect(.degrees(90))
                .position(x: scanRect.maxX - 14, y: scanRect.minY + 14)
            CornerMarker()
                .rotationEffect(.degrees(180))
                .position(x: scanRect.maxX - 14, y: scanRect.maxY - 14)
            CornerMarker()
                .rotationEffect(.degrees(270))
                .position(x: scanRect.minX + 14, y: scanRect.maxY - 14)
        }
        .allowsHitTesting(false)
    }
}

private struct CornerMarker: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 26))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 26, y: 0))
        }
        .stroke(
            Color.white,
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 26, height: 26)
    }
}

private struct QRCodeCameraScannerView: UIViewControllerRepresentable {
    let onScannedValue: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScannedValue: onScannedValue)
    }

    func makeUIViewController(context: Context) -> QRCodeCameraViewController {
        QRCodeCameraViewController(
            metadataDelegate: context.coordinator,
            onError: onError
        )
    }

    func updateUIViewController(_ uiViewController: QRCodeCameraViewController, context: Context) {
        context.coordinator.onScannedValue = onScannedValue
        uiViewController.onError = onError
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onScannedValue: (String) -> Void

        init(onScannedValue: @escaping (String) -> Void) {
            self.onScannedValue = onScannedValue
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let scannedValue = object.stringValue
            else {
                return
            }
            onScannedValue(scannedValue)
        }
    }
}

private final class QRCodeCameraViewController: UIViewController {
    var onError: (String) -> Void

    private let metadataDelegate: AVCaptureMetadataOutputObjectsDelegate
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "AlbumTransporterKit.QRCodeScanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    init(
        metadataDelegate: AVCaptureMetadataOutputObjectsDelegate,
        onError: @escaping (String) -> Void
    ) {
        self.metadataDelegate = metadataDelegate
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSessionIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSession()
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else {
            startSession()
            return
        }

        sessionQueue.async {
            do {
                try self.configureSession()
                self.isConfigured = true
                self.startSession()
            } catch {
                DispatchQueue.main.async {
                    self.onError("Album Transporter couldn't start the live camera scanner right now.")
                }
            }
        }
    }

    private func configureSession() throws {
        guard let cameraDevice = AVCaptureDevice.default(for: .video) else {
            throw ScannerConfigurationError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: cameraDevice)
        let output = AVCaptureMetadataOutput()

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard captureSession.canAddInput(input) else {
            throw ScannerConfigurationError.invalidInput
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(output) else {
            throw ScannerConfigurationError.invalidOutput
        }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(metadataDelegate, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            self.previewLayer?.removeFromSuperlayer()
            self.previewLayer = previewLayer
            self.view.layer.insertSublayer(previewLayer, at: 0)
            self.view.setNeedsLayout()
        }
    }

    private func startSession() {
        sessionQueue.async {
            guard self.isConfigured, !self.captureSession.isRunning else {
                return
            }
            self.captureSession.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async {
            guard self.captureSession.isRunning else {
                return
            }
            self.captureSession.stopRunning()
        }
    }
}

private enum ScannerConfigurationError: Error {
    case noCamera
    case invalidInput
    case invalidOutput
}
#endif
