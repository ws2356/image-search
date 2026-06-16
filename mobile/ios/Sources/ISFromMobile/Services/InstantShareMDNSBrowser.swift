import Foundation
import Network
import Common

@available(iOS 15.0, *)
public struct InstantShareDiscoveredPC: Identifiable, Equatable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let tlsPort: Int
    public let protocolVersion: String?

    public init(
        id: String,
        name: String,
        host: String,
        port: Int,
        tlsPort: Int,
        protocolVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.tlsPort = tlsPort
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
        LocalLog.debug("[MDNS Browser] startBrowsing")
        stopBrowsing()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let bonjourDescriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
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
                        LocalLog.debug("[MDNS Browser] result added: \(self.nameFromResult(result))")
                        self.resolveResult(result)
                    case .removed(let result):
                        self.browseResults.remove(result)
                        LocalLog.debug("[MDNS Browser] result removed: \(self.nameFromResult(result))")
                        self.removeResult(result)
                    case .changed(let old, let new, flags: _):
                        self.browseResults.remove(old)
                        self.browseResults.insert(new)
                        LocalLog.debug("[MDNS Browser] result changed: \(self.nameFromResult(new))")
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
                    LocalLog.debug("[MDNS Browser] state: ready (browsing)")
                case .failed(let error):
                    self.state = .stopped
                    LocalLog.error("[MDNS Browser] state: failed \(error.localizedDescription)")
                case .cancelled:
                    self.state = .stopped
                    LocalLog.debug("[MDNS Browser] state: cancelled")
                case .waiting(let error):
                    self.state = .idle
                    LocalLog.debug("[MDNS Browser] state: waiting \(error.localizedDescription)")
                @unknown default:
                    break
                }
            }
        }

        browser.start(queue: queue)
        self.state = .browsing
        LocalLog.debug("[MDNS Browser] browse started for _instantshare._tcp")
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
        LocalLog.debug("[MDNS Browser] stopped")
    }

    private func nameFromResult(_ result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint {
            return name
        }
        return result.endpoint.debugDescription
    }

    private func removeResult(_ result: NWBrowser.Result) {
        let serviceName = nameFromResult(result)
        resolvedPCs.removeValue(forKey: serviceName)
        refreshDiscovered()
    }

    private func resolveResult(_ result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        
        LocalLog.debug("[debug] NWBrowser result: \(result)")

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            LocalLog.debug("[MDNS Browser] state connection state: \(state)")
            switch state {
            case .ready:
                Task { @MainActor in
                    self.extractPCInfo(from: connection, result: result)
                    connection.cancel()
                }
            case .failed:
                connection.cancel()
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func extractPCInfo(from connection: NWConnection, result: NWBrowser.Result) {
        let endpoint = connection.currentPath?.remoteEndpoint
        
        switch endpoint {
        case .hostPort(let host, let port):
            LocalLog.debug("[MDNS Debug] state: \(connection.state) .hostPort host: \(host), port: \(port)")
        case .service(let name, let type, let domain, let interface):
            LocalLog.debug("[MDNS Debug] state: \(connection.state) service name: \(name), type: \(type), domain: \(domain), interface: \(interface)")
        case .url(let url):
            LocalLog.debug("[MDNS Debug] state: \(connection.state) .url: \(url)")
        case .unix(let path):
            LocalLog.debug("[MDNS Debug] state: \(connection.state) .unix: \(path)")
        case .opaque(let endpoint_t):
            LocalLog.debug("[MDNS Debug] state: \(connection.state) .opaque: \(endpoint_t)")
        @unknown default:
            fatalError()
        }
        
        guard case .hostPort(let host, let port) = endpoint,
              case .ipv4 = host,
                let hostString = host.cleanString else {
            if let endpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, let port) = endpoint,
               case .ipv6 = host {
                resolveWithEndpoint(host: "\(host)", port: Int(port.rawValue), result: result)
                return
            }
            LocalLog.debug("[MDNS Browser] currentPath: \(connection.currentPath)")
            LocalLog.debug("[MDNS Browser] point: \(endpoint)")
            LocalLog.debug("[MDNS Browser] remoteEndpoint: \(connection.currentPath?.remoteEndpoint)")
            
            return
        }

        resolveWithEndpoint(host: "\(hostString)", port: Int(port.rawValue), result: result)
    }

    private func resolveWithEndpoint(host: String, port: Int, result: NWBrowser.Result) {
        let txtRecord = extractTXTRecord(from: result)
        LocalLog.debug("[MDNS Browser] TXT record: \(txtRecord?.description ?? "nil")")
        LocalLog.debug("[MDNS Browser] TXT keys: \(txtRecord?.keys.sorted().joined(separator: ", ") ?? "none")")
        
        guard let deviceName =  txtRecord?["device_name"] else {
            LocalLog.error("[MDNS Browser] No device_name from TXT")
            return
        }
        let protocolVersion = txtRecord?["ver"]
        let tlsPort: Int
        if let raw = txtRecord?["tls_port"], let value = Int(raw), value > 0, value <= 65535 {
            tlsPort = value
            LocalLog.debug("[MDNS Browser] TLS port from TXT: \(tlsPort)")
        } else {
            LocalLog.error("[MDNS Browser] missing or invalid tls_port in TXT record, skipping PC")
            return
        }

        let pcId = "\(host):\(port)"
        let pc = InstantShareDiscoveredPC(
            id: pcId,
            name: String(deviceName),
            host: host,
            port: port,
            tlsPort: tlsPort,
            protocolVersion: protocolVersion
        )

        resolvedPCs[pcId] = pc
        refreshDiscovered()
        LocalLog.debug("[MDNS Browser] resolved \(pc.name) (\(pc.id)) at \(host):\(port) tlsPort=\(tlsPort)")
    }

    private func extractTXTRecord(from result: NWBrowser.Result) -> [String: String]? {
        guard case .bonjour(let txtRecord) = result.metadata else {
            LocalLog.debug("[MDNS Browser] extractTXTRecord: metadata is not .bonjour, got: \(result.metadata)")
            return nil
        }
        let dict = txtRecord.dictionary
        LocalLog.debug("[MDNS Browser] extractTXTRecord: raw dictionary has \(dict.count) entries")
        var resultDict: [String: String] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resultDict[key] = stringValue
                LocalLog.debug("[MDNS Browser] TXT key '\(key)' = '\(stringValue)' (String)")
            } else if let dataValue = value as? Data {
                let str = String(data: dataValue, encoding: .utf8) ?? ""
                resultDict[key] = str
                LocalLog.debug("[MDNS Browser] TXT key '\(key)' = '\(str)' (Data, \(dataValue.count) bytes)")
            } else {
                LocalLog.debug("[MDNS Browser] TXT key '\(key)' has unknown type: \(type(of: value))")
            }
        }
        return resultDict
    }

    private func refreshDiscovered() {
        discovered = Array(resolvedPCs.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        LocalLog.debug("[MDNS Browser] refreshDiscovered: \(discovered.count) PCs")
    }
}
