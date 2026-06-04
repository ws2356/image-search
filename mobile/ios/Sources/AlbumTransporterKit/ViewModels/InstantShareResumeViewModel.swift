import Foundation
import SwiftUI

enum InstantShareResumeState: Equatable {
    case loading
    case firstUseTrust(pin: String)
    case trustedDirect
    case transferring(progress: Double)
    case delivering
    case success
    case failed(String)
    case aborted
}

@MainActor
final class InstantShareResumeViewModel: ObservableObject {
    @Published var state: InstantShareResumeState = .loading
    @Published var deviceName: String = ""
    @Published var payloadDescription: String = ""

    private let service: InstantShareService
    private var handoffContext: InstantShareHandoffContext?

    init(service: InstantShareService) {
        self.service = service
    }

    func resumeFromHandoff() async {
        do {
            guard let context = try InstantShareHandoffContext.load() else {
                state = .failed("No pending instant-share session found.")
                return
            }
            if context.isStale {
                InstantShareHandoffContext.clear()
                state = .failed("The share session expired. Please try again from the share sheet.")
                return
            }
            self.handoffContext = context
            self.deviceName = context.selectedDeviceName ?? "Unknown Mac"
            self.payloadDescription = describePayload(context)

            if context.isTrustedDevice {
                state = .trustedDirect
                await startTrustedTransfer()
            } else {
                await startFirstUseTrust()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func confirmPIN() async {
        state = .transferring(progress: 0)
        guard let context = handoffContext,
              let config = service.connectionConfig,
              let pc = service.selectedPC else {
            state = .failed("No active session to confirm")
            return
        }

        let trustClient = InstantShareTrustClient(
            trustSessionManager: service.trustSession
        )

        do {
            try await trustClient.confirm(
                host: pc.host,
                port: pc.port,
                sessionID: config.sessionID,
                correlationID: config.correlationID
            )
            await startTrustedTransfer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func rejectPIN() {
        service.rejectTrust()
        state = .aborted
        InstantShareHandoffContext.clear()
    }

    func abort() {
        service.stopSession()
        state = .aborted
        InstantShareHandoffContext.clear()
    }

    func dismiss() {
        InstantShareHandoffContext.clear()
    }

    private func startFirstUseTrust() async {
        guard let context = handoffContext,
              let pc = service.selectedPC else {
            state = .failed("No selected PC")
            return
        }
        do {
            let config = try buildConnectionConfig(from: context)
            try await service.startSession(connectionConfig: config)

            let trustClient = InstantShareTrustClient(
                trustSessionManager: service.trustSession
            )

            try await trustClient.handshake(
                host: pc.host,
                port: pc.port,
                sessionID: config.sessionID,
                correlationID: config.correlationID
            )

            let pin = try await trustClient.apply(
                host: pc.host,
                port: pc.port,
                sessionID: config.sessionID,
                correlationID: config.correlationID
            )
            service.currentPIN = pin
            state = .firstUseTrust(pin: pin)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func startTrustedTransfer() async {
        state = .transferring(progress: 0.5)
        state = .delivering
        state = .success
        InstantShareHandoffContext.clear()
    }

    private func buildConnectionConfig(from context: InstantShareHandoffContext) throws -> InstantShareConnectionConfig {
        let payloadClass: InstantSharePayloadClass
        let targetIntent: InstantShareTargetIntent
        switch context.payloadType {
        case "text":
            payloadClass = .text
            targetIntent = .clipboardOnly
        case "image":
            payloadClass = .image
            targetIntent = .clipboardOrFile
        default:
            payloadClass = .image
            targetIntent = .clipboardOrFile
        }

        let metadata = InstantShareMetadata(
            payloadClass: payloadClass,
            targetIntent: targetIntent,
            trustMode: context.isTrustedDevice ? .trustedDirect : .firstShare
        )

        return InstantShareConnectionConfig(
            sessionID: UUID().uuidString.lowercased(),
            mobilePort: 0,
            mobileIPList: [],
            correlationID: UUID().uuidString.lowercased(),
            metadata: metadata
        )
    }

    private func describePayload(_ context: InstantShareHandoffContext) -> String {
        switch context.payloadType {
        case "text":
            let preview = context.textContent ?? ""
            return preview.count > 40 ? String(preview.prefix(40)) + "..." : preview
        case "image": return "Image" + (context.filename.map { " (\($0))" } ?? "")
        case "video": return "Video" + (context.filename.map { " (\($0))" } ?? "")
        default: return context.filename ?? "File"
        }
    }
}
