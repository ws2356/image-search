import Foundation
import Network

@available(iOS 15.0, *)
public struct InstantShareDiscoveredPC: Identifiable, Equatable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let signature: String?
    public let signatureKeyID: String?
    public let timestampMS: Int64?
    public let protocolVersion: String?

    public init(
        id: String,
        name: String,
        host: String,
        port: Int,
        signature: String? = nil,
        signatureKeyID: String? = nil,
        timestampMS: Int64? = nil,
        protocolVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.signature = signature
        self.signatureKeyID = signatureKeyID
        self.timestampMS = timestampMS
        self.protocolVersion = protocolVersion
    }

    public static func == (lhs: InstantShareDiscoveredPC, rhs: InstantShareDiscoveredPC) -> Bool {
        lhs.id == rhs.id
    }
}

@available(iOS 15.0, *)
public enum InstantShareMDNSBrowserState: String {
    case idle
    case browsing
    case stopped
}

@available(iOS 15.0, *)
@MainActor
public final class InstantShareMDNSBrowser: ObservableObject {
    @Published public private(set) var discovered: [InstantShareDiscoveredPC] = []
    @Published public private(set) var state: InstantShareMDNSBrowserState = .idle

    private var browser: NWBrowser?
    private var browseResults: Set<NWBrowser.Result> = []
    private var resolvedPCs: [String: InstantShareDiscoveredPC] = [:]
    private let queue = DispatchQueue(label: "com.aubackup.instant-share.mdns-browser")

    public init() {}

    public func startBrowsing() {
        InstantShareLog.debug("[MDNS Browser] startBrowsing")
        stopBrowsing()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let bonjourDescriptor = NWBrowser.Descriptor.bonjour(
            type: "_instantshare._tcp",
            domain: "local"
        )
        let browser = NWBrowser(for: bonjourDescriptor, using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            Task { @MainActor in
                for change in changes {
                    switch change {
                    case .added(let result):
                        self.browseResults.insert(result)
                        InstantShareLog.debug("[MDNS Browser] result added: \(self.nameFromResult(result))")
                        self.resolveResult(result)
                    case .removed(let result):
                        self.browseResults.remove(result)
                        InstantShareLog.debug("[MDNS Browser] result removed: \(self.nameFromResult(result))")
                        self.removeResult(result)
                    case .changed(let old, let new, flags: _):
                        self.browseResults.remove(old)
                        self.browseResults.insert(new)
                        InstantShareLog.debug("[MDNS Browser] result changed: \(self.nameFromResult(new))")
                        self.resolveResult(new)
                    @unknown default:
                        break
                    }
                }
            }
        }

        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                switch newState {
                case .ready:
                    self.state = .browsing
                    InstantShareLog.debug("[MDNS Browser] state: ready (browsing)")
                case .failed(let error):
                    self.state = .stopped
                    InstantShareLog.error("[MDNS Browser] state: failed \(error.localizedDescription)")
                case .cancelled:
                    self.state = .stopped
                    InstantShareLog.debug("[MDNS Browser] state: cancelled")
                case .waiting(let error):
                    self.state = .idle
                    InstantShareLog.debug("[MDNS Browser] state: waiting \(error.localizedDescription)")
                @unknown default:
                    break
                }
            }
        }

        browser.start(queue: queue)
        self.state = .browsing
        InstantShareLog.debug("[MDNS Browser] browse started for _instantshare._tcp")
    }

    public func stopBrowsing() {
        if let browser {
            browser.cancel()
            self.browser = nil
        }
        browseResults.removeAll()
        resolvedPCs.removeAll()
        discovered = []
        state = .stopped
        InstantShareLog.debug("[MDNS Browser] stopped")
    }

    private func nameFromResult(_ result: NWBrowser.Result) -> String {
        if case .bonjour(let name) = result.endpoint {
            return name
        }
        return result.endpoint.debugDescription
    }

    private func deviceIDFromResult(_ result: NWBrowser.Result) -> String {
        if case .bonjour(let name) = result.endpoint {
            return name
        }
        return result.endpoint.debugDescription
    }

    private func removeResult(_ result: NWBrowser.Result) {
        let deviceID = deviceIDFromResult(result)
        resolvedPCs.removeValue(forKey: deviceID)
        refreshDiscovered()
    }

    private func resolveResult(_ result: NWBrowser.Result) {
        let deviceID = deviceIDFromResult(result)
        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.extractPCInfo(from: connection, result: result, deviceID: deviceID)
                connection.cancel()
            case .failed:
                connection.cancel()
                InstantShareLog.debug("[MDNS Browser] connection failed for \(deviceID)")
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func extractPCInfo(from connection: NWConnection, result: NWBrowser.Result, deviceID: String) {
        guard let endpoint = connection.currentPath?.remoteEndpoint,
              case .hostPort(let host, let port) = endpoint,
              case .ipv4 = host else {
            if let endpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, let port) = endpoint,
               case .ipv6 = host {
                resolveWithEndpoint(host: "\(host)", port: Int(port.rawValue), result: result, deviceID: deviceID)
                return
            }
            InstantShareLog.debug("[MDNS Browser] extractPCInfo: could not determine host for \(deviceID)")
            return
        }
        resolveWithEndpoint(host: "\(host)", port: Int(port.rawValue), result: result, deviceID: deviceID)
    }

    private func resolveWithEndpoint(host: String, port: Int, result: NWBrowser.Result, deviceID: String) {
        let txtRecord = extractTXTRecord(from: result)
        let deviceName = txtRecord?["device_name"] ?? deviceID
        let signature = txtRecord?["signature"]
        let signatureKeyID = txtRecord?["signature_key_id"]
        let timestampMS = txtRecord?["timestamp_ms"].flatMap { Int64($0) }
        let protocolVersion = txtRecord?["ver"]
        let deviceIDFromTXT = txtRecord?["device_id"] ?? deviceID

        let pc = InstantShareDiscoveredPC(
            id: deviceIDFromTXT,
            name: String(deviceName),
            host: host,
            port: port,
            signature: signature.flatMap { String($0) },
            signatureKeyID: signatureKeyID.flatMap { String($0) },
            timestampMS: timestampMS,
            protocolVersion: protocolVersion.flatMap { String($0) }
        )

        Task { @MainActor in
            self.resolvedPCs[deviceID] = pc
            self.refreshDiscovered()
            InstantShareLog.debug("[MDNS Browser] resolved \(pc.name) at \(host):\(port)")
        }
    }

    private func extractTXTRecord(from result: NWBrowser.Result) -> [String: String]? {
        guard case .bonjour(let txtRecord) = result.metadata else {
            return nil
        }
        let dict = txtRecord.dictionary
        var result_dict: [String: String] = [:]
        for (key, value) in dict {
            result_dict[key] = String(data: value, encoding: .utf8) ?? ""
        }
        return result_dict
    }

    private func refreshDiscovered() {
        discovered = Array(resolvedPCs.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        InstantShareLog.debug("[MDNS Browser] refreshDiscovered: \(discovered.count) PCs")
    }
}
