import XCTest
@testable import NexusCore

final class TOTPTests: XCTestCase {
    func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }
    let sha1 = Array("12345678901234567890".utf8)
    let sha256 = Array("12345678901234567890123456789012".utf8)
    let sha512 = Array("1234567890123456789012345678901234567890123456789012345678901234".utf8)

    // RFC 6238 appendix B (8 digits)
    func testRFC6238Vectors() {
        XCTAssertEqual(TOTP.code(secret: sha1, at: at(59), digits: 8), "94287082")
        XCTAssertEqual(TOTP.code(secret: sha1, at: at(1_111_111_109), digits: 8), "07081804")
        XCTAssertEqual(TOTP.code(secret: sha1, at: at(20_000_000_000), digits: 8), "65353130")
        XCTAssertEqual(TOTP.code(secret: sha256, at: at(59), digits: 8, algorithm: .sha256), "46119246")
        XCTAssertEqual(TOTP.code(secret: sha512, at: at(59), digits: 8, algorithm: .sha512), "90693936")
    }

    func testSixDigitsKeepLeadingZeros() {
        XCTAssertEqual(TOTP.code(secret: sha1, at: at(1_111_111_109)), "081804")
    }

    func testRemainingWindow() {
        XCTAssertEqual(TOTP.remaining(at: at(60)), 30)
        XCTAssertEqual(TOTP.remaining(at: at(89)), 1)
        XCTAssertEqual(TOTP.remaining(at: at(10), period: 15), 5)
    }

    func testBase32() {
        XCTAssertEqual(TOTP.base32Decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ").map { String(decoding: $0, as: UTF8.self) }, "12345678901234567890")
        XCTAssertEqual(TOTP.base32Decode("gezd gnbv-GY3TQOJQ====").map(\.count), 10)
        XCTAssertNil(TOTP.base32Decode("not base32!"))
        XCTAssertNil(TOTP.base32Decode(""))
    }

    func testParseURI() {
        let u = TOTP.parse(uri: "otpauth://totp/Example%20Prod:me@x.com?secret=GEZDGNBVGY3TQOJQ&issuer=Example%20Prod&algorithm=SHA256&digits=8&period=60")
        XCTAssertEqual(u, OTPAuthURI(name: "Example Prod · me@x.com", secret: "GEZDGNBVGY3TQOJQ", algorithm: .sha256, digits: 8, period: 60))
        let d = TOTP.parse(uri: "otpauth://totp/Acme?secret=GEZDGNBVGY3TQOJQ")
        XCTAssertEqual(d?.algorithm, .sha1); XCTAssertEqual(d?.digits, 6); XCTAssertEqual(d?.period, 30); XCTAssertEqual(d?.name, "Acme")
        XCTAssertNil(TOTP.parse(uri: "otpauth://hotp/x?secret=GEZDGNBVGY3TQOJQ"))
        XCTAssertNil(TOTP.parse(uri: "otpauth://totp/x?secret=!!!"))
        XCTAssertNil(TOTP.parse(uri: "https://example.com"))
    }

    func testStoreRoundTrip() {
        let path = NSTemporaryDirectory() + "nexus-totp-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let s = TOTPStore(path: path)
        let id = s.insert(name: "b", algorithm: .sha256, digits: 8, period: 60)
        s.insert(name: "A", algorithm: .sha1, digits: 6, period: 30)
        XCTAssertEqual(s.all().map(\.name), ["A", "b"])
        s.update(id, name: "c", algorithm: .sha512, digits: 7, period: 15)
        XCTAssertEqual(s.all(query: "c").first, TOTPEntry(id: id, name: "c", algorithm: .sha512, digits: 7, period: 15))
        s.delete(id)
        XCTAssertEqual(s.all().count, 1)
    }
}
