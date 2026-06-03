import SwiftUI
import UIKit

class InstantShareExtensionViewController: UIViewController {
    private var extensionItems: [NSExtensionItem] = []
    private let viewModel = InstantShareExtensionViewModel(
        mdnsBrowser: InstantShareMDNSBrowser(),
        service: InstantShareService()
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        extensionItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        let hostingController = UIHostingController(
            rootView: InstantShareExtensionView(
                viewModel: viewModel,
                onCancel: { [weak self] in self?.cancelAction() }
            )
        )
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)

        Task {
            await viewModel.loadPayload(from: extensionItems)
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
