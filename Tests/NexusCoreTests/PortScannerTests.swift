import XCTest
@testable import NexusCore

final class PortScannerTests: XCTestCase {
    func testParsesPortsDedupesAndSorts() {
        let out = """
        p68171
        cnode
        u501
        f20
        n*:7265
        f21
        n[::1]:7265
        p3283
        cARDAgent
        u0
        f4
        n*:3283
        p50977
        cLogiPluginService
        u501
        f5
        n127.0.0.1:59869
        f6
        n[::1]:59869
        f7
        n127.0.0.1:50000
        """
        let ports = PortScanner.parse(out)
        XCTAssertEqual(ports.map(\.port), [3283, 7265, 50000, 59869])
        // port is the row number; the PID is separate (ref1: port 7265 -> PID 68171)
        let node = ports.first { $0.port == 7265 }!
        XCTAssertEqual(node.pid, 68171)
        XCTAssertEqual(node.name, "node")
        XCTAssertEqual(ports.first { $0.name == "ARDAgent" }?.uid, 0)
        XCTAssertEqual(ports.filter { $0.port == 59869 }.count, 1)
        XCTAssertEqual(ports.first { $0.port == 50000 }?.name, "LogiPluginService")
    }

    func testIgnoresGarbage() {
        XCTAssertTrue(PortScanner.parse("").isEmpty)
        XCTAssertTrue(PortScanner.parse("n*:80\nzzz\n").isEmpty) // port line before any process
    }
}
