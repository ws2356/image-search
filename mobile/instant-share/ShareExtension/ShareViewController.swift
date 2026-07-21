import Social
import UIKit
import SwiftUI
import Common
import ISFromMobile

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        LocalLog.info("[Share VC] viewDidLoad")
        
        // 1. Set up extension context for TCA dependency injection
        guard let extensionContext = self.extensionContext else {
            LocalLog.error("[Share VC] No extension context available")
            return
        }
        
        // 2. Create store — liveValue handles all service instantiation
        let store = Store(initialState: FlowFeature.State()) {
            return FlowFeature()
        } withDependencies: {
            $0.instantShareExtensionContext = InstantShareExtensionContextClient(extensionContext)
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
