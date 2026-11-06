import Foundation

/// One VPN connection. Mirrors the options in NetworkManager-l2tp's editor
/// (General, IPsec, PPP and IPv4 tabs). Secrets (password, pre-shared key)
/// are not stored here; the helper keeps them (see Secrets).
struct Profile: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "New VPN"

    // General
    var gateway: String = ""
    var username: String = ""
    var ntDomain: String = ""
    var askPasswordEachTime: Bool = false

    // IPsec
    var ipsecEnabled: Bool = true
    var remoteID: String = ""
    var localID: String = ""
    var phase1Algorithms: String = ""
    var phase2Algorithms: String = ""
    var phase1LifetimeMinutes: Int = 180
    var phase2LifetimeMinutes: Int = 60
    var legacyProposals: Bool = false
    var forceUDPEncapsulation: Bool = false
    var ipCompression: Bool = false
    var disablePFS: Bool = false

    // PPP: authentication
    var allowPAP: Bool = true
    var allowCHAP: Bool = true
    var allowMSCHAP: Bool = true
    var allowMSCHAPv2: Bool = true
    var allowEAP: Bool = true
    // PPP: security and compression
    var useMPPE: Bool = false
    var mppe128Only: Bool = false
    var mppeStateful: Bool = false
    var bsdCompression: Bool = false
    var deflateCompression: Bool = false
    var tcpHeaderCompression: Bool = true
    var protocolFieldCompression: Bool = true
    var addressControlCompression: Bool = true
    // PPP: misc
    var sendEchoPackets: Bool = true
    var mtu: Int = 1400
    var mru: Int = 1400

    // IPv4
    var sendAllTraffic: Bool = true
    var routes: String = ""          // comma separated CIDRs, e.g. 10.0.0.0/8
    var ignoreAutomaticDNS: Bool = false
    var dnsServers: String = ""      // comma separated
    var searchDomains: String = ""   // comma separated
}

// MARK: - Presets

extension Profile {
    /// Settings that work with Cisco Meraki Client VPN.
    mutating func applyMerakiPreset() {
        ipsecEnabled = true
        phase1Algorithms = "aes128-sha1-modp2048,aes128-sha1-modp1024,3des-sha1-modp1024"
        phase2Algorithms = "aes128-sha1,3des-sha1"
        disablePFS = true
        forceUDPEncapsulation = true
        legacyProposals = false
        allowPAP = true
        allowCHAP = false
        allowMSCHAP = false
        allowMSCHAPv2 = false
        allowEAP = false
        useMPPE = false
        mtu = 1400
        mru = 1400
    }
}

// MARK: - Validation (the helper re-checks everything; this is for nice errors)

extension Profile {
    static func list(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    private static let ipv4 = #"^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$"#

    /// Problems that would stop a connection, in plain words.
    var problems: [String] {
        var p: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { p.append("Name is empty") }
        if !Self.matches(gateway, #"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$"#) { p.append("Gateway must be a hostname or IP address") }
        if username.isEmpty { p.append("Username is empty") }
        if !Self.matches(remoteID, #"^[A-Za-z0-9@._:=,+-]{0,255}$"#) { p.append("Remote ID has unsupported characters") }
        if !Self.matches(localID, #"^[A-Za-z0-9@._:=,+-]{0,255}$"#) { p.append("Local ID has unsupported characters") }
        for (label, v) in [("Phase 1", phase1Algorithms), ("Phase 2", phase2Algorithms)] {
            if !Self.matches(v.replacingOccurrences(of: " ", with: ""), #"^[a-z0-9_!,-]*$"#) {
                p.append("\(label) algorithms: use strongSwan format, e.g. aes128-sha1-modp2048")
            }
        }
        if !(1...10080).contains(phase1LifetimeMinutes) { p.append("Phase 1 lifetime must be 1–10080 minutes") }
        if !(1...10080).contains(phase2LifetimeMinutes) { p.append("Phase 2 lifetime must be 1–10080 minutes") }
        if !(576...1500).contains(mtu) { p.append("MTU must be 576–1500") }
        if !(576...1500).contains(mru) { p.append("MRU must be 576–1500") }
        if !allowPAP && !allowCHAP && !allowMSCHAP && !allowMSCHAPv2 && !allowEAP {
            p.append("Allow at least one PPP authentication method")
        }
        for r in Self.list(routes) {
            let parts = r.split(separator: "/")
            if parts.count != 2 || !Self.matches(String(parts[0]), Self.ipv4) || !(0...32).contains(Int(parts[1]) ?? -1) {
                p.append("Route '\(r)' must look like 10.0.0.0/8")
            }
        }
        for d in Self.list(dnsServers) where !Self.matches(d, Self.ipv4) { p.append("DNS server '\(d)' must be an IPv4 address") }
        for d in Self.list(searchDomains) where !Self.matches(d, #"^[A-Za-z0-9.-]{1,253}$"#) { p.append("Search domain '\(d)' is not valid") }
        if !sendAllTraffic && Self.list(routes).isEmpty {
            p.append("With 'Send all traffic' off, add at least one route")
        }
        return p
    }
}

// MARK: - Helper request

extension Profile {
    /// The key=value request the privileged helper expects.
    func helperRequest(password: String, psk: String) -> String {
        func b(_ v: Bool) -> String { v ? "1" : "0" }
        func clean(_ s: String) -> String {
            s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        }
        let fields: [(String, String)] = [
            ("cmd", "up"),
            ("id", id),
            ("gateway", gateway.trimmingCharacters(in: .whitespaces)),
            ("username", clean(username)),
            ("password", clean(password)),
            ("nt_domain", clean(ntDomain)),
            ("ipsec", b(ipsecEnabled)),
            ("psk", clean(psk)),
            ("remote_id", remoteID),
            ("local_id", localID),
            ("ike", phase1Algorithms.replacingOccurrences(of: " ", with: "")),
            ("esp", phase2Algorithms.replacingOccurrences(of: " ", with: "")),
            ("ike_lifetime", String(phase1LifetimeMinutes * 60)),
            ("sa_lifetime", String(phase2LifetimeMinutes * 60)),
            ("legacy", b(legacyProposals)),
            ("forceencaps", b(forceUDPEncapsulation)),
            ("ipcomp", b(ipCompression)),
            ("pfs", b(!disablePFS)),
            ("refuse_pap", b(!allowPAP)),
            ("refuse_chap", b(!allowCHAP)),
            ("refuse_mschap", b(!allowMSCHAP)),
            ("refuse_mschapv2", b(!allowMSCHAPv2)),
            ("refuse_eap", b(!allowEAP)),
            ("mppe", b(useMPPE)),
            ("mppe128", b(mppe128Only)),
            ("mppe_stateful", b(mppeStateful)),
            ("bsdcomp", b(bsdCompression)),
            ("deflate", b(deflateCompression)),
            ("vj", b(tcpHeaderCompression)),
            ("pcomp", b(protocolFieldCompression)),
            ("accomp", b(addressControlCompression)),
            ("echo", b(sendEchoPackets)),
            ("mtu", String(mtu)),
            ("mru", String(mru)),
            ("default_route", b(sendAllTraffic)),
            ("routes", Self.list(routes).joined(separator: ",")),
            ("ignore_auto_dns", b(ignoreAutomaticDNS)),
            ("dns", Self.list(dnsServers).joined(separator: ",")),
            ("search", Self.list(searchDomains).joined(separator: ",")),
        ]
        return fields.map { "\($0.0)=\($0.1)" }.joined(separator: "\n") + "\n\n"
    }
}
