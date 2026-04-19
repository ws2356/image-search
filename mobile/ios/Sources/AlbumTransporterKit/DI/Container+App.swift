import Factory

extension Container {
    var appStateStore: Factory<AppStateStore> {
        self { UserDefaultsAppStateStore() }
            .singleton
    }

    var localDeviceIdentityProvider: Factory<LocalDeviceIdentityProviding> {
        self { UserDefaultsLocalDeviceIdentityStore() }
            .singleton
    }

    var trustedDesktopStore: Factory<TrustedDesktopStore> {
        self { UserDefaultsTrustedDesktopStore() }
            .singleton
    }

    var pairingBootstrapClient: Factory<PairingBootstrapClient> {
        self { URLSessionPairingBootstrapClient() }
            .singleton
    }

    var usbTransportRuntime: Factory<USBWebSocketTransportRuntime> {
        self { USBWebSocketTransportRuntime() }
            .singleton
    }

    var pairingUSBBootstrapClient: Factory<PairingUSBBootstrapClient> {
        self { WebSocketPairingUSBBootstrapClient(runtime: self.usbTransportRuntime()) }
            .singleton
    }

    var pairingService: Factory<PairingService> {
        self {
            let pairingDebugTransportClient = AdaptiveMobileTransferClient(
                lanClient: URLSessionMobileTransferClient(usePerBackupEphemeralSession: true),
                usbClient: WebSocketMobileTransferClient(runtime: self.usbTransportRuntime())
            )
            return DesktopBootstrapPairingService(
                bootstrapClient: self.pairingBootstrapClient(),
                usbBootstrapClient: self.pairingUSBBootstrapClient(),
                capabilityExchangeClient: pairingDebugTransportClient,
                updatePromptClient: pairingDebugTransportClient,
                identityProvider: self.localDeviceIdentityProvider(),
                trustedDesktopStore: self.trustedDesktopStore()
            )
        }
            .singleton
    }

    var qrCodePayloadDecoder: Factory<QRCodePayloadDecoding> {
        self { URLQueryQRCodePayloadDecoder() }
            .singleton
    }

    var permissionService: Factory<PermissionService> {
        self { SystemPermissionService() }
            .singleton
    }

    var transferService: Factory<TransferService> {
        self {
            PhotoLibraryTransferService(
                assetSource: PhotoLibraryAssetSource(),
                transferClient: AdaptiveMobileTransferClient(
                    lanClient: URLSessionMobileTransferClient(usePerBackupEphemeralSession: true),
                    usbClient: WebSocketMobileTransferClient(runtime: self.usbTransportRuntime())
                ),
                trustedDesktopStore: self.trustedDesktopStore()
            )
        }
            .singleton
    }

    var telemetryClient: Factory<TelemetryClient> {
        self { OpenTelemetryTelemetryClient() }
            .singleton
    }

    @MainActor
    var mobileAppModel: Factory<MobileAppModel> {
        self {
            @MainActor in
            MobileAppModel(
                stateStore: self.appStateStore(),
                qrCodePayloadDecoder: self.qrCodePayloadDecoder(),
                pairingService: self.pairingService(),
                permissionService: self.permissionService(),
                transferService: self.transferService(),
                telemetryClient: self.telemetryClient()
            )
        }
        .singleton
    }
}
