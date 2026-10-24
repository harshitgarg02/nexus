import XCTest
@testable import NexusCore

/// Deterministic RNG so generator output can be asserted exactly.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class GeneratorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_767_344.123) // 2026-10-23 14:55:44.123 UTC
    var rng = SplitMix64(state: 42)

    func testUUID4HasVersionAndVariantBits() {
        let u = Generators.uuid4(&rng)
        XCTAssertNotNil(u.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression))
        var again = SplitMix64(state: 42)
        XCTAssertEqual(Generators.uuid4(&again), u) // same seed, same output
        XCTAssertNotEqual(Generators.uuid4(&rng), u)
        XCTAssertNotNil(UUID(uuidString: u)) // Foundation agrees it's valid
    }

    func testUUID7EmbedsTimeAndSortsByTime() {
        let a = Generators.uuid7(now: now, &rng)
        XCTAssertNotNil(a.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression))
        XCTAssertEqual(Generators.uuid7Milliseconds(a), 1_792_767_344_123)
        let later = Generators.uuid7(now: now.addingTimeInterval(1), &rng)
        XCTAssertGreaterThan(later, a) // lexicographic order follows time
        XCTAssertNil(Generators.uuid7Milliseconds(Generators.uuid4(&rng))) // v4 has no timestamp
    }

    func testObjectIdLayout() {
        var st = ObjectIdState(using: &rng)
        let a = Generators.objectId(now: now, state: &st)
        let b = Generators.objectId(now: now, state: &st)
        XCTAssertEqual(a.count, 24)
        XCTAssertEqual(String(a.prefix(8)), String(format: "%08x", 1_792_767_344)) // seconds, big-endian
        XCTAssertEqual(a[a.index(a.startIndex, offsetBy: 8)..<a.index(a.startIndex, offsetBy: 18)],
                       b[b.index(b.startIndex, offsetBy: 8)..<b.index(b.startIndex, offsetBy: 18)]) // process bytes fixed
        let ca = Int(a.suffix(6), radix: 16)!, cb = Int(b.suffix(6), radix: 16)!
        XCTAssertEqual((cb - ca + 0x1000000) % 0x1000000, 1) // counter +1
        XCTAssertEqual(Generators.objectIdSeconds(a), 1_792_767_344)
        XCTAssertNil(Generators.objectIdSeconds("00000000" + String(a.suffix(16)))) // 1970: not a plausible ObjectId
        XCTAssertNil(Generators.objectIdSeconds("zzzzzzzzzzzzzzzzzzzzzzzz"))
    }

    func testULIDRoundTripAndOrdering() {
        let a = Generators.ulid(now: now, &rng)
        XCTAssertEqual(a.count, 26)
        XCTAssertTrue(a.allSatisfy { Generators.crockford.contains($0) })
        XCTAssertEqual(Generators.ulidMilliseconds(a), 1_792_767_344_123)
        XCTAssertGreaterThan(Generators.ulid(now: now.addingTimeInterval(5), &rng), a)
        XCTAssertNil(Generators.ulidMilliseconds("8ZZZZZZZZZZZZZZZZZZZZZZZZZ")) // first char > 7 overflows 48 bits
        XCTAssertNil(Generators.ulidMilliseconds("not-a-ulid"))
    }

    func testNanoidPasswordAndNumbers() {
        let n = Generators.nanoid(&rng)
        XCTAssertEqual(n.count, 21)
        XCTAssertTrue(n.allSatisfy { Generators.nanoAlphabet.contains($0) })
        XCTAssertEqual(Generators.nanoid(size: 8, &rng).count, 8)

        for _ in 0..<50 {
            let p = Generators.password(length: 12, &rng)
            XCTAssertEqual(p.count, 12)
            XCTAssertTrue(p.contains { Generators.lower.contains($0) } && p.contains { Generators.upper.contains($0) }
                          && p.contains { Generators.digits.contains($0) } && p.contains { Generators.symbols.contains($0) })
            let plain = Generators.password(length: 12, symbols: false, &rng)
            XCTAssertFalse(plain.contains { Generators.symbols.contains($0) })
        }
        XCTAssertEqual(Generators.password(length: 1, &rng).count, 4)      // clamped up
        XCTAssertEqual(Generators.password(length: 9999, &rng).count, 128) // and down

        for _ in 0..<200 { XCTAssertTrue((3...7).contains(Generators.number(7, 3, &rng))) } // swapped bounds, inclusive
        XCTAssertEqual(Generators.hexString(length: 7, &rng).count, 7)
        XCTAssertEqual(Generators.alnum(length: 10, &rng).count, 10)
    }
}

final class GeneratorRowTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_767_344)
    let utc = TimeZone(identifier: "UTC")!
    func eval(_ s: String) -> [CalcRow] { Calculator.evaluate(s, now: now, timeZone: utc) }

    func testUUIDCommand() {
        let r = eval("uuid")
        XCTAssertEqual(r.map(\.subtitle), ["UUID v4", "UUID v4 · uppercase", "UUID v4 · no dashes", "UUID v7 (time-ordered)"])
        XCTAssertTrue(r.allSatisfy(\.generated))
        XCTAssertEqual(r[1].title, r[0].title.uppercased())
        XCTAssertEqual(r[2].title, r[0].title.replacingOccurrences(of: "-", with: ""))
        XCTAssertEqual(eval("uuid 3").count, 3)
        XCTAssertEqual(eval("uuid 99").count, 10)  // capped
        XCTAssertEqual(eval("guid v7").first?.subtitle, "UUID v7 (time-ordered)")
        XCTAssertEqual(Set(eval("uuid 10").map(\.title)).count, 10) // all different
    }

    func testOtherCommands() {
        XCTAssertEqual(eval("objectid").first?.title.count, 24)
        XCTAssertEqual(eval("object id 4").count, 4)
        XCTAssertEqual(eval("oid").first?.subtitle, "MongoDB ObjectId")
        XCTAssertEqual(eval("ulid").first?.title.count, 26)
        XCTAssertEqual(eval("nanoid 10").first?.title.count, 10)
        XCTAssertEqual(eval("password 16").first?.title.count, 16)
        XCTAssertEqual(eval("hex 12").first?.title.count, 12)
        XCTAssertEqual(eval("random 5 5").first?.title, "5")
        XCTAssertTrue((1...100).contains(Int(eval("random 100").first!.title)!))
    }

    func testNotGeneratorsFallThrough() {
        // bare words that are also app names must not hijack ↵ (e.g. "Hex Fiend", "Passwords")
        for bare in ["password", "hex", "string", "random"] { XCTAssertTrue(eval(bare).isEmpty, bare) }
        XCTAssertTrue(eval("uuid foo").isEmpty)
        XCTAssertTrue(eval("password manager").isEmpty)
        XCTAssertTrue(eval("random words here").isEmpty)
        XCTAssertEqual(eval("2+2").first?.title, "4") // math still works
    }

    func testPastedIdsShowTheirTimestamp() {
        var rng = SplitMix64(state: 1)
        var st = ObjectIdState(using: &rng)
        let oid = Generators.objectId(now: now, state: &st)
        XCTAssertEqual(eval(oid).first?.title, "Fri 23 Oct 2026, 2:55:44 PM GMT")
        let v7 = Generators.uuid7(now: now.addingTimeInterval(0.5), &rng)
        XCTAssertEqual(eval(v7).first?.title, "Fri 23 Oct 2026, 2:55:44.500000 PM GMT")
        XCTAssertEqual(eval(Generators.ulid(now: now, &rng)).first?.title, "Fri 23 Oct 2026, 2:55:44 PM GMT")
        XCTAssertTrue(eval("0123456789abcdef01234567").isEmpty) // 24 hex, but 1970s timestamp: not an ObjectId
    }
}
