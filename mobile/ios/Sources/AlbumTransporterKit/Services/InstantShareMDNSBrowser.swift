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
        if case .service(let name, _, _, _) = result.endpoint {
            return name
        }
        return result.endpoint.debugDescription
    }

    private func deviceIDFromResult(_ result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint {
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
        
        print("[debug] NWBrowser result: \(result)")

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.extractPCInfo(from: connection, result: result, deviceID: deviceID)
                    connection.cancel()
                }
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
        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        
        switch endpoint {
        case .hostPort(let host, let port):
            InstantShareLog.debug("[MDNS Debug] state: \(connection.state) .hostPort host: \(host), port: \(port)")
        case .service(let name, let type, let domain, let interface):
            InstantShareLog.debug("[MDNS Debug] state: \(connection.state) service name: \(name), type: \(type), domain: \(domain), interface: \(interface)")
        case .url(let url):
            InstantShareLog.debug("[MDNS Debug] state: \(connection.state) .url: \(url)")
        case .unix(let path):
            InstantShareLog.debug("[MDNS Debug] state: \(connection.state) .unix: \(path)")
        case .opaque(let endpoint_t):
            InstantShareLog.debug("[MDNS Debug] state: \(connection.state) .opaque: \(endpoint_t)")
        @unknown default:
            fatalError()
        }
        
        guard case .hostPort(let host, let port) = endpoint,
              case .ipv4 = host,
                let hostString = host.cleanString else {
            if let endpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, let port) = endpoint,
               case .ipv6 = host {
                resolveWithEndpoint(host: "\(host)", port: Int(port.rawValue), result: result, fallbackID: deviceID)
                return
            }
            InstantShareLog.debug("[MDNS Browser] extractPCInfo: could not determine host for \(deviceID)")
            InstantShareLog.debug("[MDNS Browser] currentPath: \(connection.currentPath)")
            InstantShareLog.debug("[MDNS Browser] point: \(endpoint)")
            InstantShareLog.debug("[MDNS Browser] remoteEndpoint: \(connection.currentPath?.remoteEndpoint)")
            
            return
        }

        resolveWithEndpoint(host: "\(hostString)", port: Int(port.rawValue), result: result, fallbackID: deviceID)
    }

    private func resolveWithEndpoint(host: String, port: Int, result: NWBrowser.Result, fallbackID: String) {
        let txtRecord = extractTXTRecord(from: result)
        InstantShareLog.debug("[MDNS Browser] TXT record: \(txtRecord?.description ?? "nil")")
        InstantShareLog.debug("[MDNS Browser] TXT keys: \(txtRecord?.keys.sorted().joined(separator: ", ") ?? "none")")
        
        let deviceID: String
        if let idFromTXT = txtRecord?["device_id"], !idFromTXT.isEmpty {
            deviceID = idFromTXT
            InstantShareLog.debug("[MDNS Browser] Using device_id from TXT: \(deviceID)")
        } else {
            // TXT record missing device_id — use fallback (service name) with warning
            InstantShareLog.debug("[MDNS Browser] No device_id in TXT, using fallback: \(fallbackID)")
            deviceID = fallbackID
        }
        let deviceName = txtRecord?["device_name"] ?? deviceID
        let signature = txtRecord?["signature"]
        let signatureKeyID = txtRecord?["signature_key_id"]
        let timestampMS = txtRecord?["timestamp_ms"].flatMap { Int64($0) }
        let protocolVersion = txtRecord?["ver"]

        let pc = InstantShareDiscoveredPC(
            id: deviceID,
            name: String(deviceName),
            host: host,
            port: port,
            signature: signature,
            signatureKeyID: signatureKeyID,
            timestampMS: timestampMS,
            protocolVersion: protocolVersion
        )

        resolvedPCs[deviceID] = pc
        refreshDiscovered()
        InstantShareLog.debug("[MDNS Browser] resolved \(pc.name) (\(pc.id)) at \(host):\(port)")
    }

    private func extractTXTRecord(from result: NWBrowser.Result) -> [String: String]? {
        guard case .bonjour(let txtRecord) = result.metadata else {
            InstantShareLog.debug("[MDNS Browser] extractTXTRecord: metadata is not .bonjour, got: \(result.metadata)")
            return nil
        }
        let dict = txtRecord.dictionary
        InstantShareLog.debug("[MDNS Browser] extractTXTRecord: raw dictionary has \(dict.count) entries")
        var resultDict: [String: String] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resultDict[key] = stringValue
                InstantShareLog.debug("[MDNS Browser] TXT key '\(key)' = '\(stringValue)' (String)")
            } else if let dataValue = value as? Data {
                let str = String(data: dataValue, encoding: .utf8) ?? ""
                resultDict[key] = str
                InstantShareLog.debug("[MDNS Browser] TXT key '\(key)' = '\(str)' (Data, \(dataValue.count) bytes)")
            } else {
                InstantShareLog.debug("[MDNS Browser] TXT key '\(key)' has unknown type: \(type(of: value))")
            }
        }
        return resultDict
    }

    private func refreshDiscovered() {
        discovered = Array(resolvedPCs.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        InstantShareLog.debug("[MDNS Browser] refreshDiscovered: \(discovered.count) PCs")
    }
}
