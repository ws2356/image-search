import SwiftUI
import UIKit
import Photos

public struct QRTransferResultView: View {
    let result: QRClaimResult
    let onDismiss: () -> Void

    @State private var showCopiedToast = false
    @State private var showSavedToast = false
    @State private var showPermissionAlert = false
    @State private var showFileSavedToast = false
    @State private var showFileError = false
    @State private var fileErrorMessage = ""

    public init(result: QRClaimResult, onDismiss: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationView {
            content
                .navigationTitle("Received")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { onDismiss() }
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                toast("Copied to clipboard")
            } else if showSavedToast {
                toast("Saved to Photos")
            } else if showFileSavedToast {
                toast("Saved to Files")
            }
        }
        .alert("Photo Library Access", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AuBackup needs photo library write access to save images.")
        }
        .alert("File Error", isPresented: $showFileError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileErrorMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .text(let text):
            textContentView(text: text)
        case .html(let html):
            RichTextReceiveView(html: html)
        case .image(let fileURL, let contentType, let filename):
            imageContentView(fileURL: fileURL, contentType: contentType, filename: filename)
        case .file(let fileURL, let contentType, let filename):
            fileContentView(fileURL: fileURL, contentType: contentType, filename: filename)
        }
    }

    private func textContentView(text: String) -> some View {
        VStack(spacing: 16) {
            ScrollView {
                Text(text)
                    .font(.system(.body))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Button(action: copyToClipboard(text)) {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func imageContentView(fileURL: URL, contentType: String, filename: String?) -> some View {
        VStack(spacing: 16) {
            if let uiImage = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

            if let filename {
                Text(filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                Task {
                    await saveImageToLibrary(fileURL: fileURL)
                }
            }) {
                Label("Save to Photo Library", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func fileContentView(fileURL: URL, contentType: String, filename: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .padding(.top, 32)

            if let filename {
                Text(filename)
                    .font(.headline)
                    .foregroundStyle(.primary)
            } else {
                Text("Received File")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attrs[.size] as? Int64 {
                Text("\(fileSize) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                Task {
                    await saveImageToLibrary(fileURL: fileURL)
                }
            }) {
                Label("Open in Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func copyToClipboard(_ text: String) -> () -> Void {
        {
            UIPasteboard.general.string = text
            showCopiedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showCopiedToast = false
            }
        }
    }

    // 2. 现代化的异步保存函数
    nonisolated private func saveImageToLibrary(fileURL: URL) async {
        // 现代异步权限申请
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            do {
                // performChanges 也有现代的异步版本
                try await PHPhotoLibrary.shared().performChanges {
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, fileURL: fileURL, options: nil)
                }
                // 成功后，明确切回主线程更新 UI
                await MainActor.run {
                    showSavedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSavedToast = false
                    }
                }
            } catch {
                await MainActor.run {
                    showPermissionAlert = true
                }
            }
            
        default:
            await MainActor.run {
                showPermissionAlert = true
            }
        }
    }

    private func openFile(_ fileURL: URL) -> () -> Void {
        {
            guard UIApplication.shared.canOpenURL(fileURL) else {
                fileErrorMessage = "Cannot open file"
                showFileError = true
                return
            }
            UIApplication.shared.open(fileURL)
        }
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.8)))
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
