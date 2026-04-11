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

struct LiveQRCodeScannerCard: View {
    let status: PairingStatus
    @Binding var scannedQRCodeValue: String
    let onStartPairing: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var accessState: QRCodeScannerAccessState = .requesting
    @State private var lastSubmittedValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scan the desktop QR with the camera.", systemImage: "camera.viewfinder")
                .foregroundStyle(.secondary)

            switch accessState {
            case .requesting:
                ProgressView("Requesting camera access…")
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .ready:
                QRCodeCameraScannerView(
                    onScannedValue: handleScannedValue,
                    onError: handleScannerError
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.quaternary, lineWidth: 1)
                )

            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera access is off, so live QR scanning is unavailable. Paste the pairing link below or allow camera access in Settings.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        openURL(settingsURL)
                    }
                    .buttonStyle(.bordered)
                }

            case .unavailable(let message):
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
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
            accessState = .unavailable("Camera scanning is unavailable on this device. Paste the pairing link below instead.")
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
            accessState = .unavailable("Camera scanning is unavailable right now. Paste the pairing link below instead.")
        }
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
                    self.onError("Album Transporter couldn't start the live camera scanner. Paste the pairing link below instead.")
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
