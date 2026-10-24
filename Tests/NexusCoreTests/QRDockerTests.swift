import XCTest
import Vision
@testable import NexusCore

final class QRCodeTests: XCTestCase {
    func decode(_ image: CGImage) -> String? {
        let req = VNDetectBarcodesRequest()
        req.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return req.results?.first?.payloadStringValue
    }

    func testRoundTripsThroughAnIndependentDecoder() throws {
        for text in ["https://example.com/?q=1&r=two", "hello", "unicode: héllo ✓ 日本語", String(repeating: "x", count: 600)] {
            let img = try XCTUnwrap(QRCode.cgImage(for: text), text)
            XCTAssertEqual(decode(img), text)
            XCTAssertEqual(img.width, img.height)
        }
    }

    func testQuietZoneAndScale() throws {
        let small = try XCTUnwrap(QRCode.cgImage(for: "a", scale: 4))
        let big = try XCTUnwrap(QRCode.cgImage(for: "a", scale: 8))
        XCTAssertEqual(big.width, small.width * 2)
        // a version-1 code is 21 modules wide; Core Image adds 1 on each side, and we add 3 more: 4 in total
        XCTAssertEqual(small.width, (21 + 2 + 6) * 4)
    }

    func testLimits() {
        XCTAssertNil(QRCode.cgImage(for: ""))
        XCTAssertNotNil(QRCode.cgImage(for: String(repeating: "a", count: QRCode.maxBytes)))
        XCTAssertNil(QRCode.cgImage(for: String(repeating: "a", count: QRCode.maxBytes + 1)))
    }
}

final class DockerParseTests: XCTestCase {
    let sample = """
    {"ID":"a1b2c3","Names":"web","Image":"nginx:latest","State":"running","Status":"Up 2 hours","Ports":"0.0.0.0:8080->80/tcp, [::]:8080->80/tcp"}
    {"ID":"d4e5f6","Names":"db","Image":"postgres:16","State":"exited","Status":"Exited (0) 3 days ago","Ports":""}
    {"ID":"112233","Names":"cache,alias","Image":"redis","State":"running","Status":"Up 5 minutes","Ports":"6379/tcp"}
    not json
    {"Names":"no id"}
    """

    func testParsesAndOrdersRunningFirstThenByName() {
        let c = DockerCLI.parsePS(sample)
        XCTAssertEqual(c.map(\.name), ["cache", "web", "db"])
        XCTAssertEqual(c.map(\.isRunning), [true, true, false])
        XCTAssertEqual(c.first { $0.name == "web" }?.hostPort, 8080)
        XCTAssertNil(c.first { $0.name == "cache" }?.hostPort)  // exposed but not published
        XCTAssertNil(c.first { $0.name == "db" }?.hostPort)
        XCTAssertEqual(c.first { $0.name == "db" }?.status, "Exited (0) 3 days ago")
        XCTAssertTrue(DockerCLI.parsePS("").isEmpty)
    }

    func testLocateFindsTheFirstExecutable() {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "nexus-docker-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: dir + "/.orbstack/bin", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        let tool = dir + "/.orbstack/bin/docker"
        fm.createFile(atPath: tool, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(DockerCLI.locate(home: dir), tool)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tool)
        XCTAssertNotEqual(DockerCLI.locate(home: dir), tool) // not executable: skipped
    }
}
