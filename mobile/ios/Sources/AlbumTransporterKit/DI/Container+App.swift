import Factory

extension Container {
    var appStateStore: Factory<AppStateStore> {
        self { InMemoryAppStateStore(snapshot: .firstLaunch) }
            .singleton
    }

    var pairingService: Factory<PairingService> {
        self { DemoPairingService() }
            .singleton
    }

    var qrCodePayloadDecoder: Factory<QRCodePayloadDecoding> {
        self { URLQueryQRCodePayloadDecoder() }
            .singleton
    }

    var permissionService: Factory<PermissionService> {
        self { DemoPermissionService() }
            .singleton
    }

    var transferService: Factory<TransferService> {
        self { DemoTransferService() }
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
