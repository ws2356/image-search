import Social
import UIKit
import SwiftUI
import AlbumTransporterKit

class ShareViewController: SLComposeServiceViewController {
    private let viewModel = InstantShareExtensionViewModel(
        mdnsBrowser: InstantShareMDNSBrowser(),
        service: InstantShareService()
    )

    override func isContentValid() -> Bool {
        return viewModel.canSend
    }

    override func didSelectPost() {
        InstantShareLog.info("[Share VC] didSelectPost — starting transfer in extension")
        Task { await viewModel.send() }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        InstantShareLog.info("[Share VC] viewDidLoad")

        beginRequestExtensionTime()

        let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        InstantShareLog.info("[Share VC] \(extensionItems.count) extension items")

        let hosting = UIHostingController(
            rootView: InstantShareExtensionView(
                viewModel: viewModel,
                onCancel: { [weak self] in self?.cancelAction() }
            )
        )
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)

        Task {
            await viewModel.loadPayload(from: extensionItems)
            InstantShareLog.info("[Share VC] payload loaded, starting mDNS discovery")
            viewModel.startDiscovery()
        }
    }

    private func beginRequestExtensionTime() {
        let processInfo = ProcessInfo.processInfo
        processInfo.performExpiringActivity(withReason: "Trust handshake and data transfer") { [weak self] expired in
            if expired {
                InstantShareLog.info("[Share VC] extension time expired")
                self?.viewModel.stopDiscovery()
            }
        }
    }

    private func cancelAction() {
        viewModel.stopDiscovery()
        extensionContext?.cancelRequest(withError: NSError(
            domain: "InstantShareExtension",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "User canceled"]
        ))
    }
}
