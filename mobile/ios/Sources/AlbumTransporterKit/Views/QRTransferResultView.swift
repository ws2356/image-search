import SwiftUI
import UIKit
import Photos

struct QRTransferResultView: View {
    let result: QRClaimResult
    let onDismiss: () -> Void

    @State private var showCopiedToast = false
    @State private var showSavedToast = false
    @State private var showPermissionAlert = false

    var body: some View {
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
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .text(let text):
            textContentView(text: text)
        case .image(let data, let contentType, let filename):
            imageContentView(data: data, contentType: contentType, filename: filename)
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

    private func imageContentView(data: Data, contentType: String, filename: String?) -> some View {
        VStack(spacing: 16) {
            if let uiImage = UIImage(data: data) {
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

            Button(action: saveImageToLibrary(data)) {
                Label("Save to Photo Library", systemImage: "photo.badge.plus")
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

    private func saveImageToLibrary(_ data: Data) -> () -> Void {
        {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized, .limited:
                        PHPhotoLibrary.shared().performChanges {
                            let creationRequest = PHAssetCreationRequest.forAsset()
                            creationRequest.addResource(with: .photo, data: data, options: nil)
                        } completionHandler: { success, error in
                            DispatchQueue.main.async {
                                if success {
                                    showSavedToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showSavedToast = false
                                    }
                                } else {
                                    showPermissionAlert = true
                                }
                            }
                        }
                    default:
                        showPermissionAlert = true
                    }
                }
            }
        }
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .font(.system(.subheadline))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.8)))
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
