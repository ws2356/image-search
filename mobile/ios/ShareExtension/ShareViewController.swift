import Social
import UIKit
import SwiftUI
import Factory
import AlbumTransporterKit
import Common
import ISFromMobile

class ShareViewController: UIViewController {
    private let viewModel = Container.shared.shareExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        LocalLog.info("[Share VC] viewDidLoad")

        beginRequestExtensionTime()

        let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        LocalLog.info("[Share VC] \(extensionItems.count) extension items")

        let hosting = UIHostingController(
            rootView: InstantShareExtensionView(
                viewModel: viewModel,
                onCancel: { [weak self] in self?.cancelAction() },
                onDone: { [weak self] in self?.doneAction() }
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
            LocalLog.info("[Share VC] payload loaded, starting mDNS discovery")
            viewModel.startDiscovery()
            
            let identityProvider = Container.shared.appIdentityProvider()
            do {
                try await identityProvider.ensureSelfIdentity()
            } catch (let error) {
                LocalLog.error("[Share VC] ensureSelfIdentity failed: \(error)")
            }
        }
    }

    private func beginRequestExtensionTime() {
        let processInfo = ProcessInfo.processInfo
        processInfo.performExpiringActivity(withReason: "Trust handshake and data transfer") { [weak self] expired in
            if expired {
                LocalLog.info("[Share VC] extension time expired")
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

    private func doneAction() {
        viewModel.dismissCompletion()
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
