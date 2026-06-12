import Factory
import ISFromMobile
import Common

extension Container {
    var backupSessionStore: Factory<BackupSessionStore> {
        self { UserDefaultsBackupSessionStore() }
            .singleton
    }

    @MainActor
    var backupSessionProvider: Factory<BackupSessionProviding> {
        self { @MainActor in DefaultBackupSessionProvider(store: self.backupSessionStore()) }
            .singleton
    }

    var localDeviceIdentityProvider: Factory<LocalDeviceIdentifierProviding> {
        self { LocalDeviceIdentifierStore() }
            .singleton
    }

    var appIdentityProvider: Factory<AppIdentityProviding> {
        self { KeychainAppIdentityProvider() }
            .singleton
    }

    var trustedDesktopStore: Factory<TrustedDesktopStore> {
        self { UserDefaultsTrustedDesktopStore() }
            .singleton
    }

    var pairingBootstrapClient: Factory<PairingBootstrapClient> {
        self { URLSessionPairingBootstrapClient(telemetryClient: self.telemetryClient()) }
            .singleton
    }

    var usbTransportRuntime: Factory<USBWebSocketTransportRuntime> {
        self { USBWebSocketTransportRuntime() }
            .singleton
    }

    var pairingUSBBootstrapClient: Factory<PairingUSBBootstrapClient> {
        self {
            WebSocketPairingUSBBootstrapClient(
                runtime: self.usbTransportRuntime(),
                telemetryClient: self.telemetryClient()
            )
        }
            .singleton
    }

    var pairingService: Factory<PairingService> {
        self {
            let pairingDebugTransportClient = AdaptiveMobileTransferClient(
                lanClient: URLSessionMobileTransferClient(
                    telemetryClient: self.telemetryClient(),
                    usePerBackupEphemeralSession: true
                ),
                usbClient: WebSocketMobileTransferClient(
                    runtime: self.usbTransportRuntime(),
                    telemetryClient: self.telemetryClient()
                )
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

    var appUpdateChecker: Factory<AppUpdateChecking> {
        self { URLSessionAppUpdateChecker() }
            .singleton
    }

    var appVersionProvider: Factory<AppVersionProviding> {
        self { BundleAppVersionProvider() }
            .singleton
    }

    var transferService: Factory<TransferService> {
        self {
            PhotoLibraryTransferService(
                assetSource: PhotoLibraryAssetSource(),
                transferClient: AdaptiveMobileTransferClient(
                    lanClient: URLSessionMobileTransferClient(
                        telemetryClient: self.telemetryClient(),
                        usePerBackupEphemeralSession: true
                    ),
                    usbClient: WebSocketMobileTransferClient(
                        runtime: self.usbTransportRuntime(),
                        telemetryClient: self.telemetryClient()
                    )
                ),
                trustedDesktopStore: self.trustedDesktopStore(),
                telemetryClient: self.telemetryClient()
            )
        }
            .singleton
    }

    var telemetryClient: Factory<TelemetryClient> {
        self { OpenTelemetryTelemetryClient(identityProvider: self.localDeviceIdentityProvider()) }
            .singleton
    }

    @MainActor
    var telemetryContextProvider: Factory<TelemetryContextProvider> {
        self { @MainActor in DefaultTelemetryContextProvider() }
            .singleton
    }

    @MainActor
    var telemetryService: Factory<TelemetryService> {
        self {
            @MainActor in
            DefaultTelemetryService(
                transferService: self.transferService(),
                transportResolver: self.transferService(),
                telemetryClient: self.telemetryClient(),
                contextProvider: self.telemetryContextProvider()
            )
        }
        .singleton
    }

    @MainActor
    var mobileAppModel: Factory<MobileAppModel> {
        self {
            @MainActor in
            MobileAppModel(
                backupSessionProvider: self.backupSessionProvider(),
                qrCodePayloadDecoder: self.qrCodePayloadDecoder(),
                pairingService: self.pairingService(),
                permissionService: self.permissionService(),
                transferService: self.transferService(),
                appUpdateChecker: self.appUpdateChecker(),
                appVersionProvider: self.appVersionProvider(),
                telemetryService: self.telemetryService(),
                telemetryContextProvider: self.telemetryContextProvider(),
                appIdentityProvider: self.appIdentityProvider()
            )
        }
        .singleton
    }

    @MainActor
    var instantShareService: Factory<InstantShareService> {
        self { @MainActor in InstantShareService() }
            .singleton
    }
}
