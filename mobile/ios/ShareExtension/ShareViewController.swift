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
        return viewModel.selectedDevice != nil && viewModel.payloadEnvelope != nil
    }

    override func didSelectPost() {
        viewModel.stopDiscovery()
        let openURL = URL(string: "aubackup://instant-share/resume")!
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let application = next as? UIApplication {
                application.open(openURL, options: [:], completionHandler: nil)
                break
            }
            responder = next
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        InstantShareLog.info("[Share VC] viewDidLoad")
        let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        InstantShareLog.info("[Share VC] received \(extensionItems.count) extension items")

        let hosting = UIHostingController(
            rootView: InstantShareExtensionView(
                viewModel: viewModel,
                onCancel: { [weak self] in self?.cancelAction() },
                onSend: { [weak self] in self?.didSelectPost() }
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
            InstantShareLog.info("[Share VC] payload loaded, starting discovery")
            viewModel.startDiscovery()
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
