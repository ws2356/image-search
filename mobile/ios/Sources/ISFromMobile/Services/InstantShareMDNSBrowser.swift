import Foundation
import Network
import Common

@available(iOS 15.0, *)
public struct InstantShareDiscoveredPC: Identifiable, Equatable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let hosts: [String]
    public let port: Int
    public let tlsPort: Int
    public let protocolVersion: String?

    /// Primary (first) IP address for display and default connection attempts.
    public var primaryHost: String { hosts.first ?? "unknown" }

    /// Deterministic dedup key: sorted IP list + port.
    /// e.g. hosts=["10.0.0.1","192.168.1.5"], port=8080 → "10.0.0.1,192.168.1.5:8080"
    public static func pcKey(hosts: [String], port: Int) -> String {
        hosts.sorted().joined(separator: ",") + ":\(port)"
    }

    public init(
        id: String,
        name: String,
        hosts: [String],
        port: Int,
        tlsPort: Int,
        protocolVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hosts = hosts
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
    /// Single source of truth for discovered PCs, keyed by `sorted_ip_list:port`.
    private var discoveredMap: [String: InstantShareDiscoveredPC] = [:]
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
                        self.resolveFromTXTRecord(result)
                    case .removed(let result):
                        self.browseResults.remove(result)
                        LocalLog.debug("[MDNS Browser] result removed: \(self.nameFromResult(result))")
                        self.removeResult(result)
                    case .changed(let old, let new, flags: _):
                        self.browseResults.remove(old)
                        self.browseResults.insert(new)
                        LocalLog.debug("[MDNS Browser] result changed: \(self.nameFromResult(new))")
                        self.resolveFromTXTRecord(new)
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
        discoveredMap.removeAll()
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
        guard let key = pcKeyFromResult(result) else {
            LocalLog.debug("[MDNS Browser] could not compute key for removed result, skipping")
            return
        }
        if discoveredMap.removeValue(forKey: key) != nil {
            LocalLog.debug("[MDNS Browser] removed PC with key: \(key)")
        }
        refreshDiscovered()
    }

    /// Parse PC info directly from the mDNS TXT record (ip, port, device_name, tls_port, ver).
    /// The PC advertises `ip="<ip1>,<ip2>,<ip3>"` and `port=<int>` in its TXT record,
    /// so no NWConnection resolve step is needed.
    private func resolveFromTXTRecord(_ result: NWBrowser.Result) {
        let txtRecord = extractTXTRecord(from: result)
        LocalLog.debug("[MDNS Browser] TXT record: \(txtRecord?.description ?? "nil")")
        LocalLog.debug("[MDNS Browser] TXT keys: \(txtRecord?.keys.sorted().joined(separator: ", ") ?? "none")")

        guard let deviceName = txtRecord?["device_name"] else {
            LocalLog.error("[MDNS Browser] No device_name from TXT")
            return
        }
        guard let ipListRaw = txtRecord?["ip"], !ipListRaw.isEmpty else {
            LocalLog.error("[MDNS Browser] missing or empty ip in TXT record, skipping PC")
            return
        }
        guard let portRaw = txtRecord?["port"], let port = Int(portRaw), port > 0, port <= 65535 else {
            LocalLog.error("[MDNS Browser] missing or invalid port in TXT record, skipping PC")
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

        let hosts = ipListRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !hosts.isEmpty else {
            LocalLog.error("[MDNS Browser] ip TXT record contained no valid addresses: '\(ipListRaw)'")
            return
        }

        let key = InstantShareDiscoveredPC.pcKey(hosts: hosts, port: port)
        let pc = InstantShareDiscoveredPC(
            id: key,
            name: String(deviceName),
            hosts: hosts,
            port: port,
            tlsPort: tlsPort,
            protocolVersion: protocolVersion
        )

        discoveredMap[key] = pc
        refreshDiscovered()
        LocalLog.debug("[MDNS Browser] resolved \(pc.name) (\(pc.id)) hosts=\(hosts) port=\(port) tlsPort=\(tlsPort)")
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

    /// Extract TXT record from a browse result and compute the `sorted_ip_list:port` key.
    /// Returns nil if the result has no valid TXT record with ip and port.
    private func pcKeyFromResult(_ result: NWBrowser.Result) -> String? {
        guard let txt = extractTXTRecord(from: result),
              let ipRaw = txt["ip"], !ipRaw.isEmpty,
              let portStr = txt["port"], let port = Int(portStr), port > 0, port <= 65535 else {
            return nil
        }
        let hosts = ipRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !hosts.isEmpty else { return nil }
        return InstantShareDiscoveredPC.pcKey(hosts: hosts, port: port)
    }

    private func refreshDiscovered() {
        discovered = Array(discoveredMap.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        LocalLog.debug("[MDNS Browser] refreshDiscovered: \(discovered.count) PCs")
    }
}
