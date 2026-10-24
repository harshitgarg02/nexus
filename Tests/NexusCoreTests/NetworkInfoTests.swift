import XCTest
@testable import NexusCore

final class NetworkInfoTests: XCTestCase {
    func testParseDefaultRoute() {
        let out = """
        Routing tables

        Internet:
        Destination        Gateway            Flags               Netif Expire
        default            link#18            UCSIg           bridge100      !
        default            192.168.1.1        UGScg                 en0
        10.0.0.0/8         10.1.1.1           UGSc                  en5
        """
        let r = NetworkInfo.parseDefaultRoute(out)
        XCTAssertEqual(r?.gateway, "192.168.1.1")   // link# gateways are skipped
        XCTAssertEqual(r?.interface, "en0")
        XCTAssertNil(NetworkInfo.parseDefaultRoute("Internet:\nDestination Gateway Flags Netif\n10.0.0.0/8 10.1.1.1 UGSc en5"))
        XCTAssertNil(NetworkInfo.parseDefaultRoute(""))
    }

    func testParseDNSDedupesInOrder() {
        let out = """
        DNS configuration

        resolver #1
          search domain[0] : lan
          nameserver[0] : 192.168.1.1
          nameserver[1] : 1.1.1.1
          if_index : 15 (en0)

        resolver #2
          domain   : local
          nameserver[0] : 1.1.1.1
          nameserver[1] : 2606:4700:4700::1111
        """
        XCTAssertEqual(NetworkInfo.parseDNS(out), ["192.168.1.1", "1.1.1.1", "2606:4700:4700::1111"])
        XCTAssertEqual(NetworkInfo.parseDNS("nothing here"), [])
    }

    func testRowsPutTheDefaultRouteInterfaceFirst() {
        let wifi = NetInterface(name: "en0", display: "Wi-Fi", mac: "aa:bb:cc:dd:ee:ff", ipv4: [("192.168.1.23", 24)], ipv6: [("2001:db8::1", 64)])
        let vpn = NetInterface(name: "utun4", display: nil, mac: nil, ipv4: [("10.8.0.2", 32)], ipv6: [])
        let eth = NetInterface(name: "en5", display: "USB LAN", mac: "11:22:33:44:55:66", ipv4: [("10.0.0.7", 8)], ipv6: [])
        let rows = NetworkInfo.rows(interfaces: [eth, vpn, wifi], gateway: ("192.168.1.1", "en0"), dns: ["1.1.1.1"], hostname: "mac.local")
        XCTAssertEqual(rows.map(\.title), ["mac.local", "192.168.1.23", "2001:db8::1", "aa:bb:cc:dd:ee:ff", "10.0.0.7", "11:22:33:44:55:66",
                                           "10.8.0.2", "192.168.1.1", "1.1.1.1"])
        XCTAssertEqual(rows[1].subtitle, "Wi-Fi (en0) · IPv4 · /24")
        XCTAssertEqual(rows[2].subtitle, "Wi-Fi (en0) · IPv6 · /64")
        XCTAssertEqual(rows[6].subtitle, "utun4 · IPv4 · /32")   // no friendly name: BSD name only
        XCTAssertEqual(rows[7].subtitle, "Default gateway · en0")
        XCTAssertEqual(rows.last?.subtitle, "DNS server")
    }

    func testLiveSystemSmoke() {
        // Real machine: never crashes, never reports loopback, prefixes are sane, MACs look like MACs.
        for i in NetworkInfo.interfaces() {
            XCTAssertNotEqual(i.name, "lo0")
            XCTAssertTrue(i.ipv4.allSatisfy { (0...32).contains($0.prefix) && !$0.address.hasPrefix("127.") }, i.name)
            XCTAssertTrue(i.ipv6.allSatisfy { (0...128).contains($0.prefix) && !$0.address.lowercased().hasPrefix("fe80") }, i.name)
            if let m = i.mac { XCTAssertNotNil(m.range(of: #"^([0-9a-f]{2}:){5}[0-9a-f]{2}$"#, options: .regularExpression), m) }
        }
        XCTAssertFalse(NetworkInfo.liveRows().isEmpty) // at least the hostname
    }
}
