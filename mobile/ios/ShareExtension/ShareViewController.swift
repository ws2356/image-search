import Social
import UIKit
import SwiftUI
import ComposableArchitecture
import Common
import ISFromMobile

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        LocalLog.info("[Share VC] viewDidLoad")
        
        // 1. Set up extension context for TCA dependency injection
        InstantShareExtensionContextClient.current = InstantShareExtensionContextClient(extensionContext)
        
        LocalLog.info("[Share VC] fuck")
        for item in extensionContext?.inputItems ?? [] {
            if let shareItem = item as? NSExtensionItem {
                LocalLog.info("[Share VC] share item \(shareItem.attributedTitle)")
                LocalLog.info("[Share VC] share item \(shareItem.userInfo)")
            }
        }

        // 2. Create store — liveValue handles all service instantiation
        let store = Store(initialState: FlowFeature.State()) {
            FlowFeature()
        }

        // 3. Embed FlowView — no callbacks, features use DI for exit
        let hosting = UIHostingController(rootView: FlowView(store: store))
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
    }
}
