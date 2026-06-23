//
//  Container+ShareExtension.swift
//  ISFromMobile
//
//  Registers dependencies specific to the Share Extension target.
//  Shared dependencies (identity providers, InstantShareService) are in
//  Container+Shared.swift and are reused from Container.shared.
//
import Factory
import Common

@MainActor
extension Container {
    var mdnsBrowser: Factory<InstantShareMDNSBrowser> {
        self { @MainActor in InstantShareMDNSBrowser() }
            .singleton
    }

    // For ShareViewController to depend on
    public var shareExtensionViewModel: Factory<InstantShareExtensionViewModel> {
        self {
            @MainActor in
            InstantShareExtensionViewModel(
                mdnsBrowser: self.mdnsBrowser(),
                service: self.instantShareService(),
                appIdentityProvider: self.appIdentityProvider(),
                deviceIdentifierProvider: self.localDeviceIdentityProvider()
            )
        }
    }
    
    @MainActor
    public var instantShareService: Factory<InstantShareService> {
        self { @MainActor in InstantShareService() }
            .singleton
    }
}
