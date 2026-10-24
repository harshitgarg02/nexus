import Foundation
import Darwin
import SystemConfiguration

public struct NetInterface: Equatable {
    public let name: String          // en0
    public let display: String?      // Wi-Fi
    public let mac: String?
    public let ipv4: [(address: String, prefix: Int)]
    public let ipv6: [(address: String, prefix: Int)]

    public var label: String { display.map { "\($0) (\(name))" } ?? name }

    public static func == (a: NetInterface, b: NetInterface) -> Bool {
        a.name == b.name && a.display == b.display && a.mac == b.mac
            && a.ipv4.map(\.address) == b.ipv4.map(\.address) && a.ipv6.map(\.address) == b.ipv6.map(\.address)
    }
}

public enum NetworkInfo {
    // MARK: reading the system

    /// Interfaces that are up, not loopback, and have an address. Link-local IPv6 (fe80::) is left out.
    public static func interfaces() -> [NetInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var v4: [String: [(String, Int)]] = [:], v6: [String: [(String, Int)]] = [:], macs: [String: String] = [:]
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let sa = ifa.ifa_addr else { continue }
            let name = String(cString: ifa.ifa_name)
            switch Int32(sa.pointee.sa_family) {
            case AF_INET:
                guard let a = numeric(sa) else { continue }
                v4[name, default: []].append((a, prefixLength(ifa.ifa_netmask)))
            case AF_INET6:
                guard var a = numeric(sa) else { continue }
                if let pct = a.firstIndex(of: "%") { a = String(a[..<pct]) }
                guard !a.lowercased().hasPrefix("fe80") else { continue }
                v6[name, default: []].append((a, prefixLength(ifa.ifa_netmask)))
            case AF_LINK:
                if let m = mac(sa) { macs[name] = m }
            default: break
            }
        }
        let display = displayNames()
        return Set(v4.keys).union(v6.keys).sorted().map {
            NetInterface(name: $0, display: display[$0], mac: macs[$0], ipv4: v4[$0] ?? [], ipv6: v6[$0] ?? [])
        }
    }

    private static func numeric(_ sa: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    private static func prefixLength(_ mask: UnsafeMutablePointer<sockaddr>?) -> Int {
        guard let mask else { return 0 }
        switch Int32(mask.pointee.sa_family) {
        case AF_INET:
            return mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr).nonzeroBitCount }
        case AF_INET6:
            return mask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p in
                withUnsafeBytes(of: p.pointee.sin6_addr) { $0.reduce(0) { $0 + $1.nonzeroBitCount } }
            }
        default: return 0
        }
    }

    private static func mac(_ sa: UnsafePointer<sockaddr>) -> String? {
        let dl = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_dl.self)
        let (nlen, alen) = (Int(dl.pointee.sdl_nlen), Int(dl.pointee.sdl_alen))
        guard alen == 6, let off = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) else { return nil }
        let bytes = (0..<6).map { UnsafeRawPointer(sa).load(fromByteOffset: off + nlen + $0, as: UInt8.self) }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func displayNames() -> [String: String] {
        var out: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(i) as String?, let name = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? { out[bsd] = name }
        }
        return out
    }

    // MARK: parsing command output

    /// First IPv4 default route from `netstat -rn -f inet`: the gateway and the interface that carries it.
    public static func parseDefaultRoute(_ netstat: String) -> (gateway: String, interface: String)? {
        for line in netstat.split(separator: "\n") {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard f.count >= 4, f[0] == "default", f[1].split(separator: ".").count == 4 else { continue }
            return (f[1], f[3])
        }
        return nil
    }

    /// Distinct nameservers from `scutil --dns`, in order.
    public static func parseDNS(_ scutil: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for line in scutil.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("nameserver["), let colon = t.firstIndex(of: ":") else { continue }
            let addr = t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !addr.isEmpty, seen.insert(addr).inserted { out.append(addr) }
        }
        return out
    }

    // MARK: rows

    /// Pure builder (the app passes in live data; tests pass fixtures). The default-route interface comes first.
    public static func rows(interfaces: [NetInterface], gateway: (gateway: String, interface: String)?, dns: [String], hostname: String) -> [CalcRow] {
        var out = [CalcRow(title: hostname, subtitle: "Hostname")]
        let ordered = interfaces.sorted { a, b in
            let (pa, pb) = (a.name == gateway?.interface, b.name == gateway?.interface)
            return pa != pb ? pa : a.name < b.name
        }
        for i in ordered {
            for a in i.ipv4 { out.append(CalcRow(title: a.address, subtitle: "\(i.label) · IPv4 · /\(a.prefix)")) }
            for a in i.ipv6 { out.append(CalcRow(title: a.address, subtitle: "\(i.label) · IPv6 · /\(a.prefix)")) }
            if let m = i.mac, !i.ipv4.isEmpty { out.append(CalcRow(title: m, subtitle: "MAC · \(i.label)")) }
        }
        if let g = gateway { out.append(CalcRow(title: g.gateway, subtitle: "Default gateway · \(g.interface)")) }
        for d in dns { out.append(CalcRow(title: d, subtitle: "DNS server")) }
        return out
    }

    private nonisolated(unsafe) static var cache: (at: Date, rows: [CalcRow])?

    /// Live rows for the launcher. Cached for 5 seconds so typing doesn't re-run the system tools on every keystroke.
    public static func liveRows(now: Date = Date()) -> [CalcRow] {
        if let c = cache, now.timeIntervalSince(c.at) < 5 { return c.rows }
        let rows = self.rows(interfaces: interfaces(), gateway: parseDefaultRoute(run("/usr/sbin/netstat", ["-rn", "-f", "inet"])),
                             dns: Array(parseDNS(run("/usr/sbin/scutil", ["--dns"])).prefix(6)), hostname: ProcessInfo.processInfo.hostName)
        cache = (now, rows)
        return rows
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
